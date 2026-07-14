-- gestudio_demo_seed_full_v4.sql
-- Seed demo manual para Gestudio, pensado para ejecutarse DESPUES de Flyway V1..V6.
-- No poner en db/migration. Ejecutar manualmente contra una base de desarrollo/demo.
-- Flyway V6 es la única autoridad del catálogo RBAC y de las matrices productivas.
-- Usuario demo: admin / admin
-- Password BCrypt para "admin": $2a$10$20gyPVFS3kpF8j8KZ.c0zer5c1LUzVWJS7Uu9rdvQVFxJp8Oc1hBa

BEGIN;

-- ============================================================
-- 0. Usuario demo asignado a un rol productivo ya existente
-- ============================================================

INSERT INTO public.usuarios (
    id,
    nombre_usuario,
    contrasena,
    rol_id,
    activo,
    auth_version,
    password_changed_at,
    version
)
SELECT
    900001,
    'admin',
    '$2a$10$20gyPVFS3kpF8j8KZ.c0zer5c1LUzVWJS7Uu9rdvQVFxJp8Oc1hBa',
    r.id,
    TRUE,
    0,
    CURRENT_TIMESTAMP,
    0
FROM public.roles r
WHERE r.codigo = 'ADMINISTRADOR'
  AND NOT EXISTS (
      SELECT 1
      FROM public.usuarios u
      WHERE lower(u.nombre_usuario) = 'admin'
  );

UPDATE public.usuarios u
SET contrasena = '$2a$10$20gyPVFS3kpF8j8KZ.c0zer5c1LUzVWJS7Uu9rdvQVFxJp8Oc1hBa',
    rol_id = (SELECT id FROM public.roles WHERE codigo = 'ADMINISTRADOR'),
    activo = TRUE,
    auth_version = 0,
    password_changed_at = CURRENT_TIMESTAMP
WHERE lower(u.nombre_usuario) = 'admin';

INSERT INTO public.usuario_roles (usuario_id, rol_id, asignado_por_usuario_id)
SELECT u.id, r.id, u.id
FROM public.usuarios u
JOIN public.roles r ON r.codigo = 'ADMINISTRADOR'
WHERE lower(u.nombre_usuario) = 'admin'
ON CONFLICT DO NOTHING;

-- ============================================================
-- 1. Catálogos base
-- ============================================================

INSERT INTO public.salones (id, nombre, descripcion, activo)
VALUES
    (900001, 'Sala Azul', 'Salón principal con espejo completo y barra móvil', TRUE),
    (900002, 'Sala Verde', 'Salón mediano para grupos iniciales y clases particulares', TRUE)
ON CONFLICT (id) DO UPDATE
SET nombre = EXCLUDED.nombre,
    descripcion = EXCLUDED.descripcion,
    activo = EXCLUDED.activo;

INSERT INTO public.profesores (id, nombre, apellido, fecha_nacimiento, telefono, usuario_id, activo, version)
VALUES
    (900001, 'Valentina', 'Ramos', DATE '1989-04-18', '+54 9 223 555-1840', NULL, TRUE, 0),
    (900002, 'Martín', 'Ledesma', DATE '1985-09-03', '+54 9 11 5555-2910', NULL, TRUE, 0),
    (900003, 'Camila', 'Suárez', DATE '1994-01-25', '+54 9 221 555-8831', NULL, TRUE, 0)
ON CONFLICT (id) DO UPDATE
SET nombre = EXCLUDED.nombre,
    apellido = EXCLUDED.apellido,
    fecha_nacimiento = EXCLUDED.fecha_nacimiento,
    telefono = EXCLUDED.telefono,
    usuario_id = EXCLUDED.usuario_id,
    activo = EXCLUDED.activo;

INSERT INTO public.observaciones_profesores (id, profesor_id, fecha, observacion, activa)
VALUES
    (900001, 900001, DATE '2026-03-10', 'Coordina muestras semestrales y seguimiento de grupos infantiles.', TRUE),
    (900002, 900002, DATE '2026-03-12', 'Disponible para reemplazos los sábados por la mañana.', TRUE)
ON CONFLICT (id) DO UPDATE
SET profesor_id = EXCLUDED.profesor_id,
    fecha = EXCLUDED.fecha,
    observacion = EXCLUDED.observacion,
    activa = EXCLUDED.activa;

INSERT INTO public.bonificaciones (id, descripcion, porcentaje_descuento, valor_fijo, activo, observaciones)
VALUES
    (900001, 'Hermanos 10%', 10.0000, 0.00, TRUE, 'Descuento habitual para dos o más alumnos del mismo grupo familiar.'),
    (900002, 'Beca parcial acompañamiento', 25.0000, 0.00, TRUE, 'Beneficio sujeto a revisión trimestral.'),
    (900003, 'Promoción ingreso julio', 0.0000, 5000.00, TRUE, 'Descuento fijo para nuevas inscripciones de mitad de año.')
ON CONFLICT (id) DO UPDATE
SET descripcion = EXCLUDED.descripcion,
    porcentaje_descuento = EXCLUDED.porcentaje_descuento,
    valor_fijo = EXCLUDED.valor_fijo,
    activo = EXCLUDED.activo,
    observaciones = EXCLUDED.observaciones;

INSERT INTO public.recargos (id, descripcion, porcentaje, valor_fijo, dia_del_mes_aplicacion, activo)
VALUES
    (900001, 'Recargo por mora mensual', 8.0000, 0.00, 15, TRUE),
    (900002, 'Recargo administrativo menor', 0.0000, 2500.00, NULL, TRUE)
ON CONFLICT (id) DO UPDATE
SET descripcion = EXCLUDED.descripcion,
    porcentaje = EXCLUDED.porcentaje,
    valor_fijo = EXCLUDED.valor_fijo,
    dia_del_mes_aplicacion = EXCLUDED.dia_del_mes_aplicacion,
    activo = EXCLUDED.activo;

