# Riesgos y deuda técnica

> Estado: PARCIAL  
> Última revisión: 2026-07-24  
> Fuentes principales: `README.md`, estado de release y cierres

| Riesgo | Impacto | Prioridad | Acción |
|---|---|---:|---|
| Producción no validada | Alto | Alta | completar staging, TLS, CORS, correo, storage, monitoreo y recuperación |
| Jere Platform no desplegada | Medio/alto | Alta | transporte y smoke autorizado |
| Monitoreo externo ausente | Alto | Alta | servidor, dashboards, alertas y retención |
| Políticas externas no definidas | Alto | Alta | responsables de secretos/backups/logs |
| Rollback incompatible | Alto | Alta | mantener Flyway exacto y forward-only |

## PENDIENTE

Cobertura por módulo, legacy/duplicación, dependencias, matriz rol-permiso y auditoría completa de archivos sensibles.