# Contexto rápido para IA

> Estado: PARCIAL  
> Última revisión: 2026-07-24  
> Fuentes principales: `README.md`, POM, package.json y esta base

Gestudio es un monorepo de gestión educativa/deportiva. Backend Java 21 + Spring Boot 3.5.16 + JPA/Security/Flyway/PostgreSQL; frontend React 18 + TS + Vite. Dominios críticos: alumnos/inscripciones/asistencias, RBAC de 32 permisos, finanzas con vigencias y snapshot en `cargo_liquidaciones`, caja/inventario/reportes.

Reglas: V1–V7 inmutables; RBAC fail-closed; no `-SkipTests`; no secretos/`.env`/backups/dumps/recibos; staging/producción no confirmados; Jere Platform deshabilitada y sin push automático.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope All
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-local.ps1
```

Consultar: backend/API 03,06,08,13,16; frontend 05,07,08,15; datos 04,09,16; seguridad 10,18; operaciones 12,14,17; trazabilidad 22; incertidumbre 21.

Fuente definitiva: código/configuración vigente en `main`.