INSERT INTO public.metodo_pagos (id, descripcion, activo, recargo)
VALUES
    (900001, 'Efectivo', TRUE, 0.0000),
    (900002, 'Transferencia bancaria', TRUE, 0.0000),
    (900003, 'Débito', TRUE, 2.0000)
ON CONFLICT (id) DO UPDATE
SET descripcion = EXCLUDED.descripcion,
    activo = EXCLUDED.activo,
    recargo = EXCLUDED.recargo;

INSERT INTO public.sub_conceptos (id, descripcion, activo)
VALUES
    (900001, 'Indumentaria', TRUE),
    (900002, 'Eventos y muestras', TRUE),
    (900003, 'Administración', TRUE)
ON CONFLICT (id) DO UPDATE
SET descripcion = EXCLUDED.descripcion,
    activo = EXCLUDED.activo;

INSERT INTO public.conceptos (id, descripcion, precio, sub_concepto_id, activo)
VALUES
    (900001, 'Remera institucional', 12000.00, 900001, TRUE),
    (900002, 'Derecho de muestra anual', 18000.00, 900002, TRUE),
    (900003, 'Certificado de asistencia', 3500.00, 900003, TRUE)
ON CONFLICT (id) DO UPDATE
SET descripcion = EXCLUDED.descripcion,
    precio = EXCLUDED.precio,
    sub_concepto_id = EXCLUDED.sub_concepto_id,
    activo = EXCLUDED.activo;

INSERT INTO public.stocks (id, nombre, precio, cantidad_actual, requiere_control_de_stock, codigo_barras, activo, version)
VALUES
    (900001, 'REMERA INSTITUCIONAL NEGRA TALLE M', 8500.00, 18, TRUE, '7790000000010', TRUE, 0),
    (900002, 'MEDIAS DE DANZA ROSA TALLE 34-38', 4200.00, 12, TRUE, '7790000000027', TRUE, 0),
    (900003, 'BOTELLA PLÁSTICA ACADEMIA 750ML', 3900.00, 25, TRUE, '7790000000034', TRUE, 0)
ON CONFLICT (id) DO UPDATE
SET nombre = EXCLUDED.nombre,
    precio = EXCLUDED.precio,
    cantidad_actual = EXCLUDED.cantidad_actual,
    requiere_control_de_stock = EXCLUDED.requiere_control_de_stock,
    codigo_barras = EXCLUDED.codigo_barras,
    activo = EXCLUDED.activo;

-- ============================================================
-- 2. Alumnos, disciplinas, horarios e inscripciones
-- ============================================================

INSERT INTO public.alumnos (
    id, nombre, apellido, fecha_nacimiento, celular1, celular2, email, documento,
    fecha_incorporacion, fecha_de_baja, nombre_padres, autorizado_para_salir_solo,
    otras_notas, activo, version
)
VALUES
    (900001, 'Sofía', 'Benítez', DATE '2015-08-21', '+54 9 223 555-1010', NULL, 'familia.benitez@example.com', '50123456', DATE '2026-02-15', NULL, 'Mariana Benítez / Lucas Ferreyra', FALSE, 'Retira madre o padre. Alergia leve a frutos secos.', TRUE, 0),
    (900002, 'Martina', 'Gómez', DATE '2013-11-02', '+54 9 223 555-2020', NULL, 'martina.gomez.flia@example.com', '48765432', DATE '2026-03-01', NULL, 'Andrea Gómez', TRUE, 'Autorizada a retirarse con hermana mayor.', TRUE, 0),
    (900003, 'Julián', 'Paz', DATE '2016-05-14', '+54 9 11 5555-3030', NULL, 'familia.paz@example.com', '51222333', DATE '2026-04-10', NULL, 'Natalia Paz / Diego Paz', FALSE, 'Solicita aviso previo por cambios de horario.', TRUE, 0),
    (900004, 'Lara', 'Moreno', DATE '2012-01-30', '+54 9 221 555-4040', NULL, 'lara.moreno.flia@example.com', '47111222', DATE '2026-01-20', NULL, 'Carolina Moreno', TRUE, 'Participa en grupo avanzado.', TRUE, 0)
ON CONFLICT (id) DO UPDATE
SET nombre = EXCLUDED.nombre,
    apellido = EXCLUDED.apellido,
    fecha_nacimiento = EXCLUDED.fecha_nacimiento,
    celular1 = EXCLUDED.celular1,
    celular2 = EXCLUDED.celular2,
    email = EXCLUDED.email,
    documento = EXCLUDED.documento,
    fecha_incorporacion = EXCLUDED.fecha_incorporacion,
    fecha_de_baja = EXCLUDED.fecha_de_baja,
    nombre_padres = EXCLUDED.nombre_padres,
    autorizado_para_salir_solo = EXCLUDED.autorizado_para_salir_solo,
    otras_notas = EXCLUDED.otras_notas,
    activo = EXCLUDED.activo;

INSERT INTO public.disciplinas (
    id, nombre, salon_id, profesor_id, valor_cuota, matricula,
    clase_suelta, clase_prueba, activo, version
)
VALUES
    (900001, 'Danza Jazz Infantil', 900001, 900001, 32000.00, 18000.00, 7000.00, 0.00, TRUE, 0),
    (900002, 'Ballet Inicial', 900002, 900003, 28000.00, 16000.00, 6500.00, 0.00, TRUE, 0),
    (900003, 'Urbano Teen', 900001, 900002, 35000.00, 20000.00, 8000.00, 0.00, TRUE, 0)
ON CONFLICT (id) DO UPDATE
SET nombre = EXCLUDED.nombre,
    salon_id = EXCLUDED.salon_id,
    profesor_id = EXCLUDED.profesor_id,
    valor_cuota = EXCLUDED.valor_cuota,
    matricula = EXCLUDED.matricula,
    clase_suelta = EXCLUDED.clase_suelta,
    clase_prueba = EXCLUDED.clase_prueba,
    activo = EXCLUDED.activo;

