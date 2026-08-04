-- Defensa secundaria PostgreSQL. El rol de aplicación nunca es owner,
-- superuser ni BYPASSRLS; el rol de migración/operación permanece separado.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'gestudio_app') THEN
        EXECUTE 'CREATE ROLE gestudio_app NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'gestudio_health') THEN
        EXECUTE 'CREATE ROLE gestudio_health NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_roles
        WHERE rolname IN ('gestudio_app', 'gestudio_health')
          AND (rolsuper OR rolcreaterole OR rolcreatedb OR rolcanlogin OR rolreplication OR rolbypassrls)
    ) THEN
        RAISE EXCEPTION 'V10 multitenancy: gestudio_app/gestudio_health poseen atributos inseguros';
    END IF;
EXCEPTION
    WHEN insufficient_privilege THEN
        RAISE EXCEPTION
            'V10 multitenancy requiere que el rol Flyway pueda crear/verificar roles NOLOGIN; aprovisione gestudio_app y gestudio_health';
END;
$$;

CREATE FUNCTION public.gestudio_current_tenant_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
PARALLEL SAFE
SET search_path = pg_catalog
AS $$
DECLARE
    configured TEXT;
    privileged BOOLEAN;
BEGIN
    configured := current_setting('app.current_tenant_id', TRUE);
    IF configured IS NOT NULL AND btrim(configured) <> '' THEN
        RETURN configured::UUID;
    END IF;

    SELECT r.rolsuper OR r.rolbypassrls
    INTO privileged
    FROM pg_catalog.pg_roles r
    WHERE r.rolname = current_user;

    IF COALESCE(privileged, FALSE) THEN
        RETURN '00000000-0000-0000-0000-000000000001'::UUID;
    END IF;

    RAISE EXCEPTION 'tenant context missing'
        USING ERRCODE = '42501';
END;
$$;

REVOKE ALL ON FUNCTION public.gestudio_current_tenant_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gestudio_current_tenant_id() TO gestudio_app;

-- Auditoría necesita registrar fallos de autenticación antes de seleccionar
-- tenant. Esta variante sólo observa el setting y devuelve NULL si falta; no
-- aplica el fallback operativo ni puede autorizar datos de otro tenant.
CREATE FUNCTION public.gestudio_optional_tenant_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
PARALLEL SAFE
SET search_path = pg_catalog
AS $$
DECLARE
    configured TEXT;
BEGIN
    configured := current_setting('app.current_tenant_id', TRUE);
    IF configured IS NULL OR btrim(configured) = '' THEN
        RETURN NULL;
    END IF;
    RETURN configured::UUID;
END;
$$;

REVOKE ALL ON FUNCTION public.gestudio_optional_tenant_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gestudio_optional_tenant_id() TO gestudio_app;

-- Los defaults son seguros: el backend no mapea tenant_id en cada entidad;
-- PostgreSQL toma el contexto autenticado. Sin contexto, un rol ordinario
-- recibe 42501; sólo superuser/BYPASSRLS obtiene el tenant inicial documentado
-- para Flyway, tests legacy y operación controlada.
ALTER TABLE public.roles ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.rol_permisos ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.alumnos ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.salones ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.profesores ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.observaciones_profesores ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.bonificaciones ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.recargos ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.metodo_pagos ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.sub_conceptos ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.conceptos ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.stocks ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.disciplinas ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.disciplina_horarios ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.inscripciones ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.mensualidades ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.matriculas ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.asistencias_mensuales ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.asistencias_alumno_mensual ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.asistencias_diarias ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.ventas_stock ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.cargos ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.pagos ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.aplicaciones_pago ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.egresos ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.movimientos_caja ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.movimientos_credito ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.movimientos_stock ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.recibos ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.recibos_pendientes ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.notificaciones ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.disciplina_tarifas ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.inscripcion_condiciones_economicas ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.cargo_liquidaciones ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.cargo_eventos ALTER COLUMN tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.jere_platform_tenant_mappings
    ALTER COLUMN internal_tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.jere_platform_student_export_snapshots
    ALTER COLUMN internal_tenant_id SET DEFAULT public.gestudio_current_tenant_id();
