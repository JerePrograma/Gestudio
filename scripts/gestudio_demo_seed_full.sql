-- ESTE ARCHIVO NO ES UNA MIGRACIÓN FLYWAY.
-- Seed manual, sintético y descartable para validar Gestudio después de V1..V6.
-- No ejecutar sobre una base que contenga datos que deban conservarse.

\set ON_ERROR_STOP on

BEGIN;

SET LOCAL TIME ZONE 'America/Argentina/Buenos_Aires';

CREATE TEMP TABLE _demo_config ON COMMIT DROP AS
SELECT
    :'demo_anchor_date'::date AS anchor_date,
    date_trunc('month', :'demo_anchor_date'::date)::date AS month_0,
    (date_trunc('month', :'demo_anchor_date'::date) - interval '1 month')::date AS month_1,
    (date_trunc('month', :'demo_anchor_date'::date) - interval '2 months')::date AS month_2,
    (:'demo_anchor_date'::date::timestamp + time '12:00') AT TIME ZONE 'America/Argentina/Buenos_Aires' AS anchor_ts;

DO $$
DECLARE
    required_table text;
    missing_tables text[] := ARRAY[]::text[];
    full_role_count integer;
BEGIN
    IF (SELECT anchor_date FROM _demo_config) NOT BETWEEN DATE '2020-01-01' AND DATE '2099-12-31' THEN
        RAISE EXCEPTION 'demo_anchor_date fuera del rango admitido';
    END IF;

    FOREACH required_table IN ARRAY ARRAY[
        'flyway_schema_history', 'roles', 'usuarios', 'permisos', 'rol_permisos', 'usuario_roles',
        'alumnos', 'salones', 'profesores', 'observaciones_profesores', 'disciplinas',
        'disciplina_horarios', 'inscripciones', 'bonificaciones', 'recargos', 'metodo_pagos',
        'sub_conceptos', 'conceptos', 'disciplina_tarifas', 'inscripcion_condiciones_economicas',
        'mensualidades', 'matriculas', 'cargos', 'cargo_liquidaciones', 'pagos',
        'aplicaciones_pago', 'egresos', 'movimientos_caja', 'movimientos_credito', 'stocks',
        'ventas_stock', 'movimientos_stock', 'asistencias_mensuales',
        'asistencias_alumno_mensual', 'asistencias_diarias', 'recibos', 'recibos_pendientes',
        'refresh_sessions', 'bootstrap_ejecuciones', 'auditoria_eventos', 'cargo_eventos',
        'notificaciones'
    ] LOOP
        IF to_regclass('public.' || required_table) IS NULL THEN
            missing_tables := array_append(missing_tables, required_table);
        END IF;
    END LOOP;

    IF cardinality(missing_tables) > 0 THEN
        RAISE EXCEPTION 'Faltan tablas requeridas: %', array_to_string(missing_tables, ', ');
    END IF;

    IF (SELECT count(*) FROM public.flyway_schema_history WHERE success) <> 6
       OR EXISTS (SELECT 1 FROM public.flyway_schema_history WHERE NOT success)
       OR NOT EXISTS (
            SELECT 1
            FROM public.flyway_schema_history
            WHERE version = '6'
              AND success
              AND script = 'V6__rbac_permission_catalog_and_base_roles.sql'
       )
       OR EXISTS (
            SELECT 1
            FROM public.flyway_schema_history
            WHERE lower(script) LIKE '%demo%seed%'
               OR lower(script) LIKE '%seed%demo%'
       ) THEN
        RAISE EXCEPTION 'El historial Flyway no coincide con V1..V6 productivas';
    END IF;

    IF (SELECT count(*) FROM public.permisos WHERE activo AND sistema) <> 32 THEN
        RAISE EXCEPTION 'El catálogo productivo no contiene 32 permisos activos de sistema';
    END IF;

    SELECT count(*)
    INTO full_role_count
    FROM public.roles r
    WHERE r.activo
      AND r.sistema
      AND NOT r.editable
      AND (SELECT count(*) FROM public.rol_permisos rp WHERE rp.rol_id = r.id) =
          (SELECT count(*) FROM public.permisos p WHERE p.activo AND p.sistema);

    IF full_role_count <> 1 THEN
        RAISE EXCEPTION 'No se pudo resolver un único rol técnico completo';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.roles r
        WHERE r.codigo = 'DIRECCION' AND r.activo
          AND (SELECT count(*) FROM public.rol_permisos rp WHERE rp.rol_id = r.id) = 31
    ) OR NOT EXISTS (
        SELECT 1 FROM public.roles r
        WHERE r.codigo = 'ADMINISTRADOR' AND r.activo
          AND (SELECT count(*) FROM public.rol_permisos rp WHERE rp.rol_id = r.id) = 31
    ) OR NOT EXISTS (
        SELECT 1 FROM public.roles r
        WHERE r.codigo = 'SECRETARIA' AND r.activo
          AND (SELECT count(*) FROM public.rol_permisos rp WHERE rp.rol_id = r.id) = 17
    ) OR NOT EXISTS (
        SELECT 1 FROM public.roles r
        WHERE r.codigo = 'CAJA' AND r.activo
          AND (SELECT count(*) FROM public.rol_permisos rp WHERE rp.rol_id = r.id) = 8
    ) OR NOT EXISTS (
        SELECT 1 FROM public.roles r
        WHERE r.codigo = 'PROFESOR' AND NOT r.activo AND r.sistema AND NOT r.editable
          AND NOT EXISTS (SELECT 1 FROM public.rol_permisos rp WHERE rp.rol_id = r.id)
    ) THEN
        RAISE EXCEPTION 'La matriz de roles base no coincide con el contrato productivo';
    END IF;
END
$$;

CREATE TEMP TABLE _demo_guard ON COMMIT DROP AS
SELECT
    (SELECT count(*) FROM public.roles) AS roles_count,
    (SELECT md5(COALESCE(string_agg(
        r.id::text || '|' || r.codigo || '|' || r.activo::text || '|' || r.sistema::text || '|' || r.editable::text,
        E'\n' ORDER BY r.id), '')) FROM public.roles r) AS roles_hash,
    (SELECT count(*) FROM public.permisos) AS permissions_count,
    (SELECT md5(COALESCE(string_agg(
        p.id::text || '|' || p.codigo || '|' || p.activo::text || '|' || p.sistema::text || '|' || p.modulo || '|' || p.descripcion,
        E'\n' ORDER BY p.id), '')) FROM public.permisos p) AS permissions_hash,
    (SELECT count(*) FROM public.rol_permisos) AS matrix_count,
    (SELECT md5(COALESCE(string_agg(
        rp.rol_id::text || '|' || rp.permiso_id::text,
        E'\n' ORDER BY rp.rol_id, rp.permiso_id), '')) FROM public.rol_permisos rp) AS matrix_hash,
    (SELECT count(*) FROM public.usuarios u WHERE lower(u.nombre_usuario) NOT LIKE 'demo-%') AS other_users_count,
    (SELECT md5(COALESCE(string_agg(to_jsonb(u)::text, E'\n' ORDER BY u.id), ''))
        FROM public.usuarios u WHERE lower(u.nombre_usuario) NOT LIKE 'demo-%') AS other_users_hash,
    (SELECT count(*) FROM public.refresh_sessions) AS refresh_count,
    (SELECT count(*) FROM public.bootstrap_ejecuciones) AS bootstrap_count,
    (SELECT count(*) FROM public.auditoria_eventos) AS audit_count,
    (SELECT count(*) FROM public.cargo_eventos) AS charge_events_count,
    (SELECT count(*) FROM public.notificaciones) AS notifications_count;

DO $$
DECLARE
    expected_note text := '[DEMO:SEED_V1] anchor=' || (SELECT anchor_date::text FROM _demo_config);
    namespace_exists boolean;
BEGIN
    SELECT EXISTS (SELECT 1 FROM public.usuarios WHERE lower(nombre_usuario) LIKE 'demo-%')
        OR EXISTS (SELECT 1 FROM public.alumnos WHERE documento LIKE 'DEMO-DNI-%')
        OR EXISTS (SELECT 1 FROM public.cargos WHERE idempotency_key LIKE 'demo-seed:v1:%')
    INTO namespace_exists;

    IF namespace_exists AND NOT EXISTS (
        SELECT 1
        FROM public.alumnos
        WHERE documento = 'DEMO-DNI-A001'
          AND otras_notas = expected_note
    ) THEN
        RAISE EXCEPTION 'El namespace demo ya existe con otra fecha ancla o está incompleto';
    END IF;
END
$$;

-- Usuarios demo. El rol técnico completo se resuelve por propiedades y matriz.
CREATE TEMP TABLE _demo_users_desired (
    username varchar(100) PRIMARY KEY,
    password_hash varchar(100) NOT NULL,
    role_id bigint NOT NULL
) ON COMMIT DROP;

INSERT INTO _demo_users_desired (username, password_hash, role_id)
SELECT 'demo-superadmin', :'demo_superadmin_password_hash', r.id
FROM public.roles r
WHERE r.activo
  AND r.sistema
  AND NOT r.editable
  AND (SELECT count(*) FROM public.rol_permisos rp WHERE rp.rol_id = r.id) =
      (SELECT count(*) FROM public.permisos p WHERE p.activo AND p.sistema)
UNION ALL
SELECT 'demo-direccion', :'demo_direccion_password_hash', r.id
FROM public.roles r WHERE r.codigo = 'DIRECCION' AND r.activo
UNION ALL
SELECT 'demo-administrador', :'demo_administrador_password_hash', r.id
FROM public.roles r WHERE r.codigo = 'ADMINISTRADOR' AND r.activo
UNION ALL
SELECT 'demo-secretaria', :'demo_secretaria_password_hash', r.id
FROM public.roles r WHERE r.codigo = 'SECRETARIA' AND r.activo
UNION ALL
SELECT 'demo-caja', :'demo_caja_password_hash', r.id
FROM public.roles r WHERE r.codigo = 'CAJA' AND r.activo;

DO $$
BEGIN
    IF (SELECT count(*) FROM _demo_users_desired) <> 5
       OR EXISTS (
            SELECT 1 FROM _demo_users_desired
            WHERE password_hash !~ '^[$]2[aby][$][0-9]{2}[$][./A-Za-z0-9]{53}$'
       )
       OR (SELECT count(DISTINCT password_hash) FROM _demo_users_desired) <> 5 THEN
        RAISE EXCEPTION 'Las cinco identidades demo no tienen roles o hashes BCrypt efímeros válidos y distintos';
    END IF;
END
$$;

INSERT INTO public.usuarios (nombre_usuario, contrasena, rol_id, activo, auth_version, password_changed_at, version)
SELECT username, password_hash, role_id, TRUE, 0, (SELECT anchor_ts FROM _demo_config), 0
FROM _demo_users_desired
ON CONFLICT (lower(nombre_usuario)) DO UPDATE
SET contrasena = EXCLUDED.contrasena,
    rol_id = EXCLUDED.rol_id,
    activo = TRUE,
    password_changed_at = EXCLUDED.password_changed_at;

DELETE FROM public.usuario_roles ur
USING public.usuarios u, _demo_users_desired d
WHERE ur.usuario_id = u.id
  AND lower(u.nombre_usuario) = d.username
  AND ur.rol_id <> d.role_id;

INSERT INTO public.usuario_roles (usuario_id, rol_id, asignado_at, asignado_por_usuario_id)
SELECT u.id,
       d.role_id,
       (SELECT anchor_ts FROM _demo_config),
       (SELECT id FROM public.usuarios WHERE lower(nombre_usuario) = 'demo-superadmin')
FROM _demo_users_desired d
JOIN public.usuarios u ON lower(u.nombre_usuario) = d.username
ON CONFLICT (usuario_id, rol_id) DO UPDATE
SET asignado_at = EXCLUDED.asignado_at,
    asignado_por_usuario_id = EXCLUDED.asignado_por_usuario_id;

-- Catálogos visibles.
INSERT INTO public.salones (nombre, descripcion, activo)
VALUES
    ('DEMO · Sala Norte', 'Salón amplio con piso técnico.', TRUE),
    ('DEMO · Sala Sur', 'Salón para grupos infantiles.', TRUE),
    ('DEMO · Estudio Central', 'Espacio multipropósito de la demo.', TRUE)
ON CONFLICT (nombre) DO UPDATE
SET descripcion = EXCLUDED.descripcion,
    activo = EXCLUDED.activo;

CREATE TEMP TABLE _demo_professors_desired (
    seq integer PRIMARY KEY,
    nombre varchar(100) NOT NULL,
    apellido varchar(100) NOT NULL,
    fecha_nacimiento date,
    telefono varchar(30),
    activo boolean NOT NULL
) ON COMMIT DROP;

INSERT INTO _demo_professors_desired
SELECT n,
       'DEMO · Profesor ' || lpad(n::text, 2, '0'),
       CASE n WHEN 1 THEN 'Álvarez' WHEN 2 THEN 'Benítez' WHEN 3 THEN 'Castro'
              WHEN 4 THEN 'Domínguez' WHEN 5 THEN 'Escobar' ELSE 'Fernández' END,
       (SELECT anchor_date FROM _demo_config) - (interval '27 years' + n * interval '13 months'),
       '+54 11 5555-' || lpad((1000 + n)::text, 4, '0'),
       n <> 6
FROM generate_series(1, 6) AS g(n);