INSERT INTO public.disciplina_horarios (id, disciplina_id, dia_semana, horario_inicio, duracion)
VALUES
    (900001, 900001, 'LUNES', TIME '17:30', 1.00),
    (900002, 900001, 'MIERCOLES', TIME '17:30', 1.00),
    (900003, 900002, 'MARTES', TIME '18:00', 1.00),
    (900004, 900002, 'JUEVES', TIME '18:00', 1.00),
    (900005, 900003, 'SABADO', TIME '10:30', 1.50)
ON CONFLICT (id) DO UPDATE
SET disciplina_id = EXCLUDED.disciplina_id,
    dia_semana = EXCLUDED.dia_semana,
    horario_inicio = EXCLUDED.horario_inicio,
    duracion = EXCLUDED.duracion;

INSERT INTO public.inscripciones (
    id, alumno_id, disciplina_id, bonificacion_id, fecha_inscripcion,
    fecha_baja, estado, costo_particular, version
)
VALUES
    (900001, 900001, 900001, 900001, DATE '2026-02-15', NULL, 'ACTIVA', NULL, 0),
    (900002, 900002, 900002, NULL, DATE '2026-03-01', NULL, 'ACTIVA', NULL, 0),
    (900003, 900003, 900001, 900003, DATE '2026-04-10', NULL, 'ACTIVA', 30000.00, 0),
    (900004, 900004, 900003, 900002, DATE '2026-01-20', NULL, 'ACTIVA', NULL, 0)
ON CONFLICT (id) DO UPDATE
SET alumno_id = EXCLUDED.alumno_id,
    disciplina_id = EXCLUDED.disciplina_id,
    bonificacion_id = EXCLUDED.bonificacion_id,
    fecha_inscripcion = EXCLUDED.fecha_inscripcion,
    fecha_baja = EXCLUDED.fecha_baja,
    estado = EXCLUDED.estado,
    costo_particular = EXCLUDED.costo_particular;

-- ============================================================
-- 3. Tarifas históricas y condiciones económicas
-- ============================================================

INSERT INTO public.disciplina_tarifas (
    id, disciplina_id, vigente_desde, valor_cuota, matricula,
    clase_suelta, clase_prueba, motivo, creada_por_usuario_id, created_at, version
)
VALUES
    (900001, 900001, DATE '2026-01-01', 30000.00, 17000.00, 6500.00, 0.00, 'Tarifa inicial temporada 2026', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP, 0),
    (900002, 900001, DATE '2026-07-01', 32000.00, 18000.00, 7000.00, 0.00, 'Actualización julio 2026', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP, 0),
    (900003, 900002, DATE '2026-01-01', 28000.00, 16000.00, 6500.00, 0.00, 'Tarifa inicial temporada 2026', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP, 0),
    (900004, 900003, DATE '2026-01-01', 35000.00, 20000.00, 8000.00, 0.00, 'Tarifa inicial temporada 2026', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP, 0)
ON CONFLICT (id) DO UPDATE
SET disciplina_id = EXCLUDED.disciplina_id,
    vigente_desde = EXCLUDED.vigente_desde,
    valor_cuota = EXCLUDED.valor_cuota,
    matricula = EXCLUDED.matricula,
    clase_suelta = EXCLUDED.clase_suelta,
    clase_prueba = EXCLUDED.clase_prueba,
    motivo = EXCLUDED.motivo,
    creada_por_usuario_id = EXCLUDED.creada_por_usuario_id;

INSERT INTO public.inscripcion_condiciones_economicas (
    id, inscripcion_id, vigente_desde, costo_particular, bonificacion_id,
    bonificacion_descripcion_snapshot, bonificacion_porcentaje_snapshot,
    bonificacion_valor_fijo_snapshot, motivo, creada_por_usuario_id, created_at, version
)
VALUES
    (900001, 900001, DATE '2026-02-15', NULL, 900001, 'Hermanos 10%', 10.0000, 0.00, 'Condición inicial de inscripción', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP, 0),
    (900002, 900002, DATE '2026-03-01', NULL, NULL, NULL, 0.0000, 0.00, 'Sin bonificación inicial', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP, 0),
    (900003, 900003, DATE '2026-04-10', 30000.00, 900003, 'Promoción ingreso julio', 0.0000, 5000.00, 'Costo particular acordado por grupo familiar', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP, 0),
    (900004, 900004, DATE '2026-01-20', NULL, 900002, 'Beca parcial acompañamiento', 25.0000, 0.00, 'Beca parcial aprobada por dirección', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP, 0)
ON CONFLICT (id) DO UPDATE
SET inscripcion_id = EXCLUDED.inscripcion_id,
    vigente_desde = EXCLUDED.vigente_desde,
    costo_particular = EXCLUDED.costo_particular,
    bonificacion_id = EXCLUDED.bonificacion_id,
    bonificacion_descripcion_snapshot = EXCLUDED.bonificacion_descripcion_snapshot,
    bonificacion_porcentaje_snapshot = EXCLUDED.bonificacion_porcentaje_snapshot,
    bonificacion_valor_fijo_snapshot = EXCLUDED.bonificacion_valor_fijo_snapshot,
    motivo = EXCLUDED.motivo,
    creada_por_usuario_id = EXCLUDED.creada_por_usuario_id;

-- ============================================================
-- 4. Mensualidades, matrículas y asistencia
-- ============================================================

INSERT INTO public.mensualidades (
    id, inscripcion_id, bonificacion_id, recargo_id, anio, mes,
    fecha_generacion, fecha_vencimiento, descripcion, estado, version
)
VALUES
    (900001, 900001, 900001, NULL, 2026, 7, DATE '2026-07-01', DATE '2026-07-10', 'Cuota julio 2026 - Danza Jazz Infantil', 'EMITIDA', 0),
    (900002, 900002, NULL, 900001, 2026, 7, DATE '2026-07-01', DATE '2026-07-10', 'Cuota julio 2026 - Ballet Inicial', 'EMITIDA', 0),
    (900003, 900004, 900002, NULL, 2026, 7, DATE '2026-07-01', DATE '2026-07-10', 'Cuota julio 2026 - Urbano Teen', 'EMITIDA', 0)
