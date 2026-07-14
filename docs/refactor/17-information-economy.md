# Economía de información de la V1 canónica

## Criterio

Este inventario corresponde a `V1__canonical_schema.sql` y al código validado en
este worktree. Cada fila agrupa campos que comparten exactamente clasificación,
fuente y ciclo de actualización; todos los campos persistidos aparecen por
nombre. Las categorías son: **A** fuente de verdad, **B** snapshot histórico,
**C** dato derivado, **D** proyección operativa, **E** transitorio y **F** legado.
Los DTO no se persisten: se indican sólo para identificar el consumidor.

## Identidad, personas y catálogos

| Tabla / entidad | Campos | DTO / consumidor | Clase | Fuente canónica y actualización | Riesgo / decisión |
| --- | --- | --- | --- | --- | --- |
| `roles` / `Rol` | `id`, `descripcion`, `activo` | `RolResponse`; gestión de roles | A | Administración de roles; `RolServicio` | `activo` expresa baja lógica, no duplica otro estado. Mantener. |
| `usuarios` / `Usuario` | `id`, `nombre_usuario`, `contrasena`, `rol_id`, `activo` | `UsuarioResponse`; auth/usuarios | A | Alta/edición de usuario; contraseña sólo hash | Mantener; nunca exponer `contrasena`. |
| `alumnos` / `Alumno` | `id`, `nombre`, `apellido`, `fecha_nacimiento`, `celular1`, `celular2`, `email`, `documento`, `fecha_incorporacion`, `nombre_padres`, `autorizado_para_salir_solo`, `otras_notas` | alumno list/detail/form | A | `AlumnoServicio` | Datos originales; `cuit` se eliminó porque no tenía request, response ni consumidor. |
| `alumnos` / `Alumno` | `activo`, `fecha_de_baja` | alumno detail | A | Una única baja lógica en `AlumnoServicio` | Combinación mínima: constraint exige fecha sólo al inactivar. Mantener. |
| `alumnos` / `Alumno` | `version` | no expuesto | A | JPA optimistic lock | Control técnico de concurrencia, no estado de negocio. |
| `salones` / `Salon` | `id`, `nombre`, `descripcion`, `activo` | `SalonResponse` | A | `SalonServicio` | Catálogo con baja lógica. |
| `profesores` / `Profesor` | `id`, `nombre`, `apellido`, `fecha_nacimiento`, `telefono`, `usuario_id`, `activo`, `version` | `ProfesorResponse` | A | `ProfesorServicio` | Usuario opcional es FK, no texto. |
| `observaciones_profesores` / `ObservacionProfesor` | `id`, `profesor_id`, `fecha`, `observacion`, `activa` | `ObservacionProfesorDTO` | A | `ObservacionProfesorServicio` | `activa` es la única baja lógica. |
| `bonificaciones` / `Bonificacion` | `id`, `descripcion`, `porcentaje_descuento`, `valor_fijo`, `activo`, `observaciones` | bonificaciones/inscripción | A | `BonificacionServicio` | Regla vigente; nunca recalcula cargos históricos. |
| `recargos` / `Recargo` | `id`, `descripcion`, `porcentaje`, `valor_fijo`, `dia_del_mes_aplicacion`, `activo` | recargos/scheduler | A | `RecargoServicio` | Regla vigente; el cargo emitido conserva el resultado. |
| `metodo_pagos` / `MetodoPago` | `id`, `descripcion`, `activo`, `recargo` | métodos/pago | A | `MetodoPagoServicio` | Catálogo vigente. `recargo` es regla, no dinero cobrado. |
| `sub_conceptos` / `SubConcepto` | `id`, `descripcion`, `activo` | conceptos | A | `SubConceptoServicio` | Catálogo. |
| `conceptos` / `Concepto` | `id`, `descripcion`, `precio`, `sub_concepto_id`, `activo` | conceptos/cargo manual | A | `ConceptoServicio` | Precio vigente; `Cargo.importe_original` captura el valor emitido. |
| `stocks` / `Stock` | `id`, `nombre`, `precio`, `requiere_control_de_stock`, `codigo_barras`, `activo`, `version` | `StockResponse` | A | `StockServicio` | Producto y precio vigentes. Venta conserva precio histórico. |
| `stocks` / `Stock` | `cantidad_actual` | `StockResponse`; stock | D | Sólo `StockServicio`, en la misma transacción que `MovimientoStock` | Proyección para lock/lectura; ledger es autoridad. Auditoría `FIN-STOCK-PROYECCION` se ejecuta automáticamente en `clean verify`. No existe segunda ruta de escritura. |

