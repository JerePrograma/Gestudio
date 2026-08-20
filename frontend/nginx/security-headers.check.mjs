import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  API_ORIGIN_PLACEHOLDER,
  renderPagesHeaders,
  resolveApiOrigin,
} from "../scripts/generate-pages-headers.mjs";

const index = await readFile(new URL("../index.html", import.meta.url), "utf8");
const nginx = await readFile(new URL("./default.conf", import.meta.url), "utf8");
const pagesHeaders = await readFile(
  new URL("../public/_headers", import.meta.url),
  "utf8",
);

const securityHeaders = [
  "Content-Security-Policy",
  "X-Content-Type-Options",
  "X-Frame-Options",
  "Referrer-Policy",
  "Permissions-Policy",
];

const headersForPagesRule = (source, rule) => {
  const lines = source.split(/\r?\n/);
  const ruleIndex = lines.indexOf(rule);
  assert.notEqual(ruleIndex, -1, `Falta la regla ${rule} en _headers`);
  const headers = [];
  for (let index = ruleIndex + 1; index < lines.length && lines[index].startsWith("  "); index += 1) {
    headers.push(lines[index]);
  }
  return headers;
};

test("production security policy is defined once at the Nginx boundary", () => {
  assert.doesNotMatch(index, /Content-Security-Policy|unpkg\.com|<script>(.|\n)*?<\/script>/);
  assert.doesNotMatch(index, /skip-link|<main/);
  assert.equal((nginx.match(/add_header Content-Security-Policy/g) ?? []).length, 1);
  assert.match(nginx, /script-src 'self';/);
  assert.match(nginx, /connect-src 'self' https: http:\/\/localhost:\* http:\/\/127\.0\.0\.1:\*;/);
  assert.doesNotMatch(nginx, /unsafe-eval|script-src[^;]*unsafe-inline/);
});

test("security headers apply to every Nginx response", () => {
  for (const header of securityHeaders) {
    assert.match(nginx, new RegExp(`add_header ${header} .* always;`));
  }
});

test("activation responses use no-referrer without shadowing other Nginx headers", () => {
  const referrerMap = nginx.match(
    /map \$request_uri \$gestudio_referrer_policy \{(?<body>[\s\S]*?)\}/,
  )?.groups?.body;
  assert.ok(referrerMap, "Falta el mapa de Referrer-Policy por ruta");
  assert.match(referrerMap, /^\s*default "strict-origin-when-cross-origin";$/m);
  assert.ok(
    referrerMap.includes('~^/platform/activate(?:/)?(?:[?]|$) "no-referrer";'),
    "La política específica debe usar el URI original y cubrir query/slash sin ampliar la ruta",
  );
  assert.match(
    nginx,
    /add_header Referrer-Policy \$gestudio_referrer_policy always;/,
  );
  for (const header of securityHeaders.filter((header) => header !== "Referrer-Policy")) {
    assert.equal(
      (nginx.match(new RegExp(`add_header ${header} `, "g")) ?? []).length,
      1,
      `${header} debe conservar una única definición heredable`,
    );
  }
});

test("Cloudflare Pages template preserves the security and cache contracts", () => {
  assert.equal(
    pagesHeaders.split(API_ORIGIN_PLACEHOLDER).length - 1,
    1,
  );
  const globalHeaders = headersForPagesRule(pagesHeaders, "/*");
  for (const header of securityHeaders) {
    assert.ok(
      globalHeaders.some((line) => line.startsWith(`  ${header}:`)),
      `La regla global perdió ${header}`,
    );
  }
  for (const activationPath of ["/platform/activate", "/platform/activate/"]) {
    assert.deepEqual(
      headersForPagesRule(pagesHeaders, activationPath),
      ["  Referrer-Policy: no-referrer"],
    );
  }
  assert.match(pagesHeaders, /script-src 'self';/);
  assert.doesNotMatch(pagesHeaders, /unsafe-eval|script-src[^;]*unsafe-inline/);
  assert.match(pagesHeaders, /^\/index\.html\r?\n  Cache-Control: no-cache$/m);
  assert.match(
    pagesHeaders,
    /^\/assets\/\*\r?\n  Cache-Control: public, max-age=31536000, immutable$/m,
  );
  for (const line of pagesHeaders.split(/\r?\n/)) {
    assert.ok(line.length <= 2000, "_headers supera el límite por línea de Pages");
  }
});

test("Cloudflare Pages build writes the exact API origin into CSP", () => {
  const rendered = renderPagesHeaders(
    pagesHeaders,
    "https://api.demo.example.test/api",
  );
  assert.match(
    rendered,
    /connect-src 'self' https:\/\/api\.demo\.example\.test;/,
  );
  assert.doesNotMatch(rendered, new RegExp(API_ORIGIN_PLACEHOLDER));
  assert.equal(resolveApiOrigin("http://localhost:8080/api"), "http://localhost:8080");
  assert.throws(
    () => resolveApiOrigin("http://api.demo.example.test/api"),
    /debe usar HTTPS/,
  );
  assert.throws(
    () => renderPagesHeaders(pagesHeaders.replace(API_ORIGIN_PLACEHOLDER, ""), "https://api.example.test/api"),
    /exactamente una vez/,
  );
});
