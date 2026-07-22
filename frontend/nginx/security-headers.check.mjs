import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const index = await readFile(new URL("../index.html", import.meta.url), "utf8");
const nginx = await readFile(new URL("./default.conf", import.meta.url), "utf8");

test("production security policy is defined once at the Nginx boundary", () => {
  assert.doesNotMatch(index, /Content-Security-Policy|unpkg\.com|<script>(.|\n)*?<\/script>/);
  assert.doesNotMatch(index, /skip-link|<main/);
  assert.equal((nginx.match(/add_header Content-Security-Policy/g) ?? []).length, 1);
  assert.match(nginx, /script-src 'self';/);
  assert.match(nginx, /connect-src 'self' https: http:\/\/localhost:\* http:\/\/127\.0\.0\.1:\*;/);
  assert.doesNotMatch(nginx, /unsafe-eval|script-src[^;]*unsafe-inline/);
});

test("security headers apply to every response", () => {
  for (const header of [
    "Content-Security-Policy",
    "X-Content-Type-Options",
    "X-Frame-Options",
    "Referrer-Policy",
    "Permissions-Policy",
  ]) {
    assert.match(nginx, new RegExp(`add_header ${header} .* always;`));
  }
});