ON CONFLICT (id) DO UPDATE
SET inscripcion_id = EXCLUDED.inscripcion_id,
    bonificacion_id = EXCLUDED.bonificacion_id,
    recargo_id = EXCLUDED.recargo_id,
    anio = EXCLUDED.anio,
    mes = EXCLUDED.mes,
    fecha_generacion = EXCLUDED.fecha_generacion,
    fecha_vencimiento = EXCLUDED.fecha_vencimiento,
    descripcion = EXCLUDED.descripcion,
    estado = EXCLUDED.estado;

INSERT INTO public.matriculas (id, alumno_id, anio, fecha_emision, estado, version)
VALUES
    (900001, 900001, 2026, DATE '2026-02-15', 'EMITIDA', 0),
    (900002, 900002, 2026, DATE '2026-03-01', 'EMITIDA', 0),
    (900003, 900004, 2026, DATE '2026-01-20', 'EMITIDA', 0)
ON CONFLICT (id) DO UPDATE
SET alumno_id = EXCLUDED.alumno_id,
    anio = EXCLUDED.anio,
    fecha_emision = EXCLUDED.fecha_emision,
    estado = EXCLUDED.estado;

INSERT INTO public.asistencias_mensuales (id, disciplina_id, mes, anio)
VALUES
    (900001, 900001, 7, 2026),
    (900002, 900002, 7, 2026),
    (900003, 900003, 7, 2026)
ON CONFLICT (id) DO UPDATE
SET disciplina_id = EXCLUDED.disciplina_id,
    mes = EXCLUDED.mes,
    anio = EXCLUDED.anio;

INSERT INTO public.asistencias_alumno_mensual (id, inscripcion_id, asistencia_mensual_id, observacion, activo)
VALUES
    (900001, 900001, 900001, 'Asistencia regular durante julio.', TRUE),
    (900002, 900002, 900002, 'Avisó ausencia por viaje familiar.', TRUE),
    (900003, 900004, 900003, 'Grupo avanzado con asistencia estable.', TRUE)
ON CONFLICT (id) DO UPDATE
SET inscripcion_id = EXCLUDED.inscripcion_id,
    asistencia_mensual_id = EXCLUDED.asistencia_mensual_id,
    observacion = EXCLUDED.observacion,
    activo = EXCLUDED.activo;

INSERT INTO public.asistencias_diarias (id, asistencia_alumno_mensual_id, fecha, estado, vigente)
VALUES
    (900001, 900001, DATE '2026-07-06', 'PRESENTE', TRUE),
    (900002, 900001, DATE '2026-07-08', 'PRESENTE', TRUE),
    (900003, 900002, DATE '2026-07-07', 'AUSENTE', TRUE),
    (900004, 900003, DATE '2026-07-04', 'PRESENTE', TRUE)
ON CONFLICT (id) DO UPDATE
SET asistencia_alumno_mensual_id = EXCLUDED.asistencia_alumno_mensual_id,
    fecha = EXCLUDED.fecha,
    estado = EXCLUDED.estado,
    vigente = EXCLUDED.vigente;

-- ============================================================
-- 5. Cargos, ventas, pagos, caja, créditos y stock
-- ============================================================

INSERT INTO public.ventas_stock (
    id, alumno_id, stock_id, cantidad, precio_unitario, fecha, estado,
    idempotency_key, request_hash, reversal_idempotency_key, reversal_request_hash, version
)
VALUES
    (900001, 900002, 900001, 2, 8500.00, DATE '2026-07-05', 'REGISTRADA', 'demo-venta-stock-001', repeat('a', 64), NULL, NULL, 0)
ON CONFLICT (id) DO UPDATE
SET alumno_id = EXCLUDED.alumno_id,
    stock_id = EXCLUDED.stock_id,
    cantidad = EXCLUDED.cantidad,
    precio_unitario = EXCLUDED.precio_unitario,
    fecha = EXCLUDED.fecha,
    estado = EXCLUDED.estado,
    idempotency_key = EXCLUDED.idempotency_key,
    request_hash = EXCLUDED.request_hash,
    reversal_idempotency_key = EXCLUDED.reversal_idempotency_key,
    reversal_request_hash = EXCLUDED.reversal_request_hash;

