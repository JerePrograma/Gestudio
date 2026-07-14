# Mapa de procesos canónicos

## Casos de uso

| Proceso | Desencadenante | Transacción / orquestador | Repositorios y escrituras | Idempotencia / retry | Side effects, duplicados y decisión |
| --- | --- | --- | --- | --- | --- |
| Alta de alumno | `POST /api/alumnos` | `AlumnoServicio` | alumno | unique de datos de negocio/validadores | Un solo servicio. |
| Baja de alumno | `DELETE /api/alumnos/{id}` | `AlumnoServicio.darBajaAlumno` | `alumnos.activo/fecha_de_baja` | repetición conserva la primera fecha | No borra inscripción, asistencia ni finanzas. |
| Inscripción | `POST /api/inscripciones` | `InscripcionServicio.crearInscripcion` | inscripción; mensualidad inicial delegada | unique parcial alumno+disciplina activa; mensualidad unique período | `InscripcionServicio` coordina el alta; `MensualidadServicio` es dueño de la emisión periódica. |
| Baja de inscripción | endpoint DELETE | `InscripcionServicio.eliminarInscripcion` | estado/fecha | operación repetible | No limpia colecciones históricas. |
| Generación mensual | endpoint o cron día 1 | `MensualidadServicio.generarMensualidadesParaMesVigente` | lock ordenado de IDs activos, lectura batch, mensualidad + cargo | unique inscripción+año+mes y unique cargo/mensualidad | Dos ejecuciones simultáneas no duplican; no existe flag de proceso. |
| Matrícula | endpoint o cron anual | `MatriculaServicio.generarMatriculasAnioVigente` | mismo lock de conjunto, agrupación por alumno, matrícula + cargo | unique alumno+año y unique cargo/matrícula | Capacidad integrada en `ScheduledTasks`; ejecución concurrente probada. |
| Cargo por concepto | `POST /api/cargos/concepto` | `CargoServicio.crearPorConcepto` | cargo | `idempotency_key` unique cuando el request la provee | Descripción e importe quedan snapshot; concepto es FK. |
| Recargo | cron diario 01:00 | `RecargoServicio.aplicarRecargosAutomaticos` | cargo de tipo RECARGO | cargo enlaza `cargo_origen_id`; idempotency determinista | Revisa cargos vencidos; no reescribe importe original. |
| Venta de stock | `POST /api/stocks/ventas` | `StockServicio.vender` | venta, proyección stock, movimiento, cargo | key+hash venta; movimiento y cargo derivados con keys/uniques | Una transacción; no identifica producto por descripción. |
| Reversión de venta | `POST /api/stocks/ventas/{id}/reversion` | `StockServicio.revertirVenta` | reverso de stock, proyección, estado venta/cargo | reversal key unique + unique movimiento revertido | Requiere cargo sin aplicaciones; no borra movimientos. |
| Registro de pago | `POST /api/pagos` | `PagoServicio.registrarPago` | pago, aplicaciones, estados cargo, caja, crédito opcional, recibo, outbox | key+hash de pago; locks alumno/cargos ordenados; uniques de movimientos/recibo | Único orquestador financiero. PDF/email no se ejecutan aquí. |
| Aplicación | parte del registro de pago | `PagoServicio` | `aplicaciones_pago`, proyección cargo | unique pago+cargo; validación de saldo bajo lock | No existe endpoint que aplique por otra ruta. |
| Generación de crédito | excedente explícito del pago | `PagoServicio` | `movimientos_credito.GENERACION` | key derivada de pago unique | No hay saldo mutable en alumno. |
| Consumo de crédito | `POST /api/creditos/consumos` | `CreditoServicio.consumir` | movimiento consumo + estado cargo | key unique; lock alumno/cargo; saldo ledger | No modifica importe original. |
| Reversión de crédito | endpoint de reversión | `CreditoServicio.revertirConsumo` | movimiento compensatorio + estado cargo | key y movimiento revertido unique | No edita/borrar movimiento original. |
| Ajuste de crédito | `POST /api/creditos/ajustes` | `CreditoServicio.ajustar` | movimiento ajuste | key unique, motivo obligatorio | Ajuste explícito y auditable. |
| Egreso | `POST /api/egresos` | `EgresoServicio.agregarEgreso` | egreso + movimiento caja | key+hash egreso; key movimiento unique | Una transacción, sin tabla de caja total. |
| Reversión de egreso | `POST /api/egresos/{id}/anulacion` | `EgresoServicio.anular` | movimiento compensatorio + datos anulación | reversal key unique + movimiento revertido unique | No edita el movimiento original. |
| Resumen de caja | `GET /api/caja/resumen` | `CajaServicio` read-only | lee movimientos del período | n/a | Agrega en respuesta; no persiste totales. |
| Generación de recibo | outbox después del commit | `ReciboStorageService.procesarPendientes` | claim corto `SKIP LOCKED`; PDF/storage fuera de lock; confirmaciones cortas | unique pago+tipo/key; lease recuperable; máximo 5 intentos | Documento y trabajo técnico separados. El pago no se revierte por fallo externo. |
| Email de recibo | mismo worker | `ReciboStorageService` / `IEmailService` | `enviado_at`, outbox | un trabajo por pago | No se dispara desde controller ni desde la transacción de pago. Riesgo de crash después de SMTP y antes de commit documentado abajo. |
| Notificación de cumpleaños | cron diario 10:00 | `NotificacionService.generarYObtenerCumpleanerosDelDia` | notificación con `dedup_key` | unique dedup key | Efectos after-commit; email asíncrono y consulta REST. STOMP queda fuera de la primera release. |
| Asistencia mensual/diaria | endpoints y cron 02:00 | `AsistenciaMensualServicio` / `AsistenciaDiariaServicio` | planilla, vínculos, estados diarios | uniques de período/vínculo/fecha | Un scheduler; conserva correcciones lógicas. |