ALTER TABLE public.jere_platform_student_export_pages
    ALTER COLUMN internal_tenant_id SET DEFAULT public.gestudio_current_tenant_id();

-- Habilitación explícita, no dinámica, del inventario V9.
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles FORCE ROW LEVEL SECURITY;
ALTER TABLE public.rol_permisos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rol_permisos FORCE ROW LEVEL SECURITY;
ALTER TABLE public.alumnos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alumnos FORCE ROW LEVEL SECURITY;
ALTER TABLE public.salones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.salones FORCE ROW LEVEL SECURITY;
ALTER TABLE public.profesores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profesores FORCE ROW LEVEL SECURITY;
ALTER TABLE public.observaciones_profesores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.observaciones_profesores FORCE ROW LEVEL SECURITY;
ALTER TABLE public.bonificaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bonificaciones FORCE ROW LEVEL SECURITY;
ALTER TABLE public.recargos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recargos FORCE ROW LEVEL SECURITY;
ALTER TABLE public.metodo_pagos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.metodo_pagos FORCE ROW LEVEL SECURITY;
ALTER TABLE public.sub_conceptos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sub_conceptos FORCE ROW LEVEL SECURITY;
ALTER TABLE public.conceptos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conceptos FORCE ROW LEVEL SECURITY;
ALTER TABLE public.stocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stocks FORCE ROW LEVEL SECURITY;
ALTER TABLE public.disciplinas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.disciplinas FORCE ROW LEVEL SECURITY;
ALTER TABLE public.disciplina_horarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.disciplina_horarios FORCE ROW LEVEL SECURITY;
ALTER TABLE public.inscripciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inscripciones FORCE ROW LEVEL SECURITY;
ALTER TABLE public.mensualidades ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mensualidades FORCE ROW LEVEL SECURITY;
ALTER TABLE public.matriculas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matriculas FORCE ROW LEVEL SECURITY;
ALTER TABLE public.asistencias_mensuales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asistencias_mensuales FORCE ROW LEVEL SECURITY;
ALTER TABLE public.asistencias_alumno_mensual ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asistencias_alumno_mensual FORCE ROW LEVEL SECURITY;
ALTER TABLE public.asistencias_diarias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asistencias_diarias FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ventas_stock ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ventas_stock FORCE ROW LEVEL SECURITY;
ALTER TABLE public.cargos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cargos FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pagos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pagos FORCE ROW LEVEL SECURITY;
ALTER TABLE public.aplicaciones_pago ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.aplicaciones_pago FORCE ROW LEVEL SECURITY;
ALTER TABLE public.egresos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.egresos FORCE ROW LEVEL SECURITY;
ALTER TABLE public.movimientos_caja ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.movimientos_caja FORCE ROW LEVEL SECURITY;
ALTER TABLE public.movimientos_credito ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.movimientos_credito FORCE ROW LEVEL SECURITY;
ALTER TABLE public.movimientos_stock ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.movimientos_stock FORCE ROW LEVEL SECURITY;
ALTER TABLE public.recibos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recibos FORCE ROW LEVEL SECURITY;
ALTER TABLE public.recibos_pendientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recibos_pendientes FORCE ROW LEVEL SECURITY;
ALTER TABLE public.notificaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notificaciones FORCE ROW LEVEL SECURITY;
ALTER TABLE public.disciplina_tarifas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.disciplina_tarifas FORCE ROW LEVEL SECURITY;
ALTER TABLE public.inscripcion_condiciones_economicas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inscripcion_condiciones_economicas FORCE ROW LEVEL SECURITY;
ALTER TABLE public.cargo_liquidaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cargo_liquidaciones FORCE ROW LEVEL SECURITY;
ALTER TABLE public.cargo_eventos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cargo_eventos FORCE ROW LEVEL SECURITY;
ALTER TABLE public.jere_platform_tenant_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.jere_platform_tenant_mappings FORCE ROW LEVEL SECURITY;
ALTER TABLE public.jere_platform_student_export_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.jere_platform_student_export_snapshots FORCE ROW LEVEL SECURITY;
ALTER TABLE public.jere_platform_student_export_pages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.jere_platform_student_export_pages FORCE ROW LEVEL SECURITY;
ALTER TABLE public.refresh_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refresh_sessions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.auditoria_eventos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auditoria_eventos FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON public.roles TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.rol_permisos TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.alumnos TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.salones TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.profesores TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.observaciones_profesores TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.bonificaciones TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.recargos TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.metodo_pagos TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.sub_conceptos TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.conceptos TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.stocks TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.disciplinas TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.disciplina_horarios TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.inscripciones TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.mensualidades TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.matriculas TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.asistencias_mensuales TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.asistencias_alumno_mensual TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.asistencias_diarias TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.ventas_stock TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.cargos TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.pagos TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.aplicaciones_pago TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.egresos TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.movimientos_caja TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.movimientos_credito TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.movimientos_stock TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.recibos TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.recibos_pendientes TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.notificaciones TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.disciplina_tarifas TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.inscripcion_condiciones_economicas TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.cargo_liquidaciones TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.cargo_eventos TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.jere_platform_tenant_mappings TO gestudio_app
    USING (internal_tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (internal_tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.jere_platform_student_export_snapshots TO gestudio_app
    USING (internal_tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (internal_tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.jere_platform_student_export_pages TO gestudio_app
    USING (internal_tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (internal_tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY tenant_isolation ON public.refresh_sessions TO gestudio_app
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY audit_tenant_select ON public.auditoria_eventos
    FOR SELECT TO gestudio_app
    USING (tenant_id = public.gestudio_optional_tenant_id());
CREATE POLICY audit_tenant_insert ON public.auditoria_eventos
    FOR INSERT TO gestudio_app
    WITH CHECK (
        CASE
            WHEN public.gestudio_optional_tenant_id() IS NULL THEN tenant_id IS NULL
            ELSE tenant_id = public.gestudio_optional_tenant_id()
        END
    );

GRANT USAGE ON SCHEMA public TO gestudio_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON
    public.roles,
    public.rol_permisos,
    public.alumnos,
    public.salones,
    public.profesores,
    public.observaciones_profesores,
    public.bonificaciones,
    public.recargos,
    public.metodo_pagos,
    public.sub_conceptos,
    public.conceptos,
    public.stocks,
    public.disciplinas,
    public.disciplina_horarios,
    public.inscripciones,
    public.mensualidades,
    public.matriculas,
    public.asistencias_mensuales,
    public.asistencias_alumno_mensual,
    public.asistencias_diarias,
    public.ventas_stock,
    public.cargos,
    public.pagos,
    public.aplicaciones_pago,
    public.egresos,
    public.movimientos_caja,
    public.movimientos_credito,
    public.movimientos_stock,
    public.recibos,
    public.recibos_pendientes,
    public.notificaciones,
    public.disciplina_tarifas,
    public.inscripcion_condiciones_economicas,
    public.cargo_liquidaciones,
    public.cargo_eventos,
    public.jere_platform_tenant_mappings,
    public.jere_platform_student_export_snapshots,
    public.jere_platform_student_export_pages
TO gestudio_app;
GRANT SELECT, INSERT, UPDATE ON public.refresh_sessions TO gestudio_app;

-- Control plane previo a la selección: acceso explícito, sin RLS. No se
-- concede DELETE para evitar borrar identidad o memberships.
GRANT SELECT, INSERT, UPDATE ON
    public.tenants,
    public.tenant_memberships,
    public.platform_admins
TO gestudio_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tenant_membership_roles TO gestudio_app;
GRANT SELECT, INSERT, UPDATE ON public.usuarios TO gestudio_app;
GRANT SELECT ON public.permisos TO gestudio_app;
GRANT SELECT, INSERT ON public.usuario_roles TO gestudio_app;
GRANT SELECT, INSERT, UPDATE ON public.bootstrap_ejecuciones TO gestudio_app;
GRANT SELECT, INSERT ON public.auditoria_eventos TO gestudio_app;
GRANT SELECT ON public.v_cuotas_seguimiento TO gestudio_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO gestudio_app;

-- Health estructural sin IDs ni conteos por tenant. El owner NOLOGIN sólo
-- puede leer control plane/catálogo; no posee BYPASSRLS ni tablas de dominio.
GRANT USAGE ON SCHEMA public TO gestudio_health;
GRANT SELECT ON public.tenants, public.tenant_memberships, public.usuarios TO gestudio_health;

CREATE FUNCTION public.gestudio_multitenancy_health()
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
    expected_rls_tables CONSTANT INTEGER := 40;
    expected_tenant_columns CONSTANT INTEGER := 39;
    expected_tenant_defaults CONSTANT INTEGER := 38;
    expected_isolation_policies CONSTANT INTEGER := 39;
    secure_tables INTEGER;
    tenant_columns INTEGER;
    tenant_defaults INTEGER;
    isolation_policies INTEGER;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.tenants
        WHERE id = '00000000-0000-0000-0000-000000000001'
          AND code = 'academia-inicial'
    ) THEN
        RETURN 'RED';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.usuarios u
        WHERE NOT EXISTS (
            SELECT 1 FROM public.tenant_memberships m WHERE m.usuario_id = u.id
        )
    ) THEN
        RETURN 'RED';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_roles
        WHERE rolname = 'gestudio_app'
          AND (rolsuper OR rolcreaterole OR rolcreatedb OR rolcanlogin OR rolreplication OR rolbypassrls)
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'gestudio_app'
    ) THEN
        RETURN 'RED';
    END IF;

    SELECT count(*)
    INTO secure_tables
    FROM (VALUES
        ('roles'), ('rol_permisos'), ('alumnos'), ('salones'), ('profesores'),
        ('observaciones_profesores'), ('bonificaciones'), ('recargos'), ('metodo_pagos'),
        ('sub_conceptos'), ('conceptos'), ('stocks'), ('disciplinas'), ('disciplina_horarios'),
        ('inscripciones'), ('mensualidades'), ('matriculas'), ('asistencias_mensuales'),
        ('asistencias_alumno_mensual'), ('asistencias_diarias'), ('ventas_stock'),
        ('cargos'), ('pagos'), ('aplicaciones_pago'), ('egresos'), ('movimientos_caja'),
        ('movimientos_credito'), ('movimientos_stock'), ('recibos'), ('recibos_pendientes'),
        ('notificaciones'), ('disciplina_tarifas'), ('inscripcion_condiciones_economicas'),
        ('cargo_liquidaciones'), ('cargo_eventos'), ('jere_platform_tenant_mappings'),
        ('jere_platform_student_export_snapshots'), ('jere_platform_student_export_pages'),
        ('refresh_sessions'), ('auditoria_eventos')
    ) expected(name)
    JOIN pg_catalog.pg_class c ON c.relname = expected.name
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
    WHERE c.relrowsecurity AND c.relforcerowsecurity;

    IF secure_tables <> expected_rls_tables THEN
        RETURN 'RED';
    END IF;

    SELECT count(*)
    INTO tenant_columns
    FROM (VALUES
        ('roles','tenant_id'), ('rol_permisos','tenant_id'), ('alumnos','tenant_id'),
        ('salones','tenant_id'), ('profesores','tenant_id'), ('observaciones_profesores','tenant_id'),
        ('bonificaciones','tenant_id'), ('recargos','tenant_id'), ('metodo_pagos','tenant_id'),
        ('sub_conceptos','tenant_id'), ('conceptos','tenant_id'), ('stocks','tenant_id'),
        ('disciplinas','tenant_id'), ('disciplina_horarios','tenant_id'), ('inscripciones','tenant_id'),
        ('mensualidades','tenant_id'), ('matriculas','tenant_id'), ('asistencias_mensuales','tenant_id'),
        ('asistencias_alumno_mensual','tenant_id'), ('asistencias_diarias','tenant_id'),
        ('ventas_stock','tenant_id'), ('cargos','tenant_id'), ('pagos','tenant_id'),
        ('aplicaciones_pago','tenant_id'), ('egresos','tenant_id'), ('movimientos_caja','tenant_id'),
        ('movimientos_credito','tenant_id'), ('movimientos_stock','tenant_id'), ('recibos','tenant_id'),
        ('recibos_pendientes','tenant_id'), ('notificaciones','tenant_id'),
        ('disciplina_tarifas','tenant_id'), ('inscripcion_condiciones_economicas','tenant_id'),
        ('cargo_liquidaciones','tenant_id'), ('cargo_eventos','tenant_id'),
        ('jere_platform_tenant_mappings','internal_tenant_id'),
        ('jere_platform_student_export_snapshots','internal_tenant_id'),
        ('jere_platform_student_export_pages','internal_tenant_id'),
        ('refresh_sessions','tenant_id')
    ) expected(table_name, column_name)
    JOIN pg_catalog.pg_class c ON c.relname = expected.table_name
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
    JOIN pg_catalog.pg_attribute a
      ON a.attrelid = c.oid AND a.attname = expected.column_name AND a.attnotnull AND NOT a.attisdropped;

    IF tenant_columns <> expected_tenant_columns THEN
        RETURN 'RED';
    END IF;

    SELECT count(*)
    INTO tenant_defaults
    FROM (VALUES
        ('roles','tenant_id'), ('rol_permisos','tenant_id'), ('alumnos','tenant_id'),
        ('salones','tenant_id'), ('profesores','tenant_id'), ('observaciones_profesores','tenant_id'),
        ('bonificaciones','tenant_id'), ('recargos','tenant_id'), ('metodo_pagos','tenant_id'),
        ('sub_conceptos','tenant_id'), ('conceptos','tenant_id'), ('stocks','tenant_id'),
        ('disciplinas','tenant_id'), ('disciplina_horarios','tenant_id'), ('inscripciones','tenant_id'),
        ('mensualidades','tenant_id'), ('matriculas','tenant_id'), ('asistencias_mensuales','tenant_id'),
        ('asistencias_alumno_mensual','tenant_id'), ('asistencias_diarias','tenant_id'),
        ('ventas_stock','tenant_id'), ('cargos','tenant_id'), ('pagos','tenant_id'),
        ('aplicaciones_pago','tenant_id'), ('egresos','tenant_id'), ('movimientos_caja','tenant_id'),
        ('movimientos_credito','tenant_id'), ('movimientos_stock','tenant_id'), ('recibos','tenant_id'),
        ('recibos_pendientes','tenant_id'), ('notificaciones','tenant_id'),
        ('disciplina_tarifas','tenant_id'), ('inscripcion_condiciones_economicas','tenant_id'),
        ('cargo_liquidaciones','tenant_id'), ('cargo_eventos','tenant_id'),
        ('jere_platform_tenant_mappings','internal_tenant_id'),
        ('jere_platform_student_export_snapshots','internal_tenant_id'),
        ('jere_platform_student_export_pages','internal_tenant_id')
    ) expected(table_name, column_name)
    JOIN pg_catalog.pg_class c ON c.relname = expected.table_name
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
    JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid AND a.attname = expected.column_name
    JOIN pg_catalog.pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
    WHERE pg_catalog.pg_get_expr(d.adbin, d.adrelid) = 'public.gestudio_current_tenant_id()';

    IF tenant_defaults <> expected_tenant_defaults THEN
        RETURN 'RED';
    END IF;

    SELECT count(*)
    INTO isolation_policies
    FROM (VALUES
        ('roles'), ('rol_permisos'), ('alumnos'), ('salones'), ('profesores'),
        ('observaciones_profesores'), ('bonificaciones'), ('recargos'), ('metodo_pagos'),
        ('sub_conceptos'), ('conceptos'), ('stocks'), ('disciplinas'), ('disciplina_horarios'),
        ('inscripciones'), ('mensualidades'), ('matriculas'), ('asistencias_mensuales'),
        ('asistencias_alumno_mensual'), ('asistencias_diarias'), ('ventas_stock'),
        ('cargos'), ('pagos'), ('aplicaciones_pago'), ('egresos'), ('movimientos_caja'),
        ('movimientos_credito'), ('movimientos_stock'), ('recibos'), ('recibos_pendientes'),
        ('notificaciones'), ('disciplina_tarifas'), ('inscripcion_condiciones_economicas'),
        ('cargo_liquidaciones'), ('cargo_eventos'), ('jere_platform_tenant_mappings'),
        ('jere_platform_student_export_snapshots'), ('jere_platform_student_export_pages'),
        ('refresh_sessions')
    ) expected(name)
    JOIN pg_catalog.pg_class c ON c.relname = expected.name
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
    JOIN pg_catalog.pg_policy p ON p.polrelid = c.oid AND p.polname = 'tenant_isolation'
    JOIN pg_catalog.pg_roles app ON app.rolname = 'gestudio_app' AND app.oid = ANY(p.polroles);

    IF isolation_policies <> expected_isolation_policies THEN
        RETURN 'RED';
    END IF;

    IF (
        SELECT count(*)
        FROM pg_catalog.pg_policy p
        JOIN pg_catalog.pg_class c ON c.oid = p.polrelid AND c.relname = 'auditoria_eventos'
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
        JOIN pg_catalog.pg_roles app ON app.rolname = 'gestudio_app' AND app.oid = ANY(p.polroles)
        WHERE p.polname IN ('audit_tenant_select', 'audit_tenant_insert')
    ) <> 2 THEN
        RETURN 'RED';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint con
        JOIN pg_catalog.pg_class c ON c.oid = con.conrelid
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND NOT con.convalidated
    ) THEN
        RETURN 'RED';
    END IF;

    RETURN 'GREEN';
EXCEPTION
    WHEN OTHERS THEN
        RETURN 'RED';
END;
$$;

ALTER FUNCTION public.gestudio_multitenancy_health() OWNER TO gestudio_health;
REVOKE ALL ON FUNCTION public.gestudio_multitenancy_health() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gestudio_multitenancy_health() TO gestudio_app;

CREATE VIEW public.v_multitenancy_migration_health
WITH (security_invoker = TRUE)
AS SELECT public.gestudio_multitenancy_health() AS status;
GRANT SELECT ON public.v_multitenancy_migration_health TO gestudio_app;

DO $$
DECLARE
    migration_role_privileged BOOLEAN;
    denied_without_context BOOLEAN := FALSE;
BEGIN
    SELECT rolsuper OR rolbypassrls
    INTO migration_role_privileged
    FROM pg_catalog.pg_roles
    WHERE rolname = current_user;

    IF COALESCE(migration_role_privileged, FALSE)
       AND public.gestudio_current_tenant_id()
           <> '00000000-0000-0000-0000-000000000001'::UUID THEN
        RAISE EXCEPTION 'V10 multitenancy: fallback operativo no devuelve el tenant inicial';
    END IF;

    -- Cuando el rol Flyway puede SET ROLE, prueba realmente el fail-closed del
    -- rol app. En instalaciones con delegación más estrecha lo cubre el gate.
    IF COALESCE(migration_role_privileged, FALSE)
       OR pg_catalog.pg_has_role(current_user, 'gestudio_app', 'MEMBER') THEN
        BEGIN
            EXECUTE 'SET LOCAL ROLE gestudio_app';
            PERFORM pg_catalog.set_config('app.current_tenant_id', '', TRUE);
            PERFORM public.gestudio_current_tenant_id();
        EXCEPTION
            WHEN insufficient_privilege THEN
                denied_without_context := TRUE;
        END;

        IF NOT denied_without_context THEN
            RAISE EXCEPTION 'V10 multitenancy: gestudio_app aceptó un contexto ausente';
        END IF;
    END IF;

    IF public.gestudio_multitenancy_health() <> 'GREEN' THEN
        RAISE EXCEPTION 'V10 multitenancy: health estructural inicial no es GREEN';
    END IF;
END;
$$;