INSERT INTO public.cargos (
    id, alumno_id, tipo, descripcion, importe_original, fecha_emision,
    fecha_vencimiento, estado, mensualidad_id, matricula_id, concepto_id,
    venta_stock_id, cargo_origen_id, idempotency_key, version, created_at
)
VALUES
    (900001, 900001, 'MENSUALIDAD', 'Cuota julio 2026 - Danza Jazz Infantil', 32000.00, DATE '2026-07-01', DATE '2026-07-10', 'PARCIAL', 900001, NULL, NULL, NULL, NULL, 'demo-cargo-mensualidad-001', 0, CURRENT_TIMESTAMP),
    (900002, 900002, 'MENSUALIDAD', 'Cuota julio 2026 - Ballet Inicial', 28000.00, DATE '2026-07-01', DATE '2026-07-10', 'PARCIAL', 900002, NULL, NULL, NULL, NULL, 'demo-cargo-mensualidad-002', 0, CURRENT_TIMESTAMP),
    (900003, 900001, 'MATRICULA', 'Matrícula anual 2026 - Sofía Benítez', 18000.00, DATE '2026-02-15', DATE '2026-02-20', 'PENDIENTE', NULL, 900001, NULL, NULL, NULL, 'demo-cargo-matricula-001', 0, CURRENT_TIMESTAMP),
    (900004, 900003, 'CONCEPTO', 'Certificado y materiales administrativos', 3500.00, DATE '2026-07-03', DATE '2026-07-15', 'PENDIENTE', NULL, NULL, 900003, NULL, NULL, 'demo-cargo-concepto-001', 0, CURRENT_TIMESTAMP),
    (900005, 900002, 'VENTA_STOCK', 'Venta de remeras institucionales', 17000.00, DATE '2026-07-05', DATE '2026-07-20', 'PENDIENTE', NULL, NULL, NULL, 900001, NULL, 'demo-cargo-venta-stock-001', 0, CURRENT_TIMESTAMP),
    (900006, 900002, 'RECARGO', 'Recargo administrativo menor sobre cuota julio', 2500.00, DATE '2026-07-16', DATE '2026-07-20', 'PENDIENTE', NULL, NULL, NULL, NULL, 900002, 'demo-cargo-recargo-001', 0, CURRENT_TIMESTAMP),
    (900007, 900004, 'MENSUALIDAD', 'Cuota julio 2026 - Urbano Teen', 26250.00, DATE '2026-07-01', DATE '2026-07-10', 'PENDIENTE', 900003, NULL, NULL, NULL, NULL, 'demo-cargo-mensualidad-003', 0, CURRENT_TIMESTAMP)
ON CONFLICT (id) DO UPDATE
SET alumno_id = EXCLUDED.alumno_id,
    tipo = EXCLUDED.tipo,
    descripcion = EXCLUDED.descripcion,
    importe_original = EXCLUDED.importe_original,
    fecha_emision = EXCLUDED.fecha_emision,
    fecha_vencimiento = EXCLUDED.fecha_vencimiento,
    estado = EXCLUDED.estado,
    mensualidad_id = EXCLUDED.mensualidad_id,
    matricula_id = EXCLUDED.matricula_id,
    concepto_id = EXCLUDED.concepto_id,
    venta_stock_id = EXCLUDED.venta_stock_id,
    cargo_origen_id = EXCLUDED.cargo_origen_id,
    idempotency_key = EXCLUDED.idempotency_key;

INSERT INTO public.pagos (
    id, alumno_id, metodo_pago_id, usuario_id, fecha, monto_recibido,
    estado, idempotency_key, request_hash, reversal_idempotency_key,
    reversal_request_hash, observaciones, motivo_anulacion, fecha_anulacion,
    version, created_at
)
VALUES
    (900001, 900001, 900002, (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), DATE '2026-07-08', 20000.00, 'REGISTRADO', 'demo-pago-001', repeat('b', 64), NULL, NULL, 'Pago parcial de cuota julio por transferencia.', NULL, NULL, 0, CURRENT_TIMESTAMP)
ON CONFLICT (id) DO UPDATE
SET alumno_id = EXCLUDED.alumno_id,
    metodo_pago_id = EXCLUDED.metodo_pago_id,
    usuario_id = EXCLUDED.usuario_id,
    fecha = EXCLUDED.fecha,
    monto_recibido = EXCLUDED.monto_recibido,
    estado = EXCLUDED.estado,
    idempotency_key = EXCLUDED.idempotency_key,
    request_hash = EXCLUDED.request_hash,
    reversal_idempotency_key = EXCLUDED.reversal_idempotency_key,
    reversal_request_hash = EXCLUDED.reversal_request_hash,
    observaciones = EXCLUDED.observaciones,
    motivo_anulacion = EXCLUDED.motivo_anulacion,
    fecha_anulacion = EXCLUDED.fecha_anulacion;

INSERT INTO public.aplicaciones_pago (
    id, pago_id, cargo_id, usuario_id, importe_aplicado, estado,
    fecha, motivo_reversion, fecha_reversion, version, created_at
)
VALUES
    (900001, 900001, 900001, (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), 20000.00, 'APLICADA', DATE '2026-07-08', NULL, NULL, 0, CURRENT_TIMESTAMP)
ON CONFLICT (id) DO UPDATE
SET pago_id = EXCLUDED.pago_id,
    cargo_id = EXCLUDED.cargo_id,
    usuario_id = EXCLUDED.usuario_id,
    importe_aplicado = EXCLUDED.importe_aplicado,
    estado = EXCLUDED.estado,
    fecha = EXCLUDED.fecha,
    motivo_reversion = EXCLUDED.motivo_reversion,
    fecha_reversion = EXCLUDED.fecha_reversion;

INSERT INTO public.egresos (
    id, fecha, monto, observaciones, metodo_pago_id, estado, usuario_id,
    idempotency_key, request_hash, reversal_idempotency_key, reversal_request_hash,
    motivo_anulacion, fecha_anulacion, version
)
VALUES
    (900001, DATE '2026-07-08', 14500.00, 'Compra de artículos de limpieza y resma administrativa.', 900001, 'REGISTRADO', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), 'demo-egreso-001', repeat('c', 64), NULL, NULL, NULL, NULL, 0)
ON CONFLICT (id) DO UPDATE
SET fecha = EXCLUDED.fecha,
    monto = EXCLUDED.monto,
    observaciones = EXCLUDED.observaciones,
    metodo_pago_id = EXCLUDED.metodo_pago_id,
    estado = EXCLUDED.estado,
    usuario_id = EXCLUDED.usuario_id,
    idempotency_key = EXCLUDED.idempotency_key,
    request_hash = EXCLUDED.request_hash,
    reversal_idempotency_key = EXCLUDED.reversal_idempotency_key,
    reversal_request_hash = EXCLUDED.reversal_request_hash,
    motivo_anulacion = EXCLUDED.motivo_anulacion,
    fecha_anulacion = EXCLUDED.fecha_anulacion;

