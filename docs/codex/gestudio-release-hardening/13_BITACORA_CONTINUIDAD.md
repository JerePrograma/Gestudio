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

<!-- GATE1B-CIERRE-2026-07-20 -->
## 2026-07-20 — Implementación y validación de GATE-1B

- HEAD inicial real de `main`: `15481e38f0cf714607d0f7d5c3279a46315d7b5d`.
- HEAD funcional previo: `3f314ba8cc61a71bfa434a46593cd02336ec16e5`; los once commits posteriores eran documentales.
- rama excepcional: `agent/gate-1b-liquidacion-vigencia`.
- PR excepcional: `#13`.
- motivo: entorno local sin resolución DNS a GitHub, Docker ni PowerShell; `main` se mantuvo intacta durante implementación.
- entorno local: Git 2.47.3, Java/Javac 21.0.10, Node 22.16.0, npm 10.9.2; suites locales `NO_EJECUTADO`.
- runner: Ubuntu 24.04.4, Git 2.54.0, Java/Javac 21.0.11, Maven Wrapper 3.9.9, Node 22.14.0, npm 10.9.2, Docker 28.0.4, Compose 2.38.2, PowerShell 7.5.2.
- archivos funcionales inspeccionados/modificados: servicios de mensualidad, matrícula, inscripción, tarifas, snapshots; DTO/API; formularios de inscripción y disciplina; suites PostgreSQL; scripts de validación, smoke y seed.
- decisión: tarifa obligatoria por vigencia; condición opcional; fórmula única; snapshot atómico; matrícula por mayor importe final con desempate por menor ID de inscripción; campos legacy rechazados y retirados de UI.
- baseline reproducido: 129 tests, 128 PASS, 1 FAIL por fixture de stock no reconciliable; fixture corregido sin debilitar auditoría.
- backend final previo al cierre documental: 149 tests, 149 PASS, 0 fallos, 0 errores, 0 omitidos; 54.655 s acumulados.
- frontend: 142 tests PASS, lint PASS, build PASS.
- Scope All: PASS, incluido `docker compose config --quiet`.
- smoke: 20 pasos PASS, 0 fallos, 00:03:19, V1-V6/RBAC/integridad/reinicio/limpieza PASS, sin residuos Docker.
- seed: PASS en primera y segunda aplicación, snapshot idéntico, 5/5 logins, denegaciones esperadas, Profesor no asignable, 32 permisos estables, duración 130.2 s, sin residuos Docker.
- migraciones: V1-V6 sin cambios; no se creó V7.
- commit de implementación previo al cierre documental: `faa9418eba896a6be49930873afa3dcc4b41d7b6`.
- documento de evidencia detallada: `15_CIERRE_GATE_1B_2026-07-20.md`.
- riesgo residual: recorridos humanos, GATE-2, backup/restore, rollback, observabilidad, staging y producción.
- decisión global: GATE-1B PASS técnico; GATE-2 abierto; demo comercial/staging/producción NO-GO.

## 2026-07-20 — Integración final de GATE-1B en `main`

- PR `#13` fusionado mediante merge commit para preservar los commits temáticos.
- merge SHA: `23546e025177ff810944808d468a60b91cf621eb`.
- HEAD validado previo al merge: `37168b05426e6704d911d0685484443fbfabc4de`.
- workflows sobre el HEAD validado: `GATE-1B validation` PASS y `CI Gestudio` PASS.
- Backend final: 149/149 tests, `clean verify` PASS, exit code 0, total Maven `01:02 min`.
- Frontend final: 142/142 tests, lint PASS, build PASS, exit code 0.
- Scope All: backend, frontend y `docker compose config --quiet` PASS, exit code 0.
- smoke final: 20/20 pasos, 0 fallos, `00:03:08`, exit code 0.
- seed final: primera y segunda aplicación PASS con snapshot idéntico, 5/5 logins, `138.6 s`, exit code 0.
- recursos Docker residuales de smoke y seed: ninguno.
- revisiones e hilos pendientes del PR al fusionar: ninguno.
- no se desplegó; no se usaron bases reales; staging y producción continúan `NO-GO`.