## Flujo financiero detallado

### Pago

1. Calcula hash canónico y resuelve reintento.
2. Bloquea alumno y cargos en orden estable.
3. Valida método, importes, pertenencia, saldo y sobreaplicación.
4. Persiste pago.
5. Persiste aplicaciones y actualiza la proyección de cada cargo.
6. Persiste ingreso de caja.
7. Persiste crédito sólo si el excedente fue solicitado explícitamente.
8. Persiste documento de recibo y un único trabajo técnico.
9. Commit; el worker procesa archivo/email fuera de la transacción financiera.

Ecuación:

```text
monto_recibido = SUM(aplicaciones APLICADA) + crédito GENERACION neto
```

No existe estado “importe sin aplicar”: si hay excedente debe convertirse en
crédito explícito, o el request se rechaza.

### Reversión de pago

1. Bloquea pago y alumno.
2. Rechaza segunda key de reversión distinta.
3. Bloquea cargos en orden estable.
4. Verifica que el crédito generado no haya sido consumido.
5. Marca aplicaciones revertidas y recalcula estados de cargo.
6. Crea reverso de caja y reversos de crédito.
7. Marca el pago anulado con motivo/fecha/key.
8. Commit único; no borra ni cambia importes originales.

## Consultas y escrituras evitadas

- El listado de pagos ya no ejecuta por fila una consulta de aplicaciones, una
  consulta de saldo por cargo y una consulta de crédito. Es una consulta de
  pagos y un DTO de cuatro campos.
- Se eliminó el `flush()` explícito previo al agregado; JPA AUTO flush cubre la
  dependencia dentro de la transacción.
- La navegación frontend ya no recarga el documento completo ni repite todos
  los requests de bootstrap.
- React Query mantiene una sola cache para pagos, cargos, egresos y métodos; las
  mutaciones invalidan sólo la clave afectada.
- Alumnos, inscripciones, cargos, pagos, caja, egresos y stock limitan cada
  respuesta a una página; el máximo global solicitado es 200.
- Caja calcula ingresos/egresos con una agregación SQL sobre el ledger y sólo
  materializa la página visible de movimientos.

## Riesgos abiertos y límites demostrables

### Evidencia de performance reproducible

`CanonicalQueryPlanPostgreSqlTest` crea 500 alumnos y 20.000 cargos en una base
PostgreSQL 15 efímera, ejecuta `ANALYZE` y mide el listado de pendientes con
`EXPLAIN (ANALYZE, BUFFERS)`. El contrato exige el índice compuesto
`ix_cargos_alumno_pendientes` y 32 filas reales para el alumno objetivo. El plan
anterior, medido sobre el mismo dataset, usó `Bitmap Heap Scan` más `Sort`, 39
buffers y 0,174 ms porque el orden del índice era alumno/estado/vencimiento. El
índice parcial final usa alumno/vencimiento/id y elimina ese ordenamiento. Los
tiempos son evidencia local reproducible, no una predicción de producción. El
plan final fue `Index Only Scan`, 0 heap fetches, 6 buffers y 0,064 ms.

- El worker de recibos evita dos workers simultáneos mediante lock y unique,
  pero SMTP no ofrece idempotencia transaccional con PostgreSQL. Un crash exacto
  después del envío y antes del commit puede repetir el email. Resolverlo exige
  un proveedor con idempotency key o una confirmación externa; no se simula
  exactly-once.
- La proyección de stock tiene reconciliación automática en tests/CI, no un
  reparador operativo. No se ejecuta una corrección silenciosa de datos.
