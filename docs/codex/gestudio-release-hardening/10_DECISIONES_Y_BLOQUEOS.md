# Decisiones y bloqueos

> Última revisión: **2026-07-20**  
> Rama operativa: `main`  
> Estado global: **desarrollo local habilitado; demo interna, demo comercial, staging y producción en `NO-GO`**

[Índice](./00_INDEX.md) · [Estado actual](./12_ESTADO_ACTUAL_Y_BACKLOG.md) · [Checklist](./11_CHECKLIST_RELEASE.md) · [Bitácora de continuidad](./13_BITACORA_CONTINUIDAD.md)

## Regla de interpretación

Una recomendación no equivale a una decisión. Una implementación integrada no
equivale a una prueba ejecutada sobre el HEAD actual. Una suite verde no
autoriza staging o producción.

Estados:

- `TOMADA`: contrato funcional o técnico definido;
- `VALIDADO`: existe evidencia ejecutada identificada;
- `DEFERRED`: decisión consciente de no incluir;
- `PENDING`: falta definición, evidencia o ejecución;
- `BLOCKED`: no puede continuar sin una condición concreta;
- `CERRADO`: el bloqueo dejó de existir.

## Resumen

| ID | Estado vigente | Efecto actual |
|---|---|---|
| `DEC-RBAC-001` | `TOMADA / INTEGRADA` | Catálogo de 32 permisos y matrices base en V6 |
| `DEC-DB-001` | `TOMADA / VALIDADA` | V1-V6 inmutables; cambios futuros forward-only |
| `DEC-OWNERSHIP-001` | `TOMADA / DEFERRED SAFE` | `PROFESOR` inactivo, sin permisos y no asignable |
| `DEC-WS-001` | `TOMADA / INTEGRADA` | STOMP retirado; REST/email permanecen |
| `DEC-PRICING-001` | `TOMADA / READY_TO_IMPLEMENT` | GATE-1B puede comenzar desde `main` |
| `DEC-OBS-001` | `TOMADA / DEFERRED` | Observaciones sin superficie activa |
| `DEC-ENV-001` | local `TOMADA`; externo `PENDING` | Scripts versionados gobiernan local; staging requiere definición |
| `DEC-RELEASE-001` | `TOMADA: NO-GO EXTERNO` | Demo y despliegues requieren gates y autorización separados |

## Decisiones

### DEC-RBAC-001 — Matriz base de roles y permisos

**Decisión:** conservar los 15 códigos preexistentes y agregar exactamente 17
permisos funcionales, para un catálogo total de 32.

Matriz:

- `SUPERADMIN`: 32;
- `DIRECCION`: 31, sin `PERM_ROLES_ADMIN`;
- `ADMINISTRADOR`: 31, por compatibilidad;
- `SECRETARIA`: 17;
- `CAJA`: 8;
- `PROFESOR`: 0, inactivo y no asignable.

Reglas:

- no hay bypass por rol;
- backend es autoridad;
- `/api/**` exige acceso general y permiso funcional;
- rutas no inventariadas se deniegan;
- roles personalizados y asignaciones no canónicas se preservan;
- el seed demo no configura RBAC productivo.

**Estado:** `TOMADA / INTEGRADA`. GATE-1 está cerrado.

### DEC-DB-001 — Cadena Flyway y cambios forward-only

**Decisión:** V1-V6 son la cadena productiva conocida y permanecen inmutables.
V6 contiene catálogo y matrices RBAC.

Consecuencias:

- no editar una migración aplicada;
- cualquier corrección requiere una versión posterior libre;
- probar base vacía y upgrade desde la versión anterior;
- incluir precondiciones, reconciliación y verificación;
- no usar `gestudio_demo_seed_full.sql` como migración;
- no borrar historia financiera o de seguridad para “normalizar”.

**Estado:** `TOMADA / VALIDADA HISTÓRICAMENTE`.

### DEC-OWNERSHIP-001 — Rol Profesor

**Decisión:** primera release con `PROFESOR` presente pero:

- `activo=false`;
- sin permisos;
- no asignable;
- sin rutas ni acciones visibles.

Sólo puede reabrirse después de implementar y probar:

`principal → usuario → profesor → disciplinas → alumnos/asistencias`.

La prueba obligatoria usa dos profesores y demuestra acceso cruzado denegado.

**Estado:** `TOMADA / DEFERRED SAFE`.

### DEC-WS-001 — WebSocket y notificaciones

**Decisión:** retirar STOMP/SockJS de la primera release y mantener REST/email.

Reintroducir tiempo real exige:

- URL y protocolo por ambiente;
- origins explícitos;
- autenticación de handshake;
- autorización por destino;
- aislamiento por usuario;
- pruebas de seguridad propias.

**Estado:** `TOMADA / INTEGRADA`.

### DEC-PRICING-001 — Liquidación por vigencia

**Decisión funcional aprobada:**

| Tema | Contrato |
|---|---|
| Fecha mensual | Primer día del `YearMonth` |
| Fecha matrícula | 1 de enero |
| Sin tarifa | Rechazar; sin fallback legacy |
| Prioridad | Costo particular efectivo no nulo; si no, tarifa efectiva |
| Bonificación | Snapshots de condición efectiva |
| Historia | Última fila `vigenteDesde <= fecha` |
| Legacy | Compatibilidad física; fuera de cálculo/edición |
| Fórmula | `formula_version = 1` |
| Matrícula multidisciplina | Máximo importe efectivo entre disciplinas activas |

