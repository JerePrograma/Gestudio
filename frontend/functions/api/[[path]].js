const QUICK_TUNNEL_SUFFIX = ".trycloudflare.com";
const API_PATH_PATTERN = /^\/api(?:\/|$)/;
const SPOOFABLE_FORWARDING_HEADERS = new Set([
  "forwarded",
  "host",
  "true-client-ip",
  "via",
  "x-real-ip",
]);
const INTERNAL_URL_RESPONSE_HEADERS = ["Location", "Content-Location"];

function removeSpoofableForwardingHeaders(headers) {
  const namesToDelete = [];
  for (const [name] of headers) {
    const normalizedName = name.toLowerCase();
    if (
      normalizedName.startsWith("x-forwarded-") ||
      normalizedName.startsWith("cf-") ||
      SPOOFABLE_FORWARDING_HEADERS.has(normalizedName)
    ) {
      namesToDelete.push(name);
    }
  }

  for (const name of namesToDelete) {
    headers.delete(name);
  }
}

function rewriteInternalResponseUrls(
  headers,
  backendOrigin,
  publicOrigin,
) {
  for (const headerName of INTERNAL_URL_RESPONSE_HEADERS) {
    const value = headers.get(headerName);
    if (!value) {
      continue;
    }

    let internalUrl;
    try {
      internalUrl = new URL(value);
    } catch {
      continue;
    }

    if (internalUrl.origin !== backendOrigin) {
      continue;
    }

    headers.set(
      headerName,
      new URL(
        `${internalUrl.pathname}${internalUrl.search}${internalUrl.hash}`,
        `${publicOrigin}/`,
      ).toString(),
    );
  }
}

function jsonError(status, code) {
  return Response.json(
    { code },
    {
      status,
      headers: {
        "Cache-Control": "no-store",
        "Content-Type": "application/json; charset=utf-8",
      },
    },
  );
}

export function resolveBackendOrigin(value) {
  const rawValue = value?.trim();
  if (!rawValue) {
    throw new Error("GESTUDIO_BACKEND_ORIGIN no está configurado");
  }

  const url = new URL(rawValue);
  const hostname = url.hostname.toLowerCase();
  if (
    url.protocol !== "https:" ||
    hostname === "trycloudflare.com" ||
    !hostname.endsWith(QUICK_TUNNEL_SUFFIX) ||
    url.port ||
    url.username ||
    url.password ||
    url.pathname !== "/" ||
    url.search ||
    url.hash
  ) {
    throw new Error(
      "GESTUDIO_BACKEND_ORIGIN debe ser un origin HTTPS de Quick Tunnel sin path",
    );
  }

  return url.origin;
}

export function resolveProxyToken(value) {
  const token = value?.trim();
  if (!token || new TextEncoder().encode(token).length < 32) {
    throw new Error("GESTUDIO_PROXY_TOKEN debe tener al menos 32 bytes UTF-8");
  }
  return token;
}

export function resolveUpstreamUrl(requestUrl, backendOrigin) {
  const incomingUrl = new URL(requestUrl);
  if (!API_PATH_PATTERN.test(incomingUrl.pathname)) {
    throw new Error("La Pages Function sólo puede reenviar rutas /api");
  }

  return new URL(
    `${incomingUrl.pathname}${incomingUrl.search}`,
    `${backendOrigin}/`,
  );
}

export function buildUpstreamRequest(request, backendOrigin, proxyToken) {
  const upstreamUrl = resolveUpstreamUrl(request.url, backendOrigin);
  const upstreamRequest = new Request(new Request(upstreamUrl, request), {
    redirect: "manual",
  });
  removeSpoofableForwardingHeaders(upstreamRequest.headers);
  upstreamRequest.headers.set("X-Gestudio-Pages-Proxy", "1");
  upstreamRequest.headers.set("X-Gestudio-Proxy-Token", proxyToken);
  return upstreamRequest;
}

export async function proxyPagesApi(context, fetchImplementation = fetch) {
  let backendOrigin;
  let proxyToken;
  try {
    backendOrigin = resolveBackendOrigin(context.env.GESTUDIO_BACKEND_ORIGIN);
    proxyToken = resolveProxyToken(context.env.GESTUDIO_PROXY_TOKEN);
  } catch {
    return jsonError(503, "PROXY_NOT_CONFIGURED");
  }

  let upstreamRequest;
  try {
    upstreamRequest = buildUpstreamRequest(
      context.request,
      backendOrigin,
      proxyToken,
    );
  } catch {
    return jsonError(400, "INVALID_PROXY_REQUEST");
  }

  try {
    const upstreamResponse = await fetchImplementation(upstreamRequest);
    const responseHeaders = new Headers(upstreamResponse.headers);
    rewriteInternalResponseUrls(
      responseHeaders,
      backendOrigin,
      new URL(context.request.url).origin,
    );
    responseHeaders.set("Cache-Control", "no-store");
    return new Response(upstreamResponse.body, {
      status: upstreamResponse.status,
      statusText: upstreamResponse.statusText,
      headers: responseHeaders,
    });
  } catch {
    return jsonError(502, "BACKEND_UNAVAILABLE");
  }
}

export function onRequest(context) {
  return proxyPagesApi(context);
}
