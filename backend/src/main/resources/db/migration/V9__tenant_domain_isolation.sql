-- Discriminator, backfill e integridad relacional del dominio tenant-owned.
-- V8 dejó cerrado el inventario: esta migración enumera cada tabla afectada y
-- no ejecuta DDL sobre objetos descubiertos dinámicamente.

DO $$
DECLARE
    missing_table TEXT;
BEGIN
    SELECT string_agg(expected.name, ', ' ORDER BY expected.name)
    INTO missing_table
    FROM unnest(ARRAY[
        'roles', 'rol_permisos', 'alumnos', 'salones', 'profesores',
        'observaciones_profesores', 'bonificaciones', 'recargos', 'metodo_pagos',
        'sub_conceptos', 'conceptos', 'stocks', 'disciplinas',
        'disciplina_horarios', 'inscripciones', 'mensualidades', 'matriculas',
        'asistencias_mensuales', 'asistencias_alumno_mensual',
        'asistencias_diarias', 'ventas_stock', 'cargos', 'pagos',
        'aplicaciones_pago', 'egresos', 'movimientos_caja',
        'movimientos_credito', 'movimientos_stock', 'recibos',
        'recibos_pendientes', 'notificaciones', 'disciplina_tarifas',
        'inscripcion_condiciones_economicas', 'cargo_liquidaciones',
        'cargo_eventos', 'jere_platform_student_export_snapshots',
        'jere_platform_student_export_pages'
    ]) AS expected(name)
    WHERE to_regclass('public.' || expected.name) IS NULL;

    IF missing_table IS NOT NULL THEN
        RAISE EXCEPTION 'V9 multitenancy: faltan tablas del inventario: %', missing_table;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.tenants
        WHERE id = '00000000-0000-0000-0000-000000000001'
          AND code = 'academia-inicial'
    ) THEN
        RAISE EXCEPTION 'V9 multitenancy: tenant inicial V8 ausente';
    END IF;
END;
$$;

-- DEFAULT transitorio realiza el backfill sin disparar triggers append-only.
-- Se elimina antes de cerrar la migración: inserts futuros deben llevar tenant
-- resuelto por el backend, no caer silenciosamente en el tenant inicial.
ALTER TABLE public.roles ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.rol_permisos ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.alumnos ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.salones ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.profesores ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.observaciones_profesores ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.bonificaciones ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.recargos ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.metodo_pagos ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.sub_conceptos ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.conceptos ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.stocks ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.disciplinas ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.disciplina_horarios ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.inscripciones ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.mensualidades ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.matriculas ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.asistencias_mensuales ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.asistencias_alumno_mensual ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.asistencias_diarias ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.ventas_stock ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.cargos ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.pagos ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.aplicaciones_pago ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.egresos ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.movimientos_caja ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.movimientos_credito ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.movimientos_stock ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.recibos ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.recibos_pendientes ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.notificaciones ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.disciplina_tarifas ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.inscripcion_condiciones_economicas ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.cargo_liquidaciones ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';
ALTER TABLE public.cargo_eventos ADD COLUMN tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';

-- V7 usaba tenant_id para el receptor externo. Se hace explícita la distinción
-- antes de incorporar el tenant interno.
ALTER TABLE public.jere_platform_student_export_snapshots
    RENAME COLUMN organization_id TO external_organization_id;
ALTER TABLE public.jere_platform_student_export_snapshots
    RENAME COLUMN tenant_id TO external_tenant_id;
ALTER TABLE public.jere_platform_student_export_snapshots
    ADD COLUMN internal_tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001',
    ADD COLUMN mapping_id UUID,
    ADD COLUMN source_type VARCHAR(50) DEFAULT 'GESTUDIO_STUDENT',
    ADD COLUMN mapping_config_version BIGINT DEFAULT 1,
    ADD COLUMN signing_key_ref VARCHAR(150) DEFAULT 'deployment-env-v7';

UPDATE public.jere_platform_student_export_snapshots s
SET mapping_id = m.id,
    source_type = m.source_type,
    mapping_config_version = m.config_version,
    signing_key_ref = m.signing_key_ref
FROM public.jere_platform_tenant_mappings m
WHERE m.internal_tenant_id = s.internal_tenant_id
  AND m.external_organization_id = s.external_organization_id
  AND m.external_tenant_id = s.external_tenant_id;

ALTER TABLE public.jere_platform_student_export_pages
    ADD COLUMN internal_tenant_id UUID DEFAULT '00000000-0000-0000-0000-000000000001';

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.roles WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.rol_permisos WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.alumnos WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.salones WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.profesores WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.observaciones_profesores WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.bonificaciones WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.recargos WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.metodo_pagos WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.sub_conceptos WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.conceptos WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.stocks WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.disciplinas WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.disciplina_horarios WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.inscripciones WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.mensualidades WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.matriculas WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.asistencias_mensuales WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.asistencias_alumno_mensual WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.asistencias_diarias WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.ventas_stock WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.cargos WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.pagos WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.aplicaciones_pago WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.egresos WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.movimientos_caja WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.movimientos_credito WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.movimientos_stock WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.recibos WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.recibos_pendientes WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.notificaciones WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.disciplina_tarifas WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.inscripcion_condiciones_economicas WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.cargo_liquidaciones WHERE tenant_id IS NULL)
       OR EXISTS (SELECT 1 FROM public.cargo_eventos WHERE tenant_id IS NULL)
       OR EXISTS (
           SELECT 1 FROM public.jere_platform_student_export_snapshots
           WHERE internal_tenant_id IS NULL OR mapping_id IS NULL OR source_type IS NULL
              OR mapping_config_version IS NULL OR signing_key_ref IS NULL
       )
       OR EXISTS (
           SELECT 1 FROM public.jere_platform_student_export_pages
           WHERE internal_tenant_id IS NULL
       ) THEN
        RAISE EXCEPTION 'V9 multitenancy: backfill incompleto; no se aplicará NOT NULL';
    END IF;
