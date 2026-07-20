# Etapa 1 — Seguridad y RBAC mínimo publicable

> Estado: **`DONE / INTEGRADO EN MAIN`**  
> Fecha de reconciliación: **2026-07-20**  
> Evidencia de cierre local: **2026-07-14**  
> Rama operativa actual: `main`  
> Gate: **`GATE-1 CERRADO`**

[Índice](./00_INDEX.md) · [Matriz RBAC](./02_MATRIZ_RBAC.md) · [Etapa 1B](./04_ETAPA_1B_LIQUIDACION_FINANCIERA.md) · [Bitácora histórica](./09_BITACORA_IMPLEMENTACION.md) · [Decisiones](./10_DECISIONES_Y_BLOQUEOS.md) · [Checklist](./11_CHECKLIST_RELEASE.md) · [Estado actual](./12_ESTADO_ACTUAL_Y_BACKLOG.md)

## Nota de continuidad

La implementación se desarrolló originalmente en
`feat/rbac-production-hardening` desde el baseline `f6493a3b`. Las referencias
históricas a un PR reemplazante, checks remotos o merge pendiente describen el
momento anterior a la integración. El RBAC ya forma parte de `main`.

La evidencia histórica detallada, comandos y fallos intermedios se conservan en
[09_BITACORA_IMPLEMENTACION.md](./09_BITACORA_IMPLEMENTACION.md). Este documento
expresa el estado operativo vigente y no reescribe esa evidencia.

## Objetivo alcanzado

Gestudio dispone de un RBAC determinístico desde una base limpia, con:

- catálogo productivo de permisos;
- roles y matrices base;
- autorización backend granular y fail-closed;
- semántica HTTP 401/403/409;
- frontend alineado con permisos efectivos;
- bootstrap de SUPERADMIN independiente del seed demo;
- invalidación de acceso por usuario, rol, permiso y `authVersion`;
- `PROFESOR` inactivo hasta demostrar ownership;
- STOMP retirado para la primera release;
- Observaciones sin superficie activa.

## Contrato integrado

### Catálogo y roles

| Rol | Permisos | Estado operativo |
|---|---:|---|
| `SUPERADMIN` | 32 | Activo; matriz completa |
| `DIRECCION` | 31 | Activo; sin administración de roles |
| `ADMINISTRADOR` | 31 | Compatibilidad legacy equivalente a Dirección |
| `SECRETARIA` | 17 | Activo; operación académica y administrativa acotada |
| `CAJA` | 8 | Activo; cobros, caja y funciones aprobadas |
| `PROFESOR` | 0 | Inactivo, no asignable y sin rutas visibles |

Reglas:

- no existe bypass por nombre de rol;
- backend calcula permisos efectivos;
- `PERM_APP_ACCESO` permite entrar, pero no autoriza mutaciones sensibles;
- roles personalizados y asignaciones no canónicas se preservan;
- el seed demo no crea ni modifica el catálogo productivo;
- V6 es forward-only y V1-V5 permanecen inmutables.

### Semántica de seguridad

| Escenario | Resultado |
|---|---|
| Sin autenticación | 401 |
| Autenticado sin permiso | 403 |
| Conflicto real de negocio | 409 |
| Ruta `/api/**` no inventariada | Denegada |
| Usuario, rol o permiso inactivo | Acceso efectivo denegado |
| `authVersion` obsoleta | Sesión invalidada |
| Intento de eliminar/desactivar último SUPERADMIN | Rechazado |

## Tareas de la etapa

| Tarea | Estado | Resultado |
|---|---|---|
| `E1-001` — contrato y constantes | `DONE` | 32 permisos y matrices aprobadas |
| `E1-002` — migración RBAC | `DONE` | V6 base limpia y upgrade V5→V6 |
| `E1-003` — bootstrap utilizable | `DONE` | SUPERADMIN operativo sin seed demo |
| `E1-004` — semántica de autorización | `DONE` | 401/403/409 correctos |
| `E1-005` — endpoints granulares | `DONE` | 144/144 mappings contractualizados |
| `E1-006` — ownership Profesor | `DEFERRED SAFE` | Rol inactivo y no asignable |
| `E1-007` — contrato frontend | `DONE` | sesión, navegación, rutas y permisos alineados |
| `E1-008` — acciones sensibles | `DONE` | mutaciones visibles sólo con permiso |
| `E1-009` — STOMP/notificaciones | `DONE` | canal STOMP retirado; REST/email conservados |
| `E1-010` — suites y smoke | `DONE / INTEGRADO` | backend 129, frontend 140, All y smoke 20/20 |

## Evidencia de cierre

| Alcance | Resultado histórico de cierre |
|---|---|
| Backend focalizado RBAC/PostgreSQL | 51/51 |
| Auditoría PostgreSQL | 7/7 |
| Backend completo | 129/129 |
| Frontend | 21 archivos / 140 tests |
| Lint | PASS |
| Build frontend | 2337 módulos / PASS |
| Validación `Scope All` | PASS |
| Smoke aislado sin seed demo | 20/20 PASS |
| Docker Compose | configuración válida |
| Flyway | V1-V6; checksum V6 registrado |

Esta evidencia cerró la etapa y fue integrada. Antes de una demo interna debe
repetirse sobre el HEAD exacto vigente, porque integración no equivale a una
nueva corrida.

## Decisiones seguras que permanecen vigentes

### Profesor

No habilitar hasta implementar y probar:

`principal → usuario → profesor → disciplinas → alumnos/asistencias`.

La prueba debe usar dos profesores y demostrar acceso propio permitido y acceso
cruzado denegado. Mientras eso no exista, dejarlo inactivo es la única salida
segura.

### STOMP

No reintroducir sin:

- URL por ambiente y protocolo correcto;
- origins explícitos;
- autenticación de handshake;
- autorización por destino;
- aislamiento por usuario;
- pruebas propias.

### Observaciones

Los datos históricos pueden conservarse, pero no se habilitan endpoints, rutas
o acciones hasta definir permiso, privacidad y ownership.

### Migraciones

- V1-V6 son inmutables;
- cualquier corrección futura usa una nueva versión;
- el seed demo nunca sustituye a Flyway;
- rollback de datos requiere restore o reparación forward-only, no edición de
  migraciones aplicadas.

## Revalidación antes de demo interna

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\codex\validate.ps1 -Scope Backend

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\codex\validate.ps1 -Scope Frontend

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\codex\validate.ps1 -Scope All

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\smoke-local.ps1
```

La repetición debe registrar HEAD, versiones, exit codes, conteos, fallos,
limpieza y decisión en
[13_BITACORA_CONTINUIDAD.md](./13_BITACORA_CONTINUIDAD.md).

## GATE-1

- [x] Contrato RBAC aprobado.
- [x] V6 forward-only aplicada desde vacío y desde V5.
- [x] Catálogo y matrices exactos.
- [x] Bootstrap utilizable sin seed demo.
- [x] 401/403/409 correctos.
- [x] Writes sensibles con permiso explícito.
- [x] Delegación sin escalamiento.
- [x] Último SUPERADMIN protegido.
- [x] `PROFESOR` inactivo y no asignable.
- [x] Menú, rutas y acciones alineados.
- [x] STOMP retirado.
- [x] Backend, frontend, All y smoke verdes en cierre histórico.
- [x] Cambios integrados a `main`.

**Resultado: `GATE-1 CERRADO`.**

La siguiente etapa habilitada es
[Etapa 1B — Liquidación financiera por vigencia](./04_ETAPA_1B_LIQUIDACION_FINANCIERA.md).
