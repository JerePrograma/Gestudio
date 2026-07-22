# Demo remota sin dominio propio

## Arquitectura elegida

Esta variante utiliza exclusivamente servicios gratuitos de Cloudflare:

```text
navegador
  -> https://<proyecto>.pages.dev
  -> Pages Function /api/*
  -> https://<aleatorio>.trycloudflare.com
  -> cloudflared local
  -> http://127.0.0.1:18080
  -> backend remote-demo
  -> PostgreSQL local sin puerto publicado
```

GitHub Pages no se utiliza porque sólo sirve contenido estático y no ofrece una
función de proxy equivalente. Sin proxy, el frontend `github.io` y el backend
`trycloudflare.com` quedarían en sitios distintos y romperían el contrato actual
de cookie `SameSite=Strict`.

Cloudflare Pages entrega automáticamente un hostname `*.pages.dev`. La Pages
Function mantiene el acceso del navegador en el mismo origin y reenvía únicamente
`/api` y `/api/*` al Quick Tunnel configurado en tiempo de ejecución.

## Alcance y limitaciones

- Es una demo temporal, no producción.
- Quick Tunnel genera un hostname aleatorio en cada inicio.
- El hostname de Quick Tunnel no debe compartirse con los testers.
- Quick Tunnel no ofrece SLA, limita las solicitudes concurrentes y no soporta
  Server-Sent Events.
- Cada cambio de hostname requiere actualizar `GESTUDIO_BACKEND_ORIGIN` en Pages.
- El host local, Docker y `cloudflared` deben permanecer encendidos.
- PostgreSQL continúa sin puerto publicado.
- El backend continúa expuesto sólo en `127.0.0.1:18080`.

## Contratos añadidos

### Pages Function

`frontend/functions/api/[[path]].js`:

- sólo acepta un origin HTTPS `*.trycloudflare.com` sin path;
- sólo reenvía rutas `/api`;
- elimina headers de forwarding controlables por el cliente;
- conserva `Authorization`, cookies, método, body, query y `Origin`;
- añade `X-Gestudio-Proxy-Token`;
- devuelve errores controlados sin revelar el origin interno;
- aplica `Cache-Control: no-store` a respuestas de API.

`frontend/public/_routes.json` limita las invocaciones de Functions a:

```json
{
  "version": 1,
  "include": ["/api", "/api/*"],
  "exclude": []
}
```

### Backend

El perfil `remote-demo` exige `APP_REMOTE_DEMO_PROXY_TOKEN`, con un mínimo de
32 bytes UTF-8. Todas las rutas `/api` quedan ocultas con `404` cuando el header
`X-Gestudio-Proxy-Token` falta o no coincide. El readiness local permanece
accesible para el launcher.

El mismo valor debe existir en dos lugares no versionados:

- `.env.remote-demo` como `APP_REMOTE_DEMO_PROXY_TOKEN`;
- Cloudflare Pages como secreto `GESTUDIO_PROXY_TOKEN`.

## Configuración de Cloudflare Pages

Crear un proyecto Pages conectado al repositorio `JerePrograma/Gestudio`:

| Campo | Valor |
|---|---|
| Production branch | `main` |
| Root directory | `frontend` |
| Build command | `npm ci && npm run build` |
| Build output directory | `dist` |
| Node.js | `22` |

Variables de producción:

| Variable | Valor |
|---|---|
| `VITE_API_BASE_URL` | `https://<proyecto>.pages.dev/api` |
| `VITE_APP_TIME_ZONE` | `America/Argentina/Buenos_Aires` |
| `GESTUDIO_BACKEND_ORIGIN` | hostname actual `https://*.trycloudflare.com` |
| `GESTUDIO_PROXY_TOKEN` | el mismo secreto que `APP_REMOTE_DEMO_PROXY_TOKEN` |

`GESTUDIO_PROXY_TOKEN` debe guardarse como secreto cifrado. El origin de Quick
Tunnel puede guardarse como variable de texto porque cambia en cada sesión.

Deshabilitar deployments de preview mientras se use una sola configuración CORS.
Los previews tienen otros origins y no están incluidos en
`APP_CORS_ALLOWED_ORIGINS`.

## Configuración local

En `.env.remote-demo`:

```dotenv
APP_CORS_ALLOWED_ORIGINS=https://<proyecto>.pages.dev
APP_REMOTE_DEMO_PROXY_TOKEN=<secreto-aleatorio-independiente>
```

El resto de los secretos debe seguir siendo independiente:

- `POSTGRES_PASSWORD`;
- `JWT_SECRET`;
- `APP_REMOTE_DEMO_PROXY_TOKEN`;
- `APP_OBSERVABILITY_METRICS_TOKEN`.

No usar `trycloudflare.com` como CORS origin. El navegador se comunica con Pages,
no directamente con Quick Tunnel.

## Secuencia operativa

1. Actualizar `main` y comprobar árbol limpio.
2. Crear el proyecto Pages y obtener su URL `*.pages.dev`.
3. Crear `.env.remote-demo` con ese origin y cuatro secretos independientes.
4. Iniciar el stack local mediante `scripts/demo-remote.ps1 -Action Start`.
5. Iniciar Quick Tunnel hacia `http://127.0.0.1:18080`.
6. Copiar el hostname `trycloudflare.com` a `GESTUDIO_BACKEND_ORIGIN`.
7. Copiar el mismo proxy token a `GESTUDIO_PROXY_TOKEN` como secreto.
8. Redeployar Pages.
9. Probar login y refresh únicamente mediante la URL `pages.dev`.
10. Al detener la demo, detener primero el túnel y luego el stack.

## Criterios de aceptación

- `https://<proyecto>.pages.dev` carga la SPA.
- Las llamadas del navegador utilizan `https://<proyecto>.pages.dev/api/...`.
- La cookie de refresh queda asociada al hostname `pages.dev`, es `Secure`,
  `HttpOnly`, `SameSite=Strict`, host-only y con path `/api/login`.
- Una llamada directa al hostname `trycloudflare.com/api/...` sin el token devuelve
  `404`.
- El proxy no permite `/actuator/**`.
- PostgreSQL no tiene bindings de host.
- El backend sólo tiene `127.0.0.1:18080`.
- `.env.remote-demo` y los secretos de Cloudflare no aparecen en Git.