INSERT INTO public.movimientos_caja (
    id, tipo, fecha, importe, metodo_pago_id, pago_id, egreso_id,
    movimiento_revertido_id, usuario_id, idempotency_key, motivo, created_at
)
VALUES
    (900001, 'INGRESO_PAGO', DATE '2026-07-08', 20000.00, 900002, 900001, NULL, NULL, (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), 'demo-caja-ingreso-pago-001', NULL, CURRENT_TIMESTAMP),
    (900002, 'EGRESO', DATE '2026-07-08', 14500.00, 900001, NULL, 900001, NULL, (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), 'demo-caja-egreso-001', NULL, CURRENT_TIMESTAMP),
    (900003, 'AJUSTE_INGRESO', DATE '2026-07-08', 2500.00, 900001, NULL, NULL, NULL, (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), 'demo-caja-ajuste-ingreso-001', 'Ajuste inicial de caja para demo.', CURRENT_TIMESTAMP)
ON CONFLICT (id) DO UPDATE
SET tipo = EXCLUDED.tipo,
    fecha = EXCLUDED.fecha,
    importe = EXCLUDED.importe,
    metodo_pago_id = EXCLUDED.metodo_pago_id,
    pago_id = EXCLUDED.pago_id,
    egreso_id = EXCLUDED.egreso_id,
    movimiento_revertido_id = EXCLUDED.movimiento_revertido_id,
    usuario_id = EXCLUDED.usuario_id,
    idempotency_key = EXCLUDED.idempotency_key,
    motivo = EXCLUDED.motivo;

INSERT INTO public.movimientos_credito (
    id, alumno_id, tipo, importe, pago_id, cargo_id, movimiento_revertido_id,
    usuario_id, idempotency_key, request_hash, motivo, created_at
)
VALUES
    (900001, 900002, 'AJUSTE_CREDITO', 8000.00, NULL, NULL, NULL, (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), 'demo-credito-ajuste-001', repeat('d', 64), 'Crédito cargado por saldo a favor informado por la familia.', CURRENT_TIMESTAMP),
    (900002, 900002, 'CONSUMO', 5000.00, NULL, 900002, NULL, (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), 'demo-credito-consumo-001', repeat('e', 64), NULL, CURRENT_TIMESTAMP)
ON CONFLICT (id) DO UPDATE
SET alumno_id = EXCLUDED.alumno_id,
    tipo = EXCLUDED.tipo,
    importe = EXCLUDED.importe,
    pago_id = EXCLUDED.pago_id,
    cargo_id = EXCLUDED.cargo_id,
    movimiento_revertido_id = EXCLUDED.movimiento_revertido_id,
    usuario_id = EXCLUDED.usuario_id,
    idempotency_key = EXCLUDED.idempotency_key,
    request_hash = EXCLUDED.request_hash,
    motivo = EXCLUDED.motivo;

INSERT INTO public.movimientos_stock (
    id, stock_id, tipo, cantidad, venta_stock_id, movimiento_revertido_id,
    usuario_id, idempotency_key, motivo, created_at
)
VALUES
    (900001, 900001, 'INGRESO', 20, NULL, NULL, (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), 'demo-stock-ingreso-001', 'Stock inicial de remeras para demo.', CURRENT_TIMESTAMP),
    (900002, 900001, 'VENTA', 2, 900001, NULL, (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), 'demo-stock-venta-001', NULL, CURRENT_TIMESTAMP),
    (900003, 900002, 'INGRESO', 12, NULL, NULL, (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), 'demo-stock-ingreso-002', 'Stock inicial de medias para demo.', CURRENT_TIMESTAMP),
    (900004, 900003, 'INGRESO', 25, NULL, NULL, (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), 'demo-stock-ingreso-003', 'Stock inicial de botellas para demo.', CURRENT_TIMESTAMP)
ON CONFLICT (id) DO UPDATE
SET stock_id = EXCLUDED.stock_id,
    tipo = EXCLUDED.tipo,
    cantidad = EXCLUDED.cantidad,
    venta_stock_id = EXCLUDED.venta_stock_id,
    movimiento_revertido_id = EXCLUDED.movimiento_revertido_id,
    usuario_id = EXCLUDED.usuario_id,
    idempotency_key = EXCLUDED.idempotency_key,
    motivo = EXCLUDED.motivo;

-- ============================================================
-- 6. Recibos y seguimiento de cargos
-- ============================================================

INSERT INTO public.recibos (id, pago_id, storage_key, generado_at, enviado_at)
VALUES
    (900001, 900001, 'demo/recibos/recibo_900001.pdf', CURRENT_TIMESTAMP, NULL)
ON CONFLICT (id) DO UPDATE
SET pago_id = EXCLUDED.pago_id,
    storage_key = EXCLUDED.storage_key,
    generado_at = EXCLUDED.generado_at,
    enviado_at = EXCLUDED.enviado_at;

INSERT INTO public.recibos_pendientes (
    id, pago_id, tipo, estado, intentos, next_attempt_at, idempotency_key,
    claim_token, claimed_at, lease_until, ultimo_error, created_at, processed_at
)
VALUES
    (900001, 900001, 'GENERAR_Y_ENVIAR', 'PENDIENTE', 0, CURRENT_TIMESTAMP, 'demo-recibo-pendiente-001', NULL, NULL, NULL, NULL, CURRENT_TIMESTAMP, NULL)
ON CONFLICT (id) DO UPDATE
SET pago_id = EXCLUDED.pago_id,
    tipo = EXCLUDED.tipo,
    estado = EXCLUDED.estado,
    intentos = EXCLUDED.intentos,
    next_attempt_at = EXCLUDED.next_attempt_at,
    idempotency_key = EXCLUDED.idempotency_key,
    claim_token = EXCLUDED.claim_token,
    claimed_at = EXCLUDED.claimed_at,
    lease_until = EXCLUDED.lease_until,
    ultimo_error = EXCLUDED.ultimo_error,
    processed_at = EXCLUDED.processed_at;