## Oferta, inscripción y asistencia

| Tabla / entidad | Campos | DTO / consumidor | Clase | Fuente canónica y actualización | Riesgo / decisión |
| --- | --- | --- | --- | --- | --- |
| `disciplinas` / `Disciplina` | `id`, `nombre`, `salon_id`, `profesor_id`, `valor_cuota`, `matricula`, `clase_suelta`, `clase_prueba`, `activo`, `version` | `DisciplinaResponse`; disciplina/inscripción | A | `DisciplinaServicio` | Precios vigentes; no reescriben cargos históricos. |
| `disciplina_horarios` / `DisciplinaHorario` | `id`, `disciplina_id`, `dia_semana`, `horario_inicio`, `duracion` | horario de disciplina | A | `DisciplinaHorarioServicio` | Composición editable; único `ON DELETE CASCADE` permitido. |
| `inscripciones` / `Inscripcion` | `id`, `alumno_id`, `disciplina_id`, `bonificacion_id`, `fecha_inscripcion`, `costo_particular`, `version` | `InscripcionResponse` | A | `InscripcionServicio` | Regla de inscripción; costo particular es precio vigente de esa relación. |
| `inscripciones` / `Inscripcion` | `estado`, `fecha_baja` | `InscripcionResponse` | A | Baja/fin en `InscripcionServicio` | Combinación mínima validada por constraint. |
| `mensualidades` / `Mensualidad` | `id`, `inscripcion_id`, `bonificacion_id`, `recargo_id`, `anio`, `mes`, `fecha_generacion`, `fecha_vencimiento`, `estado`, `version` | `MensualidadResponse` | A | `MensualidadServicio`; unique inscripción/período | Origen cobrable e idempotencia natural. |
| `mensualidades` / `Mensualidad` | `descripcion` | cargo/recibo | B | Capturada al generar el período | Snapshot visual; nunca se usa como FK. |
| `matriculas` / `Matricula` | `id`, `alumno_id`, `anio`, `fecha_emision`, `estado`, `version` | `MatriculaResponse` | A | `MatriculaServicio`; unique alumno/año | Origen anual e idempotencia natural. |
| `asistencias_mensuales` / `AsistenciaMensual` | `id`, `disciplina_id`, `mes`, `anio` | asistencia mensual | A | `AsistenciaMensualServicio`; unique disciplina/período | Identidad de planilla. |
| `asistencias_alumno_mensual` / `AsistenciaAlumnoMensual` | `id`, `inscripcion_id`, `asistencia_mensual_id`, `observacion`, `activo` | detalle de asistencia | A | `AsistenciaMensualServicio` | `activo` es corrección lógica del vínculo; no duplica estado diario. |
| `asistencias_diarias` / `AsistenciaDiaria` | `id`, `asistencia_alumno_mensual_id`, `fecha`, `estado`, `vigente` | asistencia diaria | A | `AsistenciaDiariaServicio` | `estado` registra presencia; `vigente` conserva correcciones sin borrar historia. Semánticas distintas. |

## Finanzas, stock y efectos