END;
$$;

-- Cierre del backfill y FK directa al control plane.
ALTER TABLE public.roles ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_roles_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.rol_permisos ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_rol_permisos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.alumnos ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_alumnos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.salones ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_salones_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.profesores ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_profesores_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.observaciones_profesores ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_observaciones_profesores_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.bonificaciones ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_bonificaciones_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.recargos ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_recargos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.metodo_pagos ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_metodo_pagos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.sub_conceptos ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_sub_conceptos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.conceptos ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_conceptos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.stocks ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_stocks_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.disciplinas ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_disciplinas_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.disciplina_horarios ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_disciplina_horarios_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.inscripciones ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_inscripciones_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.mensualidades ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_mensualidades_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.matriculas ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_matriculas_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.asistencias_mensuales ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_asistencias_mensuales_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.asistencias_alumno_mensual ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_asistencias_alumno_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.asistencias_diarias ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_asistencias_diarias_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.ventas_stock ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_ventas_stock_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.cargos ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_cargos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.pagos ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_pagos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.aplicaciones_pago ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_aplicaciones_pago_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.egresos ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_egresos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.movimientos_caja ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_movimientos_caja_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.movimientos_credito ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_movimientos_credito_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.movimientos_stock ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_movimientos_stock_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.recibos ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_recibos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.recibos_pendientes ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_recibos_pendientes_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.notificaciones ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_notificaciones_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.disciplina_tarifas ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_disciplina_tarifas_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.inscripcion_condiciones_economicas ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_condiciones_economicas_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.cargo_liquidaciones ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_cargo_liquidaciones_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.cargo_eventos ALTER COLUMN tenant_id DROP DEFAULT, ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_cargo_eventos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;

ALTER TABLE public.jere_platform_student_export_snapshots
    ALTER COLUMN internal_tenant_id DROP DEFAULT,
    ALTER COLUMN internal_tenant_id SET NOT NULL,
    ALTER COLUMN mapping_id SET NOT NULL,
    ALTER COLUMN source_type DROP DEFAULT,
    ALTER COLUMN source_type SET NOT NULL,
    ALTER COLUMN mapping_config_version DROP DEFAULT,
    ALTER COLUMN mapping_config_version SET NOT NULL,
    ALTER COLUMN signing_key_ref DROP DEFAULT,
    ALTER COLUMN signing_key_ref SET NOT NULL,
    ADD CONSTRAINT fk_jere_snapshot_tenant FOREIGN KEY (internal_tenant_id)
        REFERENCES public.tenants(id) ON DELETE RESTRICT;
ALTER TABLE public.jere_platform_student_export_pages
    ALTER COLUMN internal_tenant_id DROP DEFAULT,
    ALTER COLUMN internal_tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_jere_pages_tenant FOREIGN KEY (internal_tenant_id)
        REFERENCES public.tenants(id) ON DELETE RESTRICT;

-- Cada agregado con ID obtiene una clave candidata tenant-aware. Las PK
-- globales se conservan para compatibilidad, pero ninguna FK de negocio nueva
-- depende sólo de ellas.
ALTER TABLE public.roles ADD CONSTRAINT uq_roles_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.alumnos ADD CONSTRAINT uq_alumnos_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.salones ADD CONSTRAINT uq_salones_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.profesores ADD CONSTRAINT uq_profesores_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.observaciones_profesores ADD CONSTRAINT uq_observaciones_profesores_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.bonificaciones ADD CONSTRAINT uq_bonificaciones_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.recargos ADD CONSTRAINT uq_recargos_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.metodo_pagos ADD CONSTRAINT uq_metodo_pagos_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.sub_conceptos ADD CONSTRAINT uq_sub_conceptos_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.conceptos ADD CONSTRAINT uq_conceptos_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.stocks ADD CONSTRAINT uq_stocks_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.disciplinas ADD CONSTRAINT uq_disciplinas_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.disciplina_horarios ADD CONSTRAINT uq_disciplina_horarios_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.inscripciones ADD CONSTRAINT uq_inscripciones_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.mensualidades ADD CONSTRAINT uq_mensualidades_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.matriculas ADD CONSTRAINT uq_matriculas_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.asistencias_mensuales ADD CONSTRAINT uq_asistencias_mensuales_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.asistencias_alumno_mensual ADD CONSTRAINT uq_asistencias_alumno_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.asistencias_diarias ADD CONSTRAINT uq_asistencias_diarias_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.ventas_stock ADD CONSTRAINT uq_ventas_stock_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.cargos ADD CONSTRAINT uq_cargos_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.pagos ADD CONSTRAINT uq_pagos_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.aplicaciones_pago ADD CONSTRAINT uq_aplicaciones_pago_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.egresos ADD CONSTRAINT uq_egresos_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.movimientos_caja ADD CONSTRAINT uq_movimientos_caja_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.movimientos_credito ADD CONSTRAINT uq_movimientos_credito_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.movimientos_stock ADD CONSTRAINT uq_movimientos_stock_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.recibos ADD CONSTRAINT uq_recibos_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.recibos_pendientes ADD CONSTRAINT uq_recibos_pendientes_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.notificaciones ADD CONSTRAINT uq_notificaciones_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.disciplina_tarifas ADD CONSTRAINT uq_disciplina_tarifas_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.inscripcion_condiciones_economicas ADD CONSTRAINT uq_condiciones_economicas_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.cargo_liquidaciones ADD CONSTRAINT uq_cargo_liquidaciones_tenant_id UNIQUE (tenant_id, cargo_id);
ALTER TABLE public.cargo_eventos ADD CONSTRAINT uq_cargo_eventos_tenant_id UNIQUE (tenant_id, id);
ALTER TABLE public.jere_platform_student_export_snapshots
    ADD CONSTRAINT uq_jere_snapshots_tenant_checkpoint UNIQUE (internal_tenant_id, checkpoint);
