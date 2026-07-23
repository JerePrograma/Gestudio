# Despliegue público de la demo remota

## Objetivo

Publicar la demo en esta topología temporal:

```text
https://gestudio-demo-jere-287b8c90.pages.dev
  -> Pages Function /api/*
  -> Quick Tunnel HTTPS aleatorio
  -> cloudflared local
  -> http://127.0.0.1:18080
  -> backend y PostgreSQL locales
```

El frontend puede continuar disponible aunque el host local o el túnel estén
apagados. En ese caso las llamadas `/api/*` fallan. Un `530` con `Error 1016`
indica que Pages conserva un hostname `trycloudflare.com` que ya no resuelve.

## Comando canónico

Desde una copia limpia y actualizada de `main`:

```powershell
pwsh -NoProfile `
  -File .\scripts\deploy-remote-demo-public.ps1
```

El script:

1. exige `main` limpia y sincronizada con `origin/main`;
2. inicia o recrea `db` y `backend` mediante `demo-remote.ps1 -Action Start`;
3. valida readiness local en `127.0.0.1:18080`;
4. detiene únicamente Quick Tunnels registrados previamente por Gestudio;
5. inicia un Quick Tunnel nuevo forzando transporte HTTP/2;
6. espera el registro de la conexión, resolución DNS y respuestas HTTP reales;
7. comprueba que el túnel directo devuelva `404` sin proxy token y `401` con el
   token correcto pero sin sesión;
8. actualiza `GESTUDIO_BACKEND_ORIGIN` y `GESTUDIO_PROXY_TOKEN` en Pages;
9. ejecuta `npm ci` y `npm run build`;
10. despliega `frontend/dist` como producción de la rama `main`;
11. valida frontend `200`, API sin sesión `401`, refresh sin cookie `401` y CORS.

## Estado local

La herramienta guarda sólo datos operativos no secretos en:

```text
%USERPROFILE%\Documents\Gestudio-RemoteDemo\public-deployment.json
```

Los logs de `cloudflared` quedan bajo:

```text
%USERPROFILE%\Documents\Gestudio-RemoteDemo\logs
```

Nunca se persisten contraseñas, JWT, proxy tokens ni valores de
`.env.remote-demo`.

## Requisitos

- Windows y PowerShell 7.
- Docker Desktop iniciado.
- Git, Node.js, npm y `cloudflared` disponibles en `PATH`.
- Wrangler autenticado para la cuenta propietaria del proyecto Pages.
- `.env.remote-demo` presente e ignorado por Git.
- Salida TCP al puerto `7844` permitida para `cloudflared`.

## Resultado esperado

```text
[PASS] Backend local - readiness UP
[PASS] Conector cloudflared - conexión registrada por HTTP/2
[PASS] DNS Quick Tunnel
[PASS] Quick Tunnel hacia backend - HTTP 401
[PASS] Bindings Pages
[PASS] Cloudflare Pages
[PASS] Refresh público - HTTP 401 JSON sin cookie; sin 530/1016
[PASS] DEMO REMOTA PÚBLICA - disponible
```

## Disponibilidad

Después del despliegue deben permanecer encendidos:

- el equipo local;
- Docker Desktop;
- los contenedores `gestudio-remote-demo`;
- el proceso `cloudflared` registrado por el script;
- la conexión a Internet.

Quick Tunnel es apropiado únicamente para demostración y pruebas. Cada ejecución
completa crea un hostname aleatorio nuevo y vuelve a desplegar Pages con ese
origin. Para disponibilidad estable se debe reemplazar por un túnel nombrado.