UPDATE public.profesores p
SET apellido = d.apellido,
    fecha_nacimiento = d.fecha_nacimiento,
    telefono = d.telefono,
    usuario_id = NULL,
    activo = d.activo
FROM _demo_professors_desired d
WHERE p.nombre = d.nombre;

INSERT INTO public.profesores (nombre, apellido, fecha_nacimiento, telefono, usuario_id, activo, version)
SELECT d.nombre, d.apellido, d.fecha_nacimiento, d.telefono, NULL, d.activo, 0
FROM _demo_professors_desired d
WHERE NOT EXISTS (SELECT 1 FROM public.profesores p WHERE p.nombre = d.nombre);

UPDATE public.observaciones_profesores op
SET fecha = (SELECT anchor_date - 20 FROM _demo_config),
    activa = TRUE
FROM public.profesores p, _demo_professors_desired d
WHERE op.profesor_id = p.id
  AND p.nombre = d.nombre
  AND op.observacion = '[DEMO:PROFESOR:' || lpad(d.seq::text, 2, '0') || '] Seguimiento interno ficticio.';

INSERT INTO public.observaciones_profesores (profesor_id, fecha, observacion, activa)
SELECT p.id,
       (SELECT anchor_date - 20 FROM _demo_config),
       '[DEMO:PROFESOR:' || lpad(d.seq::text, 2, '0') || '] Seguimiento interno ficticio.',
       TRUE
FROM _demo_professors_desired d
JOIN public.profesores p ON p.nombre = d.nombre
WHERE NOT EXISTS (
    SELECT 1 FROM public.observaciones_profesores op
    WHERE op.profesor_id = p.id
      AND op.observacion = '[DEMO:PROFESOR:' || lpad(d.seq::text, 2, '0') || '] Seguimiento interno ficticio.'
);

INSERT INTO public.bonificaciones
    (descripcion, porcentaje_descuento, valor_fijo, activo, observaciones)
VALUES
    ('DEMO · Hermanos 10%', 10.0000, 0.00, TRUE, 'Beneficio ficticio por grupo familiar.'),
    ('DEMO · Beca 25%', 25.0000, 0.00, TRUE, 'Beca parcial ficticia.'),
    ('DEMO · Descuento fijo', 0.0000, 3500.00, TRUE, 'Descuento fijo de demostración.'),
    ('DEMO · Beneficio inactivo', 5.0000, 0.00, FALSE, 'Histórico no asignable.')
ON CONFLICT (descripcion) DO UPDATE
SET porcentaje_descuento = EXCLUDED.porcentaje_descuento,
    valor_fijo = EXCLUDED.valor_fijo,
    activo = EXCLUDED.activo,
    observaciones = EXCLUDED.observaciones;

INSERT INTO public.recargos
    (descripcion, porcentaje, valor_fijo, dia_del_mes_aplicacion, activo)
VALUES
    ('DEMO · Mora 5%', 5.0000, 0.00, 11, TRUE),
    ('DEMO · Gestión fija', 0.0000, 2500.00, 16, TRUE),
    ('DEMO · Recargo histórico', 8.0000, 0.00, 20, FALSE)
ON CONFLICT (descripcion) DO UPDATE
SET porcentaje = EXCLUDED.porcentaje,
    valor_fijo = EXCLUDED.valor_fijo,
    dia_del_mes_aplicacion = EXCLUDED.dia_del_mes_aplicacion,
    activo = EXCLUDED.activo;

INSERT INTO public.metodo_pagos (descripcion, activo, recargo)
VALUES
    ('DEMO · Efectivo', TRUE, 0.0000),
    ('DEMO · Transferencia', TRUE, 0.0000),
    ('DEMO · Débito', TRUE, 0.0000),
    ('DEMO · Crédito', TRUE, 3.0000)
ON CONFLICT (descripcion) DO UPDATE
SET activo = EXCLUDED.activo,
    recargo = EXCLUDED.recargo;

INSERT INTO public.sub_conceptos (descripcion, activo)
VALUES
    ('DEMO · Indumentaria', TRUE),
    ('DEMO · Materiales', TRUE),
    ('DEMO · Eventos', TRUE),
    ('DEMO · Administración', TRUE)
ON CONFLICT (descripcion) DO UPDATE SET activo = EXCLUDED.activo;

CREATE TEMP TABLE _demo_concepts_desired (
    seq integer PRIMARY KEY,
    sub_description varchar(150) NOT NULL,
    description varchar(150) NOT NULL,
    price numeric(19,2) NOT NULL
) ON COMMIT DROP;

INSERT INTO _demo_concepts_desired VALUES
    (1, 'DEMO · Indumentaria', 'DEMO · Remera institucional', 12000.00),
    (2, 'DEMO · Indumentaria', 'DEMO · Medias de danza', 8500.00),
    (3, 'DEMO · Materiales', 'DEMO · Kit de práctica', 9500.00),
    (4, 'DEMO · Materiales', 'DEMO · Cuaderno coreográfico', 6000.00),
    (5, 'DEMO · Eventos', 'DEMO · Entrada muestra', 15000.00),
    (6, 'DEMO · Eventos', 'DEMO · Taller especial', 18000.00),
    (7, 'DEMO · Administración', 'DEMO · Certificado', 7000.00),
    (8, 'DEMO · Administración', 'DEMO · Duplicado de credencial', 5000.00);

INSERT INTO public.conceptos (descripcion, precio, sub_concepto_id, activo)
SELECT d.description, d.price, sc.id, TRUE
FROM _demo_concepts_desired d
JOIN public.sub_conceptos sc ON sc.descripcion = d.sub_description
ON CONFLICT (sub_concepto_id, descripcion) DO UPDATE
SET precio = EXCLUDED.precio,
    activo = EXCLUDED.activo;

CREATE TEMP TABLE _demo_stocks_desired (
    seq integer PRIMARY KEY,
    nombre varchar(150) NOT NULL,
    precio numeric(19,2) NOT NULL,
    cantidad integer NOT NULL,
    control boolean NOT NULL,
    barcode varchar(100) NOT NULL
) ON COMMIT DROP;

INSERT INTO _demo_stocks_desired VALUES
    (1, 'DEMO · Botella reutilizable', 5000.00, 21, TRUE, 'DEMO-STOCK-001'),
    (2, 'DEMO · Remera negra', 9000.00, 17, TRUE, 'DEMO-STOCK-002'),
    (3, 'DEMO · Medias rosa', 6500.00, 19, TRUE, 'DEMO-STOCK-003'),
    (4, 'DEMO · Bolso pequeño', 11000.00, 18, TRUE, 'DEMO-STOCK-004'),
    (5, 'DEMO · Cuaderno', 4500.00, 19, TRUE, 'DEMO-STOCK-005'),
    (6, 'DEMO · Entrada digital', 7500.00, 20, FALSE, 'DEMO-STOCK-006');

INSERT INTO public.stocks
    (nombre, precio, cantidad_actual, requiere_control_de_stock, codigo_barras, activo, version)
SELECT nombre, precio, cantidad, control, barcode, TRUE, 0
FROM _demo_stocks_desired
ON CONFLICT (nombre) DO UPDATE
SET precio = EXCLUDED.precio,
    cantidad_actual = EXCLUDED.cantidad_actual,
    requiere_control_de_stock = EXCLUDED.requiere_control_de_stock,
    codigo_barras = EXCLUDED.codigo_barras,
    activo = EXCLUDED.activo;

-- Alumnos, disciplinas e inscripciones.
CREATE TEMP TABLE _demo_disciplines_desired (
    seq integer PRIMARY KEY,
    nombre varchar(150) NOT NULL,
    room_name varchar(100) NOT NULL,
    professor_name varchar(100) NOT NULL,
    cuota numeric(19,2) NOT NULL,
    matricula numeric(19,2) NOT NULL
) ON COMMIT DROP;

INSERT INTO _demo_disciplines_desired
SELECT n,
       CASE n WHEN 1 THEN 'DEMO · Ballet inicial' WHEN 2 THEN 'DEMO · Jazz infantil'
              WHEN 3 THEN 'DEMO · Urbano teen' WHEN 4 THEN 'DEMO · Contemporáneo'
              WHEN 5 THEN 'DEMO · Ritmos adultos' ELSE 'DEMO · Entrenamiento escénico' END,
       CASE ((n - 1) % 3) WHEN 0 THEN 'DEMO · Sala Norte'
                            WHEN 1 THEN 'DEMO · Sala Sur' ELSE 'DEMO · Estudio Central' END,
       'DEMO · Profesor ' || lpad(n::text, 2, '0'),
       40000.00 + (n - 1) * 1500.00,
       36000.00
FROM generate_series(1, 6) AS g(n);

UPDATE public.disciplinas d
SET salon_id = s.id,
    profesor_id = p.id,
    valor_cuota = x.cuota,
    matricula = x.matricula,
    clase_suelta = 9000.00,
    clase_prueba = 5000.00,
    activo = TRUE
FROM _demo_disciplines_desired x
JOIN public.salones s ON s.nombre = x.room_name
JOIN public.profesores p ON p.nombre = x.professor_name
WHERE d.nombre = x.nombre;

INSERT INTO public.disciplinas
    (nombre, salon_id, profesor_id, valor_cuota, matricula, clase_suelta, clase_prueba, activo, version)
SELECT x.nombre, s.id, p.id, x.cuota, x.matricula, 9000.00, 5000.00, TRUE, 0
FROM _demo_disciplines_desired x
JOIN public.salones s ON s.nombre = x.room_name
JOIN public.profesores p ON p.nombre = x.professor_name
WHERE NOT EXISTS (SELECT 1 FROM public.disciplinas d WHERE d.nombre = x.nombre);

INSERT INTO public.disciplina_horarios (disciplina_id, dia_semana, horario_inicio, duracion)
SELECT d.id,
       CASE x.seq WHEN 1 THEN 'LUNES' WHEN 2 THEN 'MARTES' WHEN 3 THEN 'MIERCOLES'
                  WHEN 4 THEN 'JUEVES' WHEN 5 THEN 'VIERNES' ELSE 'SABADO' END,
       (time '17:00' + (x.seq - 1) * interval '30 minutes')::time,
       1.50
FROM _demo_disciplines_desired x
JOIN public.disciplinas d ON d.nombre = x.nombre
ON CONFLICT (disciplina_id, dia_semana, horario_inicio) DO UPDATE
SET duracion = EXCLUDED.duracion;

INSERT INTO public.disciplina_horarios (disciplina_id, dia_semana, horario_inicio, duracion)
SELECT d.id,
       CASE x.seq WHEN 1 THEN 'MIERCOLES' WHEN 2 THEN 'JUEVES' WHEN 3 THEN 'VIERNES'
                  WHEN 4 THEN 'SABADO' ELSE 'MARTES' END,
       (time '18:00' + (x.seq - 1) * interval '20 minutes')::time,
       1.25
FROM _demo_disciplines_desired x
JOIN public.disciplinas d ON d.nombre = x.nombre
WHERE x.seq <= 5
ON CONFLICT (disciplina_id, dia_semana, horario_inicio) DO UPDATE
SET duracion = EXCLUDED.duracion;

INSERT INTO public.alumnos
    (nombre, apellido, fecha_nacimiento, celular1, celular2, email, documento,
     fecha_incorporacion, fecha_de_baja, nombre_padres, autorizado_para_salir_solo,
     otras_notas, activo, version)
SELECT
    CASE ((n - 1) % 8) WHEN 0 THEN 'Sofía' WHEN 1 THEN 'Mateo' WHEN 2 THEN 'Valentina'
         WHEN 3 THEN 'Joaquín' WHEN 4 THEN 'Martina' WHEN 5 THEN 'Thiago'
         WHEN 6 THEN 'Camila' ELSE 'Benjamín' END || ' ' || lpad(n::text, 2, '0'),
    CASE ((n - 1) % 7) WHEN 0 THEN 'Benítez' WHEN 1 THEN 'Gómez' WHEN 2 THEN 'Pérez'
         WHEN 3 THEN 'Romero' WHEN 4 THEN 'Sosa' WHEN 5 THEN 'Torres' ELSE 'Vega' END,
    (SELECT anchor_date FROM _demo_config) -
        CASE WHEN n <= 18 THEN interval '12 years' + n * interval '2 months'
             ELSE interval '25 years' + n * interval '5 months' END,
    '+54 11 4444-' || lpad((2000 + n)::text, 4, '0'),
    NULL,
    'alumno' || lpad(n::text, 3, '0') || '@gestudio-demo.invalid',
    'DEMO-DNI-A' || lpad(n::text, 3, '0'),
    (SELECT anchor_date FROM _demo_config) - (90 + n),
    CASE WHEN n = 28 THEN (SELECT anchor_date - 15 FROM _demo_config) ELSE NULL END,
    CASE WHEN n <= 18 THEN 'Familia demo ' || lpad(n::text, 2, '0') ELSE NULL END,
    n > 10,
    CASE WHEN n = 1 THEN '[DEMO:SEED_V1] anchor=' || (SELECT anchor_date::text FROM _demo_config)
         ELSE '[DEMO:ALUMNO:' || lpad(n::text, 3, '0') || '] Datos completamente ficticios.' END,
    n <> 28,
    0