La condición económica puede estar ausente; en ese caso se usa la tarifa sin
descuento. La ausencia de tarifa bloquea la liquidación.

**Estado:** `TOMADA / READY_TO_IMPLEMENT`. El bloqueo por RBAC terminó; comenzar
por `E1B-001` y tests de caracterización.

### DEC-OBS-001 — Observaciones de profesores

**Decisión:** conservar tabla, entidad y datos históricos, pero excluir la
función de la primera release.

No habilitar hasta definir:

- necesidad comercial;
- permiso dedicado;
- privacidad;
- ownership;
- endpoints y contratos coherentes;
- pruebas de acceso propio y cruzado.

**Estado:** `TOMADA / DEFERRED`.

### DEC-ENV-001 — Entorno y mutaciones externas

**Decisión local:**

- `scripts/codex/setup.ps1` y `scripts/codex/validate.ps1` son el contrato
  versionado;
- no editar manualmente configuración autogenerada como fuente de verdad;
- setup no inicia Docker ni acredita salud;
- Docker y servicios se ejecutan conscientemente;
- no usar una base real o `localhost:5432` para pruebas destructivas.

**Decisión externa:** staging y producción requieren host, dominio, TLS,
secretos, responsables, datos permitidos, ventana, backup/restore y rollback.

**Estado:** local `TOMADA`; externo `PENDING / NO-GO`.

### DEC-RELEASE-001 — Estado de salida

Se distinguen cinco decisiones:

| Salida | Estado |
|---|---|
| Continuar desarrollo y validación local | `GO` |
| Demo interna | `NO-GO` hasta validación y recorridos |
| Demo comercial | `NO-GO` hasta demo interna aprobada |
| Staging | `NO-GO` hasta ambiente, restore, rollback y autorización |
| Producción | `NO-GO` hasta todos los gates y autorización final |

Un build, commit o smoke aislado no cambia estas decisiones.

## Bloqueos

### BLK-001 — Autoridad para matriz RBAC

**Estado:** `CERRADO` el 2026-07-14.

La matriz fue aprobada, implementada, validada históricamente e integrada.

### BLK-002 — Suite frontend roja del baseline

**Estado:** `CERRADO` el 2026-07-14.

Los tres fallos preexistentes fueron corregidos; la evidencia histórica terminó
en 21 archivos/140 tests, lint y build verdes.

### BLK-003 — Integración remota RBAC

**Estado:** `CERRADO`.

La documentación histórica hablaba de un PR y merge pendientes. Los cambios ya
forman parte de `main`; GATE-1B está habilitado.

### BLK-004 — Evidencia actual del demo

**Estado:** `BLOCKED POR EJECUCIÓN`.

El seed, validador y lanzador persistente existen en `main`, pero no se registró
una corrida completa sobre el HEAD actual.

Condición de cierre:

- Backend, Frontend y All con exit codes;
- smoke canónico;
- `validate-demo-seed.ps1`;
- segunda ejecución idéntica;
- sin recursos Docker residuales;
- cinco logins y matriz representativa 200/400/401/403;
- entrada en la bitácora de continuidad.

### BLK-005 — Doble fuente financiera

**Estado:** `ABIERTO / TÉCNICO`.

Mensualidades y matrículas todavía consumen campos legacy, mientras tarifas,
condiciones y `cargo_liquidaciones` existen sin integración completa.

Condición de cierre: completar `E1B-001..007` y GATE-1B.

### BLK-006 — Ambiente externo y operación

**Estado:** `BLOCKED`.

Faltan:

- host y dominio;
- TLS y CORS;
- secretos;
- responsables y ventana;
- política y automatización de backup;
- restore aislado;
- artefacto anterior;
- rollback ensayado;
- health, métricas, alertas y runbook;
- autorización explícita.

No bloquea desarrollo local ni GATE-1B. Bloquea staging y producción.

## Próximas acciones

1. ejecutar y registrar validaciones del HEAD actual;
2. corregir cualquier fallo del demo;
3. iniciar `E1B-001`;
4. cerrar GATE-1B;
5. completar UX crítica;
6. aprobar demo interna;
7. definir y ensayar staging;
8. considerar producción sólo con autorización.

El cambio de cualquier decisión debe actualizar este documento,
[12_ESTADO_ACTUAL_Y_BACKLOG.md](./12_ESTADO_ACTUAL_Y_BACKLOG.md),
[11_CHECKLIST_RELEASE.md](./11_CHECKLIST_RELEASE.md) y
[13_BITACORA_CONTINUIDAD.md](./13_BITACORA_CONTINUIDAD.md).

<!-- GATE1B-DECISIONES-2026-07-20 -->
## Decisiones incorporadas — 20 de julio de 2026

1. **Rama/PR excepcional**: se autorizó `agent/gate-1b-liquidacion-vigencia` y PR `#13` porque el entorno local no podía clonar GitHub ni ejecutar Docker/PowerShell. `main` quedó protegido hasta obtener evidencia.
2. **Desempate de matrícula**: menor ID de inscripción después de comparar `importeFinal` descendente.
3. **Compatibilidad API**: campos legacy permanecen temporalmente para deserialización, pero todo valor no nulo se rechaza; no hay pérdida silenciosa de intención.
4. **Disciplina nueva**: se crea la ficha y se redirige a Tarifas para cargar una vigencia explícita; los importes legacy no se presentan como fuente efectiva.
5. **Sin migración nueva**: V1-V6 cubren el snapshot requerido; no existe necesidad material para V7.
6. **NO-GO sostenido**: cierre de GATE-1B no habilita demo comercial, staging ni producción.