ALTER TABLE public.jere_platform_student_export_pages
    ADD CONSTRAINT uq_jere_pages_tenant_page UNIQUE (internal_tenant_id, snapshot_checkpoint, page_number);

-- Unicidades funcionales locales. Se retiran sólo las fronteras globales que
-- impedirían usar la misma clave de negocio legítima en dos academias.
ALTER TABLE public.roles DROP CONSTRAINT uq_roles_descripcion;
ALTER TABLE public.roles DROP CONSTRAINT uq_roles_codigo;
ALTER TABLE public.roles
    ADD CONSTRAINT uq_roles_tenant_descripcion UNIQUE (tenant_id, descripcion),
    ADD CONSTRAINT uq_roles_tenant_codigo UNIQUE (tenant_id, codigo);

DROP INDEX public.uq_alumnos_documento;
CREATE UNIQUE INDEX uq_alumnos_tenant_documento
    ON public.alumnos (tenant_id, documento) WHERE documento IS NOT NULL;

ALTER TABLE public.salones DROP CONSTRAINT uq_salones_nombre;
ALTER TABLE public.salones ADD CONSTRAINT uq_salones_tenant_nombre UNIQUE (tenant_id, nombre);

ALTER TABLE public.profesores DROP CONSTRAINT uq_profesores_usuario;
ALTER TABLE public.profesores ADD CONSTRAINT uq_profesores_tenant_usuario UNIQUE (tenant_id, usuario_id);

ALTER TABLE public.bonificaciones DROP CONSTRAINT uq_bonificaciones_descripcion;
ALTER TABLE public.bonificaciones ADD CONSTRAINT uq_bonificaciones_tenant_descripcion UNIQUE (tenant_id, descripcion);
ALTER TABLE public.recargos DROP CONSTRAINT uq_recargos_descripcion;
ALTER TABLE public.recargos ADD CONSTRAINT uq_recargos_tenant_descripcion UNIQUE (tenant_id, descripcion);
ALTER TABLE public.metodo_pagos DROP CONSTRAINT uq_metodos_pago_descripcion;
ALTER TABLE public.metodo_pagos ADD CONSTRAINT uq_metodos_pago_tenant_descripcion UNIQUE (tenant_id, descripcion);
ALTER TABLE public.sub_conceptos DROP CONSTRAINT uq_sub_conceptos_descripcion;
ALTER TABLE public.sub_conceptos ADD CONSTRAINT uq_sub_conceptos_tenant_descripcion UNIQUE (tenant_id, descripcion);
ALTER TABLE public.conceptos DROP CONSTRAINT uq_conceptos_sub_descripcion;
ALTER TABLE public.conceptos ADD CONSTRAINT uq_conceptos_tenant_sub_descripcion UNIQUE (tenant_id, sub_concepto_id, descripcion);

ALTER TABLE public.stocks DROP CONSTRAINT uq_stocks_nombre;
ALTER TABLE public.stocks ADD CONSTRAINT uq_stocks_tenant_nombre UNIQUE (tenant_id, nombre);
DROP INDEX public.uq_stocks_codigo_barras;
CREATE UNIQUE INDEX uq_stocks_tenant_codigo_barras
    ON public.stocks (tenant_id, codigo_barras) WHERE codigo_barras IS NOT NULL;

ALTER TABLE public.disciplina_horarios DROP CONSTRAINT uq_horarios_disciplina;
ALTER TABLE public.disciplina_horarios
    ADD CONSTRAINT uq_horarios_tenant_disciplina UNIQUE (tenant_id, disciplina_id, dia_semana, horario_inicio);
DROP INDEX public.uq_inscripciones_activas;
CREATE UNIQUE INDEX uq_inscripciones_tenant_activas
    ON public.inscripciones (tenant_id, alumno_id, disciplina_id) WHERE estado = 'ACTIVA';

ALTER TABLE public.mensualidades DROP CONSTRAINT uq_mensualidades_periodo;
ALTER TABLE public.mensualidades
    ADD CONSTRAINT uq_mensualidades_tenant_periodo UNIQUE (tenant_id, inscripcion_id, anio, mes);
ALTER TABLE public.matriculas DROP CONSTRAINT uq_matriculas_periodo;
ALTER TABLE public.matriculas
    ADD CONSTRAINT uq_matriculas_tenant_periodo UNIQUE (tenant_id, alumno_id, anio);
