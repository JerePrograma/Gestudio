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

test("Cloudflare Pages template preserves the security and cache contracts", () => {
  assert.equal(
    pagesHeaders.split(API_ORIGIN_PLACEHOLDER).length - 1,
    1,
  );
  for (const header of securityHeaders) {
    assert.match(pagesHeaders, new RegExp(`^  ${header}:`, "m"));
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