FROM generate_series(1, 28) AS g(n)
ON CONFLICT (documento) WHERE documento IS NOT NULL DO UPDATE
SET nombre = EXCLUDED.nombre,
    apellido = EXCLUDED.apellido,
    fecha_nacimiento = EXCLUDED.fecha_nacimiento,
    celular1 = EXCLUDED.celular1,
    celular2 = EXCLUDED.celular2,
    email = EXCLUDED.email,
    fecha_incorporacion = EXCLUDED.fecha_incorporacion,
    fecha_de_baja = EXCLUDED.fecha_de_baja,
    nombre_padres = EXCLUDED.nombre_padres,
    autorizado_para_salir_solo = EXCLUDED.autorizado_para_salir_solo,
    otras_notas = EXCLUDED.otras_notas,
    activo = EXCLUDED.activo;

CREATE TEMP TABLE _demo_enrollments_desired ON COMMIT DROP AS
SELECT
    n AS seq,
    'DEMO-DNI-A' || lpad(n::text, 3, '0') AS document,
    ((n - 1) % 6) + 1 AS discipline_seq,
    'ACTIVA'::varchar(12) AS state,
    NULL::date AS end_date,
    CASE WHEN n % 5 = 0 THEN 37000.00::numeric(19,2) ELSE NULL::numeric(19,2) END AS custom_cost
FROM generate_series(1, 26) AS g(n)
UNION ALL
SELECT
    26 + n,
    'DEMO-DNI-A' || lpad(n::text, 3, '0'),
    (n % 6) + 1,
    CASE WHEN n = 7 THEN 'INACTIVA' WHEN n = 8 THEN 'FINALIZADA' ELSE 'ACTIVA' END,
    CASE WHEN n >= 7 THEN (SELECT anchor_date - 25 FROM _demo_config) ELSE NULL END,
    NULL::numeric(19,2)
FROM generate_series(1, 8) AS g(n);

UPDATE public.inscripciones i
SET bonificacion_id = CASE WHEN x.seq % 3 = 0 THEN b.id ELSE NULL END,
    fecha_inscripcion = (SELECT anchor_date - (160 + x.seq) FROM _demo_config),
    fecha_baja = x.end_date,
    estado = x.state,
    costo_particular = x.custom_cost
FROM _demo_enrollments_desired x
JOIN public.alumnos a ON a.documento = x.document
JOIN _demo_disciplines_desired dd ON dd.seq = x.discipline_seq
JOIN public.disciplinas d ON d.nombre = dd.nombre
LEFT JOIN public.bonificaciones b ON b.descripcion = 'DEMO · Hermanos 10%'
WHERE i.alumno_id = a.id
  AND i.disciplina_id = d.id;

INSERT INTO public.inscripciones
    (alumno_id, disciplina_id, bonificacion_id, fecha_inscripcion, fecha_baja, estado, costo_particular, version)
SELECT a.id,
       d.id,
       CASE WHEN x.seq % 3 = 0 THEN b.id ELSE NULL END,
       (SELECT anchor_date - (160 + x.seq) FROM _demo_config),
       x.end_date,
       x.state,
       x.custom_cost,
       0
FROM _demo_enrollments_desired x
JOIN public.alumnos a ON a.documento = x.document
JOIN _demo_disciplines_desired dd ON dd.seq = x.discipline_seq
JOIN public.disciplinas d ON d.nombre = dd.nombre
LEFT JOIN public.bonificaciones b ON b.descripcion = 'DEMO · Hermanos 10%'
WHERE NOT EXISTS (
    SELECT 1 FROM public.inscripciones i
    WHERE i.alumno_id = a.id AND i.disciplina_id = d.id
);

-- Vigencias económicas.
INSERT INTO public.disciplina_tarifas
    (disciplina_id, vigente_desde, valor_cuota, matricula, clase_suelta, clase_prueba,
     motivo, creada_por_usuario_id, created_at, version)
SELECT d.id,
       periods.start_date,
       CASE WHEN periods.current_rate THEN dd.cuota ELSE dd.cuota - 5000.00 END,
       dd.matricula,
       9000.00,
       5000.00,
       CASE WHEN periods.current_rate THEN '[DEMO:TARIFA] Vigencia actual.'
            ELSE '[DEMO:TARIFA] Vigencia histórica.' END,
       u.id,
       (SELECT anchor_ts FROM _demo_config) + dd.seq * interval '1 second',
       0
FROM _demo_disciplines_desired dd
JOIN public.disciplinas d ON d.nombre = dd.nombre
CROSS JOIN LATERAL (
    VALUES
        ((SELECT month_2 - interval '3 months' FROM _demo_config)::date, FALSE),
        ((SELECT month_0 FROM _demo_config), TRUE)
) AS periods(start_date, current_rate)
JOIN public.usuarios u ON lower(u.nombre_usuario) = 'demo-administrador'
ON CONFLICT (disciplina_id, vigente_desde) DO UPDATE
SET valor_cuota = EXCLUDED.valor_cuota,
    matricula = EXCLUDED.matricula,
    clase_suelta = EXCLUDED.clase_suelta,
    clase_prueba = EXCLUDED.clase_prueba,
    motivo = EXCLUDED.motivo,
    creada_por_usuario_id = EXCLUDED.creada_por_usuario_id,
    created_at = EXCLUDED.created_at;

CREATE TEMP TABLE _demo_enrollment_ids ON COMMIT DROP AS
SELECT i.id,
       a.id AS student_id,
       a.documento,
       i.disciplina_id,
       row_number() OVER (ORDER BY a.documento, d.nombre) AS seq
FROM public.inscripciones i
JOIN public.alumnos a ON a.id = i.alumno_id AND a.documento LIKE 'DEMO-DNI-%'
JOIN public.disciplinas d ON d.id = i.disciplina_id AND d.nombre LIKE 'DEMO · %';

CREATE TEMP TABLE _demo_conditions_desired ON COMMIT DROP AS
SELECT e.id AS enrollment_id,
       (SELECT month_2 - interval '3 months' FROM _demo_config)::date AS start_date,
       CASE WHEN e.seq % 5 = 0 THEN 37000.00::numeric(19,2) ELSE NULL::numeric(19,2) END AS custom_cost,
       CASE WHEN e.seq % 3 = 0 THEN b.id ELSE NULL END AS bonus_id,
       CASE WHEN e.seq % 3 = 0 THEN b.descripcion ELSE NULL END AS bonus_description,
       CASE WHEN e.seq % 3 = 0 THEN b.porcentaje_descuento ELSE 0.0000 END AS bonus_percent,
       0.00::numeric(19,2) AS bonus_fixed,
       '[DEMO:CONDICION] Condición histórica.'::varchar(500) AS reason,
       e.seq
FROM _demo_enrollment_ids e
LEFT JOIN public.bonificaciones b ON b.descripcion = 'DEMO · Hermanos 10%'
UNION ALL
SELECT e.id,
       (SELECT month_0 FROM _demo_config),
       CASE WHEN e.seq % 2 = 0 THEN 39000.00::numeric(19,2) ELSE NULL::numeric(19,2) END,
       b.id,
       b.descripcion,
       b.porcentaje_descuento,
       b.valor_fijo,
       '[DEMO:CONDICION] Cambio de condición actual.',
       100 + e.seq
FROM _demo_enrollment_ids e
JOIN public.bonificaciones b ON b.descripcion = 'DEMO · Beca 25%'
WHERE e.seq <= 6;

INSERT INTO public.inscripcion_condiciones_economicas
    (inscripcion_id, vigente_desde, costo_particular, bonificacion_id,
     bonificacion_descripcion_snapshot, bonificacion_porcentaje_snapshot,
     bonificacion_valor_fijo_snapshot, motivo, creada_por_usuario_id, created_at, version)
SELECT x.enrollment_id,
       x.start_date,
       x.custom_cost,
       x.bonus_id,
       x.bonus_description,
       x.bonus_percent,
       x.bonus_fixed,
       x.reason,
       u.id,
       (SELECT anchor_ts FROM _demo_config) + x.seq * interval '1 second',
       0
FROM _demo_conditions_desired x
JOIN public.usuarios u ON lower(u.nombre_usuario) = 'demo-administrador'
ON CONFLICT (inscripcion_id, vigente_desde) DO UPDATE
SET costo_particular = EXCLUDED.costo_particular,
    bonificacion_id = EXCLUDED.bonificacion_id,
    bonificacion_descripcion_snapshot = EXCLUDED.bonificacion_descripcion_snapshot,
    bonificacion_porcentaje_snapshot = EXCLUDED.bonificacion_porcentaje_snapshot,
    bonificacion_valor_fijo_snapshot = EXCLUDED.bonificacion_valor_fijo_snapshot,
    motivo = EXCLUDED.motivo,
    creada_por_usuario_id = EXCLUDED.creada_por_usuario_id,
    created_at = EXCLUDED.created_at;

-- Mensualidades, matrículas y asistencias.
CREATE TEMP TABLE _demo_monthly_desired ON COMMIT DROP AS
SELECT e.id AS enrollment_id,
       extract(year FROM period.start_date)::integer AS year_value,
       extract(month FROM period.start_date)::integer AS month_value,
       period.start_date AS period_start,
       e.seq
FROM _demo_enrollment_ids e
CROSS JOIN LATERAL (
    VALUES ((SELECT month_2 FROM _demo_config)), ((SELECT month_1 FROM _demo_config))
) AS period(start_date)
UNION ALL
SELECT e.id,
       extract(year FROM (SELECT month_0 FROM _demo_config))::integer,
       extract(month FROM (SELECT month_0 FROM _demo_config))::integer,
       (SELECT month_0 FROM _demo_config),
       100 + e.seq
FROM _demo_enrollment_ids e
JOIN _demo_enrollments_desired desired
  ON desired.document = e.documento
 AND desired.discipline_seq = (
      SELECT dd.seq FROM public.disciplinas d
      JOIN _demo_disciplines_desired dd ON dd.nombre = d.nombre
      WHERE d.id = e.disciplina_id
 )
WHERE desired.seq IN (1, 2);

INSERT INTO public.mensualidades
    (inscripcion_id, bonificacion_id, recargo_id, anio, mes, fecha_generacion,
     fecha_vencimiento, descripcion, estado, version)
SELECT x.enrollment_id,
       CASE WHEN x.seq % 3 = 0 THEN b.id ELSE NULL END,
       CASE WHEN x.seq % 7 = 0 THEN r.id ELSE NULL END,
       x.year_value,
       x.month_value,
       x.period_start,
       x.period_start + 9,
       'DEMO · Cuota ' || to_char(x.period_start, 'MM/YYYY'),
       'EMITIDA',
       0
FROM _demo_monthly_desired x
LEFT JOIN public.bonificaciones b ON b.descripcion = 'DEMO · Hermanos 10%'
LEFT JOIN public.recargos r ON r.descripcion = 'DEMO · Mora 5%'
ON CONFLICT (inscripcion_id, anio, mes) DO UPDATE
SET bonificacion_id = EXCLUDED.bonificacion_id,
    recargo_id = EXCLUDED.recargo_id,
    fecha_generacion = EXCLUDED.fecha_generacion,
    fecha_vencimiento = EXCLUDED.fecha_vencimiento,
    descripcion = EXCLUDED.descripcion,
    estado = EXCLUDED.estado;

INSERT INTO public.matriculas (alumno_id, anio, fecha_emision, estado, version)
SELECT a.id,
       extract(year FROM (SELECT anchor_date FROM _demo_config))::integer,
       make_date(extract(year FROM (SELECT anchor_date FROM _demo_config))::integer, 2, 15),
       'EMITIDA',
       0
FROM public.alumnos a
WHERE a.documento BETWEEN 'DEMO-DNI-A001' AND 'DEMO-DNI-A026'
ON CONFLICT (alumno_id, anio) DO UPDATE
SET fecha_emision = EXCLUDED.fecha_emision,
    estado = EXCLUDED.estado;

INSERT INTO public.asistencias_mensuales (disciplina_id, mes, anio)
SELECT d.id,
       extract(month FROM (SELECT month_1 FROM _demo_config))::integer,
       extract(year FROM (SELECT month_1 FROM _demo_config))::integer
FROM public.disciplinas d
WHERE d.nombre LIKE 'DEMO · %'
ON CONFLICT (disciplina_id, anio, mes) DO NOTHING;

CREATE TEMP TABLE _demo_attendance_enrollments ON COMMIT DROP AS
SELECT id AS enrollment_id, disciplina_id
FROM (
    SELECT e.*,
           i.estado,
           row_number() OVER (PARTITION BY e.disciplina_id ORDER BY e.documento, e.id) AS position
    FROM _demo_enrollment_ids e
    JOIN public.inscripciones i ON i.id = e.id
    WHERE i.estado = 'ACTIVA'
) ranked
WHERE position <= 3;

INSERT INTO public.asistencias_alumno_mensual
    (inscripcion_id, asistencia_mensual_id, observacion, activo)
SELECT e.enrollment_id,
       am.id,
       '[DEMO:ASISTENCIA] Planilla ficticia del período anterior.',
       TRUE
FROM _demo_attendance_enrollments e
JOIN public.asistencias_mensuales am
  ON am.disciplina_id = e.disciplina_id
 AND am.anio = extract(year FROM (SELECT month_1 FROM _demo_config))::integer
 AND am.mes = extract(month FROM (SELECT month_1 FROM _demo_config))::integer
ON CONFLICT (asistencia_mensual_id, inscripcion_id) DO UPDATE
SET observacion = EXCLUDED.observacion,
    activo = EXCLUDED.activo;

