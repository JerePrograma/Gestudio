# Integraciones

> Estado: PARCIAL  
> Última revisión: 2026-07-24  
> Fuentes principales: `docs/integrations/jere-platform-student-export-v1.md`, backend

## Jere Platform

Exportador `GESTUDIO_STUDENT` incorporado por V7: ID, nombre visible y activo. Deshabilitado por defecto; requiere tenant y secreto independiente; no hace push automático.

Componentes: `gestudio/integraciones/jereplatform/api/StudentSourceExportController` y handler asociado. Receptor multipágina integrado; transporte desplegado Gestudio → Jere Platform PENDIENTE.

## Correo

`spring-boot-starter-mail` está presente. Flujos, timeouts y reintentos PENDIENTES.

## Observabilidad externa

Prometheus local confirmado; servidor, dashboards, alertas y retención PENDIENTES.