INSERT INTO public.cargo_liquidaciones (
    cargo_id, periodo_desde, tarifa_disciplina_id, condicion_inscripcion_id,
    origen_precio, importe_base, descuento_porcentaje, descuento_importe,
    recargo_porcentaje, recargo_importe, importe_final, formula_version,
    observaciones, calculada_por_usuario_id, created_at
)
VALUES
    (900001, DATE '2026-07-01', 900002, 900001, 'TARIFA_HISTORICA', 32000.00, 10.0000, 3200.00, 0.0000, 0.00, 32000.00, 1, 'Liquidación demo de cuota mensual con bonificación familiar.', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP),
    (900002, DATE '2026-07-01', 900003, 900002, 'TARIFA_HISTORICA', 28000.00, 0.0000, 0.00, 8.0000, 0.00, 28000.00, 1, 'Liquidación demo de cuota mensual con recargo asociado.', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP),
    (900003, DATE '2026-01-01', NULL, NULL, 'MANUAL_HISTORICO', 18000.00, 0.0000, 0.00, 0.0000, 0.00, 18000.00, 1, 'Matrícula anual demo.', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP),
    (900004, DATE '2026-07-01', NULL, NULL, 'MANUAL_HISTORICO', 3500.00, 0.0000, 0.00, 0.0000, 0.00, 3500.00, 1, 'Cargo administrativo demo.', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP),
    (900005, DATE '2026-07-01', NULL, NULL, 'MANUAL_HISTORICO', 17000.00, 0.0000, 0.00, 0.0000, 0.00, 17000.00, 1, 'Cargo generado por venta de stock demo.', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP),
    (900006, DATE '2026-07-01', NULL, NULL, 'MANUAL_HISTORICO', 2500.00, 0.0000, 0.00, 0.0000, 2500.00, 2500.00, 1, 'Recargo administrativo demo.', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP),
    (900007, DATE '2026-07-01', 900004, 900004, 'TARIFA_HISTORICA', 35000.00, 25.0000, 8750.00, 0.0000, 0.00, 26250.00, 1, 'Liquidación demo de beca parcial.', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP)
ON CONFLICT (cargo_id) DO UPDATE
SET periodo_desde = EXCLUDED.periodo_desde,
    tarifa_disciplina_id = EXCLUDED.tarifa_disciplina_id,
    condicion_inscripcion_id = EXCLUDED.condicion_inscripcion_id,
    origen_precio = EXCLUDED.origen_precio,
    importe_base = EXCLUDED.importe_base,
    descuento_porcentaje = EXCLUDED.descuento_porcentaje,
    descuento_importe = EXCLUDED.descuento_importe,
    recargo_porcentaje = EXCLUDED.recargo_porcentaje,
    recargo_importe = EXCLUDED.recargo_importe,
    importe_final = EXCLUDED.importe_final,
    formula_version = EXCLUDED.formula_version,
    observaciones = EXCLUDED.observaciones,
    calculada_por_usuario_id = EXCLUDED.calculada_por_usuario_id;

INSERT INTO public.cargo_eventos (
    cargo_id, tipo, estado_anterior, estado_nuevo, saldo_anterior, saldo_nuevo,
    referencia_tipo, referencia_id, idempotency_key, usuario_id, ocurrido_at,
    correlation_id, metadata
)
VALUES
    (900001, 'EMITIDO', NULL, 'PENDIENTE', NULL, 32000.00, 'CARGO', 900001, 'demo-cargo-900001-emitido', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP, NULL, '{"demo": true}'::jsonb),
    (900001, 'PAGO_APLICADO', 'PENDIENTE', 'PARCIAL', 32000.00, 12000.00, 'APLICACION_PAGO', 900001, 'demo-cargo-900001-pago-aplicado', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP, NULL, '{"importe": "20000.00"}'::jsonb),
    (900002, 'EMITIDO', NULL, 'PENDIENTE', NULL, 28000.00, 'CARGO', 900002, 'demo-cargo-900002-emitido', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP, NULL, '{"demo": true}'::jsonb),
    (900002, 'CREDITO_APLICADO', 'PENDIENTE', 'PARCIAL', 28000.00, 23000.00, 'MOVIMIENTO_CREDITO', 900002, 'demo-cargo-900002-credito-aplicado', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP, NULL, '{"importe": "5000.00"}'::jsonb),
    (900003, 'EMITIDO', NULL, 'PENDIENTE', NULL, 18000.00, 'CARGO', 900003, 'demo-cargo-900003-emitido', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP, NULL, '{"demo": true}'::jsonb),
    (900004, 'EMITIDO', NULL, 'PENDIENTE', NULL, 3500.00, 'CARGO', 900004, 'demo-cargo-900004-emitido', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP, NULL, '{"demo": true}'::jsonb),
    (900005, 'EMITIDO', NULL, 'PENDIENTE', NULL, 17000.00, 'CARGO', 900005, 'demo-cargo-900005-emitido', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP, NULL, '{"demo": true}'::jsonb),
    (900006, 'RECARGO_CREADO', NULL, 'PENDIENTE', NULL, 2500.00, 'CARGO', 900006, 'demo-cargo-900006-recargo-creado', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP, NULL, '{"cargoOrigenId": 900002}'::jsonb),
    (900007, 'EMITIDO', NULL, 'PENDIENTE', NULL, 26250.00, 'CARGO', 900007, 'demo-cargo-900007-emitido', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP, NULL, '{"demo": true}'::jsonb)
ON CONFLICT (idempotency_key) DO NOTHING;

-- ============================================================
-- 7. Seguridad, auditoría y notificaciones
-- ============================================================

