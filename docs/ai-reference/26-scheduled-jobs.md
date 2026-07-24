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

## Inconsistencia confirmada

El comentario del job de cumpleaños dice 08:00, pero el cron ejecuta 10:00. El código es la verdad operativa hasta que se decida y corrija.

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

El job de cumpleaños atrapa `IOException` y registra error; revisar semántica de otros fallos. No se confirmó un lock distribuido; una producción con múltiples réplicas debe resolver ejecución única o idempotencia fuerte.
