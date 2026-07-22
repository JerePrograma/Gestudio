const QUICK_TUNNEL_SUFFIX = ".trycloudflare.com";
const API_PATH_PATTERN = /^\/api(?:\/|$)/;
const FORWARDED_HEADERS = [
  "cf-connecting-ip",
  "cf-ipcountry",
  "cf-ray",
  "forwarded",
  "host",
  "x-forwarded-for",
  "x-forwarded-host",
  "x-forwarded-proto",
];

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

export function buildUpstreamRequest(request, backendOrigin) {
  const upstreamUrl = resolveUpstreamUrl(request.url, backendOrigin);
  const headers = new Headers(request.headers);
  for (const header of FORWARDED_HEADERS) {
    headers.delete(header);
  }
  headers.set("X-Gestudio-Pages-Proxy", "1");

  const init = {
    method: request.method,
    headers,
    redirect: "manual",
  };
  if (request.method !== "GET" && request.method !== "HEAD") {
    init.body = request.body;
    init.duplex = "half";
  }

  return new Request(upstreamUrl, init);
}

export async function proxyPagesApi(context, fetchImplementation = fetch) {
  let backendOrigin;
  try {
    backendOrigin = resolveBackendOrigin(context.env.GESTUDIO_BACKEND_ORIGIN);
  } catch {
    return jsonError(503, "BACKEND_ORIGIN_NOT_CONFIGURED");
  }

  let upstreamRequest;
  try {
    upstreamRequest = buildUpstreamRequest(context.request, backendOrigin);
  } catch {
    return jsonError(400, "INVALID_PROXY_REQUEST");
  }

  try {
    return await fetchImplementation(upstreamRequest);
  } catch {
    return jsonError(502, "BACKEND_UNAVAILABLE");
  }
}

export function onRequest(context) {
  return proxyPagesApi(context);
}