INSERT INTO public.asistencias_diarias
    (asistencia_alumno_mensual_id, fecha, estado, vigente)
SELECT aam.id,
       (SELECT month_1 FROM _demo_config) + days.day_number - 1,
       CASE WHEN (aam.id + days.day_number) % 4 = 0 THEN 'AUSENTE' ELSE 'PRESENTE' END,
       TRUE
FROM public.asistencias_alumno_mensual aam
JOIN _demo_attendance_enrollments e ON e.enrollment_id = aam.inscripcion_id
JOIN public.asistencias_mensuales am
  ON am.id = aam.asistencia_mensual_id
 AND am.disciplina_id = e.disciplina_id
CROSS JOIN (VALUES (5), (12), (19)) AS days(day_number)
ON CONFLICT (asistencia_alumno_mensual_id, fecha) DO UPDATE
SET estado = EXCLUDED.estado,
    vigente = EXCLUDED.vigente;

-- Ventas y cargos. Las claves naturales del namespace reemplazan IDs rígidos.
INSERT INTO public.ventas_stock
    (alumno_id, stock_id, cantidad, precio_unitario, fecha, estado,
     idempotency_key, request_hash, reversal_idempotency_key, reversal_request_hash, version)
SELECT a.id,
       s.id,
       CASE WHEN x.seq IN (2, 4, 6) THEN 2 ELSE 1 END,
       x.precio,
       (SELECT anchor_date - (12 - x.seq) FROM _demo_config),
       CASE WHEN x.seq = 6 THEN 'ANULADA' ELSE 'REGISTRADA' END,
       'demo-seed:v1:venta:' || lpad(x.seq::text, 3, '0'),
       repeat(md5('demo-seed:v1:venta:' || lpad(x.seq::text, 3, '0')), 2),
       CASE WHEN x.seq = 6 THEN 'demo-seed:v1:venta-reversa:006' ELSE NULL END,
       CASE WHEN x.seq = 6 THEN repeat(md5('demo-seed:v1:venta-reversa:006'), 2) ELSE NULL END,
       0
FROM _demo_stocks_desired x
JOIN public.stocks s ON s.codigo_barras = x.barcode
JOIN public.alumnos a ON a.documento = 'DEMO-DNI-A' || lpad(x.seq::text, 3, '0')
ON CONFLICT (idempotency_key) DO UPDATE
SET alumno_id = EXCLUDED.alumno_id,
    stock_id = EXCLUDED.stock_id,
    cantidad = EXCLUDED.cantidad,
    precio_unitario = EXCLUDED.precio_unitario,
    fecha = EXCLUDED.fecha,
    estado = EXCLUDED.estado,
    request_hash = EXCLUDED.request_hash,
    reversal_idempotency_key = EXCLUDED.reversal_idempotency_key,
    reversal_request_hash = EXCLUDED.reversal_request_hash;

CREATE TEMP TABLE _demo_monthly_charge_data ON COMMIT DROP AS
SELECT m.id AS monthly_id,
       i.alumno_id,
       a.documento,
       d.nombre AS discipline_name,
       m.anio,
       m.mes,
       m.fecha_generacion,
       m.fecha_vencimiento,
       row_number() OVER (ORDER BY a.documento, d.nombre, m.anio, m.mes) AS seq
FROM public.mensualidades m
JOIN public.inscripciones i ON i.id = m.inscripcion_id
JOIN public.alumnos a ON a.id = i.alumno_id AND a.documento LIKE 'DEMO-DNI-%'
JOIN public.disciplinas d ON d.id = i.disciplina_id AND d.nombre LIKE 'DEMO · %';

INSERT INTO public.cargos
    (alumno_id, tipo, descripcion, importe_original, fecha_emision, fecha_vencimiento,
     estado, mensualidad_id, matricula_id, concepto_id, venta_stock_id, cargo_origen_id,
     idempotency_key, version, created_at)
SELECT x.alumno_id,
       'MENSUALIDAD',
       'DEMO · ' || x.discipline_name || ' ' || lpad(x.mes::text, 2, '0') || '/' || x.anio,
       CASE WHEN x.seq <= 10 THEN 24000.00 ELSE 40000.00 END,
       x.fecha_generacion,
       x.fecha_vencimiento,
       'PENDIENTE',
       x.monthly_id,
       NULL, NULL, NULL, NULL,
       'demo-seed:v1:cargo:mensualidad:' || x.documento || ':' || x.anio || ':' || lpad(x.mes::text, 2, '0') || ':' || lpad(x.seq::text, 3, '0'),
       0,
       (SELECT anchor_ts FROM _demo_config) + x.seq * interval '1 second'
FROM _demo_monthly_charge_data x
ON CONFLICT (idempotency_key) DO UPDATE
SET alumno_id = EXCLUDED.alumno_id,
    descripcion = EXCLUDED.descripcion,
    importe_original = EXCLUDED.importe_original,
    fecha_emision = EXCLUDED.fecha_emision,
    fecha_vencimiento = EXCLUDED.fecha_vencimiento,
    estado = EXCLUDED.estado,
    mensualidad_id = EXCLUDED.mensualidad_id,
    created_at = EXCLUDED.created_at;

INSERT INTO public.cargos
    (alumno_id, tipo, descripcion, importe_original, fecha_emision, fecha_vencimiento,
     estado, mensualidad_id, matricula_id, concepto_id, venta_stock_id, cargo_origen_id,
     idempotency_key, version, created_at)
SELECT m.alumno_id,
       'MATRICULA',
       'DEMO · Matrícula anual ' || m.anio,
       36000.00,
       m.fecha_emision,
       m.fecha_emision + 5,
       'PENDIENTE',
       NULL, m.id, NULL, NULL, NULL,
       'demo-seed:v1:cargo:matricula:' || a.documento || ':' || m.anio,
       0,
       (SELECT anchor_ts FROM _demo_config) + (100 + row_number() OVER (ORDER BY a.documento)) * interval '1 second'
FROM public.matriculas m
JOIN public.alumnos a ON a.id = m.alumno_id AND a.documento LIKE 'DEMO-DNI-%'
ON CONFLICT (idempotency_key) DO UPDATE
SET alumno_id = EXCLUDED.alumno_id,
    descripcion = EXCLUDED.descripcion,
    importe_original = EXCLUDED.importe_original,
    fecha_emision = EXCLUDED.fecha_emision,
    fecha_vencimiento = EXCLUDED.fecha_vencimiento,
    estado = EXCLUDED.estado,
    matricula_id = EXCLUDED.matricula_id,
    created_at = EXCLUDED.created_at;

INSERT INTO public.cargos
    (alumno_id, tipo, descripcion, importe_original, fecha_emision, fecha_vencimiento,
     estado, mensualidad_id, matricula_id, concepto_id, venta_stock_id, cargo_origen_id,
     idempotency_key, version, created_at)
SELECT v.alumno_id,
       'VENTA_STOCK',
       'DEMO · Venta de ' || s.nombre,
       v.cantidad * v.precio_unitario,
       v.fecha,
       v.fecha + 10,
       CASE WHEN v.estado = 'ANULADA' THEN 'ANULADO' ELSE 'PENDIENTE' END,
       NULL, NULL, NULL, v.id, NULL,
       'demo-seed:v1:cargo:' || v.idempotency_key,
       0,
       (SELECT anchor_ts FROM _demo_config) + (140 + row_number() OVER (ORDER BY v.idempotency_key)) * interval '1 second'
FROM public.ventas_stock v
JOIN public.stocks s ON s.id = v.stock_id
WHERE v.idempotency_key LIKE 'demo-seed:v1:venta:%'
ON CONFLICT (idempotency_key) DO UPDATE
SET alumno_id = EXCLUDED.alumno_id,
    descripcion = EXCLUDED.descripcion,
    importe_original = EXCLUDED.importe_original,
    fecha_emision = EXCLUDED.fecha_emision,
    fecha_vencimiento = EXCLUDED.fecha_vencimiento,
    estado = EXCLUDED.estado,
    venta_stock_id = EXCLUDED.venta_stock_id,
    created_at = EXCLUDED.created_at;

INSERT INTO public.cargos
    (alumno_id, tipo, descripcion, importe_original, fecha_emision, fecha_vencimiento,
     estado, mensualidad_id, matricula_id, concepto_id, venta_stock_id, cargo_origen_id,
     idempotency_key, version, created_at)
SELECT a.id,
       'CONCEPTO',
       x.description,
       CASE WHEN x.seq = 1 THEN 12000.00 ELSE 50000.00 END,
       (SELECT anchor_date - (9 - x.seq) FROM _demo_config),
       (SELECT anchor_date + 7 FROM _demo_config),
       'PENDIENTE',
       NULL, NULL, c.id, NULL, NULL,
       'demo-seed:v1:cargo:concepto:' || lpad(x.seq::text, 3, '0'),
       0,
       (SELECT anchor_ts FROM _demo_config) + (160 + x.seq) * interval '1 second'
FROM _demo_concepts_desired x
JOIN public.sub_conceptos sc ON sc.descripcion = x.sub_description
JOIN public.conceptos c ON c.sub_concepto_id = sc.id AND c.descripcion = x.description
JOIN public.alumnos a ON a.documento = 'DEMO-DNI-A' || lpad(x.seq::text, 3, '0')
ON CONFLICT (idempotency_key) DO UPDATE
SET alumno_id = EXCLUDED.alumno_id,
    descripcion = EXCLUDED.descripcion,
    importe_original = EXCLUDED.importe_original,
    fecha_emision = EXCLUDED.fecha_emision,
    fecha_vencimiento = EXCLUDED.fecha_vencimiento,
    estado = EXCLUDED.estado,
    concepto_id = EXCLUDED.concepto_id,
    created_at = EXCLUDED.created_at;

CREATE TEMP TABLE _demo_surcharge_origins ON COMMIT DROP AS
SELECT c.id,
       c.alumno_id,
       row_number() OVER (ORDER BY c.idempotency_key) AS seq
FROM public.cargos c
WHERE c.idempotency_key LIKE 'demo-seed:v1:cargo:mensualidad:%'
ORDER BY c.idempotency_key
LIMIT 5;

INSERT INTO public.cargos
    (alumno_id, tipo, descripcion, importe_original, fecha_emision, fecha_vencimiento,
     estado, mensualidad_id, matricula_id, concepto_id, venta_stock_id, cargo_origen_id,
     idempotency_key, version, created_at)
SELECT x.alumno_id,
       'RECARGO',
       'DEMO · Recargo vinculado ' || lpad(x.seq::text, 2, '0'),
       5000.00,
       (SELECT anchor_date - 2 FROM _demo_config),
       (SELECT anchor_date + 5 FROM _demo_config),
       'PENDIENTE',
       NULL, NULL, NULL, NULL, x.id,
       'demo-seed:v1:cargo:recargo:' || lpad(x.seq::text, 3, '0'),
       0,
       (SELECT anchor_ts FROM _demo_config) + (180 + x.seq) * interval '1 second'
FROM _demo_surcharge_origins x
ON CONFLICT (idempotency_key) DO UPDATE
SET alumno_id = EXCLUDED.alumno_id,
    descripcion = EXCLUDED.descripcion,
    importe_original = EXCLUDED.importe_original,
    fecha_emision = EXCLUDED.fecha_emision,
    fecha_vencimiento = EXCLUDED.fecha_vencimiento,
    estado = EXCLUDED.estado,
    cargo_origen_id = EXCLUDED.cargo_origen_id,
    created_at = EXCLUDED.created_at;

INSERT INTO public.cargo_liquidaciones
    (cargo_id, periodo_desde, tarifa_disciplina_id, condicion_inscripcion_id,
     origen_precio, importe_base, descuento_porcentaje, descuento_importe,
     recargo_porcentaje, recargo_importe, importe_final, formula_version,
     observaciones, calculada_por_usuario_id, created_at)
SELECT c.id,
       date_trunc('month', c.fecha_emision)::date,
       NULL,
       NULL,
       'MANUAL_HISTORICO',
       c.importe_original,
       0.0000,
       0.00,
       0.0000,
       0.00,
       c.importe_original,
       1,
       '[DEMO:LIQUIDACION] Snapshot sintético; no genera eventos productivos.',
       u.id,
       c.created_at
FROM public.cargos c
JOIN public.alumnos a ON a.id = c.alumno_id AND a.documento LIKE 'DEMO-DNI-%'
JOIN public.usuarios u ON lower(u.nombre_usuario) = 'demo-administrador'
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
    calculada_por_usuario_id = EXCLUDED.calculada_por_usuario_id,
    created_at = EXCLUDED.created_at;

