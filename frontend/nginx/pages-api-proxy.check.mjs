import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  buildUpstreamRequest,
  proxyPagesApi,
  resolveBackendOrigin,
  resolveProxyToken,
  resolveUpstreamUrl,
} from "../functions/api/[[path]].js";

const PAGES_ORIGIN = "https://gestudio-demo-jere-287b8c90.pages.dev";
const QUICK_TUNNEL_ORIGIN = "https://random-name.trycloudflare.com";
const PROXY_TOKEN = "pages-proxy-token-independent-32-bytes";
const routes = JSON.parse(
  await readFile(new URL("../public/_routes.json", import.meta.url), "utf8"),
);

test("Pages Functions only invokes the exact API proxy routes", () => {
  assert.deepEqual(routes, {
    version: 1,
    include: ["/api", "/api/*"],
    exclude: [],
  });

  for (const [path, expectedPath] of [
    ["/api", "/api"],
    ["/api/", "/api/"],
    ["/api/alumnos?pagina=2&tenant=alpha", "/api/alumnos?pagina=2&tenant=alpha"],
  ]) {
    assert.equal(
      resolveUpstreamUrl(
        `${PAGES_ORIGIN}${path}`,
        QUICK_TUNNEL_ORIGIN,
      ).toString(),
      `${QUICK_TUNNEL_ORIGIN}${expectedPath}`,
    );
  }

  for (const path of [
    "/",
    "/apix",
    "/api-v2",
    "/actuator/health",
    "/api%2Factuator/health",
  ]) {
    assert.throws(() =>
      resolveUpstreamUrl(`${PAGES_ORIGIN}${path}`, QUICK_TUNNEL_ORIGIN),
    );
  }
});

test("Quick Tunnel origin and proxy token are fail-closed", () => {
  assert.equal(
    resolveBackendOrigin(QUICK_TUNNEL_ORIGIN),
    QUICK_TUNNEL_ORIGIN,
  );
  assert.equal(resolveProxyToken(PROXY_TOKEN), PROXY_TOKEN);
  for (const invalidOrigin of [
    "",
    "http://random-name.trycloudflare.com",
    "https://trycloudflare.com",
    "https://api.example.com",
    "https://random-name.trycloudflare.com/path",
    "https://user:password@random-name.trycloudflare.com",
  ]) {
    assert.throws(() => resolveBackendOrigin(invalidOrigin));
  }
  assert.throws(() => resolveProxyToken("short"));
});

test("POST proxy preserves body, query and credentials while replacing spoofable headers", async () => {
  const payload = { username: "alpha.demo.presentacion", tenant: "alpha" };
  const incoming = new Request(
    `${PAGES_ORIGIN}/api/login?continue=%2Falumnos&source=public-demo`,
    {
      method: "POST",
      headers: {
        Authorization: "Bearer test-token",
        Cookie: "gestudio_remote_demo_refresh=test-cookie",
        Origin: PAGES_ORIGIN,
        "Content-Type": "application/json",
        "X-Gestudio-Proxy-Token": "client-controlled-token",
        "X-Forwarded-For": "203.0.113.10",
        "X-Forwarded-Host": "attacker.example",
        "X-Forwarded-Port": "8443",
        "X-Forwarded-Prefix": "/spoofed",
        "X-Forwarded-Proto": "http",
        Forwarded: "for=203.0.113.10;host=attacker.example;proto=http",
        Host: "attacker.example",
        "CF-Connecting-IP": "203.0.113.10",
        "CF-IPCountry": "XX",
        "CF-Ray": "spoofed-ray",
        "CF-Visitor": '{"scheme":"http"}',
        "X-Real-IP": "203.0.113.10",
        "True-Client-IP": "203.0.113.10",
        Via: "evil-proxy",
      },
      body: JSON.stringify(payload),
    },
  );

  const upstream = buildUpstreamRequest(
    incoming,
    QUICK_TUNNEL_ORIGIN,
    PROXY_TOKEN,
  );

  assert.equal(
    upstream.url,
    `${QUICK_TUNNEL_ORIGIN}/api/login?continue=%2Falumnos&source=public-demo`,
  );
  assert.equal(upstream.method, "POST");
  assert.equal(upstream.redirect, "manual");
  assert.equal(upstream.headers.get("authorization"), "Bearer test-token");
  assert.equal(
    upstream.headers.get("cookie"),
    "gestudio_remote_demo_refresh=test-cookie",
  );
  assert.equal(upstream.headers.get("origin"), PAGES_ORIGIN);
  assert.equal(upstream.headers.get("content-type"), "application/json");
  assert.deepEqual(await upstream.json(), payload);

  for (const header of [
    "x-forwarded-for",
    "x-forwarded-host",
    "x-forwarded-port",
    "x-forwarded-prefix",
    "x-forwarded-proto",
    "forwarded",
    "host",
    "cf-connecting-ip",
    "cf-ipcountry",
    "cf-ray",
    "cf-visitor",
    "x-real-ip",
    "true-client-ip",
    "via",
  ]) {
    assert.equal(upstream.headers.get(header), null, `${header} was forwarded`);
  }

  assert.equal(upstream.headers.get("x-gestudio-pages-proxy"), "1");
  assert.equal(upstream.headers.get("x-gestudio-proxy-token"), PROXY_TOKEN);
});

