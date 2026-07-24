# Demo, manual y certificación

> Estado: CONFIRMADO  
> Última revisión: 2026-07-24  
> Fuentes principales: scripts y documentación bajo `docs/testing`, `docs/manual-usuarios`, `docs/operations`

## Demo local persistente

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Start
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Status
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Stop
```

- Proyecto Compose aislado `gestudio-demo-local`.
- Puertos usuales 18081/18080/15432.
- `Start` recrea backend/frontend sin borrar DB.
- Aplica seed dos veces para comprobar idempotencia.
- `Status` verifica imágenes, revisión, Compose, Flyway, health, frontend y fecha de negocio.
- `Reset` es la única operación que elimina volúmenes.

## Dataset

Seed demo manual fuera de Flyway, 914 filas en la evidencia fechada, cinco usuarios y matriz RBAC. No contiene personas reales. Cambiar conteos exige actualizar validadores y docs coordinadamente.

## Demo remota

Scripts y Compose remoto exponen backend en loopback y frontend opcional; CI valida perfiles, puertos, cookies seguras, seed y parsing PowerShell. Cloudflare Pages es demo, no producción.

## Manual visual

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\manual\Build-Manual.ps1
```

- Playwright recorre la demo real.
- Genera capturas, HTML, PDF y metadata.
- Artefactos no se versionan.
- Cubre cinco roles y pantallas desktop/móvil.
- Soporta reanudación desde una captura; exige que las previas existan.
- `Validate-Manual.ps1` comprueba recorrido/artefactos.

## Certificación integral

```powershell
pwsh -NoProfile -File .\scripts\certify-api-complete.ps1
```

Fases:

1. inventario de 146 endpoints y política RBAC;
2. smoke mutable en PostgreSQL/Docker descartable;
3. demo pública no mutante con login, refresh, módulos, PDF, CORS y logout.

Variantes:

```powershell
pwsh -NoProfile -File .\scripts\certify-api-complete.ps1 -SkipIsolatedLifecycle
pwsh -NoProfile -File .\scripts\certify-api-complete.ps1 -SkipPublic
pwsh -NoProfile -File .\scripts\certify-api-complete.ps1 -VerboseHttp
```

## Informes y seguridad

Se generan fuera del checkout en Documents, como JSON y Markdown. Incluyen commit, duración, método/ruta/HTTP/request ID y fallos sanitizados. No incluyen password, JWT, cookie, request body ni secreto.

Tras usar una contraseña demo en chat, ticket o captura, considerarla expuesta: rotarla y revocar sesiones.

## Criterio PASS

Inventario/RBAC, ciclo aislado, requests públicas, ausencia de 5xx, login/refresh/logout/CORS, árbol Git limpio e informes sanitizados.