-- Pagos y aplicaciones. Cada pago agrupa como máximo dos cargos del mismo alumno.
CREATE TEMP TABLE _demo_application_targets ON COMMIT DROP AS
WITH target_charges AS (
    SELECT c.id AS charge_id,
           c.alumno_id,
           a.documento,
           'M'::text AS source_kind,
           c.idempotency_key
    FROM public.cargos c
    JOIN public.alumnos a ON a.id = c.alumno_id AND a.documento LIKE 'DEMO-DNI-%'
    WHERE c.tipo = 'MENSUALIDAD'
      AND c.idempotency_key LIKE 'demo-seed:v1:cargo:mensualidad:%'
    UNION ALL
    SELECT c.id,
           c.alumno_id,
           a.documento,
           'R'::text,
           c.idempotency_key
    FROM public.cargos c
    JOIN public.alumnos a ON a.id = c.alumno_id
    WHERE c.tipo = 'MATRICULA'
      AND a.documento BETWEEN 'DEMO-DNI-A003' AND 'DEMO-DNI-A014'
      AND c.idempotency_key LIKE 'demo-seed:v1:cargo:matricula:%'
), numbered AS (
    SELECT t.*,
           row_number() OVER (ORDER BY t.documento, t.source_kind, t.idempotency_key) AS application_no,
           row_number() OVER (PARTITION BY t.alumno_id ORDER BY t.source_kind, t.idempotency_key) AS student_application_no
    FROM target_charges t
), grouped AS (
    SELECT n.*,
           ((n.student_application_no - 1) / 2 + 1)::integer AS local_payment_no
    FROM numbered n
), payment_numbered AS (
    SELECT g.*,
           dense_rank() OVER (ORDER BY g.documento, g.local_payment_no)::integer AS payment_no
    FROM grouped g
)
SELECT p.charge_id,
       p.alumno_id,
       p.documento,
       p.application_no::integer,
       p.payment_no,
       CASE WHEN p.application_no <= 78 THEN 24000.00::numeric(19,2)
            WHEN p.application_no <= 80 THEN 33350.00::numeric(19,2)
            ELSE 10000.00::numeric(19,2) END AS applied_amount
FROM payment_numbered p;

DO $$
BEGIN
    IF (SELECT count(*) FROM _demo_application_targets) <> 82
       OR (SELECT count(DISTINCT payment_no) FROM _demo_application_targets) <> 48
       OR EXISTS (
            SELECT 1
            FROM _demo_application_targets t
            JOIN public.cargos c ON c.id = t.charge_id
            WHERE t.applied_amount > c.importe_original
       ) THEN
        RAISE EXCEPTION 'No se pudo construir la distribución determinista 82 aplicaciones / 48 pagos';
    END IF;
END
$$;

CREATE TEMP TABLE _demo_payments_desired ON COMMIT DROP AS
SELECT t.payment_no,
       t.alumno_id,
       sum(t.applied_amount) + CASE WHEN t.payment_no = 1 THEN 18000.00 ELSE 0.00 END AS received_amount,
       'demo-seed:v1:pago:' || lpad(t.payment_no::text, 3, '0') AS idempotency_key
FROM _demo_application_targets t
GROUP BY t.payment_no, t.alumno_id;

INSERT INTO public.pagos
    (alumno_id, metodo_pago_id, usuario_id, fecha, monto_recibido, estado,
     idempotency_key, request_hash, reversal_idempotency_key, reversal_request_hash,
     observaciones, motivo_anulacion, fecha_anulacion, version, created_at)
SELECT x.alumno_id,
       mp.id,
       u.id,
       (SELECT anchor_date FROM _demo_config) - ((48 - x.payment_no) % 28),
       x.received_amount,
       CASE WHEN x.payment_no = 48 THEN 'ANULADO' ELSE 'REGISTRADO' END,
       x.idempotency_key,
       repeat(md5(x.idempotency_key), 2),
       CASE WHEN x.payment_no = 48 THEN 'demo-seed:v1:pago-reversa:048' ELSE NULL END,
       CASE WHEN x.payment_no = 48 THEN repeat(md5('demo-seed:v1:pago-reversa:048'), 2) ELSE NULL END,
       CASE WHEN x.payment_no = 1 THEN '[DEMO:PAGO] Incluye excedente para crédito.'
            WHEN (SELECT count(*) FROM _demo_application_targets t WHERE t.payment_no = x.payment_no) = 2
                THEN '[DEMO:PAGO] Distribuido entre dos cargos.'
            ELSE '[DEMO:PAGO] Aplicado a un cargo.' END,
       CASE WHEN x.payment_no = 48 THEN '[DEMO:PAGO] Anulación ficticia.' ELSE NULL END,
       CASE WHEN x.payment_no = 48 THEN (SELECT anchor_ts + interval '6 minutes' FROM _demo_config) ELSE NULL END,
       0,
       (SELECT anchor_ts FROM _demo_config) + (200 + x.payment_no) * interval '1 second'
FROM _demo_payments_desired x
JOIN _demo_stocks_desired ordinal ON ordinal.seq = ((x.payment_no - 1) % 4) + 1
JOIN public.metodo_pagos mp ON mp.descripcion = CASE ordinal.seq
    WHEN 1 THEN 'DEMO · Efectivo' WHEN 2 THEN 'DEMO · Transferencia'
    WHEN 3 THEN 'DEMO · Débito' ELSE 'DEMO · Crédito' END
JOIN public.usuarios u ON lower(u.nombre_usuario) = 'demo-caja'
ON CONFLICT (idempotency_key) DO UPDATE
SET alumno_id = EXCLUDED.alumno_id,
    metodo_pago_id = EXCLUDED.metodo_pago_id,
    usuario_id = EXCLUDED.usuario_id,
    fecha = EXCLUDED.fecha,
    monto_recibido = EXCLUDED.monto_recibido,
    estado = EXCLUDED.estado,
    request_hash = EXCLUDED.request_hash,
    reversal_idempotency_key = EXCLUDED.reversal_idempotency_key,
    reversal_request_hash = EXCLUDED.reversal_request_hash,
    observaciones = EXCLUDED.observaciones,
    motivo_anulacion = EXCLUDED.motivo_anulacion,
    fecha_anulacion = EXCLUDED.fecha_anulacion,
    created_at = EXCLUDED.created_at;

INSERT INTO public.aplicaciones_pago
    (pago_id, cargo_id, usuario_id, importe_aplicado, estado, fecha,
     motivo_reversion, fecha_reversion, version, created_at)
SELECT p.id,
       t.charge_id,
       u.id,
       t.applied_amount,
       CASE WHEN t.payment_no = 48 THEN 'REVERTIDA' ELSE 'APLICADA' END,
       p.fecha,
       CASE WHEN t.payment_no = 48 THEN '[DEMO:PAGO] Aplicación revertida por anulación.' ELSE NULL END,
       CASE WHEN t.payment_no = 48 THEN (SELECT anchor_ts + interval '6 minutes' FROM _demo_config) ELSE NULL END,
       0,
       (SELECT anchor_ts FROM _demo_config) + (260 + t.application_no) * interval '1 second'
FROM _demo_application_targets t
JOIN public.pagos p ON p.idempotency_key = 'demo-seed:v1:pago:' || lpad(t.payment_no::text, 3, '0')
JOIN public.usuarios u ON lower(u.nombre_usuario) = 'demo-caja'
ON CONFLICT (pago_id, cargo_id) DO UPDATE
SET usuario_id = EXCLUDED.usuario_id,
    importe_aplicado = EXCLUDED.importe_aplicado,
    estado = EXCLUDED.estado,
    fecha = EXCLUDED.fecha,
    motivo_reversion = EXCLUDED.motivo_reversion,
    fecha_reversion = EXCLUDED.fecha_reversion,
    created_at = EXCLUDED.created_at;

-- Crédito: generación por excedente, consumos, reversiones y ajustes.
CREATE TEMP TABLE _demo_credit_context ON COMMIT DROP AS
SELECT c.id AS charge_id,
       row_number() OVER (
           ORDER BY CASE c.tipo WHEN 'VENTA_STOCK' THEN 1 WHEN 'CONCEPTO' THEN 2
                                WHEN 'MATRICULA' THEN 3 ELSE 4 END,
                    c.idempotency_key
       )::integer AS seq
FROM public.cargos c
JOIN public.alumnos a ON a.id = c.alumno_id AND a.documento = 'DEMO-DNI-A001'
WHERE c.estado <> 'ANULADO'
  AND NOT EXISTS (SELECT 1 FROM _demo_application_targets t WHERE t.charge_id = c.id)
ORDER BY seq
LIMIT 4;

DO $$
BEGIN
    IF (SELECT count(*) FROM _demo_credit_context) <> 4 THEN
        RAISE EXCEPTION 'No se pudieron resolver cuatro cargos de crédito del mismo alumno';
    END IF;
END
$$;

CREATE TEMP TABLE _demo_credit_originals (
    seq integer PRIMARY KEY,
    movement_type varchar(15) NOT NULL,
    amount numeric(19,2) NOT NULL,
    payment_no integer,
    charge_seq integer,
    reason varchar(500)
) ON COMMIT DROP;

INSERT INTO _demo_credit_originals VALUES
    (1, 'GENERACION', 18000.00, 1, NULL, NULL),
    (2, 'AJUSTE_CREDITO', 10000.00, NULL, NULL, '[DEMO:CREDITO] Ajuste positivo.'),
    (3, 'AJUSTE_DEBITO', 2000.00, NULL, NULL, '[DEMO:CREDITO] Ajuste de débito.'),
    (4, 'CONSUMO', 5000.00, NULL, 1, NULL),
    (5, 'CONSUMO', 4000.00, NULL, 2, NULL),
    (7, 'AJUSTE_CREDITO', 6000.00, NULL, NULL, '[DEMO:CREDITO] Segundo ajuste positivo.'),
    (8, 'AJUSTE_DEBITO', 4000.00, NULL, NULL, '[DEMO:CREDITO] Segundo ajuste de débito.'),
    (9, 'CONSUMO', 2000.00, NULL, 3, NULL),
    (10, 'CONSUMO', 3000.00, NULL, 4, NULL);

INSERT INTO public.movimientos_credito
    (alumno_id, tipo, importe, pago_id, cargo_id, movimiento_revertido_id,
     usuario_id, idempotency_key, request_hash, motivo, created_at)
SELECT a.id,
       x.movement_type,
       x.amount,
       p.id,
       cc.charge_id,
       NULL,
       u.id,
       'demo-seed:v1:credito:' || lpad(x.seq::text, 3, '0'),
       repeat(md5('demo-seed:v1:credito:' || lpad(x.seq::text, 3, '0')), 2),
       x.reason,
       (SELECT anchor_ts FROM _demo_config) + (360 + x.seq) * interval '1 second'
FROM _demo_credit_originals x
JOIN public.alumnos a ON a.documento = 'DEMO-DNI-A001'
JOIN public.usuarios u ON lower(u.nombre_usuario) = 'demo-caja'
LEFT JOIN public.pagos p
  ON p.idempotency_key = 'demo-seed:v1:pago:' || lpad(x.payment_no::text, 3, '0')
LEFT JOIN _demo_credit_context cc ON cc.seq = x.charge_seq
ON CONFLICT (idempotency_key) DO UPDATE
SET alumno_id = EXCLUDED.alumno_id,
    tipo = EXCLUDED.tipo,
    importe = EXCLUDED.importe,
    pago_id = EXCLUDED.pago_id,
    cargo_id = EXCLUDED.cargo_id,
    movimiento_revertido_id = EXCLUDED.movimiento_revertido_id,
    usuario_id = EXCLUDED.usuario_id,
    request_hash = EXCLUDED.request_hash,
    motivo = EXCLUDED.motivo,
    created_at = EXCLUDED.created_at;

INSERT INTO public.movimientos_credito
    (alumno_id, tipo, importe, pago_id, cargo_id, movimiento_revertido_id,
     usuario_id, idempotency_key, request_hash, motivo, created_at)
SELECT original.alumno_id,
       'REVERSO',
       original.importe,
       NULL,
       NULL,
       original.id,
       u.id,
       reversal.key_value,
       repeat(md5(reversal.key_value), 2),
       '[DEMO:CREDITO] Reversión de consumo.',
       (SELECT anchor_ts FROM _demo_config) + reversal.seq * interval '1 second'
FROM (VALUES
    (6, 'demo-seed:v1:credito:006', 'demo-seed:v1:credito:005'),
    (11, 'demo-seed:v1:credito:011', 'demo-seed:v1:credito:010')
) AS reversal(seq, key_value, original_key)
JOIN public.movimientos_credito original ON original.idempotency_key = reversal.original_key
JOIN public.usuarios u ON lower(u.nombre_usuario) = 'demo-caja'
ON CONFLICT (idempotency_key) DO UPDATE
SET alumno_id = EXCLUDED.alumno_id,
    tipo = EXCLUDED.tipo,
    importe = EXCLUDED.importe,
    pago_id = EXCLUDED.pago_id,
    cargo_id = EXCLUDED.cargo_id,
    movimiento_revertido_id = EXCLUDED.movimiento_revertido_id,
    usuario_id = EXCLUDED.usuario_id,
    request_hash = EXCLUDED.request_hash,
    motivo = EXCLUDED.motivo,
    created_at = EXCLUDED.created_at;