ALTER TABLE public.asistencias_mensuales DROP CONSTRAINT uq_asistencias_mensuales_periodo;
ALTER TABLE public.asistencias_mensuales
    ADD CONSTRAINT uq_asistencias_mensuales_tenant_periodo UNIQUE (tenant_id, disciplina_id, anio, mes);
ALTER TABLE public.asistencias_alumno_mensual DROP CONSTRAINT uq_asistencia_alumno_periodo;
ALTER TABLE public.asistencias_alumno_mensual
    ADD CONSTRAINT uq_asistencia_alumno_tenant_periodo UNIQUE (tenant_id, asistencia_mensual_id, inscripcion_id);
ALTER TABLE public.asistencias_diarias DROP CONSTRAINT uq_asistencias_diarias_fecha;
ALTER TABLE public.asistencias_diarias
    ADD CONSTRAINT uq_asistencias_diarias_tenant_fecha UNIQUE (tenant_id, asistencia_alumno_mensual_id, fecha);

ALTER TABLE public.ventas_stock DROP CONSTRAINT uq_ventas_stock_idempotency;
ALTER TABLE public.ventas_stock DROP CONSTRAINT uq_ventas_stock_reversal;
ALTER TABLE public.ventas_stock
    ADD CONSTRAINT uq_ventas_stock_tenant_idempotency UNIQUE (tenant_id, idempotency_key),
    ADD CONSTRAINT uq_ventas_stock_tenant_reversal UNIQUE (tenant_id, reversal_idempotency_key);

ALTER TABLE public.cargos DROP CONSTRAINT uq_cargos_mensualidad;
ALTER TABLE public.cargos DROP CONSTRAINT uq_cargos_matricula;
ALTER TABLE public.cargos DROP CONSTRAINT uq_cargos_venta_stock;
ALTER TABLE public.cargos DROP CONSTRAINT uq_cargos_idempotency;
ALTER TABLE public.cargos
    ADD CONSTRAINT uq_cargos_tenant_mensualidad UNIQUE (tenant_id, mensualidad_id),
    ADD CONSTRAINT uq_cargos_tenant_matricula UNIQUE (tenant_id, matricula_id),
    ADD CONSTRAINT uq_cargos_tenant_venta_stock UNIQUE (tenant_id, venta_stock_id),
    ADD CONSTRAINT uq_cargos_tenant_idempotency UNIQUE (tenant_id, idempotency_key);

ALTER TABLE public.pagos DROP CONSTRAINT uq_pagos_idempotency;
ALTER TABLE public.pagos DROP CONSTRAINT uq_pagos_reversal_idempotency;
ALTER TABLE public.pagos
    ADD CONSTRAINT uq_pagos_tenant_idempotency UNIQUE (tenant_id, idempotency_key),
    ADD CONSTRAINT uq_pagos_tenant_reversal UNIQUE (tenant_id, reversal_idempotency_key);
ALTER TABLE public.aplicaciones_pago DROP CONSTRAINT uq_aplicaciones_pago_cargo;
ALTER TABLE public.aplicaciones_pago
    ADD CONSTRAINT uq_aplicaciones_tenant_pago_cargo UNIQUE (tenant_id, pago_id, cargo_id);

ALTER TABLE public.egresos DROP CONSTRAINT uq_egresos_idempotency;
ALTER TABLE public.egresos DROP CONSTRAINT uq_egresos_reversal;
ALTER TABLE public.egresos
    ADD CONSTRAINT uq_egresos_tenant_idempotency UNIQUE (tenant_id, idempotency_key),
    ADD CONSTRAINT uq_egresos_tenant_reversal UNIQUE (tenant_id, reversal_idempotency_key);
ALTER TABLE public.movimientos_caja DROP CONSTRAINT uq_movimientos_caja_idempotency;
ALTER TABLE public.movimientos_caja DROP CONSTRAINT uq_movimientos_caja_reversion;
ALTER TABLE public.movimientos_caja
    ADD CONSTRAINT uq_movimientos_caja_tenant_idempotency UNIQUE (tenant_id, idempotency_key),
    ADD CONSTRAINT uq_movimientos_caja_tenant_reversion UNIQUE (tenant_id, movimiento_revertido_id);
ALTER TABLE public.movimientos_credito DROP CONSTRAINT uq_movimientos_credito_idempotency;
ALTER TABLE public.movimientos_credito DROP CONSTRAINT uq_movimientos_credito_reversion;
ALTER TABLE public.movimientos_credito
    ADD CONSTRAINT uq_movimientos_credito_tenant_idempotency UNIQUE (tenant_id, idempotency_key),
    ADD CONSTRAINT uq_movimientos_credito_tenant_reversion UNIQUE (tenant_id, movimiento_revertido_id);
ALTER TABLE public.movimientos_stock DROP CONSTRAINT uq_movimientos_stock_idempotency;
ALTER TABLE public.movimientos_stock DROP CONSTRAINT uq_movimientos_stock_reversion;
ALTER TABLE public.movimientos_stock
    ADD CONSTRAINT uq_movimientos_stock_tenant_idempotency UNIQUE (tenant_id, idempotency_key),
    ADD CONSTRAINT uq_movimientos_stock_tenant_reversion UNIQUE (tenant_id, movimiento_revertido_id);

