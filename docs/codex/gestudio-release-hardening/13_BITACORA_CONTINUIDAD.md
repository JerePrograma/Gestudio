# Bitácora de continuidad postintegración

> Inicio: 2026-07-20  
> Zona horaria: `America/Argentina/Buenos_Aires`  
> Esta bitácora continúa la evidencia histórica de `09_BITACORA_IMPLEMENTACION.md` sin reescribirla.

## 2026-07-20 — reconciliación remota del estado real

### Alcance

- verificar repositorio, rama por defecto y HEAD remoto;
- revisar commits posteriores al cierre local de RBAC;
- inspeccionar estrategia comercial, demo, seed y frontend;
- comparar estado real con índice, etapas y checklist;
- identificar bloqueos falsos, progreso no registrado y evidencia faltante;
- publicar una fuente canónica de continuidad.

### Evidencia GitHub

| Elemento | Resultado |
|---|---|
| Repositorio | `JerePrograma/Gestudio` |
| Rama | `main` |
| Baseline funcional auditado | `3f314ba8cc61a71bfa434a46593cd02336ec16e5` |
| PR abiertos | 0 observados |
| Issues abiertos | 0 observados |
| Status checks del baseline | 0 publicados |
| Workflow runs del baseline | 0 publicados |

### Commits reconciliados

| SHA | Alcance | Estado |
|---|---|---|
| `9093fd4d` | cierre documental RBAC y próximos gates | Integrado |
| `888dacd9` | merge del endurecimiento del seed demo | Integrado |
| `f983f94d` | estrategia comercial canónica | Integrado |
| `e8b603f6` | entorno demo y validación del seed | Integrado |
| `3f314ba8` | tablas y pantallas de gestión | Baseline funcional auditado |

### Hallazgos

1. `00_INDEX.md`, `03_ETAPA_1_SEGURIDAD_RBAC.md`,
   `04_ETAPA_1B_LIQUIDACION_FINANCIERA.md`,
   `10_DECISIONES_Y_BLOQUEOS.md` y `11_CHECKLIST_RELEASE.md` conservaban estados
   anteriores al merge de RBAC.
2. GATE-1 ya no está pendiente de PR o merge.
3. GATE-1B quedó habilitado para comenzar desde `main`.
4. La estrategia comercial es canónica y contiene la grilla de precios vigente.
5. El seed y el lanzador demo están integrados, pero no existe evidencia publicada
   de una corrida completa sobre el baseline funcional auditado.
6. Las mejoras UX del último commit funcional son reales pero parciales.
7. La API de GitHub no expuso checks ni workflow runs asociados al baseline.

### Decisiones

- Mantener `NO-GO` para staging y producción.
- Considerar GATE-1 `DONE / INTEGRADO`.
- Considerar GATE-1B `READY_TO_START`.
- Mantener demo interna `BLOCKED` hasta una corrida reproducible.
- No inferir que un script integrado fue ejecutado.
- No iniciar cambios financieros sin tests de caracterización.
- Centralizar el nuevo estado en `12_ESTADO_ACTUAL_Y_BACKLOG.md`.

### Archivos de continuidad

- `12_ESTADO_ACTUAL_Y_BACKLOG.md` — estado, alcance, progreso, backlog, riesgos y gates.
- `13_BITACORA_CONTINUIDAD.md` — cronología posterior a la bitácora histórica.
- `00_INDEX.md` — tablero reconciliado.
- `03_ETAPA_1_SEGURIDAD_RBAC.md` — cierre integrado de GATE-1.
- `04_ETAPA_1B_LIQUIDACION_FINANCIERA.md` — etapa desbloqueada.
- `10_DECISIONES_Y_BLOQUEOS.md` — decisiones y bloqueos vigentes.
- `11_CHECKLIST_RELEASE.md` — checklist vigente.
- `14_AUDITORIA_TECNICA_E1B.md` — alcance técnico exacto del siguiente gate.
- `README.md` — acceso a la documentación canónica.

### Validaciones ejecutadas durante esta revisión

No se ejecutaron suites de aplicación, Docker ni smoke desde el entorno de
revisión. La revisión fue remota y documental sobre GitHub. Esta limitación se
registra deliberadamente para no convertir inspección estática en evidencia de
ejecución.

## 2026-07-20 — publicación documental directa en `main`

### Commits publicados

| SHA | Cambio |
|---|---|
| `c1b2c361` | estado actual y backlog maestro |
| `3f48b461` | inicio de bitácora de continuidad |
| `c336c43e` | tablero maestro reconciliado |
| `f0bd8169` | Etapa 1B habilitada |
| `3385bafe` | checklist de release vigente |
| `bff17dd4` | README actualizado a Gestudio |
| `fa08da15` | GATE-1 marcado cerrado e integrado |
| `6ba2a509` | decisiones y bloqueos reconciliados |
| `47eb116a` | auditoría técnica detallada de GATE-1B |

Todos se publicaron directamente sobre `main`, conforme al flujo operativo
vigente. Son cambios documentales; no modifican Java, TypeScript, SQL ni Flyway.

### Hallazgos técnicos adicionales de GATE-1B

- `MensualidadServicio` sigue leyendo `Inscripcion.costoParticular`,
  `Disciplina.valorCuota` y `Bonificacion` legacy.
- `MatriculaServicio` sigue leyendo `Disciplina.matricula` y elige el máximo sin
  dejar origen trazado.
- `LiquidacionCargoServicio` existe, pero no tiene caller productivo.
- `CargoServicio` ya provee idempotencia por origen y debe reutilizarse.
- `cargo_liquidaciones` ya tiene PK, FK, importes, origen y fórmula suficientes;
  no se justifica V7 por la información auditada.
- la tarifa ausente debe fallar;
- la condición ausente es válida, aunque el método público actual sea estricto;
- el recargo automático es un cargo tardío separado y no debe sumarse al cargo
  inicial durante GATE-1B;
- el request manual de mensualidad conserva una bonificación ad hoc incompatible
  con la nueva fuente única y debe retirarse o rechazarse explícitamente.

### Decisión de implementación

No se publicaron cambios financieros sin ejecución local. El siguiente cambio
de código debe comenzar con tests PostgreSQL de caracterización y seguir el
alcance de `14_AUDITORIA_TECNICA_E1B.md`.

### Próxima entrada obligatoria

Registrar la ejecución de:

1. Backend;
2. Frontend;
3. `Scope All`;
4. smoke canónico;
5. `validate-demo-seed.ps1`;
6. demo persistente y recorridos por rol;
7. tests de caracterización E1B cuando se inicie código.

La entrada debe incluir HEAD, versiones, comandos, exit codes, conteos, fallos,
recursos residuales y decisión de gate.
