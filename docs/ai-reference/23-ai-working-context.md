# Contexto compacto para IA

> Estado: CONFIRMADO  
> Última revisión: 2026-08-13
> Fuentes principales: síntesis de la base documental, código e issues vigentes

## Sistema

Gestudio es un monorepo y monolito modular para academia: alumnos, profesores, disciplinas, inscripciones, asistencia, tarifas, condiciones, matrículas, mensualidades, cargos, pagos, crédito, caja, egresos, stock, recibos, reportes, notificaciones y RBAC.

El sistema distingue dos scopes no intercambiables: TENANT para operación
funcional y PLATFORM para el control plane SUPERADMIN. PLATFORM usa
`platform_admins`, MFA/step-up, sesiones/cookie propias y un datasource
PostgreSQL dedicado sin `SUPERUSER`/`BYPASSRLS`. Fresh usa B12 sin seed
funcional; upgrades V1-V11 aplican V12 de forma preservativa. Antes de actuar,
leer el `GESTUDIO_FINALIZACION_SUPERADMIN_MEGAPROMPT.md` raíz.

## Stack

- Backend Java 21 / Spring Boot 3.5.16 / Maven / PostgreSQL / JPA / Flyway.
- Frontend React 18 / TypeScript 5.6 / Vite 6.
- Docker Compose, PowerShell, Actuator/Prometheus.

## Fuentes de verdad

`AGENTS.md` → código/config/migraciones/pruebas → docs operativas → `docs/ai-reference`. `.kiro` es histórica.

## Rutas esenciales

- Seguridad: `backend/.../infra/seguridad`.
- API: `controladores`, `tarifas/api`, `integraciones/jereplatform/api`.
- Dominio: `servicios`, `entidades`, `repositorios`.
- Migraciones: `backend/src/main/resources/db/migration`.
- UI/router: `frontend/src/rutas/routes.ts`.
- Validación: `scripts/codex`, `smoke-local.ps1`, `certify-api-complete.ps1`.

## Contratos críticos

- 146 mappings API inventariados dinámicamente.
- 32 rutas UI declaradas.
- 32 permisos.
- Toda función: `PERM_APP_ACCESO` + permiso funcional.
- `/api/**` no declarado: deny.
- Access JWT + refresh cookie HttpOnly/rotativa.
- Flyway forward-only; migraciones publicadas inmutables.
- Dinero con `BigDecimal`.
- No borrar historia: usar baja/anulación/reversión.
- Tarifas/condiciones por vigencia y snapshot de cargo.
- Frontend no calcula la verdad financiera.
- Respuestas paginadas públicas mediante `PageResponse<T>`; no exponer `PageImpl`.
- Jere exporta sólo ID/nombre/activo, sin push automático.

## Comandos

```powershell
git status --short --branch
git fetch origin
git switch main
git pull --ff-only origin main
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope All
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-local.ps1
```

No `-SkipTests`, reset hard, clean destructivo, force push ni secretos.

## Riesgos inmediatos

Producción no acreditada ([#23](https://github.com/JerePrograma/Gestudio/issues/23)); observabilidad externa pendiente ([#24](https://github.com/JerePrograma/Gestudio/issues/24)); transporte Jere no desplegado ([#25](https://github.com/JerePrograma/Gestudio/issues/25)); majors frontend diferidos ([#26](https://github.com/JerePrograma/Gestudio/issues/26)); observaciones denegadas; cron cumpleaños comentario/valor inconsistente; GET notificaciones con side effect; SMTP/IMAP no atómico; permisos reservados; respuestas legacy no paginadas.

## Consulta por tarea

- Backend/API: 03, 06, 08, 10, 13, 16.
- Frontend: 07, 08, 25.
- DB: 04, 09, 16.
- Seguridad: 10, 18, 25.
- Operación: 12, 14, 17, 27, 28.
- Jobs: 26.
- Megaprompt Codex: este documento + 16 + 18 + 21.

## Regla de trabajo

Antes de cambiar: confirmar HEAD/main limpio, localizar símbolos reales y consumidores, preservar contratos, aplicar cambio mínimo, validar con comandos del repo, revisar diff y publicar sin fuerza.