test("proxy errors are no-store, generic and never disclose the tunnel", async () => {
  const request = new Request(`${PAGES_ORIGIN}/api/login/refresh`, {
    method: "POST",
  });

  const cases = [
    {
      expectedStatus: 503,
      expectedCode: "PROXY_NOT_CONFIGURED",
      response: await proxyPagesApi({ env: {}, request }),
    },
    {
      expectedStatus: 502,
      expectedCode: "BACKEND_UNAVAILABLE",
      response: await proxyPagesApi(
        {
          env: {
            GESTUDIO_BACKEND_ORIGIN: QUICK_TUNNEL_ORIGIN,
            GESTUDIO_PROXY_TOKEN: PROXY_TOKEN,
          },
          request,
        },
        async () => {
          throw new Error(`offline: ${QUICK_TUNNEL_ORIGIN}`);
        },
      ),
    },
  ];

  for (const { expectedStatus, expectedCode, response } of cases) {
    assert.equal(response.status, expectedStatus);
    assert.equal(response.headers.get("cache-control"), "no-store");
    const body = await response.text();
    assert.deepEqual(JSON.parse(body), { code: expectedCode });
    assert.doesNotMatch(body, /trycloudflare\.com/i);
  }
});

test("actuator cannot use the Pages Function as an open proxy", async () => {
  let upstreamCalled = false;
  const response = await proxyPagesApi(
    {
      env: {
        GESTUDIO_BACKEND_ORIGIN: QUICK_TUNNEL_ORIGIN,
        GESTUDIO_PROXY_TOKEN: PROXY_TOKEN,
      },
      request: new Request(`${PAGES_ORIGIN}/actuator/health/readiness`),
    },
    async () => {
      upstreamCalled = true;
      return new Response("must not happen");
    },
  );

  assert.equal(upstreamCalled, false);
  assert.equal(response.status, 400);
  assert.equal(response.headers.get("cache-control"), "no-store");
  const body = await response.text();
  assert.deepEqual(JSON.parse(body), { code: "INVALID_PROXY_REQUEST" });
  assert.doesNotMatch(body, /trycloudflare\.com/i);
});

test("proxy keeps the secure refresh cookie and rewrites internal response URLs", async () => {
  const request = new Request(`${PAGES_ORIGIN}/api/login/refresh`, {
    method: "POST",
  });

  let capturedRequest;
  const upstreamResponse = await proxyPagesApi(
    {
      env: {
        GESTUDIO_BACKEND_ORIGIN: QUICK_TUNNEL_ORIGIN,
        GESTUDIO_PROXY_TOKEN: PROXY_TOKEN,
      },
      request,
    },
    async (upstreamRequest) => {
      capturedRequest = upstreamRequest;
      return new Response("ok", {
        status: 201,
        headers: {
          "Cache-Control": "public, max-age=3600",
          "Set-Cookie":
            "gestudio_remote_demo_refresh=value; Secure; HttpOnly; SameSite=Strict; Path=/api/login",
          Location: `${QUICK_TUNNEL_ORIGIN}/api/usuarios/perfil?source=refresh#session`,
          "Content-Location": `${QUICK_TUNNEL_ORIGIN}/api/login/refresh?representation=current#body`,
        },
      });
    },
  );

  assert.equal(
    capturedRequest.url,
    `${QUICK_TUNNEL_ORIGIN}/api/login/refresh`,
  );
  assert.equal(upstreamResponse.status, 201);
  assert.equal(upstreamResponse.headers.get("cache-control"), "no-store");
  assert.equal(
    upstreamResponse.headers.get("location"),
    `${PAGES_ORIGIN}/api/usuarios/perfil?source=refresh#session`,
  );
  assert.equal(
    upstreamResponse.headers.get("content-location"),
    `${PAGES_ORIGIN}/api/login/refresh?representation=current#body`,
  );

  const cookie = upstreamResponse.headers.get("set-cookie");
  assert.ok(cookie);
  assert.match(cookie, /^gestudio_remote_demo_refresh=value(?:;|$)/i);
  assert.match(cookie, /(?:^|;)\s*Secure(?:;|$)/i);
  assert.match(cookie, /(?:^|;)\s*HttpOnly(?:;|$)/i);
  assert.match(cookie, /(?:^|;)\s*SameSite=Strict(?:;|$)/i);
  assert.match(cookie, /(?:^|;)\s*Path=\/api\/login(?:;|$)/i);
  assert.doesNotMatch(cookie, /(?:^|;)\s*Domain=/i);
});