ALTER TABLE public.recibos DROP CONSTRAINT uq_recibos_pago;
ALTER TABLE public.recibos ADD CONSTRAINT uq_recibos_tenant_pago UNIQUE (tenant_id, pago_id);
ALTER TABLE public.recibos_pendientes DROP CONSTRAINT uq_recibos_pendientes_pago_tipo;
ALTER TABLE public.recibos_pendientes DROP CONSTRAINT uq_recibos_pendientes_idempotency;
ALTER TABLE public.recibos_pendientes
    ADD CONSTRAINT uq_recibos_pendientes_tenant_pago UNIQUE (tenant_id, pago_id, tipo),
    ADD CONSTRAINT uq_recibos_pendientes_tenant_idempotency UNIQUE (tenant_id, idempotency_key);
ALTER TABLE public.notificaciones DROP CONSTRAINT uq_notificaciones_dedup;
ALTER TABLE public.notificaciones ADD CONSTRAINT uq_notificaciones_tenant_dedup UNIQUE (tenant_id, dedup_key);

ALTER TABLE public.disciplina_tarifas DROP CONSTRAINT uq_disciplina_tarifas_inicio;
ALTER TABLE public.disciplina_tarifas
    ADD CONSTRAINT uq_disciplina_tarifas_tenant_inicio UNIQUE (tenant_id, disciplina_id, vigente_desde);
ALTER TABLE public.inscripcion_condiciones_economicas DROP CONSTRAINT uq_inscripcion_condicion_inicio;
ALTER TABLE public.inscripcion_condiciones_economicas
    ADD CONSTRAINT uq_condiciones_tenant_inicio UNIQUE (tenant_id, inscripcion_id, vigente_desde);
ALTER TABLE public.cargo_eventos DROP CONSTRAINT uq_cargo_evento_idempotency;
ALTER TABLE public.cargo_eventos
    ADD CONSTRAINT uq_cargo_eventos_tenant_idempotency UNIQUE (tenant_id, idempotency_key);

DROP INDEX public.uq_auditoria_idempotency;
CREATE UNIQUE INDEX uq_auditoria_tenant_idempotency
    ON public.auditoria_eventos (tenant_id, idempotency_key)
    WHERE tenant_id IS NOT NULL AND idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX uq_auditoria_global_idempotency
    ON public.auditoria_eventos (idempotency_key)
    WHERE tenant_id IS NULL AND idempotency_key IS NOT NULL;

ALTER TABLE public.jere_platform_student_export_pages DROP CONSTRAINT uq_jere_student_export_cursor;
ALTER TABLE public.jere_platform_student_export_pages
    ADD CONSTRAINT uq_jere_pages_tenant_cursor UNIQUE (internal_tenant_id, cursor_token);
DROP INDEX public.uq_jere_student_export_first_page;
CREATE UNIQUE INDEX uq_jere_pages_tenant_first_page
    ON public.jere_platform_student_export_pages (internal_tenant_id, snapshot_checkpoint)
    WHERE cursor_token IS NULL;
DROP INDEX public.ix_jere_student_export_mapping_created;
CREATE INDEX ix_jere_snapshots_tenant_mapping_created
    ON public.jere_platform_student_export_snapshots (
        internal_tenant_id, external_organization_id, external_tenant_id, created_at DESC
    );