INSERT INTO public.refresh_sessions (
    id, family_id, usuario_id, token_hash, auth_version, issued_at, expires_at,
    used_at, revoked_at, revoke_reason, replaced_by_id, user_agent_hash, ip_hash
)
VALUES
    ('11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), repeat('1', 64), 0, CURRENT_TIMESTAMP - INTERVAL '1 hour', CURRENT_TIMESTAMP + INTERVAL '30 days', NULL, NULL, NULL, NULL, repeat('2', 64), repeat('3', 64))
ON CONFLICT (id) DO UPDATE
SET usuario_id = EXCLUDED.usuario_id,
    token_hash = EXCLUDED.token_hash,
    auth_version = EXCLUDED.auth_version,
    issued_at = EXCLUDED.issued_at,
    expires_at = EXCLUDED.expires_at,
    used_at = EXCLUDED.used_at,
    revoked_at = EXCLUDED.revoked_at,
    revoke_reason = EXCLUDED.revoke_reason,
    replaced_by_id = EXCLUDED.replaced_by_id,
    user_agent_hash = EXCLUDED.user_agent_hash,
    ip_hash = EXCLUDED.ip_hash;

INSERT INTO public.bootstrap_ejecuciones (tipo, usuario_id, ejecutado_at)
VALUES
    ('DEMO_SEED_ADMIN', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), CURRENT_TIMESTAMP)
ON CONFLICT (tipo) DO UPDATE
SET usuario_id = EXCLUDED.usuario_id,
    ejecutado_at = EXCLUDED.ejecutado_at;

INSERT INTO public.auditoria_eventos (
    id, categoria, accion, entidad_tipo, entidad_id, actor_usuario_id,
    actor_username_snapshot, actor_role_snapshot, ocurrido_at, fecha_negocio,
    correlation_id, idempotency_key, estado_anterior, estado_nuevo, metadata
)
VALUES
    (900001, 'SISTEMA', 'DEMO_SEED_EJECUTADO', 'DEMO', 'gestudio-demo', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), 'admin', 'ADMINISTRADOR', CURRENT_TIMESTAMP, CURRENT_DATE, NULL, 'demo-auditoria-seed-001', NULL, '{"estado": "demo cargada"}'::jsonb, '{"origen": "gestudio_demo_seed_full.sql"}'::jsonb),
    (900002, 'SEGURIDAD', 'USUARIO_DEMO_DISPONIBLE', 'USUARIO', 'admin', (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), 'admin', 'ADMINISTRADOR', CURRENT_TIMESTAMP, CURRENT_DATE, NULL, 'demo-auditoria-admin-001', NULL, '{"usuario": "admin"}'::jsonb, '{"demo": true}'::jsonb)
ON CONFLICT (idempotency_key) WHERE idempotency_key IS NOT NULL DO NOTHING;

INSERT INTO public.notificaciones (
    id, usuario_id, tipo, mensaje, fecha_creacion, fecha_negocio, dedup_key, leida
)
VALUES
    (900001, (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), 'DEMO', 'Demo cargada: hay alumnos, mensualidades, pagos, caja, stock y créditos para revisar.', CURRENT_TIMESTAMP, CURRENT_DATE, 'demo-notificacion-seed-001', FALSE),
    (900002, (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'admin'), 'CAJA', 'La caja demo incluye un ingreso, un egreso y un ajuste menor.', CURRENT_TIMESTAMP, CURRENT_DATE, 'demo-notificacion-caja-001', FALSE)
ON CONFLICT (id) DO UPDATE
SET usuario_id = EXCLUDED.usuario_id,
    tipo = EXCLUDED.tipo,
    mensaje = EXCLUDED.mensaje,
    fecha_creacion = EXCLUDED.fecha_creacion,
    fecha_negocio = EXCLUDED.fecha_negocio,
    dedup_key = EXCLUDED.dedup_key,
    leida = EXCLUDED.leida;

-- ============================================================
-- 8. Ajuste de secuencias identity para inserts futuros
-- ============================================================

DO $$
DECLARE
    t text;
    seq text;
    max_id bigint;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'roles',
        'usuarios',
        'alumnos',
        'salones',
        'profesores',
        'observaciones_profesores',
        'bonificaciones',
        'recargos',
        'metodo_pagos',
        'sub_conceptos',
        'conceptos',
        'stocks',
        'disciplinas',
        'disciplina_horarios',
        'inscripciones',
        'mensualidades',
        'matriculas',
        'asistencias_mensuales',
        'asistencias_alumno_mensual',
        'asistencias_diarias',
        'ventas_stock',
        'cargos',
        'pagos',
        'aplicaciones_pago',
        'egresos',
        'movimientos_caja',
        'movimientos_credito',
        'movimientos_stock',
        'recibos',
        'recibos_pendientes',
        'notificaciones',
        'auditoria_eventos',
        'disciplina_tarifas',
        'inscripcion_condiciones_economicas',
        'cargo_eventos'
    ] LOOP
        SELECT pg_get_serial_sequence('public.' || t, 'id') INTO seq;

        IF seq IS NOT NULL THEN
            EXECUTE format('SELECT max(id) FROM public.%I', t) INTO max_id;

            IF max_id IS NOT NULL THEN
                EXECUTE format('SELECT setval(%L, %s, true)', seq, max_id);
            END IF;
        END IF;
    END LOOP;
END $$;

COMMIT;

-- Validación rápida sugerida:
-- SELECT 'roles' AS tabla, count(*) FROM public.roles
-- UNION ALL SELECT 'usuarios', count(*) FROM public.usuarios
-- UNION ALL SELECT 'permisos', count(*) FROM public.permisos
-- UNION ALL SELECT 'alumnos', count(*) FROM public.alumnos
-- UNION ALL SELECT 'cargos', count(*) FROM public.cargos
-- UNION ALL SELECT 'pagos', count(*) FROM public.pagos
-- UNION ALL SELECT 'egresos', count(*) FROM public.egresos
-- UNION ALL SELECT 'movimientos_caja', count(*) FROM public.movimientos_caja
-- UNION ALL SELECT 'movimientos_credito', count(*) FROM public.movimientos_credito
-- UNION ALL SELECT 'movimientos_stock', count(*) FROM public.movimientos_stock;
