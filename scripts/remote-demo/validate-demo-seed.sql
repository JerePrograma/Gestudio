WITH demo_students AS (
    SELECT id FROM alumnos WHERE email LIKE '%@correo.local'
), demo_professors AS (
    SELECT id FROM profesores WHERE telefono LIKE '+54 9 11 5555-11%'
), demo_disciplines AS (
    SELECT id FROM disciplinas WHERE nombre IN (
        'Ballet Inicial (4 a 6 años)', 'Jazz Infantil (7 a 10 años)', 'Danza Urbana Teen',
        'Danza Contemporánea', 'Ritmos Latinos Adultos', 'Entrenamiento Escénico'
    )
), demo_enrollments AS (
    SELECT i.id FROM inscripciones i JOIN demo_students a ON a.id = i.alumno_id
), demo_charges AS (
    SELECT id FROM cargos WHERE idempotency_key LIKE 'demo-seed:v1:%'
), demo_payments AS (
    SELECT id FROM pagos WHERE idempotency_key LIKE 'demo-seed:v1:%'
), actual AS (
    SELECT jsonb_build_object(
        'usuarios', (SELECT count(*) FROM usuarios WHERE lower(nombre_usuario) LIKE 'demo-%'),
        'usuario_roles', (SELECT count(*) FROM usuario_roles ur JOIN usuarios u ON u.id=ur.usuario_id WHERE lower(u.nombre_usuario) LIKE 'demo-%'),
        'salones', (SELECT count(*) FROM salones WHERE nombre IN ('Sala Principal','Estudio Infantil','Sala de Ensayo')),
        'profesores', (SELECT count(*) FROM demo_professors),
        'observaciones_profesores', (SELECT count(*) FROM observaciones_profesores op JOIN demo_professors p ON p.id=op.profesor_id WHERE op.observacion='Seguimiento pedagógico trimestral al día.'),
        'bonificaciones', (SELECT count(*) FROM bonificaciones WHERE descripcion IN ('Descuento hermanos 10%','Beca institucional 25%','Convenio familiar','Promoción apertura 2025')),
        'recargos', (SELECT count(*) FROM recargos WHERE descripcion IN ('Mora por vencimiento 5%','Gastos administrativos','Recargo extraordinario 2025')),
        'metodo_pagos', (SELECT count(*) FROM metodo_pagos WHERE descripcion IN ('Efectivo','Transferencia bancaria','Tarjeta de débito','Tarjeta de crédito')),
        'sub_conceptos', (SELECT count(*) FROM sub_conceptos WHERE descripcion IN ('Indumentaria','Materiales de clase','Eventos y talleres','Trámites administrativos')),
        'conceptos', (SELECT count(*) FROM conceptos WHERE descripcion IN ('Remera institucional','Medias de danza','Kit de práctica','Cuaderno coreográfico','Entrada muestra anual','Taller intensivo de fin de semana','Certificado de alumno regular','Duplicado de credencial')),
        'stocks', (SELECT count(*) FROM stocks WHERE codigo_barras IN ('7790000000012','7790000000029','7790000000036','7790000000043','7790000000050','7790000000067')),
        'disciplinas', (SELECT count(*) FROM demo_disciplines),
        'disciplina_horarios', (SELECT count(*) FROM disciplina_horarios h JOIN demo_disciplines d ON d.id=h.disciplina_id),
        'alumnos', (SELECT count(*) FROM demo_students),
        'inscripciones', (SELECT count(*) FROM demo_enrollments),
        'disciplina_tarifas', (SELECT count(*) FROM disciplina_tarifas t JOIN demo_disciplines d ON d.id=t.disciplina_id),
        'inscripcion_condiciones_economicas', (SELECT count(*) FROM inscripcion_condiciones_economicas c JOIN demo_enrollments i ON i.id=c.inscripcion_id),
        'mensualidades', (SELECT count(*) FROM mensualidades m JOIN demo_enrollments i ON i.id=m.inscripcion_id),
        'matriculas', (SELECT count(*) FROM matriculas m JOIN demo_students a ON a.id=m.alumno_id),
        'asistencias_mensuales', (SELECT count(*) FROM asistencias_mensuales am JOIN demo_disciplines d ON d.id=am.disciplina_id),
        'asistencias_alumno_mensual', (SELECT count(*) FROM asistencias_alumno_mensual aam JOIN demo_enrollments i ON i.id=aam.inscripcion_id),
        'asistencias_diarias', (SELECT count(*) FROM asistencias_diarias ad JOIN asistencias_alumno_mensual aam ON aam.id=ad.asistencia_alumno_mensual_id JOIN demo_enrollments i ON i.id=aam.inscripcion_id),
        'ventas_stock', (SELECT count(*) FROM ventas_stock WHERE idempotency_key LIKE 'demo-seed:v1:%'),
        'cargos', (SELECT count(*) FROM demo_charges),
        'cargo_liquidaciones', (SELECT count(*) FROM cargo_liquidaciones cl JOIN demo_charges c ON c.id=cl.cargo_id),
        'pagos', (SELECT count(*) FROM demo_payments),
        'aplicaciones_pago', (SELECT count(*) FROM aplicaciones_pago ap JOIN demo_payments p ON p.id=ap.pago_id),
        'egresos', (SELECT count(*) FROM egresos WHERE idempotency_key LIKE 'demo-seed:v1:%'),
        'movimientos_caja', (SELECT count(*) FROM movimientos_caja WHERE idempotency_key LIKE 'demo-seed:v1:%'),
        'movimientos_credito', (SELECT count(*) FROM movimientos_credito WHERE idempotency_key LIKE 'demo-seed:v1:%'),
        'movimientos_stock', (SELECT count(*) FROM movimientos_stock WHERE idempotency_key LIKE 'demo-seed:v1:%'),
        'recibos', (SELECT count(*) FROM recibos r JOIN demo_payments p ON p.id=r.pago_id),
        'recibos_pendientes', (SELECT count(*) FROM recibos_pendientes rp JOIN demo_payments p ON p.id=rp.pago_id)
    ) AS counts
), expected AS (
    SELECT jsonb_build_object(
        'usuarios',5,'usuario_roles',5,'salones',3,'profesores',6,'observaciones_profesores',6,
        'bonificaciones',4,'recargos',3,'metodo_pagos',4,'sub_conceptos',4,'conceptos',8,
        'stocks',6,'disciplinas',6,'disciplina_horarios',11,'alumnos',28,'inscripciones',34,
        'disciplina_tarifas',12,'inscripcion_condiciones_economicas',40,'mensualidades',70,
        'matriculas',26,'asistencias_mensuales',6,'asistencias_alumno_mensual',18,
        'asistencias_diarias',54,'ventas_stock',6,'cargos',115,'cargo_liquidaciones',115,
        'pagos',48,'aplicaciones_pago',82,'egresos',7,'movimientos_caja',61,
        'movimientos_credito',11,'movimientos_stock',14,'recibos',48,'recibos_pendientes',48
    ) AS counts
), expected_matrix(role_code, permission_code) AS (
    SELECT 'SUPERADMIN', codigo FROM permisos
    UNION ALL SELECT 'DIRECCION', codigo FROM permisos WHERE codigo <> 'PERM_ROLES_ADMIN'
    UNION ALL SELECT 'ADMINISTRADOR', codigo FROM permisos WHERE codigo <> 'PERM_ROLES_ADMIN'
    UNION ALL SELECT 'SECRETARIA', codigo FROM permisos WHERE codigo IN ('PERM_APP_ACCESO','PERM_PAGOS_REGISTRAR','PERM_CREDITOS_CONSUMIR','PERM_CONDICIONES_ECONOMICAS_ADMIN','PERM_ALUMNOS_LEER','PERM_ALUMNOS_ADMIN','PERM_INSCRIPCIONES_LEER','PERM_INSCRIPCIONES_ADMIN','PERM_DISCIPLINAS_LEER','PERM_PROFESORES_LEER','PERM_ASISTENCIAS_LEER','PERM_ASISTENCIAS_REGISTRAR','PERM_PAGOS_LEER','PERM_CAJA_LEER','PERM_STOCK_LEER','PERM_REPORTES_LEER','PERM_CONFIG_LEER')
    UNION ALL SELECT 'CAJA', codigo FROM permisos WHERE codigo IN ('PERM_APP_ACCESO','PERM_ALUMNOS_LEER','PERM_PAGOS_LEER','PERM_PAGOS_REGISTRAR','PERM_CAJA_LEER','PERM_STOCK_LEER','PERM_CONFIG_LEER','PERM_CREDITOS_CONSUMIR')
), actual_matrix AS (
    SELECT r.codigo, p.codigo FROM roles r JOIN rol_permisos rp ON rp.rol_id=r.id JOIN permisos p ON p.id=rp.permiso_id
    WHERE r.codigo IN ('SUPERADMIN','DIRECCION','ADMINISTRADOR','SECRETARIA','CAJA','PROFESOR')
), matrix_diff AS (
    (SELECT * FROM expected_matrix EXCEPT SELECT * FROM actual_matrix)
    UNION ALL
    (SELECT * FROM actual_matrix EXCEPT SELECT * FROM expected_matrix)
), expected_demo_users(username, role_code) AS (
    VALUES ('demo-superadmin','SUPERADMIN'),('demo-direccion','DIRECCION'),
           ('demo-administrador','ADMINISTRADOR'),('demo-secretaria','SECRETARIA'),('demo-caja','CAJA')
), actual_demo_users AS (
    SELECT lower(u.nombre_usuario), r.codigo
    FROM usuarios u JOIN usuario_roles ur ON ur.usuario_id=u.id JOIN roles r ON r.id=ur.rol_id
    WHERE lower(u.nombre_usuario) LIKE 'demo-%' AND u.activo
), demo_user_diff AS (
    (SELECT * FROM expected_demo_users EXCEPT SELECT * FROM actual_demo_users)
    UNION ALL
    (SELECT * FROM actual_demo_users EXCEPT SELECT * FROM expected_demo_users)
)
SELECT CASE WHEN
    (SELECT counts FROM actual) = (SELECT counts FROM expected)
    AND (SELECT sum(value::integer) FROM actual, LATERAL jsonb_each_text(counts)) = 914
    AND (SELECT count(*) FROM roles) = 6
    AND (SELECT count(*) FROM permisos WHERE activo AND sistema) = 32
    AND (SELECT count(*) FROM rol_permisos) = 119
    AND NOT EXISTS (SELECT 1 FROM matrix_diff)
    AND NOT EXISTS (SELECT 1 FROM demo_user_diff)
    AND EXISTS (
        SELECT 1 FROM alumnos WHERE documento='49287134' AND activo
          AND extract(month FROM fecha_nacimiento)=extract(month FROM (CURRENT_TIMESTAMP AT TIME ZONE 'America/Argentina/Buenos_Aires')::date)
          AND extract(day FROM fecha_nacimiento)=extract(day FROM (CURRENT_TIMESTAMP AT TIME ZONE 'America/Argentina/Buenos_Aires')::date)
          AND otras_notas LIKE 'Ficha revisada por administración. Actualización de referencia: %'
    )
THEN 'true' ELSE 'false' END;