| Tabla / entidad | Campos | DTO / consumidor | Clase | Fuente canónica y actualización | Riesgo / decisión |
| --- | --- | --- | --- | --- | --- |
| `ventas_stock` / `VentaStock` | `id`, `alumno_id`, `stock_id`, `cantidad`, `fecha`, `idempotency_key`, `request_hash`, `version` | cargo/stock | A | `StockServicio.vender` | Hecho de venta; key+hash separan retry de conflicto. |
| `ventas_stock` / `VentaStock` | `precio_unitario` | cargo/recibo | B | Copiado del producto al vender | Snapshot histórico inmutable. |
| `ventas_stock` / `VentaStock` | `estado`, `reversal_idempotency_key`, `reversal_request_hash` | reversión de venta | A | `StockServicio.revertirVenta` | Estado, clave y contenido de la única reversión. |
| `cargos` / `Cargo` | `id`, `alumno_id`, `tipo`, `fecha_emision`, `fecha_vencimiento`, `mensualidad_id`, `matricula_id`, `concepto_id`, `venta_stock_id`, `cargo_origen_id`, `idempotency_key`, `version`, `created_at` | `CargoResponse`; cobranza/reportes | A | Orquestador del origen vía `CargoServicio`; una FK de origen exacta | Autoridad de la obligación. |
| `cargos` / `Cargo` | `descripcion`, `importe_original` | cobranza/recibo | B | Capturados al emitir | Snapshots históricos inmutables; no identifican entidades. |
| `cargos` / `Cargo` | `estado` | listados operativos | D | `CargoServicio.actualizarEstado` en la misma transacción que aplicaciones/consumos/reversiones | Saldo se deriva de aplicaciones + crédito. Auditorías `STATE-CARGO-*` y test concurrente reconcilian la proyección. |
| saldo de cargo | no existe columna | `CargoResponse.saldo`, `importeAplicado` | C | `importe_original - aplicaciones activas - consumos netos de crédito` | Se calcula; no se persiste. |
| `pagos` / `Pago` | `id`, `alumno_id`, `metodo_pago_id`, `usuario_id`, `fecha`, `monto_recibido`, `observaciones`, `version`, `created_at` | pago detail/summary | A | `PagoServicio.registrarPago` | Dinero recibido y actor originales. |
| `pagos` / `Pago` | `idempotency_key`, `request_hash` | no se expone hash | A | Registro de pago | La unique impide duplicado; hash distingue mismo request de reutilización conflictiva. |
| `pagos` / `Pago` | `estado`, `reversal_idempotency_key`, `reversal_request_hash`, `motivo_anulacion`, `fecha_anulacion` | detalle/lista | A | `PagoServicio.anularPago` | Historia mínima de anulación; constraint impide combinaciones inválidas. |
| total aplicado/crédito de pago | no existe columna equivalente | `PagoResponse.aplicaciones`, `creditoGenerado` | C | Ledger y aplicaciones | Ecuación auditada; no se almacena un segundo total. |
| `aplicaciones_pago` / `AplicacionPago` | `id`, `pago_id`, `cargo_id`, `usuario_id`, `importe_aplicado`, `fecha`, `version`, `created_at` | `AplicacionPagoResponse` | A | `PagoServicio` | Hecho histórico de aplicación. |
| `aplicaciones_pago` / `AplicacionPago` | `estado`, `motivo_reversion`, `fecha_reversion` | detalle de pago | A | Reversión transaccional del pago | Conserva historia sin filas clonadas ni borrado. |
| `egresos` / `Egreso` | `id`, `fecha`, `monto`, `observaciones`, `metodo_pago_id`, `usuario_id`, `version` | `EgresoResponse` | A | `EgresoServicio.agregarEgreso` | Orden de egreso; caja se explica por ledger. |
| `egresos` / `Egreso` | `idempotency_key`, `request_hash`, `estado`, `reversal_idempotency_key`, `reversal_request_hash`, `motivo_anulacion`, `fecha_anulacion` | egreso list/detail | A | Registro/reversión de egreso | Hash distingue reintento de conflicto; estado conserva anulación. |
| `movimientos_caja` / `MovimientoCaja` | todos: `id`, `tipo`, `fecha`, `importe`, `metodo_pago_id`, `pago_id`, `egreso_id`, `movimiento_revertido_id`, `usuario_id`, `idempotency_key`, `motivo`, `created_at` | `MovimientoCajaResponse`, `ResumenCajaResponse` | A | Pago, egreso o ajuste; append-only | Única autoridad de caja. Totales son agregados C, no tablas. |
| `movimientos_credito` / `MovimientoCredito` | todos: `id`, `alumno_id`, `tipo`, `importe`, `pago_id`, `cargo_id`, `movimiento_revertido_id`, `usuario_id`, `idempotency_key`, `request_hash`, `motivo`, `created_at` | saldo/movimiento de crédito | A | `PagoServicio` y `CreditoServicio`; append-only | Única autoridad del crédito. Saldo es C y no existe en `alumnos`. |
| `movimientos_stock` / `MovimientoStock` | todos: `id`, `stock_id`, `tipo`, `cantidad`, `venta_stock_id`, `movimiento_revertido_id`, `usuario_id`, `idempotency_key`, `motivo`, `created_at` | stock/venta | A | Sólo `StockServicio`; append-only | Autoridad de movimientos; reconcilia proyección `cantidad_actual`. |
| `recibos` / `Recibo` | `id`, `pago_id`, `storage_key`, `generado_at`, `enviado_at` | descarga de recibo | A/B | Worker de recibos | Documento histórico y hechos de generación/envío. Se eliminaron estado, intentos y error duplicados. |
| `recibos_pendientes` / `ReciboPendiente` | `id`, `pago_id`, `tipo`, `estado`, `intentos`, `next_attempt_at`, `ultimo_error`, `idempotency_key`, `claim_token`, `claimed_at`, `lease_until`, `created_at`, `processed_at` | sin payload frontend | A | Outbox específica y worker | Estado técnico único; claim/lease recuperable, sin contenido financiero duplicado. |
| `notificaciones` / `Notificacion` | `id`, `usuario_id`, `tipo`, `mensaje`, `fecha_creacion`, `fecha_negocio`, `dedup_key`, `leida` | REST/email | A | `NotificacionService` | Mensaje persistido y deduplicado; STOMP queda fuera de la primera release. |

