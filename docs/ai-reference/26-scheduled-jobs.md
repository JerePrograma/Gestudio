# Tareas programadas

> Estado: CONFIRMADO  
> Última revisión: 2026-07-24  
> Fuentes principales: `../../backend/src/main/java/gestudio/servicios/ScheduledTasks.java`

## Habilitación

El bean sólo existe cuando:

```text
app.scheduling-enabled=true
```

Variable externa: `APP_SCHEDULING_ENABLED`. Dev/test la mantienen apagada; producción puede habilitarla. Todos los cron usan `${app.time-zone}`.

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