-- El estado materializado se deriva de aplicaciones y consumo neto de crédito.
WITH paid AS (
    SELECT ap.cargo_id, sum(ap.importe_aplicado) AS amount
    FROM public.aplicaciones_pago ap
    WHERE ap.estado = 'APLICADA'
    GROUP BY ap.cargo_id
), credit AS (
    SELECT cargo_id, sum(amount) AS amount
    FROM (
        SELECT mc.cargo_id, mc.importe AS amount
        FROM public.movimientos_credito mc
        WHERE mc.tipo = 'CONSUMO'
        UNION ALL
        SELECT original.cargo_id, -reversal.importe
        FROM public.movimientos_credito reversal
        JOIN public.movimientos_credito original ON original.id = reversal.movimiento_revertido_id
        WHERE reversal.tipo = 'REVERSO' AND original.tipo = 'CONSUMO'
    ) movements
    GROUP BY cargo_id
), balances AS (
    SELECT c.id,
           c.estado,
           c.importe_original,
           c.venta_stock_id,
           COALESCE(paid.amount, 0) AS paid_amount,
           COALESCE(credit.amount, 0) AS credit_amount
    FROM public.cargos c
    JOIN public.alumnos a ON a.id = c.alumno_id AND a.documento LIKE 'DEMO-DNI-%'
    LEFT JOIN paid ON paid.cargo_id = c.id
    LEFT JOIN credit ON credit.cargo_id = c.id
)
UPDATE public.cargos c
SET estado = CASE
    WHEN balances.estado = 'ANULADO' OR EXISTS (
        SELECT 1 FROM public.ventas_stock v WHERE v.id = balances.venta_stock_id AND v.estado = 'ANULADA'
    ) THEN 'ANULADO'
    WHEN balances.importe_original - balances.paid_amount - balances.credit_amount = 0 THEN 'PAGADO'
    WHEN balances.importe_original - balances.paid_amount - balances.credit_amount < balances.importe_original THEN 'PARCIAL'
    ELSE 'PENDIENTE'
END
FROM balances
WHERE c.id = balances.id;

-- Egresos y libro de caja.
CREATE TEMP TABLE _demo_expenses_desired ON COMMIT DROP AS
SELECT n AS seq,
       (10000 + n * 1250)::numeric(19,2) AS amount,
       CASE WHEN n = 7 THEN 'ANULADO'::varchar(10) ELSE 'REGISTRADO'::varchar(10) END AS state,
       'demo-seed:v1:egreso:' || lpad(n::text, 3, '0') AS key_value
FROM generate_series(1, 7) AS g(n);

INSERT INTO public.egresos
    (fecha, monto, observaciones, metodo_pago_id, estado, usuario_id,
     idempotency_key, request_hash, reversal_idempotency_key, reversal_request_hash,
     motivo_anulacion, fecha_anulacion, version)
SELECT (SELECT anchor_date - (8 - x.seq) FROM _demo_config),
       x.amount,
       '[DEMO:EGRESO] Operación ficticia ' || lpad(x.seq::text, 2, '0') || '.',
       mp.id,
       x.state,
       u.id,
       x.key_value,
       repeat(md5(x.key_value), 2),
       CASE WHEN x.seq = 7 THEN 'demo-seed:v1:egreso-reversa:007' ELSE NULL END,
       CASE WHEN x.seq = 7 THEN repeat(md5('demo-seed:v1:egreso-reversa:007'), 2) ELSE NULL END,
       CASE WHEN x.seq = 7 THEN '[DEMO:EGRESO] Anulación ficticia.' ELSE NULL END,
       CASE WHEN x.seq = 7 THEN (SELECT anchor_ts + interval '7 minutes' FROM _demo_config) ELSE NULL END,
       0
FROM _demo_expenses_desired x
JOIN public.metodo_pagos mp ON mp.descripcion = CASE WHEN x.seq % 2 = 0
    THEN 'DEMO · Transferencia' ELSE 'DEMO · Efectivo' END
JOIN public.usuarios u ON lower(u.nombre_usuario) = 'demo-administrador'
ON CONFLICT (idempotency_key) DO UPDATE
SET fecha = EXCLUDED.fecha,
    monto = EXCLUDED.monto,
    observaciones = EXCLUDED.observaciones,
    metodo_pago_id = EXCLUDED.metodo_pago_id,
    estado = EXCLUDED.estado,
    usuario_id = EXCLUDED.usuario_id,
    request_hash = EXCLUDED.request_hash,
    reversal_idempotency_key = EXCLUDED.reversal_idempotency_key,
    reversal_request_hash = EXCLUDED.reversal_request_hash,
    motivo_anulacion = EXCLUDED.motivo_anulacion,
    fecha_anulacion = EXCLUDED.fecha_anulacion;

INSERT INTO public.movimientos_caja
    (tipo, fecha, importe, metodo_pago_id, pago_id, egreso_id,
     movimiento_revertido_id, usuario_id, idempotency_key, motivo, created_at)
SELECT 'INGRESO_PAGO',
       p.fecha,
       p.monto_recibido,
       p.metodo_pago_id,
       p.id,
       NULL,
       NULL,
       u.id,
       'demo-seed:v1:caja:pago:' || lpad(x.payment_no::text, 3, '0'),
       NULL,
       (SELECT anchor_ts FROM _demo_config) + (400 + x.payment_no) * interval '1 second'
FROM _demo_payments_desired x
JOIN public.pagos p ON p.idempotency_key = x.idempotency_key
JOIN public.usuarios u ON lower(u.nombre_usuario) = 'demo-caja'
ON CONFLICT (idempotency_key) DO UPDATE
SET tipo = EXCLUDED.tipo,
    fecha = EXCLUDED.fecha,
    importe = EXCLUDED.importe,
    metodo_pago_id = EXCLUDED.metodo_pago_id,
    pago_id = EXCLUDED.pago_id,
    egreso_id = EXCLUDED.egreso_id,
    movimiento_revertido_id = EXCLUDED.movimiento_revertido_id,
    usuario_id = EXCLUDED.usuario_id,
    motivo = EXCLUDED.motivo,
    created_at = EXCLUDED.created_at;

INSERT INTO public.movimientos_caja
    (tipo, fecha, importe, metodo_pago_id, pago_id, egreso_id,
     movimiento_revertido_id, usuario_id, idempotency_key, motivo, created_at)
SELECT 'REVERSO',
       (SELECT anchor_date FROM _demo_config),
       original.importe,
       original.metodo_pago_id,
       NULL,
       NULL,
       original.id,
       u.id,
       'demo-seed:v1:caja:reversa-pago:048',
       '[DEMO:CAJA] Reversión del pago anulado.',
       (SELECT anchor_ts + interval '7 minutes' FROM _demo_config)
FROM public.movimientos_caja original
JOIN public.usuarios u ON lower(u.nombre_usuario) = 'demo-caja'
WHERE original.idempotency_key = 'demo-seed:v1:caja:pago:048'
ON CONFLICT (idempotency_key) DO UPDATE
SET tipo = EXCLUDED.tipo,
    fecha = EXCLUDED.fecha,
    importe = EXCLUDED.importe,
    metodo_pago_id = EXCLUDED.metodo_pago_id,
    pago_id = EXCLUDED.pago_id,
    egreso_id = EXCLUDED.egreso_id,
    movimiento_revertido_id = EXCLUDED.movimiento_revertido_id,
    usuario_id = EXCLUDED.usuario_id,
    motivo = EXCLUDED.motivo,
    created_at = EXCLUDED.created_at;

INSERT INTO public.movimientos_caja
    (tipo, fecha, importe, metodo_pago_id, pago_id, egreso_id,
     movimiento_revertido_id, usuario_id, idempotency_key, motivo, created_at)
SELECT 'EGRESO',
       e.fecha,
       e.monto,
       e.metodo_pago_id,
       NULL,
       e.id,
       NULL,
       u.id,
       'demo-seed:v1:caja:egreso:' || lpad(x.seq::text, 3, '0'),
       NULL,
       (SELECT anchor_ts FROM _demo_config) + (460 + x.seq) * interval '1 second'
FROM _demo_expenses_desired x
JOIN public.egresos e ON e.idempotency_key = x.key_value
JOIN public.usuarios u ON lower(u.nombre_usuario) = 'demo-administrador'
ON CONFLICT (idempotency_key) DO UPDATE
SET tipo = EXCLUDED.tipo,
    fecha = EXCLUDED.fecha,
    importe = EXCLUDED.importe,
    metodo_pago_id = EXCLUDED.metodo_pago_id,
    pago_id = EXCLUDED.pago_id,
    egreso_id = EXCLUDED.egreso_id,
    movimiento_revertido_id = EXCLUDED.movimiento_revertido_id,
    usuario_id = EXCLUDED.usuario_id,
    motivo = EXCLUDED.motivo,
    created_at = EXCLUDED.created_at;

INSERT INTO public.movimientos_caja
    (tipo, fecha, importe, metodo_pago_id, pago_id, egreso_id,
     movimiento_revertido_id, usuario_id, idempotency_key, motivo, created_at)
SELECT 'REVERSO',
       (SELECT anchor_date FROM _demo_config),
       original.importe,
       original.metodo_pago_id,
       NULL,
       NULL,
       original.id,
       u.id,
       'demo-seed:v1:caja:reversa-egreso:007',
       '[DEMO:CAJA] Reversión del egreso anulado.',
       (SELECT anchor_ts + interval '8 minutes' FROM _demo_config)
FROM public.movimientos_caja original
JOIN public.usuarios u ON lower(u.nombre_usuario) = 'demo-administrador'
WHERE original.idempotency_key = 'demo-seed:v1:caja:egreso:007'
ON CONFLICT (idempotency_key) DO UPDATE
SET tipo = EXCLUDED.tipo,
    fecha = EXCLUDED.fecha,
    importe = EXCLUDED.importe,
    metodo_pago_id = EXCLUDED.metodo_pago_id,
    pago_id = EXCLUDED.pago_id,
    egreso_id = EXCLUDED.egreso_id,
    movimiento_revertido_id = EXCLUDED.movimiento_revertido_id,
    usuario_id = EXCLUDED.usuario_id,
    motivo = EXCLUDED.motivo,
    created_at = EXCLUDED.created_at;

INSERT INTO public.movimientos_caja
    (tipo, fecha, importe, metodo_pago_id, pago_id, egreso_id,
     movimiento_revertido_id, usuario_id, idempotency_key, motivo, created_at)
SELECT CASE WHEN n <= 3 THEN 'AJUSTE_INGRESO' ELSE 'AJUSTE_EGRESO' END,
       (SELECT anchor_date FROM _demo_config),
       (1000 + n * 250)::numeric(19,2),
       mp.id,
       NULL,
       NULL,
       NULL,
       u.id,
       'demo-seed:v1:caja:ajuste:' || lpad(n::text, 3, '0'),
       '[DEMO:CAJA] Ajuste manual ficticio.',
       (SELECT anchor_ts FROM _demo_config) + (480 + n) * interval '1 second'
FROM generate_series(1, 4) AS g(n)
JOIN public.metodo_pagos mp ON mp.descripcion = 'DEMO · Efectivo'
JOIN public.usuarios u ON lower(u.nombre_usuario) = 'demo-administrador'
ON CONFLICT (idempotency_key) DO UPDATE
SET tipo = EXCLUDED.tipo,
    fecha = EXCLUDED.fecha,
    importe = EXCLUDED.importe,
    metodo_pago_id = EXCLUDED.metodo_pago_id,
    pago_id = EXCLUDED.pago_id,
    egreso_id = EXCLUDED.egreso_id,
    movimiento_revertido_id = EXCLUDED.movimiento_revertido_id,
    usuario_id = EXCLUDED.usuario_id,
    motivo = EXCLUDED.motivo,
    created_at = EXCLUDED.created_at;

-- Libro de stock: cinco ingresos, seis ventas, dos ajustes y una reversión.
INSERT INTO public.movimientos_stock
    (stock_id, tipo, cantidad, venta_stock_id, movimiento_revertido_id,
     usuario_id, idempotency_key, motivo, created_at)
SELECT s.id,
       'INGRESO',
       20,
       NULL,
       NULL,
       u.id,
       'demo-seed:v1:stock:ingreso:' || lpad(x.seq::text, 3, '0'),
       '[DEMO:STOCK] Existencia inicial.',
       (SELECT anchor_ts FROM _demo_config) + (500 + x.seq) * interval '1 second'
FROM _demo_stocks_desired x
JOIN public.stocks s ON s.codigo_barras = x.barcode
JOIN public.usuarios u ON lower(u.nombre_usuario) = 'demo-administrador'
WHERE x.seq <= 5
ON CONFLICT (idempotency_key) DO UPDATE
SET stock_id = EXCLUDED.stock_id,
    tipo = EXCLUDED.tipo,
    cantidad = EXCLUDED.cantidad,
    venta_stock_id = EXCLUDED.venta_stock_id,
    movimiento_revertido_id = EXCLUDED.movimiento_revertido_id,
    usuario_id = EXCLUDED.usuario_id,
    motivo = EXCLUDED.motivo,
    created_at = EXCLUDED.created_at;

INSERT INTO public.movimientos_stock
    (stock_id, tipo, cantidad, venta_stock_id, movimiento_revertido_id,
     usuario_id, idempotency_key, motivo, created_at)
SELECT v.stock_id,
       'VENTA',
       v.cantidad,
       v.id,
       NULL,
       u.id,
       'demo-seed:v1:stock:venta:' || lpad(x.seq::text, 3, '0'),
       NULL,
       (SELECT anchor_ts FROM _demo_config) + (510 + x.seq) * interval '1 second'
FROM _demo_stocks_desired x
JOIN public.ventas_stock v ON v.idempotency_key = 'demo-seed:v1:venta:' || lpad(x.seq::text, 3, '0')
JOIN public.usuarios u ON lower(u.nombre_usuario) = 'demo-administrador'
ON CONFLICT (idempotency_key) DO UPDATE
SET stock_id = EXCLUDED.stock_id,
    tipo = EXCLUDED.tipo,
    cantidad = EXCLUDED.cantidad,
    venta_stock_id = EXCLUDED.venta_stock_id,
    movimiento_revertido_id = EXCLUDED.movimiento_revertido_id,
    usuario_id = EXCLUDED.usuario_id,
    motivo = EXCLUDED.motivo,
    created_at = EXCLUDED.created_at;

