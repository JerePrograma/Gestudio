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

const PROXY_TOKEN = "pages-proxy-token-independent-32-bytes";
const routes = JSON.parse(
  await readFile(new URL("../public/_routes.json", import.meta.url), "utf8"),
);

test("Pages Functions only invokes the API proxy routes", () => {
  assert.deepEqual(routes, {
    version: 1,
    include: ["/api", "/api/*"],
    exclude: [],
  });
});

test("Quick Tunnel origin and proxy token are fail-closed", () => {
  assert.equal(
    resolveBackendOrigin("https://random-name.trycloudflare.com"),
    "https://random-name.trycloudflare.com",
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

test("proxy preserves the API path and query without becoming an open proxy", () => {
  assert.equal(
    resolveUpstreamUrl(
      "https://gestudio-demo.pages.dev/api/alumnos?page=2",
      "https://random-name.trycloudflare.com",
    ).toString(),
    "https://random-name.trycloudflare.com/api/alumnos?page=2",
  );
  assert.throws(() =>
    resolveUpstreamUrl(
      "https://gestudio-demo.pages.dev/actuator/health",
      "https://random-name.trycloudflare.com",
    ),
  );
});

test("proxy strips spoofable forwarding headers and preserves application credentials", () => {
  const incoming = new Request(
    "https://gestudio-demo.pages.dev/api/usuarios/perfil",
    {
      headers: {
        Authorization: "Bearer test-token",
        Cookie: "gestudio_remote_demo_refresh=test-cookie",
        Origin: "https://gestudio-demo.pages.dev",
        "CF-Connecting-IP": "203.0.113.10",
        "X-Forwarded-For": "203.0.113.10",
      },
    },
  );

  const upstream = buildUpstreamRequest(
    incoming,
    "https://random-name.trycloudflare.com",
    PROXY_TOKEN,
  );
  assert.equal(
    upstream.url,
    "https://random-name.trycloudflare.com/api/usuarios/perfil",
  );
  assert.equal(upstream.headers.get("authorization"), "Bearer test-token");
  assert.equal(
    upstream.headers.get("cookie"),
    "gestudio_remote_demo_refresh=test-cookie",
  );
  assert.equal(
    upstream.headers.get("origin"),
    "https://gestudio-demo.pages.dev",
  );
  assert.equal(upstream.headers.get("cf-connecting-ip"), null);
  assert.equal(upstream.headers.get("x-forwarded-for"), null);
  assert.equal(upstream.headers.get("x-gestudio-pages-proxy"), "1");
  assert.equal(upstream.headers.get("x-gestudio-proxy-token"), PROXY_TOKEN);
});

test("proxy returns controlled errors and preserves the upstream response", async () => {
  const request = new Request(
    "https://gestudio-demo.pages.dev/api/login/refresh",
    { method: "POST" },
  );

  const missingConfiguration = await proxyPagesApi({ env: {}, request });
  assert.equal(missingConfiguration.status, 503);
  assert.deepEqual(await missingConfiguration.json(), {
    code: "PROXY_NOT_CONFIGURED",
  });

  const unavailable = await proxyPagesApi(
    {
      env: {
        GESTUDIO_BACKEND_ORIGIN:
          "https://random-name.trycloudflare.com",
        GESTUDIO_PROXY_TOKEN: PROXY_TOKEN,
      },
      request,
    },
    async () => {
      throw new Error("offline");
    },
  );
  assert.equal(unavailable.status, 502);

  let capturedRequest;
  const upstreamResponse = await proxyPagesApi(
    {
      env: {
        GESTUDIO_BACKEND_ORIGIN:
          "https://random-name.trycloudflare.com",
        GESTUDIO_PROXY_TOKEN: PROXY_TOKEN,
      },
      request,
    },
    async (upstreamRequest) => {
      capturedRequest = upstreamRequest;
      return new Response("ok", {
        status: 201,
        headers: {
          "Set-Cookie":
            "gestudio_remote_demo_refresh=value; Secure; HttpOnly; SameSite=Strict; Path=/api/login",
        },
      });
    },
  );

  assert.equal(
    capturedRequest.url,
    "https://random-name.trycloudflare.com/api/login/refresh",
  );
  assert.equal(upstreamResponse.status, 201);
  assert.equal(upstreamResponse.headers.get("cache-control"), "no-store");
  assert.match(
    upstreamResponse.headers.get("set-cookie"),
    /SameSite=Strict/,
  );
});
