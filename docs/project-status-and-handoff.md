# Estado del proyecto y handoff

> Fecha: 20 de julio de 2026  
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
| PR rollback | `#19` |
| Siguiente gate | observabilidad mínima |

## Estado

| Área | Estado |
|---|---|
| RBAC y 32 permisos | integrado/probado |
| Liquidación por vigencia | integrado/probado |
| Flyway V1-V7 | integrado/probado |
| Demo automatizada | PASS |
| Emisor firmado de estudiantes | integrado, apagado |
| Backup/restore | PASS técnico |
| Rollback backend | PASS técnico en PR #19 |
| Demo humana | pendiente |
| Observabilidad | pendiente |
| GATE-2 | pendiente |
| Staging/producción | no autorizados |

## Evidencia vigente

- backend: 162/162 PASS;
- frontend: 142/142 PASS;
- lint/build/imágenes: PASS;
- Scope All, smoke V1-V7 y seed doble: PASS;
- backup/restore: 9 PASS, 0 fallos;
- rollback: 8 PASS, 0 fallos, `00:03:21`;
- imagen V6 rechazada;
- dato y Flyway V7 preservados;
- retorno al actual verificado;
- recursos residuales: ninguno.

## Operación

Runbooks:

- `docs/operations/local-runbook.md`;
- `docs/operations/backup-restore.md`;
- `docs/operations/rollback.md`.

Scripts:

- `scripts/ops/backup-postgres.ps1`;
- `scripts/ops/restore-postgres.ps1`;
- `scripts/ops/rollback-backend.ps1`;
- `scripts/ops/verify-backup-restore.ps1`;
- `scripts/ops/verify-application-rollback.ps1`.

## Integración Jere Platform

El emisor V7 produce referencias mínimas firmadas y permanece apagado. No realiza transporte automático. El receptor multipágina sigue bloqueado por `JerePrograma/jere-platform#59`.

## Siguiente trabajo exacto

1. fusionar PR `#19` después de revalidar el HEAD documental final;
2. incorporar Actuator y Prometheus sin exponer detalles sensibles;
3. publicar health, liveness y readiness;
4. agregar correlación `X-Request-ID` y MDC;
5. proteger métricas administrativas;
6. cambiar healthcheck Docker de puerto a readiness HTTP;
7. agregar tests de seguridad y health PostgreSQL;
8. documentar alertas y runbook de incidentes;
9. repetir aplicación, smoke, seed, recovery y rollback;
10. continuar con GATE-2 y recorridos humanos.

## Riesgos abiertos

- observabilidad/alertas ausentes;
- registry, digest, firma y promoción no definidos;
- política real de backup incompleta;
- recorridos humanos y GATE-2 pendientes;
- ambiente staging inexistente;
- producción no autorizada.

## Restricciones

- no usar bases reales para drills;
- no editar V1-V7;
- no ejecutar down migrations;
- no habilitar Profesor/Observaciones/STOMP;
- no activar V7 como integración productiva;
- no desplegar.