INSERT INTO public.movimientos_stock
    (stock_id, tipo, cantidad, venta_stock_id, movimiento_revertido_id,
     usuario_id, idempotency_key, motivo, created_at)
SELECT s.id,
       adjustment.movement_type,
       adjustment.quantity,
       NULL,
       NULL,
       u.id,
       adjustment.key_value,
       adjustment.reason,
       (SELECT anchor_ts FROM _demo_config) + adjustment.seq * interval '1 second'
FROM (VALUES
    (520, 'DEMO-STOCK-001', 'AJUSTE_POSITIVO', 2, 'demo-seed:v1:stock:ajuste-positivo:001', '[DEMO:STOCK] Ajuste positivo.'),
    (521, 'DEMO-STOCK-002', 'AJUSTE_NEGATIVO', 1, 'demo-seed:v1:stock:ajuste-negativo:002', '[DEMO:STOCK] Ajuste negativo.')
) AS adjustment(seq, barcode, movement_type, quantity, key_value, reason)
JOIN public.stocks s ON s.codigo_barras = adjustment.barcode
JOIN public.usuarios u ON lower(u.nombre_usuario) = 'demo-administrador'
ON CONFLICT (idempotency_key) DO UPDATE
SET stock_id = EXCLUDED.stock_id,
    tipo = EXCLUDED.tipo,
    cantidad = EXCLUDED.cantidad,
    venta_stock_id = EXCLUDED.venta_stock_id,
    movimiento_revertido_id = EXCLUDED.movimiento_revertido_id,
    usuario_id = EXCLUDED.usuario_id,
    motivo = EXCLUDED.motivo,
    created_at = EXCLUDED.created_at;

INSERT INTO public.movimientos_stock
    (stock_id, tipo, cantidad, venta_stock_id, movimiento_revertido_id,
     usuario_id, idempotency_key, motivo, created_at)
SELECT original.stock_id,
       'REVERSO',
       original.cantidad,
       NULL,
       original.id,
       u.id,
       'demo-seed:v1:stock:reversa-venta:006',
       '[DEMO:STOCK] Restitución por venta anulada.',
       (SELECT anchor_ts + interval '9 minutes' FROM _demo_config)
FROM public.movimientos_stock original
JOIN public.usuarios u ON lower(u.nombre_usuario) = 'demo-administrador'
WHERE original.idempotency_key = 'demo-seed:v1:stock:venta:006'
ON CONFLICT (idempotency_key) DO UPDATE
SET stock_id = EXCLUDED.stock_id,
    tipo = EXCLUDED.tipo,
    cantidad = EXCLUDED.cantidad,
    venta_stock_id = EXCLUDED.venta_stock_id,
    movimiento_revertido_id = EXCLUDED.movimiento_revertido_id,
    usuario_id = EXCLUDED.usuario_id,
    motivo = EXCLUDED.motivo,
    created_at = EXCLUDED.created_at;

-- Recibos históricos y outbox técnica; no se crean archivos físicos.
INSERT INTO public.recibos (pago_id, storage_key, generado_at, enviado_at)
SELECT p.id,
       'demo/recibos/pago-' || lpad(x.payment_no::text, 3, '0') || '.pdf',
       (SELECT anchor_ts FROM _demo_config) + (600 + x.payment_no) * interval '1 second',
       CASE WHEN x.payment_no % 4 = 0
            THEN (SELECT anchor_ts FROM _demo_config) + (700 + x.payment_no) * interval '1 second'
            ELSE NULL END
FROM _demo_payments_desired x
JOIN public.pagos p ON p.idempotency_key = x.idempotency_key
ON CONFLICT (pago_id) DO UPDATE
SET storage_key = EXCLUDED.storage_key,
    generado_at = EXCLUDED.generado_at,
    enviado_at = EXCLUDED.enviado_at;

INSERT INTO public.recibos_pendientes
    (pago_id, tipo, estado, intentos, next_attempt_at, idempotency_key,
     claim_token, claimed_at, lease_until, ultimo_error, created_at, processed_at)
SELECT p.id,
       'GENERAR_Y_ENVIAR',
       CASE WHEN x.payment_no % 4 = 0 THEN 'COMPLETADO' ELSE 'PENDIENTE' END,
       CASE WHEN x.payment_no % 4 = 0 THEN 1 ELSE 0 END,
       (SELECT anchor_ts FROM _demo_config) + interval '1 day',
       'demo-seed:v1:recibo:' || lpad(x.payment_no::text, 3, '0'),
       NULL,
       NULL,
       NULL,
       NULL,
       (SELECT anchor_ts FROM _demo_config) + (750 + x.payment_no) * interval '1 second',
       CASE WHEN x.payment_no % 4 = 0
            THEN (SELECT anchor_ts FROM _demo_config) + (800 + x.payment_no) * interval '1 second'
            ELSE NULL END
FROM _demo_payments_desired x
JOIN public.pagos p ON p.idempotency_key = x.idempotency_key
ON CONFLICT (pago_id, tipo) DO UPDATE
SET estado = EXCLUDED.estado,
    intentos = EXCLUDED.intentos,
    next_attempt_at = EXCLUDED.next_attempt_at,
    idempotency_key = EXCLUDED.idempotency_key,
    claim_token = EXCLUDED.claim_token,
    claimed_at = EXCLUDED.claimed_at,
    lease_until = EXCLUDED.lease_until,
    ultimo_error = EXCLUDED.ultimo_error,
    created_at = EXCLUDED.created_at,
    processed_at = EXCLUDED.processed_at;

-- Validaciones internas antes de confirmar la transacción.
DO $$
DECLARE
    actual_counts jsonb;
    expected_counts jsonb;
    direct_total integer;
    registered_payments numeric(19,2);
    active_applications numeric(19,2);
    active_payment_credit numeric(19,2);
    net_credit numeric(19,2);