-- FKs compuestas: una referencia válida por ID deja de ser suficiente si el
-- tenant del hijo no coincide con el tenant del padre.
ALTER TABLE public.tenant_membership_roles
    ADD CONSTRAINT fk_membership_roles_tenant_role FOREIGN KEY (tenant_id, role_id)
        REFERENCES public.roles(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.rol_permisos
    ADD CONSTRAINT fk_rol_permisos_tenant_role FOREIGN KEY (tenant_id, rol_id)
        REFERENCES public.roles(tenant_id, id) ON DELETE CASCADE;
ALTER TABLE public.observaciones_profesores
    ADD CONSTRAINT fk_observaciones_tenant_profesor FOREIGN KEY (tenant_id, profesor_id)
        REFERENCES public.profesores(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.conceptos
    ADD CONSTRAINT fk_conceptos_tenant_subconcepto FOREIGN KEY (tenant_id, sub_concepto_id)
        REFERENCES public.sub_conceptos(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.disciplinas
    ADD CONSTRAINT fk_disciplinas_tenant_salon FOREIGN KEY (tenant_id, salon_id)
        REFERENCES public.salones(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_disciplinas_tenant_profesor FOREIGN KEY (tenant_id, profesor_id)
        REFERENCES public.profesores(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.disciplina_horarios
    ADD CONSTRAINT fk_horarios_tenant_disciplina FOREIGN KEY (tenant_id, disciplina_id)
        REFERENCES public.disciplinas(tenant_id, id) ON DELETE CASCADE;
ALTER TABLE public.inscripciones
    ADD CONSTRAINT fk_inscripciones_tenant_alumno FOREIGN KEY (tenant_id, alumno_id)
        REFERENCES public.alumnos(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_inscripciones_tenant_disciplina FOREIGN KEY (tenant_id, disciplina_id)
        REFERENCES public.disciplinas(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_inscripciones_tenant_bonificacion FOREIGN KEY (tenant_id, bonificacion_id)
        REFERENCES public.bonificaciones(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.mensualidades
    ADD CONSTRAINT fk_mensualidades_tenant_inscripcion FOREIGN KEY (tenant_id, inscripcion_id)
        REFERENCES public.inscripciones(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_mensualidades_tenant_bonificacion FOREIGN KEY (tenant_id, bonificacion_id)
        REFERENCES public.bonificaciones(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_mensualidades_tenant_recargo FOREIGN KEY (tenant_id, recargo_id)
        REFERENCES public.recargos(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.matriculas
    ADD CONSTRAINT fk_matriculas_tenant_alumno FOREIGN KEY (tenant_id, alumno_id)
        REFERENCES public.alumnos(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.asistencias_mensuales
    ADD CONSTRAINT fk_asistencias_mensuales_tenant_disciplina FOREIGN KEY (tenant_id, disciplina_id)
        REFERENCES public.disciplinas(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.asistencias_alumno_mensual
    ADD CONSTRAINT fk_asistencia_alumno_tenant_inscripcion FOREIGN KEY (tenant_id, inscripcion_id)
        REFERENCES public.inscripciones(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_asistencia_alumno_tenant_mensual FOREIGN KEY (tenant_id, asistencia_mensual_id)
        REFERENCES public.asistencias_mensuales(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.asistencias_diarias
    ADD CONSTRAINT fk_asistencias_diarias_tenant_alumno FOREIGN KEY (tenant_id, asistencia_alumno_mensual_id)
        REFERENCES public.asistencias_alumno_mensual(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.ventas_stock
    ADD CONSTRAINT fk_ventas_stock_tenant_alumno FOREIGN KEY (tenant_id, alumno_id)
        REFERENCES public.alumnos(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_ventas_stock_tenant_stock FOREIGN KEY (tenant_id, stock_id)
        REFERENCES public.stocks(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.cargos
    ADD CONSTRAINT fk_cargos_tenant_alumno FOREIGN KEY (tenant_id, alumno_id)
        REFERENCES public.alumnos(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_cargos_tenant_mensualidad FOREIGN KEY (tenant_id, mensualidad_id)
        REFERENCES public.mensualidades(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_cargos_tenant_matricula FOREIGN KEY (tenant_id, matricula_id)
        REFERENCES public.matriculas(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_cargos_tenant_concepto FOREIGN KEY (tenant_id, concepto_id)
        REFERENCES public.conceptos(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_cargos_tenant_venta_stock FOREIGN KEY (tenant_id, venta_stock_id)
        REFERENCES public.ventas_stock(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_cargos_tenant_origen FOREIGN KEY (tenant_id, cargo_origen_id)
        REFERENCES public.cargos(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.pagos
    ADD CONSTRAINT fk_pagos_tenant_alumno FOREIGN KEY (tenant_id, alumno_id)
        REFERENCES public.alumnos(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_pagos_tenant_metodo FOREIGN KEY (tenant_id, metodo_pago_id)
        REFERENCES public.metodo_pagos(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.aplicaciones_pago
    ADD CONSTRAINT fk_aplicaciones_tenant_pago FOREIGN KEY (tenant_id, pago_id)
        REFERENCES public.pagos(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_aplicaciones_tenant_cargo FOREIGN KEY (tenant_id, cargo_id)
        REFERENCES public.cargos(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.egresos
    ADD CONSTRAINT fk_egresos_tenant_metodo FOREIGN KEY (tenant_id, metodo_pago_id)
        REFERENCES public.metodo_pagos(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.movimientos_caja
    ADD CONSTRAINT fk_movimientos_caja_tenant_metodo FOREIGN KEY (tenant_id, metodo_pago_id)
        REFERENCES public.metodo_pagos(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_movimientos_caja_tenant_pago FOREIGN KEY (tenant_id, pago_id)
        REFERENCES public.pagos(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_movimientos_caja_tenant_egreso FOREIGN KEY (tenant_id, egreso_id)
        REFERENCES public.egresos(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_movimientos_caja_tenant_revertido FOREIGN KEY (tenant_id, movimiento_revertido_id)
        REFERENCES public.movimientos_caja(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.movimientos_credito
    ADD CONSTRAINT fk_movimientos_credito_tenant_alumno FOREIGN KEY (tenant_id, alumno_id)
        REFERENCES public.alumnos(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_movimientos_credito_tenant_pago FOREIGN KEY (tenant_id, pago_id)
        REFERENCES public.pagos(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_movimientos_credito_tenant_cargo FOREIGN KEY (tenant_id, cargo_id)
        REFERENCES public.cargos(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_movimientos_credito_tenant_revertido FOREIGN KEY (tenant_id, movimiento_revertido_id)
        REFERENCES public.movimientos_credito(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.movimientos_stock
    ADD CONSTRAINT fk_movimientos_stock_tenant_stock FOREIGN KEY (tenant_id, stock_id)
        REFERENCES public.stocks(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_movimientos_stock_tenant_venta FOREIGN KEY (tenant_id, venta_stock_id)
        REFERENCES public.ventas_stock(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_movimientos_stock_tenant_revertido FOREIGN KEY (tenant_id, movimiento_revertido_id)
        REFERENCES public.movimientos_stock(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.recibos
    ADD CONSTRAINT fk_recibos_tenant_pago FOREIGN KEY (tenant_id, pago_id)
        REFERENCES public.pagos(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.recibos_pendientes
    ADD CONSTRAINT fk_recibos_pendientes_tenant_pago FOREIGN KEY (tenant_id, pago_id)
        REFERENCES public.pagos(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.disciplina_tarifas
    ADD CONSTRAINT fk_tarifas_tenant_disciplina FOREIGN KEY (tenant_id, disciplina_id)
        REFERENCES public.disciplinas(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.inscripcion_condiciones_economicas
    ADD CONSTRAINT fk_condiciones_tenant_inscripcion FOREIGN KEY (tenant_id, inscripcion_id)
        REFERENCES public.inscripciones(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_condiciones_tenant_bonificacion FOREIGN KEY (tenant_id, bonificacion_id)
        REFERENCES public.bonificaciones(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.cargo_liquidaciones
    ADD CONSTRAINT fk_liquidacion_tenant_cargo FOREIGN KEY (tenant_id, cargo_id)
        REFERENCES public.cargos(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_liquidacion_tenant_tarifa FOREIGN KEY (tenant_id, tarifa_disciplina_id)
        REFERENCES public.disciplina_tarifas(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_liquidacion_tenant_condicion FOREIGN KEY (tenant_id, condicion_inscripcion_id)
        REFERENCES public.inscripcion_condiciones_economicas(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE public.cargo_eventos
    ADD CONSTRAINT fk_cargo_eventos_tenant_cargo FOREIGN KEY (tenant_id, cargo_id)
        REFERENCES public.cargos(tenant_id, id) ON DELETE RESTRICT;

ALTER TABLE public.jere_platform_student_export_snapshots
    ADD CONSTRAINT fk_jere_snapshot_effective_mapping FOREIGN KEY (
        internal_tenant_id, mapping_id, external_organization_id,
        external_tenant_id, source_type, mapping_config_version, signing_key_ref
    ) REFERENCES public.jere_platform_tenant_mappings (
        internal_tenant_id, id, external_organization_id,
        external_tenant_id, source_type, config_version, signing_key_ref
    ) ON DELETE RESTRICT;
ALTER TABLE public.jere_platform_student_export_pages
    ADD CONSTRAINT fk_jere_pages_tenant_snapshot FOREIGN KEY (internal_tenant_id, snapshot_checkpoint)
        REFERENCES public.jere_platform_student_export_snapshots(internal_tenant_id, checkpoint)
        ON DELETE RESTRICT;

-- Índices de acceso habituales con tenant como primer componente. Las claves
-- candidatas anteriores cubren lookups por ID; estos cubren listados/jobs.
CREATE INDEX ix_alumnos_tenant_activo_nombre ON public.alumnos (tenant_id, activo, apellido, nombre);
CREATE INDEX ix_profesores_tenant_activo_nombre ON public.profesores (tenant_id, activo, apellido, nombre);
CREATE INDEX ix_disciplinas_tenant_activo_nombre ON public.disciplinas (tenant_id, activo, nombre);
CREATE INDEX ix_inscripciones_tenant_alumno_estado ON public.inscripciones (tenant_id, alumno_id, estado);
CREATE INDEX ix_inscripciones_tenant_disciplina_estado ON public.inscripciones (tenant_id, disciplina_id, estado);
CREATE INDEX ix_mensualidades_tenant_vencimiento ON public.mensualidades (tenant_id, fecha_vencimiento, estado);
CREATE INDEX ix_cargos_tenant_pendientes ON public.cargos (tenant_id, estado, fecha_vencimiento, alumno_id);
CREATE INDEX ix_pagos_tenant_alumno_fecha ON public.pagos (tenant_id, alumno_id, fecha DESC);
CREATE INDEX ix_egresos_tenant_fecha_metodo ON public.egresos (tenant_id, fecha, metodo_pago_id);
CREATE INDEX ix_movimientos_caja_tenant_fecha ON public.movimientos_caja (tenant_id, fecha, metodo_pago_id);
CREATE INDEX ix_movimientos_credito_tenant_alumno ON public.movimientos_credito (tenant_id, alumno_id, created_at);
CREATE INDEX ix_movimientos_stock_tenant_stock ON public.movimientos_stock (tenant_id, stock_id, created_at);
CREATE INDEX ix_recibos_pendientes_tenant_worker
    ON public.recibos_pendientes (tenant_id, estado, next_attempt_at, lease_until, id);
CREATE INDEX ix_notificaciones_tenant_usuario
    ON public.notificaciones (tenant_id, usuario_id, leida, fecha_creacion DESC);
CREATE INDEX ix_cargo_eventos_tenant_cargo_fecha
    ON public.cargo_eventos (tenant_id, cargo_id, ocurrido_at, id);
CREATE INDEX ix_rol_permisos_tenant_role
    ON public.rol_permisos (tenant_id, rol_id, permiso_id);

-- Proyección tenant-safe: además de RLS, todos los joins y agregaciones llevan
-- el discriminator. security_invoker evita ejecutar con privilegios del owner.
DROP VIEW public.v_cuotas_seguimiento;
CREATE VIEW public.v_cuotas_seguimiento
WITH (security_invoker = TRUE)
AS
WITH pagos AS (
    SELECT tenant_id, cargo_id, sum(importe_aplicado) AS aplicado, max(fecha) AS ultima_fecha
    FROM public.aplicaciones_pago
    WHERE estado = 'APLICADA'
    GROUP BY tenant_id, cargo_id
), credito AS (
    SELECT tenant_id, cargo_id, sum(importe) AS aplicado, max(fecha) AS ultima_fecha
    FROM (
        SELECT tenant_id, cargo_id, importe, created_at::date AS fecha
        FROM public.movimientos_credito
        WHERE tipo = 'CONSUMO'
        UNION ALL
        SELECT reverso.tenant_id, original.cargo_id, -reverso.importe, reverso.created_at::date
        FROM public.movimientos_credito reverso
        JOIN public.movimientos_credito original
          ON original.tenant_id = reverso.tenant_id
         AND original.id = reverso.movimiento_revertido_id
        WHERE reverso.tipo = 'REVERSO' AND original.tipo = 'CONSUMO'
    ) neto
    GROUP BY tenant_id, cargo_id
), cargos_saldo AS (
    SELECT c.*,
           coalesce(p.aplicado, 0) AS aplicado_pagos,
           coalesce(cr.aplicado, 0) AS aplicado_credito,
           c.importe_original - coalesce(p.aplicado, 0) - coalesce(cr.aplicado, 0) AS saldo,
           greatest(p.ultima_fecha, cr.ultima_fecha) AS ultima_fecha_aplicacion
    FROM public.cargos c
    LEFT JOIN pagos p ON p.tenant_id = c.tenant_id AND p.cargo_id = c.id
    LEFT JOIN credito cr ON cr.tenant_id = c.tenant_id AND cr.cargo_id = c.id
), recargos AS (
    SELECT tenant_id, cargo_origen_id,
           sum(importe_original) AS importe_original,
           sum(saldo) AS saldo
    FROM cargos_saldo
    WHERE tipo = 'RECARGO'
    GROUP BY tenant_id, cargo_origen_id
)
SELECT c.tenant_id,
       c.id AS cargo_id,
       i.alumno_id,
       concat_ws(' ', a.nombre, a.apellido) AS alumno,
       i.id AS inscripcion_id,
       i.disciplina_id,
       d.nombre AS disciplina,
       m.anio,
       m.mes,
       m.fecha_generacion,
       m.fecha_vencimiento,
       l.tarifa_disciplina_id,
       td.valor_cuota AS tarifa_utilizada,
       l.importe_base,
       l.descuento_porcentaje,
       l.descuento_importe,
       c.importe_original,
       c.aplicado_pagos,
       c.aplicado_credito,
       c.saldo AS saldo_cuota,
       coalesce(r.importe_original, 0) AS recargos_vinculados,
       coalesce(r.saldo, 0) AS saldo_recargos,
       c.saldo + coalesce(r.saldo, 0) AS saldo_total_periodo,
       c.estado AS estado_persistido,
       CASE WHEN c.estado = 'ANULADO' THEN 'ANULADO'
            WHEN c.saldo = 0 THEN 'PAGADO'
            WHEN c.saldo < c.importe_original THEN 'PARCIAL'
            ELSE 'PENDIENTE' END AS estado_esperado,
       c.ultima_fecha_aplicacion,
       CASE WHEN c.saldo + coalesce(r.saldo, 0) > 0 AND m.fecha_vencimiento < CURRENT_DATE
            THEN CURRENT_DATE - m.fecha_vencimiento ELSE 0 END AS dias_mora,
       l.origen_precio,
       l.formula_version
FROM cargos_saldo c
JOIN public.mensualidades m ON m.tenant_id = c.tenant_id AND m.id = c.mensualidad_id
JOIN public.inscripciones i ON i.tenant_id = m.tenant_id AND i.id = m.inscripcion_id
JOIN public.alumnos a ON a.tenant_id = i.tenant_id AND a.id = i.alumno_id
JOIN public.disciplinas d ON d.tenant_id = i.tenant_id AND d.id = i.disciplina_id
JOIN public.cargo_liquidaciones l ON l.tenant_id = c.tenant_id AND l.cargo_id = c.id
LEFT JOIN public.disciplina_tarifas td
  ON td.tenant_id = l.tenant_id AND td.id = l.tarifa_disciplina_id
LEFT JOIN recargos r ON r.tenant_id = c.tenant_id AND r.cargo_origen_id = c.id
WHERE c.tipo = 'MENSUALIDAD';

-- Los identificadores efectivos de snapshots/páginas son append-only. Un
-- cambio de mapping crea otra fila/version; nunca reinterpreta historia.
CREATE FUNCTION public.rechazar_mutacion_jere_export()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'exports Jere Platform son append-only' USING ERRCODE = '55000';
END;
$$;

CREATE TRIGGER trg_jere_snapshots_append_only
    BEFORE UPDATE OR DELETE ON public.jere_platform_student_export_snapshots
    FOR EACH ROW EXECUTE FUNCTION public.rechazar_mutacion_jere_export();
CREATE TRIGGER trg_jere_pages_append_only
    BEFORE UPDATE OR DELETE ON public.jere_platform_student_export_pages
    FOR EACH ROW EXECUTE FUNCTION public.rechazar_mutacion_jere_export();

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.tenant_membership_roles tmr
        JOIN public.roles r ON r.id = tmr.role_id
        WHERE tmr.tenant_id <> r.tenant_id
    ) THEN
        RAISE EXCEPTION 'V9 multitenancy: role asignado a membership de otro tenant';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.jere_platform_student_export_pages p
        JOIN public.jere_platform_student_export_snapshots s
          ON s.checkpoint = p.snapshot_checkpoint
        WHERE p.internal_tenant_id <> s.internal_tenant_id
    ) THEN
        RAISE EXCEPTION 'V9 multitenancy: página Jere ligada a snapshot de otro tenant';
    END IF;
END;
$$;
