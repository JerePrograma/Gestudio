# Gestudio release hardening — tablero maestro

> Última actualización: 20 de julio de 2026  
> Rama operativa: `main`  
> Estado global: **NO-GO para demo comercial, staging y producción**

## Estado ejecutivo

| Campo | Estado vigente |
|---|---|
| Seguridad/RBAC | GATE-1 cerrado y revalidado |
| Liquidación financiera | GATE-1B cerrado técnicamente |
| Flyway | V1-V7 integradas e inmutables |
| Demo automatizada | PASS |
| Demo humana | pendiente |
| Integración Jere Platform | source integrada; end-to-end bloqueado externamente |
| Backup técnico | PASS |
| Restore aislado | PASS |
| Rollback backend | PASS técnico |
| Observabilidad | siguiente gate operativo |
| GATE-2 UX | abierto |
| Staging | NO-GO |
| Producción | NO-GO |

La fuente operativa vigente es [12_ESTADO_ACTUAL_Y_BACKLOG.md](12_ESTADO_ACTUAL_Y_BACKLOG.md).

## Fuentes canónicas

1. [Baseline y hallazgos](01_BASELINE_Y_HALLAZGOS.md)
2. [Matriz RBAC](02_MATRIZ_RBAC.md)
3. [Etapa 1 — Seguridad/RBAC](03_ETAPA_1_SEGURIDAD_RBAC.md)
4. [Etapa 1B — Liquidación financiera](04_ETAPA_1B_LIQUIDACION_FINANCIERA.md)
5. [Etapa 2 — UX operativa](05_ETAPA_2_UX_OPERATIVA.md)
6. [Etapa 3 — Componentes y contratos](06_ETAPA_3_COMPONENTES_Y_CONTRATOS.md)
7. [Etapa 4 — Demo y publicación](07_ETAPA_4_DEMO_Y_PUBLICACION.md)
8. [Plan de pruebas](08_PLAN_DE_PRUEBAS.md)
9. [Bitácora histórica](09_BITACORA_IMPLEMENTACION.md)
10. [Decisiones y bloqueos](10_DECISIONES_Y_BLOQUEOS.md)
11. [Checklist vigente](11_CHECKLIST_RELEASE.md)
12. [Estado y backlog](12_ESTADO_ACTUAL_Y_BACKLOG.md)
13. [Bitácora de continuidad](13_BITACORA_CONTINUIDAD.md)
14. [Auditoría GATE-1B](14_AUDITORIA_TECNICA_E1B.md)
15. [Cierre GATE-1B](15_CIERRE_GATE_1B_2026-07-20.md)
16. [Cierre V7, backup y restore](16_CIERRE_BACKUP_RESTORE_Y_V7_2026-07-20.md)
17. [Cierre rollback forward-compatible](17_CIERRE_ROLLBACK_FORWARD_COMPATIBLE_2026-07-20.md)

## Runbooks

- [Puesta en marcha y flujo de uso](../../operations/local-runbook.md)
- [Backup y restore](../../operations/backup-restore.md)
- [Rollback de aplicación](../../operations/rollback.md)
- [Desarrollo local](../../development/local-development.md)
- [Demo persistente](../../testing/demo-local.md)
- [Dataset demo](../../testing/demo-seed.md)
- [Integración Jere Platform](../../integrations/jere-platform-student-export-v1.md)

## Evidencia vigente

- backend: 162/162 PASS;
- frontend: 142/142 PASS;
- lint/build/imágenes: PASS;
- Scope All, smoke V1-V7 y seed doble: PASS;
- backup/restore: PASS;
- rollback actual → anterior compatible → actual: PASS;
- datos y Flyway V7 preservados;
- recursos residuales: ninguno.

## Reglas operativas

- V1-V7 son inmutables y forward-only.
- Un artefacto rollback debe contener exactamente las migraciones aplicadas.
- No usar tags mutables como única referencia operativa.
- `PROFESOR` permanece inactivo.
- 401, 403 y 409 mantienen semánticas distintas.
- STOMP permanece retirado.
- campos financieros legacy fuera de operación.
- emisor V7 apagado por defecto.
- backups, dumps, recibos y secretos fuera de Git.
- un gate verde no autoriza staging ni producción.

## Orden siguiente

1. integrar cierre de rollback;
2. cerrar observabilidad mínima;
3. completar GATE-2 y recorridos humanos;
4. definir políticas de backup, artefactos y secretos;
5. obtener staging;
6. repetir gates en staging;
7. evaluar producción sólo con autorización independiente.

## Decisión

**Desarrollo y validación local: GO.**  
**Demo comercial, staging y producción: NO-GO.**