BEGIN
    SELECT jsonb_build_object(
        'usuarios', (SELECT count(*) FROM public.usuarios WHERE lower(nombre_usuario) LIKE 'demo-%'),
        'usuario_roles', (SELECT count(*) FROM public.usuario_roles ur JOIN public.usuarios u ON u.id = ur.usuario_id WHERE lower(u.nombre_usuario) LIKE 'demo-%'),
        'salones', (SELECT count(*) FROM public.salones WHERE nombre LIKE 'DEMO · %'),
        'profesores', (SELECT count(*) FROM public.profesores WHERE nombre LIKE 'DEMO · Profesor %'),
        'observaciones_profesores', (SELECT count(*) FROM public.observaciones_profesores op JOIN public.profesores p ON p.id = op.profesor_id WHERE p.nombre LIKE 'DEMO · Profesor %'),
        'bonificaciones', (SELECT count(*) FROM public.bonificaciones WHERE descripcion LIKE 'DEMO · %'),
        'recargos', (SELECT count(*) FROM public.recargos WHERE descripcion LIKE 'DEMO · %'),
        'metodo_pagos', (SELECT count(*) FROM public.metodo_pagos WHERE descripcion LIKE 'DEMO · %'),
        'sub_conceptos', (SELECT count(*) FROM public.sub_conceptos WHERE descripcion LIKE 'DEMO · %'),
        'conceptos', (SELECT count(*) FROM public.conceptos WHERE descripcion LIKE 'DEMO · %'),
        'stocks', (SELECT count(*) FROM public.stocks WHERE codigo_barras LIKE 'DEMO-STOCK-%'),
        'disciplinas', (SELECT count(*) FROM public.disciplinas WHERE nombre LIKE 'DEMO · %'),
        'disciplina_horarios', (
            SELECT count(*) FROM public.disciplina_horarios h
            JOIN public.disciplinas d ON d.id = h.disciplina_id WHERE d.nombre LIKE 'DEMO · %'
        ),
        'alumnos', (SELECT count(*) FROM public.alumnos WHERE documento LIKE 'DEMO-DNI-%'),
        'inscripciones', (
            SELECT count(*) FROM public.inscripciones i
            JOIN public.alumnos a ON a.id = i.alumno_id WHERE a.documento LIKE 'DEMO-DNI-%'
        ),
        'disciplina_tarifas', (
            SELECT count(*) FROM public.disciplina_tarifas t
            JOIN public.disciplinas d ON d.id = t.disciplina_id WHERE d.nombre LIKE 'DEMO · %'
        ),
        'inscripcion_condiciones_economicas', (
            SELECT count(*) FROM public.inscripcion_condiciones_economicas c
            JOIN public.inscripciones i ON i.id = c.inscripcion_id
            JOIN public.alumnos a ON a.id = i.alumno_id WHERE a.documento LIKE 'DEMO-DNI-%'
        ),
        'mensualidades', (
            SELECT count(*) FROM public.mensualidades m
            JOIN public.inscripciones i ON i.id = m.inscripcion_id
            JOIN public.alumnos a ON a.id = i.alumno_id WHERE a.documento LIKE 'DEMO-DNI-%'
        ),
        'matriculas', (
            SELECT count(*) FROM public.matriculas m
            JOIN public.alumnos a ON a.id = m.alumno_id WHERE a.documento LIKE 'DEMO-DNI-%'
        ),
        'asistencias_mensuales', (
            SELECT count(*) FROM public.asistencias_mensuales am
            JOIN public.disciplinas d ON d.id = am.disciplina_id WHERE d.nombre LIKE 'DEMO · %'
        ),
        'asistencias_alumno_mensual', (
            SELECT count(*) FROM public.asistencias_alumno_mensual aam
            JOIN public.inscripciones i ON i.id = aam.inscripcion_id
            JOIN public.alumnos a ON a.id = i.alumno_id WHERE a.documento LIKE 'DEMO-DNI-%'
        ),
        'asistencias_diarias', (
            SELECT count(*) FROM public.asistencias_diarias ad
            JOIN public.asistencias_alumno_mensual aam ON aam.id = ad.asistencia_alumno_mensual_id
            JOIN public.inscripciones i ON i.id = aam.inscripcion_id
            JOIN public.alumnos a ON a.id = i.alumno_id WHERE a.documento LIKE 'DEMO-DNI-%'
        ),
        'ventas_stock', (SELECT count(*) FROM public.ventas_stock WHERE idempotency_key LIKE 'demo-seed:v1:%'),
        'cargos', (SELECT count(*) FROM public.cargos WHERE idempotency_key LIKE 'demo-seed:v1:%'),
        'cargo_liquidaciones', (
            SELECT count(*) FROM public.cargo_liquidaciones cl
            JOIN public.cargos c ON c.id = cl.cargo_id WHERE c.idempotency_key LIKE 'demo-seed:v1:%'
        ),
        'pagos', (SELECT count(*) FROM public.pagos WHERE idempotency_key LIKE 'demo-seed:v1:%'),
        'aplicaciones_pago', (
            SELECT count(*) FROM public.aplicaciones_pago ap
            JOIN public.pagos p ON p.id = ap.pago_id WHERE p.idempotency_key LIKE 'demo-seed:v1:%'
        ),
        'egresos', (SELECT count(*) FROM public.egresos WHERE idempotency_key LIKE 'demo-seed:v1:%'),
        'movimientos_caja', (SELECT count(*) FROM public.movimientos_caja WHERE idempotency_key LIKE 'demo-seed:v1:%'),
        'movimientos_credito', (SELECT count(*) FROM public.movimientos_credito WHERE idempotency_key LIKE 'demo-seed:v1:%'),
        'movimientos_stock', (SELECT count(*) FROM public.movimientos_stock WHERE idempotency_key LIKE 'demo-seed:v1:%'),
        'recibos', (
            SELECT count(*) FROM public.recibos r
            JOIN public.pagos p ON p.id = r.pago_id WHERE p.idempotency_key LIKE 'demo-seed:v1:%'
        ),
        'recibos_pendientes', (
            SELECT count(*) FROM public.recibos_pendientes rp
            JOIN public.pagos p ON p.id = rp.pago_id WHERE p.idempotency_key LIKE 'demo-seed:v1:%'
        )
    ) INTO actual_counts;

    expected_counts := jsonb_build_object(
        'usuarios', 5, 'usuario_roles', 5, 'salones', 3, 'profesores', 6,
        'observaciones_profesores', 6, 'bonificaciones', 4, 'recargos', 3,
        'metodo_pagos', 4, 'sub_conceptos', 4, 'conceptos', 8, 'stocks', 6,
        'disciplinas', 6, 'disciplina_horarios', 11, 'alumnos', 28,
        'inscripciones', 34, 'disciplina_tarifas', 12,
        'inscripcion_condiciones_economicas', 40, 'mensualidades', 70,
        'matriculas', 26, 'asistencias_mensuales', 6,
        'asistencias_alumno_mensual', 18, 'asistencias_diarias', 54,
        'ventas_stock', 6, 'cargos', 115, 'cargo_liquidaciones', 115,
        'pagos', 48, 'aplicaciones_pago', 82, 'egresos', 7,
        'movimientos_caja', 61, 'movimientos_credito', 11,
        'movimientos_stock', 14, 'recibos', 48, 'recibos_pendientes', 48
    );

    IF actual_counts <> expected_counts THEN
        RAISE EXCEPTION 'Conteos demo inesperados. Esperado=%, actual=%', expected_counts, actual_counts;
    END IF;

    SELECT sum(value::integer) INTO direct_total FROM jsonb_each_text(actual_counts);
    IF direct_total <> 914 THEN
        RAISE EXCEPTION 'El total de filas gestionadas directamente debe ser 914 y fue %', direct_total;
    END IF;

    SELECT COALESCE(sum(p.monto_recibido), 0)
    INTO registered_payments
    FROM public.pagos p
    WHERE p.idempotency_key LIKE 'demo-seed:v1:%' AND p.estado = 'REGISTRADO';

    SELECT COALESCE(sum(ap.importe_aplicado), 0)
    INTO active_applications
    FROM public.aplicaciones_pago ap
    JOIN public.pagos p ON p.id = ap.pago_id
    WHERE p.idempotency_key LIKE 'demo-seed:v1:%' AND ap.estado = 'APLICADA';

    SELECT COALESCE(sum(CASE mc.tipo WHEN 'GENERACION' THEN mc.importe
                                     WHEN 'REVERSO' THEN -mc.importe ELSE 0 END), 0)
    INTO active_payment_credit
    FROM public.movimientos_credito mc
    WHERE mc.idempotency_key LIKE 'demo-seed:v1:%'
      AND (mc.pago_id IS NOT NULL OR mc.idempotency_key LIKE 'demo-seed:v1:credito:reversa-generacion%');

    SELECT COALESCE(sum(CASE mc.tipo
        WHEN 'GENERACION' THEN mc.importe
        WHEN 'AJUSTE_CREDITO' THEN mc.importe
        WHEN 'CONSUMO' THEN -mc.importe
        WHEN 'AJUSTE_DEBITO' THEN -mc.importe
        WHEN 'REVERSO' THEN CASE WHEN original.tipo = 'CONSUMO' THEN mc.importe ELSE -mc.importe END
        ELSE 0 END), 0)
    INTO net_credit
    FROM public.movimientos_credito mc
    LEFT JOIN public.movimientos_credito original ON original.id = mc.movimiento_revertido_id
    WHERE mc.idempotency_key LIKE 'demo-seed:v1:%';

    IF registered_payments <> 1956700.00
       OR active_applications <> 1938700.00
       OR active_payment_credit <> 18000.00
       OR net_credit <> 21000.00
       OR registered_payments <> active_applications + active_payment_credit THEN
        RAISE EXCEPTION 'Conciliación financiera inesperada: pagos=%, aplicaciones=%, crédito de pagos=%, crédito neto=%',
            registered_payments, active_applications, active_payment_credit, net_credit;
    END IF;

    IF EXISTS (
        WITH applications AS (
            SELECT pago_id, sum(importe_aplicado) AS amount
            FROM public.aplicaciones_pago WHERE estado = 'APLICADA' GROUP BY pago_id
        ), generated_credit AS (
            SELECT pago_id, sum(importe) AS amount
            FROM public.movimientos_credito WHERE tipo = 'GENERACION' GROUP BY pago_id
        )
        SELECT 1
        FROM public.pagos p
        LEFT JOIN applications ap ON ap.pago_id = p.id
        LEFT JOIN generated_credit mc ON mc.pago_id = p.id
        WHERE p.idempotency_key LIKE 'demo-seed:v1:%'
          AND p.estado = 'REGISTRADO'
          AND p.monto_recibido <> COALESCE(ap.amount, 0) + COALESCE(mc.amount, 0)
    ) THEN
        RAISE EXCEPTION 'Existe un pago registrado no conciliado con aplicaciones y crédito';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.pagos p
        JOIN public.aplicaciones_pago ap ON ap.pago_id = p.id
        WHERE p.idempotency_key = 'demo-seed:v1:pago:048'
          AND (p.estado <> 'ANULADO' OR ap.estado <> 'REVERTIDA')
    ) THEN
        RAISE EXCEPTION 'El escenario de pago anulado no quedó completamente revertido';
    END IF;

    IF EXISTS (
        WITH paid AS (
            SELECT cargo_id, sum(importe_aplicado) AS amount
            FROM public.aplicaciones_pago WHERE estado = 'APLICADA' GROUP BY cargo_id
        ), credit AS (
            SELECT cargo_id, sum(amount) AS amount
            FROM (
                SELECT cargo_id, importe AS amount
                FROM public.movimientos_credito WHERE tipo = 'CONSUMO'
                UNION ALL
                SELECT original.cargo_id, -reversal.importe
                FROM public.movimientos_credito reversal
                JOIN public.movimientos_credito original ON original.id = reversal.movimiento_revertido_id
                WHERE reversal.tipo = 'REVERSO' AND original.tipo = 'CONSUMO'
            ) movements GROUP BY cargo_id
        )
        SELECT 1
        FROM public.cargos c
        JOIN public.alumnos a ON a.id = c.alumno_id AND a.documento LIKE 'DEMO-DNI-%'
        LEFT JOIN paid ON paid.cargo_id = c.id
        LEFT JOIN credit ON credit.cargo_id = c.id
        WHERE COALESCE(paid.amount, 0) + COALESCE(credit.amount, 0) > c.importe_original
           OR c.estado <> CASE
                WHEN c.estado = 'ANULADO' THEN 'ANULADO'
                WHEN c.importe_original - COALESCE(paid.amount, 0) - COALESCE(credit.amount, 0) = 0 THEN 'PAGADO'
                WHEN c.importe_original - COALESCE(paid.amount, 0) - COALESCE(credit.amount, 0) < c.importe_original THEN 'PARCIAL'
                ELSE 'PENDIENTE' END
    ) THEN
        RAISE EXCEPTION 'Existen saldos o estados de cargo incoherentes';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.cargo_liquidaciones cl
        JOIN public.cargos c ON c.id = cl.cargo_id AND c.idempotency_key LIKE 'demo-seed:v1:%'
        WHERE cl.importe_final <> cl.importe_base - cl.descuento_importe + cl.recargo_importe
           OR cl.importe_final <> c.importe_original
    ) THEN
        RAISE EXCEPTION 'Las liquidaciones demo no concilian con sus cargos';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM (
            SELECT mc.alumno_id,
                   sum(CASE mc.tipo
                       WHEN 'GENERACION' THEN mc.importe
                       WHEN 'AJUSTE_CREDITO' THEN mc.importe
                       WHEN 'CONSUMO' THEN -mc.importe
                       WHEN 'AJUSTE_DEBITO' THEN -mc.importe
                       WHEN 'REVERSO' THEN CASE WHEN original.tipo = 'CONSUMO' THEN mc.importe ELSE -mc.importe END
                       ELSE 0 END) AS balance
            FROM public.movimientos_credito mc
            LEFT JOIN public.movimientos_credito original ON original.id = mc.movimiento_revertido_id
            WHERE mc.idempotency_key LIKE 'demo-seed:v1:%'
            GROUP BY mc.alumno_id
        ) balances
        WHERE balances.balance < 0
    ) THEN
        RAISE EXCEPTION 'Existe un saldo de crédito demo negativo';
    END IF;

    IF EXISTS (
        WITH book AS (
            SELECT ms.stock_id,
                   sum(CASE ms.tipo WHEN 'INGRESO' THEN ms.cantidad
                                    WHEN 'AJUSTE_POSITIVO' THEN ms.cantidad
                                    WHEN 'REVERSO' THEN ms.cantidad
                                    WHEN 'VENTA' THEN -ms.cantidad
                                    WHEN 'AJUSTE_NEGATIVO' THEN -ms.cantidad ELSE 0 END) AS quantity
            FROM public.movimientos_stock ms
            WHERE ms.idempotency_key LIKE 'demo-seed:v1:%'
            GROUP BY ms.stock_id
        )
        SELECT 1
        FROM public.stocks s
        JOIN book ON book.stock_id = s.id
        WHERE s.codigo_barras LIKE 'DEMO-STOCK-%'
          AND s.requiere_control_de_stock
          AND (s.cantidad_actual < 0 OR s.cantidad_actual <> book.quantity)
    ) THEN
        RAISE EXCEPTION 'El stock materializado no coincide con el libro demo';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.ventas_stock v
        LEFT JOIN public.cargos c ON c.venta_stock_id = v.id
        LEFT JOIN public.movimientos_stock original ON original.venta_stock_id = v.id AND original.tipo = 'VENTA'
        LEFT JOIN public.movimientos_stock reversal ON reversal.movimiento_revertido_id = original.id AND reversal.tipo = 'REVERSO'
        WHERE v.idempotency_key LIKE 'demo-seed:v1:%'
          AND (c.id IS NULL OR original.id IS NULL
               OR (v.estado = 'REGISTRADA' AND (c.estado = 'ANULADO' OR reversal.id IS NOT NULL))
               OR (v.estado = 'ANULADA' AND (c.estado <> 'ANULADO' OR reversal.id IS NULL)))
    ) THEN
        RAISE EXCEPTION 'Las ventas demo no concilian con cargo y libro de stock';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.usuarios u
        JOIN public.usuario_roles ur ON ur.usuario_id = u.id
        JOIN public.roles r ON r.id = ur.rol_id
        WHERE lower(u.nombre_usuario) LIKE 'demo-%'
          AND (NOT r.activo OR r.codigo = 'PROFESOR' OR u.rol_id <> ur.rol_id)
    ) THEN
        RAISE EXCEPTION 'Las identidades demo tienen roles inactivos, diferidos o desincronizados';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM (
            SELECT movimiento_revertido_id FROM public.movimientos_caja
            WHERE idempotency_key LIKE 'demo-seed:v1:%' AND movimiento_revertido_id IS NOT NULL
            GROUP BY movimiento_revertido_id HAVING count(*) > 1
            UNION ALL
            SELECT movimiento_revertido_id FROM public.movimientos_credito
            WHERE idempotency_key LIKE 'demo-seed:v1:%' AND movimiento_revertido_id IS NOT NULL
            GROUP BY movimiento_revertido_id HAVING count(*) > 1
            UNION ALL
            SELECT movimiento_revertido_id FROM public.movimientos_stock
            WHERE idempotency_key LIKE 'demo-seed:v1:%' AND movimiento_revertido_id IS NOT NULL
            GROUP BY movimiento_revertido_id HAVING count(*) > 1
        ) duplicates
    ) THEN
        RAISE EXCEPTION 'Existe más de una reversión para una operación original';
    END IF;

    IF (SELECT count(*) FROM public.roles) <> (SELECT roles_count FROM _demo_guard)
       OR (SELECT md5(COALESCE(string_agg(
            r.id::text || '|' || r.codigo || '|' || r.activo::text || '|' || r.sistema::text || '|' || r.editable::text,
            E'\n' ORDER BY r.id), '')) FROM public.roles r) <> (SELECT roles_hash FROM _demo_guard)
       OR (SELECT count(*) FROM public.permisos) <> (SELECT permissions_count FROM _demo_guard)
       OR (SELECT md5(COALESCE(string_agg(
            p.id::text || '|' || p.codigo || '|' || p.activo::text || '|' || p.sistema::text || '|' || p.modulo || '|' || p.descripcion,
            E'\n' ORDER BY p.id), '')) FROM public.permisos p) <> (SELECT permissions_hash FROM _demo_guard)
       OR (SELECT count(*) FROM public.rol_permisos) <> (SELECT matrix_count FROM _demo_guard)
       OR (SELECT md5(COALESCE(string_agg(
            rp.rol_id::text || '|' || rp.permiso_id::text,
            E'\n' ORDER BY rp.rol_id, rp.permiso_id), '')) FROM public.rol_permisos rp) <> (SELECT matrix_hash FROM _demo_guard) THEN
        RAISE EXCEPTION 'El catálogo o la matriz RBAC cambió durante el seed';
    END IF;

    IF (SELECT count(*) FROM public.usuarios u WHERE lower(u.nombre_usuario) NOT LIKE 'demo-%') <>
           (SELECT other_users_count FROM _demo_guard)
       OR (SELECT md5(COALESCE(string_agg(to_jsonb(u)::text, E'\n' ORDER BY u.id), ''))
           FROM public.usuarios u WHERE lower(u.nombre_usuario) NOT LIKE 'demo-%') <>
           (SELECT other_users_hash FROM _demo_guard) THEN
        RAISE EXCEPTION 'El seed modificó usuarios ajenos al namespace demo';
    END IF;

    IF (SELECT count(*) FROM public.refresh_sessions) <> (SELECT refresh_count FROM _demo_guard)
       OR (SELECT count(*) FROM public.bootstrap_ejecuciones) <> (SELECT bootstrap_count FROM _demo_guard)
       OR (SELECT count(*) FROM public.auditoria_eventos) <> (SELECT audit_count FROM _demo_guard)
       OR (SELECT count(*) FROM public.cargo_eventos) <> (SELECT charge_events_count FROM _demo_guard)
       OR (SELECT count(*) FROM public.notificaciones) <> (SELECT notifications_count FROM _demo_guard) THEN
        RAISE EXCEPTION 'El SQL pobló una tabla derivada reservada a servicios productivos';
    END IF;

    RAISE NOTICE 'Seed demo validado: 914 filas, RBAC intacto y libros conciliados.';
END
$$;

COMMIT;

\echo GESTUDIO DEMO SEED: ejecución completada y validada
