# Guía de desarrollo

> Estado: CONFIRMADO  
> Última revisión: 2026-07-24  
> Fuentes principales: `../development/local-development.md`, `../../README.md`, scripts

## Requisitos

PowerShell 5.1 o 7, Git 2.x, JDK 21, Maven Wrapper, Node 22 LTS, npm 10.x, Docker Desktop y Compose v2. Python no es requisito de ejecución.

## Preparación

```powershell
git status --short --branch
git fetch origin
git switch main
git pull --ff-only origin main
Copy-Item .env.local.example .env
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\setup.ps1
```

`setup.ps1` valida JDK, resuelve backend y ejecuta `npm ci`; no prueba salud.

## Variables mínimas

Usar perfil `dev`, PostgreSQL local, `ddl-auto=validate`, Flyway activo, timezone Buenos Aires, receipts path local, orígenes CORS locales y schedulers apagados. Consultar [`../development/environment-variables.md`](../development/environment-variables.md). No copiar secretos reales.

## Ejecución separada

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-db.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-backend.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-frontend.ps1
```

Detener infraestructura conservando datos:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\stop.ps1
```

## Compose completo

```powershell
docker compose --env-file .env -p gestudio config
docker compose --env-file .env -p gestudio up -d --build
docker compose --env-file .env -p gestudio ps
docker compose --env-file .env -p gestudio down --remove-orphans
```

No usar `down --volumes` salvo decisión explícita de perder datos.

## Validación canónica

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\status.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope All
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-local.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-demo-seed.ps1
```

No usar `-SkipTests`.

## Validación directa

Backend:

```powershell
Push-Location backend
.\mvnw.cmd clean verify
Pop-Location
```

Frontend:

```powershell
Push-Location frontend
npm ci
npm run lint
npm test
npm run build
npm audit
npm audit --omit=dev
Pop-Location
```

## Demo, manual y certificación

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Start
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\manual\Build-Manual.ps1
pwsh -NoProfile -File .\scripts\certify-api-complete.ps1
```

Detalles en [28-demo-manual-and-certification.md](28-demo-manual-and-certification.md).

## Migraciones

Nunca editar una aplicada. Crear la siguiente versión contigua; validar base limpia, upgrade, constraints y reconciliación.

## Depuración

```powershell
docker compose --env-file .env -p gestudio ps
docker compose --env-file .env -p gestudio logs --tail 200 db backend frontend
```
