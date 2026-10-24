# Tareas programadas

> Estado: CONFIRMADO  
> Última revisión: 2026-10-23
> Fuentes principales: `../../backend/src/main/java/gestudio/servicios/ScheduledTasks.java`, `../../backend/src/main/java/gestudio/servicios/pdfs/ReciboStorageService.java`, `../../backend/src/main/resources/application.yml`

## Habilitación

El bean sólo existe cuando:

```text
app.scheduling-enabled=true
```

Variable externa: `APP_SCHEDULING_ENABLED`. Dev/test la mantienen apagada; producción puede habilitarla. Todos los cron usan `${app.time-zone}`.

El worker de recibos usa `app.receipts.worker-enabled`, controlable mediante
`APP_RECEIPTS_WORKER_ENABLED`. Sin override hereda el valor **efectivo** de
`app.scheduling-enabled`, conservando la configuración existente, incluida
producción. Se puede activar sólo recibos con global `false` y worker `true`,
o desactivar recibos con global `true` y worker `false`. Su intervalo es
`APP_RECEIPTS_WORKER_DELAY_MS` (30000 por defecto). Esta selección no habilita
correo: la política de proveedor, dry-run, kill-switch y red sigue separada.
`RuntimeProfilesTest` prueba las combinaciones y el arranque sin envíos.

## Inventario

| Cron real | Método | Servicio | Finalidad |
|---|---|---|---|
| `0 0 0 1 * *` | `generarMensualidadesMesVigente` | `MensualidadServicio` | día 1, 00:00 |
| `0 0 0 1 1 *` | `generarMatriculasAnioVigente` | `MatriculaServicio` | 1 de enero, 00:00 |
| `0 0 1 * * *` | `aplicarRecargosAutomaticos` | `RecargoServicio` | diario, 01:00 |
| `0 0 2 * * *` | `crearAsistenciasParaInscripcionesActivas` | `AsistenciaMensualServicio` | diario, 02:00 |
| `0 0 10 * * *` | `enviarNotificacionesCumpleanios` | `NotificacionService` | diario, 10:00 |

El comentario y el cron del job de cumpleaños están alineados a las 10:00.

## Solapamiento con endpoints manuales

- Mensualidades: `/api/mensualidades/generar-mensualidades`.
- Asistencias: `/api/asistencias-mensuales/crear-asistencias-activos-detallado`.
- Cumpleaños: `/api/notificaciones/cumpleaneros`.

Los servicios deben ser idempotentes porque job y operación manual pueden coincidir.

## Reglas de cambio

- Usar constraints DB para idempotencia, no sólo flags en memoria.
- Probar timezone y fecha civil.
- Considerar ejecución concurrente y reintentos.
- No incluir envío externo dentro de una transacción larga.
- Registrar cantidad/resultado, no datos personales.
- Actualizar este documento, tests y runbook.

## Riesgos

El job de cumpleaños contiene fallos del adaptador y registra sólo tipo/resultado
sanitizado. La deduplicación PostgreSQL evita dos disparos por persona/fecha,
pero no existe lock distribuido ni outbox de cumpleaños; una producción con
múltiples réplicas debe conservar esa garantía o reforzarla según el SLA. Activar
el scheduler nunca habilita email: la política de proveedor se evalúa aparte.
