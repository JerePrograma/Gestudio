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
| Integración Jere Platform | emisor source-owned integrado; end-to-end bloqueado externamente |
| Backup técnico | PASS |
| Restore aislado | PASS |
| Rollback | siguiente gate operativo |
| Observabilidad | pendiente |
| GATE-2 UX | abierto |
| Staging | NO-GO |
| Producción | NO-GO |

La fuente operativa vigente es [12_ESTADO_ACTUAL_Y_BACKLOG.md](12_ESTADO_ACTUAL_Y_BACKLOG.md). Los documentos anteriores conservan evidencia histórica, pero no deben prevalecer sobre el estado unificado.

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
11. [Checklist de release vigente](11_CHECKLIST_RELEASE.md)
12. [Estado actual y backlog unificado](12_ESTADO_ACTUAL_Y_BACKLOG.md)
13. [Bitácora de continuidad](13_BITACORA_CONTINUIDAD.md)
14. [Auditoría técnica de GATE-1B](14_AUDITORIA_TECNICA_E1B.md)
15. [Cierre de GATE-1B](15_CIERRE_GATE_1B_2026-07-20.md)
16. [Cierre V7, backup y restore](16_CIERRE_BACKUP_RESTORE_Y_V7_2026-07-20.md)

## Runbooks

- [Puesta en marcha y flujo de uso](../../operations/local-runbook.md)
- [Backup y restore](../../operations/backup-restore.md)
- [Desarrollo local](../../development/local-development.md)
- [Demo persistente](../../testing/demo-local.md)
- [Dataset demo](../../testing/demo-seed.md)
- [Integración Jere Platform V1](../../integrations/jere-platform-student-export-v1.md)
- [Estrategia comercial](../../comercial/estrategia-comercial.md)

## Progreso por etapa

| Etapa | Estado | Próxima condición |
|---|---|---|
| GATE-0 — baseline | CERRADO | mantener reproducibilidad |
| GATE-1 — RBAC | CERRADO | no reabrir sin regresión |
| GATE-1B — finanzas | CERRADO TÉCNICAMENTE | recorridos humanos y UX |
| V7 — exportación firmada | INTEGRADA | receptor multipágina externo |
| Demo automatizada | PASS | recorrido humano por cinco roles |
| Backup/restore | PASS TÉCNICO | política de custodia, RPO/RTO y responsables |
| Rollback | ABIERTO | drill forward-compatible |
| Observabilidad | ABIERTO | health, métricas, logs y alertas |
| GATE-2 — UX | PARCIAL | inventario y recorridos exhaustivos |
| Staging | BLOQUEADO | ambiente y gates operativos |
| Producción | NO AUTORIZADA | todos los gates y decisión independiente |

## Evidencia vigente

- backend: 162/162 PASS después de V7;
- frontend: 142/142 PASS;
- lint y build: PASS;
- imágenes backend/frontend: PASS;
- `Scope All`: PASS;
- smoke V1-V7: PASS;
- seed doble: PASS;
- cinco logins demo y matrices RBAC: PASS;
- backup/restore descartable: PASS;
- recursos Docker residuales en gates: ninguno.

## Reglas operativas

- V1-V7 son inmutables; toda corrección es forward-only.
- No ejecutar down migrations como rollback.
- `PROFESOR` permanece inactivo y no asignable.
- 401, 403 y 409 conservan semánticas distintas.
- STOMP permanece retirado.
- Los campos financieros legacy no son fuentes operativas.
- El emisor V7 permanece deshabilitado por defecto.
- Los backups, dumps, recibos y secretos no se versionan.
- Una suite verde no autoriza staging ni producción.
- No se usa una base real para pruebas destructivas.

## Orden de ejecución vigente

1. integrar cierre de backup/restore;
2. probar rollback forward-compatible conservando V7;
3. volver al artefacto actual y verificar datos;
4. cerrar observabilidad mínima;
5. completar recorridos humanos y GATE-2;
6. definir política de backup, secretos y responsables;
7. obtener staging;
8. repetir todos los gates en staging;
9. evaluar producción sólo con autorización explícita.

## Decisión

**Desarrollo y validación local: GO.**  
**Demo comercial, staging y producción: NO-GO.**
