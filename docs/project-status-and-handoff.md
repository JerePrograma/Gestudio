# Estado del proyecto y handoff

> Fecha: 21 de julio de 2026  
> Rama operativa: `main`  
> Estado externo: **NO-GO para demo comercial, staging y producción**

Git/GitHub son autoridad si este documento queda desactualizado. Fuente vigente: `docs/codex/gestudio-release-hardening/12_ESTADO_ACTUAL_Y_BACKLOG.md`.

## Snapshot

| Campo | Valor |
|---|---|
| Baseline continuidad | `15481e38f0cf714607d0f7d5c3279a46315d7b5d` |
| Merge GATE-1B | `23546e025177ff810944808d468a60b91cf621eb` |
| Registro GATE-1B | `ef4f9c31dab9a3dfce43f913177089f80ae0205a` |
| Merge integración V7 | `e1afec960ddeb72d61932a1eb1f4a83a65899540` |
| Merge backup/restore | `57731d7132ae5df19371153cd2f5e1a8d77fc94a` |
| Merge rollback | `2eb9a8442c9a0c329c7ddaea42d3ea5c5827f35c` |
| Merge observabilidad | `7dc07d649a468934f3c099a92e5d32747cf64347` (`#20`) |
| HEAD reconciliado antes de GATE-2 | `db89c3e11056e95417cc093034c821bc3dfdd015` |
| Siguiente gate interno | GATE-2 y recorridos humanos |

## Estado

| Área | Estado |
|---|---|
| RBAC y 32 permisos | integrado/probado |
| Liquidación por vigencia | integrado/probado |
| Flyway V1-V7 | integrado/probado |
| Demo automatizada | PASS histórico; revalidación requerida sobre cada SHA candidato |
| Emisor firmado de estudiantes | integrado, apagado |
| Receptor multipágina Jere Platform | integrado mediante `jere-platform#60`; `#59` cerrado |
| Transporte desplegado Gestudio → Jere Platform | no ejecutado ni autorizado |
| Backup/restore | PASS técnico |
| Rollback backend | PASS e integrado en main |
| Observabilidad source-owned | PASS técnico e integrada en main mediante `#20` |
| Monitoreo/alertas externas | bloqueado por ambiente |
| Demo humana | pendiente |
| GATE-2 | pendiente |
| Staging/producción | no autorizados |

## Evidencia vigente

- backend previo a observabilidad: 162/162 PASS;
- backend con observabilidad: 171 pruebas y regresiones de contexts/slices corregidas;
- frontend: 142/142 PASS;
- lint/build/imágenes: PASS en gates integrados;
- Scope All: PASS después de correcciones;
- smoke V1-V7 y seed doble: PASS en gates integrados y obligatorios sobre cada HEAD final;
- backup/restore: 9 PASS, 0 fallos;
- rollback: 8 PASS, 0 fallos, `00:03:21`;
- observabilidad: 8 PASS, 0 fallos, `00:01:34.3933724`;
- imagen V6 rechazada;
- dato y Flyway V7 preservados;
- Prometheus cerrado sin token y abierto con token exacto;
- request ID y logs sanitizados verificados;
- recursos residuales: ninguno en drills verdes.

Los conteos anteriores son evidencia histórica integrada. No sustituyen workflows verdes sobre un SHA nuevo ni la validación visual humana.

## Operación

Runbooks:

- `docs/operations/local-runbook.md`;
- `docs/operations/backup-restore.md`;
- `docs/operations/rollback.md`;
- `docs/operations/observability.md`.

Scripts:

- `scripts/ops/backup-postgres.ps1`;
- `scripts/ops/restore-postgres.ps1`;
- `scripts/ops/rollback-backend.ps1`;
- `scripts/ops/verify-backup-restore.ps1`;
- `scripts/ops/verify-application-rollback.ps1`;
- `scripts/ops/verify-observability.ps1`.

Workflows permanentes:

- `CI Gestudio`;
- `GATE-1B validation`;
- `Backup restore verification`;
- `Application rollback verification`;
- `Observability verification`.

## Integración Jere Platform

El emisor V7 produce referencias mínimas firmadas y permanece apagado. No realiza transporte automático. El receptor multipágina fue integrado en `JerePrograma/jere-platform` mediante PR `#60`, y el bloqueo técnico `#59` fue cerrado. El issue coordinador `#51` permanece abierto porque también incluye transporte desplegado, Scalaris y requisitos productivos.

No existe evidencia de conexión desplegada Gestudio → Jere Platform. La existencia de emisor y receptor en código no equivale a integración operativa.

## Siguiente trabajo exacto

1. ejecutar los cinco recorridos humanos por rol sobre un SHA exacto;
2. inventariar y corregir únicamente IDs técnicos y estados loading/empty/error reproducibles;
3. validar pagos/caja/egresos/recibos, stock y asistencia con evidencia funcional;
4. validar foco, teclado, labels, contraste y anchos 360, 390, 768 y escritorio;
5. ejecutar backend, frontend, Scope All, smoke y seed después de cada corrección;
6. definir política de backups, artefactos y secretos;
7. proveer Prometheus/storage/dashboard/alertas y responsables;
8. obtener staging y repetir todos los gates;
9. mantener producción en NO-GO.

## Riesgos abiertos

- alertas y retención externas ausentes;
- registry, digest, firma y promoción no definidos;
- política real de backup incompleta;
- secret manager y rotación no demostrados;
- recorridos humanos y GATE-2 pendientes;
- ambiente staging inexistente;
- producción no autorizada;
- transporte Gestudio → Jere Platform no desplegado ni probado end-to-end.

## Restricciones

- no usar bases reales para drills;
- no editar V1-V7;
- no ejecutar down migrations;
- no habilitar Profesor/Observaciones/STOMP;
- no activar V7 como integración productiva;
- no exponer Prometheus sin token y segmentación;
- no registrar cuerpos, cookies, tokens ni secretos;
- no desplegar.
