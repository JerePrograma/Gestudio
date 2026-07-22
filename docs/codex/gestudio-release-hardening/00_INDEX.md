# Índice de hardening de Gestudio

Los documentos 01–22 son bitácoras históricas de sus respectivos cortes. El
estado vigente del release está en:

1. [Cierre técnico 2026-07-22](23_CIERRE_RELEASE_2026-07-22.md)
2. [Estado y traspaso](../../project-status-and-handoff.md)
3. [Checklist de release](11_CHECKLIST_RELEASE.md)
4. [Estado y riesgos](12_ESTADO_ACTUAL_Y_BACKLOG.md)

## Estado vigente

| Superficie | Estado local 2026-07-22 |
|---|---|
| Backend Java 21 / Spring Boot | 203 pruebas; 0 fallos; 0 errores |
| Frontend React/TypeScript | 149 pruebas + 2 contratos Nginx; build verde |
| Flyway | V1-V7 integradas, contiguas e inmutables |
| Demo | 914 filas, cinco roles, RBAC e idempotencia |
| Navegador | cinco roles, escritorio/móvil y logout UI |
| Smoke | 20/20 |
| Observabilidad | 8/8 |
| Backup/restore | 12/12 en PS 7 y PS 5.1 |
| Rollback de aplicación | 8/8 en PS 7 y PS 5.1 |
| Docker | imágenes no-root, config y build sin cache |

El SHA publicado y los enlaces de GitHub Actions pertenecen al informe externo
del release. No se usan placeholders ni se intenta auto-referenciar el commit.

## Runbooks vigentes

- [Desarrollo local](../../development/local-development.md)
- [Variables](../../development/environment-variables.md)
- [Operación local](../../operations/local-runbook.md)
- [Observabilidad](../../operations/observability.md)
- [Backup/restore](../../operations/backup-restore.md)
- [Rollback](../../operations/rollback.md)
- [Demo](../../testing/demo-local.md)
- [Seed](../../testing/demo-seed.md)
- [Recorrido por rol](../../testing/human-role-walkthrough.md)

Staging y producción requieren aprobación independiente y evidencia del ambiente;
el repositorio no los declara desplegados.