## Datos transitorios y derivados no persistidos

| Dato | Clase | Fuente |
| --- | --- | --- |
| `PagoRegistroRequest`, `PagoAnulacionRequest`, hashes canónicos antes de persistir | E | Request HTTP. |
| selección de cargos, formularios y estados de loading | E | UI local. |
| saldo de crédito | C | Suma firmada de `movimientos_credito`. |
| saldo e importe aplicado de cargo | C | Aplicaciones activas y consumos/reversos de crédito. |
| totales de caja por período/método | C | Agregación de `movimientos_caja`. |
| importe total de venta | C | `cantidad * precio_unitario`; el cargo conserva el importe histórico emitido. |
| edad | C | `fecha_nacimiento` y `Clock`. |
| `PagoResumenResponse` | E | Proyección API de cuatro campos, sin persistencia. |

## Decisiones cerradas

- No existen saldos persistidos de cargo o crédito ni tablas de totales de caja.
- `cantidad_actual` y `Cargo.estado` son las únicas proyecciones operativas;
  tienen una sola ruta transaccional y reconciliación automática en el gate
  PostgreSQL. No se afirma todavía una ventaja de performance porque no existe
  comparación con dataset productivo.
- Los snapshots conservados son descripción e importe original de cargo,
  descripción de mensualidad, precio unitario de venta y monto recibido.
- `request_hash` sólo se conserva en pago y egreso, donde una key repetida con
  payload diferente debe distinguirse de un reintento idéntico.
