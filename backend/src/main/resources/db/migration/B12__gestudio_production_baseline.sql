-- Baseline productivo canónico equivalente al esquema V1..V12.
--
-- Flyway aplica este archivo solamente sobre una base nueva. No contiene
-- tenants, usuarios, memberships, roles funcionales, asignaciones ni datos de
-- negocio. El único contenido inicial permitido es el catálogo global de 32
-- permisos requerido para autorizar los roles que cree el control plane.

DO $$
DECLARE
    technical_role TEXT;
BEGIN
    FOREACH technical_role IN ARRAY ARRAY[
        'gestudio_app',
        'gestudio_health',
        'gestudio_platform'
    ]
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = technical_role
        ) THEN
            EXECUTE pg_catalog.format(
                'CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS',
                technical_role
            );
        END IF;
    END LOOP;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles
        WHERE rolname IN ('gestudio_app', 'gestudio_health', 'gestudio_platform')
          AND (
              rolsuper OR rolcreaterole OR rolcreatedb OR rolcanlogin
              OR rolinherit OR rolreplication OR rolbypassrls
          )
    ) OR (
        SELECT count(*)
        FROM pg_catalog.pg_roles
        WHERE rolname IN ('gestudio_app', 'gestudio_health', 'gestudio_platform')
    ) <> 3 THEN
        RAISE EXCEPTION 'B12 baseline: los roles técnicos faltan o poseen atributos inseguros';
    END IF;
EXCEPTION
    WHEN insufficient_privilege THEN
        RAISE EXCEPTION
            'B12 baseline requiere crear/verificar gestudio_app, gestudio_health y gestudio_platform como NOLOGIN';
END;
$$;

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: gestudio_current_tenant_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gestudio_current_tenant_id() RETURNS uuid
    LANGUAGE plpgsql STABLE PARALLEL SAFE
    SET search_path TO 'pg_catalog'
    AS $$
DECLARE
    configured TEXT;
BEGIN
    configured := current_setting('app.current_tenant_id', TRUE);
    IF configured IS NOT NULL AND btrim(configured) <> '' THEN
        RETURN configured::UUID;
    END IF;

    RAISE EXCEPTION 'tenant context missing'
        USING ERRCODE = '42501';
END;
$$;


--
-- Name: gestudio_multitenancy_health(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gestudio_multitenancy_health() RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $$
DECLARE
    expected_rls_tables CONSTANT INTEGER := 42;
    expected_tenant_columns CONSTANT INTEGER := 39;
    expected_tenant_defaults CONSTANT INTEGER := 38;
    expected_isolation_policies CONSTANT INTEGER := 39;
    secure_tables INTEGER;
    tenant_columns INTEGER;
    tenant_defaults INTEGER;
    isolation_policies INTEGER;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.usuarios u
        WHERE NOT EXISTS (
            SELECT 1 FROM public.tenant_memberships m WHERE m.usuario_id = u.id
        )
          AND NOT EXISTS (
            SELECT 1 FROM public.platform_admins pa
            WHERE pa.usuario_id = u.id
        )
    ) THEN
        RETURN 'RED';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.platform_admins pa
        LEFT JOIN public.usuarios u ON u.id = pa.usuario_id
        WHERE u.id IS NULL OR pa.security_version < 0
    ) THEN
        RETURN 'RED';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles
        WHERE rolname IN ('gestudio_app', 'gestudio_health', 'gestudio_platform')
          AND (
              rolsuper OR rolcreaterole OR rolcreatedb OR rolcanlogin
              OR rolinherit OR rolreplication OR rolbypassrls
          )
    ) OR (
        SELECT count(*) FROM pg_catalog.pg_roles
        WHERE rolname IN ('gestudio_app', 'gestudio_health', 'gestudio_platform')
    ) <> 3 THEN
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
        ('refresh_sessions'), ('auditoria_eventos'), ('tenant_memberships'),
        ('tenant_membership_roles')
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

    IF (
        SELECT count(*)
        FROM pg_catalog.pg_policy p
        JOIN pg_catalog.pg_class c ON c.oid = p.polrelid
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
        WHERE EXISTS (
                  SELECT 1 FROM pg_catalog.pg_roles role_row
                  WHERE role_row.rolname = 'gestudio_app'
                    AND role_row.oid = ANY(p.polroles)
              )
          AND EXISTS (
                  SELECT 1 FROM pg_catalog.pg_roles role_row
                  WHERE role_row.rolname = 'gestudio_platform'
                    AND role_row.oid = ANY(p.polroles)
              )
          AND ((c.relname = 'tenant_memberships'
               AND p.polname IN ('membership_global_select',
                                  'membership_target_insert', 'membership_target_update'))
            OR (c.relname = 'tenant_membership_roles'
                AND p.polname IN ('membership_target_select', 'membership_target_insert',
                                  'membership_target_update', 'membership_target_delete')))
    ) <> 7 THEN
        RETURN 'RED';
    END IF;

    IF (
        SELECT count(*)
        FROM pg_catalog.pg_policy p
        JOIN pg_catalog.pg_class c ON c.oid = p.polrelid
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
        JOIN pg_catalog.pg_roles platform_role
          ON platform_role.rolname = 'gestudio_platform'
         AND platform_role.oid = ANY(p.polroles)
        WHERE p.polname = 'platform_target_tenant'
          AND c.relname IN ('roles', 'rol_permisos')
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


--
-- Name: gestudio_optional_tenant_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gestudio_optional_tenant_id() RETURNS uuid
    LANGUAGE plpgsql STABLE PARALLEL SAFE
    SET search_path TO 'pg_catalog'
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


--
-- Name: impedir_cambio_codigo_permisos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.impedir_cambio_codigo_permisos() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.codigo <> OLD.codigo THEN
        RAISE EXCEPTION 'permisos.codigo es inmutable' USING ERRCODE = '55000';
END IF;

RETURN NEW;
END;
$$;


--
-- Name: impedir_cambio_codigo_roles(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.impedir_cambio_codigo_roles() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.codigo <> OLD.codigo THEN
        RAISE EXCEPTION 'roles.codigo es inmutable' USING ERRCODE = '55000';
END IF;

RETURN NEW;
END;
$$;


--
-- Name: rechazar_mutacion_auditoria(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rechazar_mutacion_auditoria() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'auditoria_eventos es append-only' USING ERRCODE = '55000';
END;
$$;


--
-- Name: rechazar_mutacion_cargo_evento(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rechazar_mutacion_cargo_evento() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'cargo_eventos es append-only' USING ERRCODE = '55000';
END;
$$;


--
-- Name: rechazar_mutacion_jere_export(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rechazar_mutacion_jere_export() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'exports Jere Platform son append-only' USING ERRCODE = '55000';
END;
$$;


--
-- Name: rechazar_mutacion_jere_mapping(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rechazar_mutacion_jere_mapping() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'jere_platform_tenant_mappings es inmutable; no admite borrado'
            USING ERRCODE = '55000';
    END IF;

    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.internal_tenant_id IS DISTINCT FROM OLD.internal_tenant_id
       OR NEW.external_organization_id IS DISTINCT FROM OLD.external_organization_id
       OR NEW.external_tenant_id IS DISTINCT FROM OLD.external_tenant_id
       OR NEW.source_type IS DISTINCT FROM OLD.source_type
       OR NEW.config_version IS DISTINCT FROM OLD.config_version
       OR NEW.signing_key_ref IS DISTINCT FROM OLD.signing_key_ref
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.created_by_usuario_id IS DISTINCT FROM OLD.created_by_usuario_id
       OR (NOT OLD.active AND NEW.active)
       OR (OLD.deactivated_at IS NOT NULL AND NEW.deactivated_at IS DISTINCT FROM OLD.deactivated_at) THEN
        RAISE EXCEPTION 'jere_platform_tenant_mappings es inmutable; sólo puede desactivarse'
            USING ERRCODE = '55000';
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: rechazar_mutacion_platform_audit(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rechazar_mutacion_platform_audit() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
BEGIN
    RAISE EXCEPTION 'platform_audit_events es append-only' USING ERRCODE = '55000';
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: alumnos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alumnos (
    id bigint NOT NULL,
    nombre character varying(100) NOT NULL,
    apellido character varying(100),
    fecha_nacimiento date,
    celular1 character varying(30),
    celular2 character varying(30),
    email character varying(254),
    documento character varying(30),
    fecha_incorporacion date NOT NULL,
    fecha_de_baja date,
    nombre_padres character varying(200),
    autorizado_para_salir_solo boolean,
    otras_notas text,
    activo boolean DEFAULT true NOT NULL,
    version bigint DEFAULT 0 NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_alumnos_baja CHECK (((activo AND (fecha_de_baja IS NULL)) OR (NOT activo)))
);

ALTER TABLE ONLY public.alumnos FORCE ROW LEVEL SECURITY;


--
-- Name: alumnos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.alumnos ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.alumnos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: aplicaciones_pago; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.aplicaciones_pago (
    id bigint NOT NULL,
    pago_id bigint NOT NULL,
    cargo_id bigint NOT NULL,
    usuario_id bigint NOT NULL,
    importe_aplicado numeric(19,2) NOT NULL,
    estado character varying(10) DEFAULT 'APLICADA'::character varying NOT NULL,
    fecha date NOT NULL,
    motivo_reversion character varying(500),
    fecha_reversion timestamp with time zone,
    version bigint DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_aplicaciones_estado CHECK (((estado)::text = ANY ((ARRAY['APLICADA'::character varying, 'REVERTIDA'::character varying])::text[]))),
    CONSTRAINT ck_aplicaciones_importe CHECK ((importe_aplicado > (0)::numeric)),
    CONSTRAINT ck_aplicaciones_reversion CHECK (((((estado)::text = 'APLICADA'::text) AND (fecha_reversion IS NULL) AND (motivo_reversion IS NULL)) OR (((estado)::text = 'REVERTIDA'::text) AND (fecha_reversion IS NOT NULL) AND (motivo_reversion IS NOT NULL))))
);

ALTER TABLE ONLY public.aplicaciones_pago FORCE ROW LEVEL SECURITY;


--
-- Name: aplicaciones_pago_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.aplicaciones_pago ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.aplicaciones_pago_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: asistencias_alumno_mensual; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asistencias_alumno_mensual (
    id bigint NOT NULL,
    inscripcion_id bigint NOT NULL,
    asistencia_mensual_id bigint NOT NULL,
    observacion character varying(500),
    activo boolean DEFAULT true NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL
);

ALTER TABLE ONLY public.asistencias_alumno_mensual FORCE ROW LEVEL SECURITY;


--
-- Name: asistencias_alumno_mensual_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.asistencias_alumno_mensual ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.asistencias_alumno_mensual_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: asistencias_diarias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asistencias_diarias (
    id bigint NOT NULL,
    asistencia_alumno_mensual_id bigint NOT NULL,
    fecha date NOT NULL,
    estado character varying(10) NOT NULL,
    vigente boolean DEFAULT true NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_asistencias_diarias_estado CHECK (((estado)::text = ANY ((ARRAY['PRESENTE'::character varying, 'AUSENTE'::character varying, 'JUSTIFICADO'::character varying])::text[])))
);

ALTER TABLE ONLY public.asistencias_diarias FORCE ROW LEVEL SECURITY;


--
-- Name: asistencias_diarias_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.asistencias_diarias ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.asistencias_diarias_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: asistencias_mensuales; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asistencias_mensuales (
    id bigint NOT NULL,
    disciplina_id bigint NOT NULL,
    mes integer NOT NULL,
    anio integer NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_asistencias_mensuales_anio CHECK (((anio >= 2000) AND (anio <= 9999))),
    CONSTRAINT ck_asistencias_mensuales_mes CHECK (((mes >= 1) AND (mes <= 12)))
);

ALTER TABLE ONLY public.asistencias_mensuales FORCE ROW LEVEL SECURITY;


--
-- Name: asistencias_mensuales_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.asistencias_mensuales ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.asistencias_mensuales_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auditoria_eventos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditoria_eventos (
    id bigint NOT NULL,
    categoria character varying(30) NOT NULL,
    accion character varying(100) NOT NULL,
    entidad_tipo character varying(100),
    entidad_id character varying(100),
    actor_usuario_id bigint,
    actor_username_snapshot character varying(100),
    actor_role_snapshot character varying(50),
    ocurrido_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    fecha_negocio date NOT NULL,
    correlation_id uuid,
    idempotency_key character varying(150),
    estado_anterior jsonb,
    estado_nuevo jsonb,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    tenant_id uuid,
    CONSTRAINT ck_auditoria_categoria CHECK (((categoria)::text = ANY ((ARRAY['SEGURIDAD'::character varying, 'USUARIOS'::character varying, 'TARIFAS'::character varying, 'FACTURACION'::character varying, 'PAGOS'::character varying, 'CAJA'::character varying, 'STOCK'::character varying, 'SISTEMA'::character varying])::text[])))
);

ALTER TABLE ONLY public.auditoria_eventos FORCE ROW LEVEL SECURITY;


--
-- Name: auditoria_eventos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.auditoria_eventos ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auditoria_eventos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: bonificaciones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bonificaciones (
    id bigint NOT NULL,
    descripcion character varying(150) NOT NULL,
    porcentaje_descuento numeric(7,4) DEFAULT 0 NOT NULL,
    valor_fijo numeric(19,2) DEFAULT 0 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    observaciones character varying(500),
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_bonificaciones_porcentaje CHECK (((porcentaje_descuento >= (0)::numeric) AND (porcentaje_descuento <= (100)::numeric))),
    CONSTRAINT ck_bonificaciones_valor CHECK ((valor_fijo >= (0)::numeric))
);

ALTER TABLE ONLY public.bonificaciones FORCE ROW LEVEL SECURITY;


--
-- Name: bonificaciones_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.bonificaciones ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.bonificaciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: bootstrap_ejecuciones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bootstrap_ejecuciones (
    tipo character varying(50) NOT NULL,
    usuario_id bigint,
    ejecutado_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: cargo_eventos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cargo_eventos (
    id bigint NOT NULL,
    cargo_id bigint NOT NULL,
    tipo character varying(30) NOT NULL,
    estado_anterior character varying(10),
    estado_nuevo character varying(10),
    saldo_anterior numeric(19,2),
    saldo_nuevo numeric(19,2),
    referencia_tipo character varying(30),
    referencia_id bigint,
    idempotency_key character varying(150) NOT NULL,
    usuario_id bigint,
    ocurrido_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    correlation_id uuid,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_cargo_evento_tipo CHECK (((tipo)::text = ANY ((ARRAY['EMITIDO'::character varying, 'PAGO_APLICADO'::character varying, 'PAGO_REVERTIDO'::character varying, 'CREDITO_APLICADO'::character varying, 'CREDITO_REVERTIDO'::character varying, 'RECARGO_CREADO'::character varying, 'ANULADO'::character varying])::text[])))
);

ALTER TABLE ONLY public.cargo_eventos FORCE ROW LEVEL SECURITY;


--
-- Name: cargo_eventos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.cargo_eventos ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.cargo_eventos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: cargo_liquidaciones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cargo_liquidaciones (
    cargo_id bigint NOT NULL,
    periodo_desde date NOT NULL,
    tarifa_disciplina_id bigint,
    condicion_inscripcion_id bigint,
    origen_precio character varying(30) NOT NULL,
    importe_base numeric(19,2) NOT NULL,
    descuento_porcentaje numeric(7,4) DEFAULT 0 NOT NULL,
    descuento_importe numeric(19,2) DEFAULT 0 NOT NULL,
    recargo_porcentaje numeric(7,4) DEFAULT 0 NOT NULL,
    recargo_importe numeric(19,2) DEFAULT 0 NOT NULL,
    importe_final numeric(19,2) NOT NULL,
    formula_version integer NOT NULL,
    observaciones character varying(500),
    calculada_por_usuario_id bigint,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_cargo_liquidacion_importes CHECK (((importe_base >= (0)::numeric) AND ((descuento_porcentaje >= (0)::numeric) AND (descuento_porcentaje <= (100)::numeric)) AND (descuento_importe >= (0)::numeric) AND ((recargo_porcentaje >= (0)::numeric) AND (recargo_porcentaje <= (100)::numeric)) AND (recargo_importe >= (0)::numeric) AND (importe_final >= (0)::numeric))),
    CONSTRAINT ck_cargo_liquidacion_origen CHECK (((origen_precio)::text = ANY ((ARRAY['TARIFA_HISTORICA'::character varying, 'COSTO_PARTICULAR'::character varying, 'MANUAL_HISTORICO'::character varying, 'MIGRADO_CARGO_EXISTENTE'::character varying])::text[])))
);

ALTER TABLE ONLY public.cargo_liquidaciones FORCE ROW LEVEL SECURITY;


--
-- Name: cargos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cargos (
    id bigint NOT NULL,
    alumno_id bigint NOT NULL,
    tipo character varying(20) NOT NULL,
    descripcion character varying(255) NOT NULL,
    importe_original numeric(19,2) NOT NULL,
    fecha_emision date NOT NULL,
    fecha_vencimiento date NOT NULL,
    estado character varying(10) DEFAULT 'PENDIENTE'::character varying NOT NULL,
    mensualidad_id bigint,
    matricula_id bigint,
    concepto_id bigint,
    venta_stock_id bigint,
    cargo_origen_id bigint,
    idempotency_key character varying(100),
    version bigint DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_cargos_estado CHECK (((estado)::text = ANY ((ARRAY['PENDIENTE'::character varying, 'PARCIAL'::character varying, 'PAGADO'::character varying, 'ANULADO'::character varying])::text[]))),
    CONSTRAINT ck_cargos_importe CHECK ((importe_original >= (0)::numeric)),
    CONSTRAINT ck_cargos_origen CHECK (((((tipo)::text = 'MENSUALIDAD'::text) AND (mensualidad_id IS NOT NULL) AND (matricula_id IS NULL) AND (concepto_id IS NULL) AND (venta_stock_id IS NULL) AND (cargo_origen_id IS NULL)) OR (((tipo)::text = 'MATRICULA'::text) AND (mensualidad_id IS NULL) AND (matricula_id IS NOT NULL) AND (concepto_id IS NULL) AND (venta_stock_id IS NULL) AND (cargo_origen_id IS NULL)) OR (((tipo)::text = 'CONCEPTO'::text) AND (mensualidad_id IS NULL) AND (matricula_id IS NULL) AND (concepto_id IS NOT NULL) AND (venta_stock_id IS NULL) AND (cargo_origen_id IS NULL)) OR (((tipo)::text = 'VENTA_STOCK'::text) AND (mensualidad_id IS NULL) AND (matricula_id IS NULL) AND (concepto_id IS NULL) AND (venta_stock_id IS NOT NULL) AND (cargo_origen_id IS NULL)) OR (((tipo)::text = 'RECARGO'::text) AND (mensualidad_id IS NULL) AND (matricula_id IS NULL) AND (concepto_id IS NULL) AND (venta_stock_id IS NULL) AND (cargo_origen_id IS NOT NULL)))),
    CONSTRAINT ck_cargos_tipo CHECK (((tipo)::text = ANY ((ARRAY['MENSUALIDAD'::character varying, 'MATRICULA'::character varying, 'CONCEPTO'::character varying, 'VENTA_STOCK'::character varying, 'RECARGO'::character varying])::text[])))
);

ALTER TABLE ONLY public.cargos FORCE ROW LEVEL SECURITY;


--
-- Name: cargos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.cargos ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.cargos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: conceptos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conceptos (
    id bigint NOT NULL,
    descripcion character varying(150) NOT NULL,
    precio numeric(19,2) NOT NULL,
    sub_concepto_id bigint NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_conceptos_precio CHECK ((precio >= (0)::numeric))
);

ALTER TABLE ONLY public.conceptos FORCE ROW LEVEL SECURITY;


--
-- Name: conceptos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.conceptos ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.conceptos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: disciplina_horarios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.disciplina_horarios (
    id bigint NOT NULL,
    disciplina_id bigint NOT NULL,
    dia_semana character varying(12) NOT NULL,
    horario_inicio time without time zone NOT NULL,
    duracion numeric(5,2) NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_horarios_dia CHECK (((dia_semana)::text = ANY ((ARRAY['LUNES'::character varying, 'MARTES'::character varying, 'MIERCOLES'::character varying, 'JUEVES'::character varying, 'VIERNES'::character varying, 'SABADO'::character varying, 'DOMINGO'::character varying])::text[]))),
    CONSTRAINT ck_horarios_duracion CHECK ((duracion > (0)::numeric))
);

ALTER TABLE ONLY public.disciplina_horarios FORCE ROW LEVEL SECURITY;


--
-- Name: disciplina_horarios_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.disciplina_horarios ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.disciplina_horarios_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: disciplina_tarifas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.disciplina_tarifas (
    id bigint NOT NULL,
    disciplina_id bigint NOT NULL,
    vigente_desde date NOT NULL,
    valor_cuota numeric(19,2) NOT NULL,
    matricula numeric(19,2) DEFAULT 0 NOT NULL,
    clase_suelta numeric(19,2) DEFAULT 0 NOT NULL,
    clase_prueba numeric(19,2) DEFAULT 0 NOT NULL,
    motivo character varying(500) NOT NULL,
    creada_por_usuario_id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    version bigint DEFAULT 0 NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_disciplina_tarifas_importes CHECK (((valor_cuota >= (0)::numeric) AND (matricula >= (0)::numeric) AND (clase_suelta >= (0)::numeric) AND (clase_prueba >= (0)::numeric)))
);

ALTER TABLE ONLY public.disciplina_tarifas FORCE ROW LEVEL SECURITY;


--
-- Name: disciplina_tarifas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.disciplina_tarifas ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.disciplina_tarifas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: disciplinas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.disciplinas (
    id bigint NOT NULL,
    nombre character varying(150) NOT NULL,
    salon_id bigint,
    profesor_id bigint NOT NULL,
    valor_cuota numeric(19,2) NOT NULL,
    matricula numeric(19,2) DEFAULT 0 NOT NULL,
    clase_suelta numeric(19,2) DEFAULT 0 NOT NULL,
    clase_prueba numeric(19,2) DEFAULT 0 NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    version bigint DEFAULT 0 NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_disciplinas_clase_prueba CHECK ((clase_prueba >= (0)::numeric)),
    CONSTRAINT ck_disciplinas_clase_suelta CHECK ((clase_suelta >= (0)::numeric)),
    CONSTRAINT ck_disciplinas_matricula CHECK ((matricula >= (0)::numeric)),
    CONSTRAINT ck_disciplinas_valor_cuota CHECK ((valor_cuota >= (0)::numeric))
);

ALTER TABLE ONLY public.disciplinas FORCE ROW LEVEL SECURITY;


--
-- Name: disciplinas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.disciplinas ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.disciplinas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: egresos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.egresos (
    id bigint NOT NULL,
    fecha date NOT NULL,
    monto numeric(19,2) NOT NULL,
    observaciones character varying(500),
    metodo_pago_id bigint NOT NULL,
    estado character varying(10) DEFAULT 'REGISTRADO'::character varying NOT NULL,
    usuario_id bigint NOT NULL,
    idempotency_key character varying(100) NOT NULL,
    request_hash character varying(64) NOT NULL,
    reversal_idempotency_key character varying(100),
    reversal_request_hash character varying(64),
    motivo_anulacion character varying(500),
    fecha_anulacion timestamp with time zone,
    version bigint DEFAULT 0 NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_egresos_anulacion CHECK (((((estado)::text = 'REGISTRADO'::text) AND (fecha_anulacion IS NULL) AND (motivo_anulacion IS NULL) AND (reversal_idempotency_key IS NULL) AND (reversal_request_hash IS NULL)) OR (((estado)::text = 'ANULADO'::text) AND (fecha_anulacion IS NOT NULL) AND (motivo_anulacion IS NOT NULL) AND (reversal_idempotency_key IS NOT NULL) AND (reversal_request_hash IS NOT NULL)))),
    CONSTRAINT ck_egresos_estado CHECK (((estado)::text = ANY ((ARRAY['REGISTRADO'::character varying, 'ANULADO'::character varying])::text[]))),
    CONSTRAINT ck_egresos_monto CHECK ((monto > (0)::numeric))
);

ALTER TABLE ONLY public.egresos FORCE ROW LEVEL SECURITY;


--
-- Name: egresos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.egresos ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.egresos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inscripcion_condiciones_economicas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inscripcion_condiciones_economicas (
    id bigint NOT NULL,
    inscripcion_id bigint NOT NULL,
    vigente_desde date NOT NULL,
    costo_particular numeric(19,2),
    bonificacion_id bigint,
    bonificacion_descripcion_snapshot character varying(150),
    bonificacion_porcentaje_snapshot numeric(7,4) DEFAULT 0 NOT NULL,
    bonificacion_valor_fijo_snapshot numeric(19,2) DEFAULT 0 NOT NULL,
    motivo character varying(500) NOT NULL,
    creada_por_usuario_id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    version bigint DEFAULT 0 NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_inscripcion_condicion_importes CHECK ((((costo_particular IS NULL) OR (costo_particular >= (0)::numeric)) AND ((bonificacion_porcentaje_snapshot >= (0)::numeric) AND (bonificacion_porcentaje_snapshot <= (100)::numeric)) AND (bonificacion_valor_fijo_snapshot >= (0)::numeric)))
);

ALTER TABLE ONLY public.inscripcion_condiciones_economicas FORCE ROW LEVEL SECURITY;


--
-- Name: inscripcion_condiciones_economicas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inscripcion_condiciones_economicas ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.inscripcion_condiciones_economicas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inscripciones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inscripciones (
    id bigint NOT NULL,
    alumno_id bigint NOT NULL,
    disciplina_id bigint NOT NULL,
    bonificacion_id bigint,
    fecha_inscripcion date NOT NULL,
    fecha_baja date,
    estado character varying(12) DEFAULT 'ACTIVA'::character varying NOT NULL,
    costo_particular numeric(19,2),
    version bigint DEFAULT 0 NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_inscripciones_baja CHECK (((((estado)::text = 'ACTIVA'::text) AND (fecha_baja IS NULL)) OR ((estado)::text = ANY ((ARRAY['INACTIVA'::character varying, 'FINALIZADA'::character varying])::text[])))),
    CONSTRAINT ck_inscripciones_costo CHECK (((costo_particular IS NULL) OR (costo_particular >= (0)::numeric))),
    CONSTRAINT ck_inscripciones_estado CHECK (((estado)::text = ANY ((ARRAY['ACTIVA'::character varying, 'INACTIVA'::character varying, 'FINALIZADA'::character varying])::text[])))
);

ALTER TABLE ONLY public.inscripciones FORCE ROW LEVEL SECURITY;


--
-- Name: inscripciones_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inscripciones ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.inscripciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: jere_platform_student_export_pages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jere_platform_student_export_pages (
    snapshot_checkpoint uuid NOT NULL,
    page_number integer NOT NULL,
    cursor_token uuid,
    next_cursor_token uuid,
    full_snapshot boolean NOT NULL,
    record_count integer NOT NULL,
    payload bytea NOT NULL,
    payload_sha256 character(64) NOT NULL,
    signature character varying(71) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    internal_tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_jere_student_export_page_number CHECK (((page_number >= 1) AND (page_number <= 1000))),
    CONSTRAINT ck_jere_student_export_page_records CHECK (((record_count >= 0) AND (record_count <= 1000))),
    CONSTRAINT ck_jere_student_export_payload_hash CHECK ((payload_sha256 ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT ck_jere_student_export_payload_size CHECK ((octet_length(payload) <= 1000000)),
    CONSTRAINT ck_jere_student_export_signature CHECK (((signature)::text ~ '^sha256=[0-9a-f]{64}$'::text))
);

ALTER TABLE ONLY public.jere_platform_student_export_pages FORCE ROW LEVEL SECURITY;


--
-- Name: jere_platform_student_export_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jere_platform_student_export_snapshots (
    checkpoint uuid NOT NULL,
    external_organization_id character varying(100) NOT NULL,
    external_tenant_id uuid NOT NULL,
    status character varying(20) NOT NULL,
    page_size integer NOT NULL,
    page_count integer NOT NULL,
    total_records integer NOT NULL,
    created_by bigint NOT NULL,
    created_at timestamp with time zone NOT NULL,
    version bigint DEFAULT 0 NOT NULL,
    internal_tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    mapping_id uuid NOT NULL,
    source_type character varying(50) NOT NULL,
    mapping_config_version bigint NOT NULL,
    signing_key_ref character varying(150) NOT NULL,
    CONSTRAINT ck_jere_student_export_organization CHECK ((length(TRIM(BOTH FROM external_organization_id)) > 0)),
    CONSTRAINT ck_jere_student_export_pages CHECK ((((page_size >= 1) AND (page_size <= 1000)) AND ((page_count >= 1) AND (page_count <= 1000)))),
    CONSTRAINT ck_jere_student_export_status CHECK (((status)::text = 'READY'::text)),
    CONSTRAINT ck_jere_student_export_total CHECK ((total_records >= 0))
);

ALTER TABLE ONLY public.jere_platform_student_export_snapshots FORCE ROW LEVEL SECURITY;


--
-- Name: jere_platform_tenant_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jere_platform_tenant_mappings (
    id uuid NOT NULL,
    internal_tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    external_organization_id character varying(100) NOT NULL,
    external_tenant_id uuid NOT NULL,
    source_type character varying(50) NOT NULL,
    config_version bigint NOT NULL,
    signing_key_ref character varying(150) NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deactivated_at timestamp with time zone,
    created_by_usuario_id bigint,
    CONSTRAINT ck_jere_mapping_organization CHECK ((length(btrim((external_organization_id)::text)) > 0)),
    CONSTRAINT ck_jere_mapping_signing_ref CHECK ((length(btrim((signing_key_ref)::text)) > 0)),
    CONSTRAINT ck_jere_mapping_source_type CHECK (((source_type)::text ~ '^[A-Z][A-Z0-9_]{2,49}$'::text)),
    CONSTRAINT ck_jere_mapping_state CHECK (((active AND (deactivated_at IS NULL)) OR ((NOT active) AND (deactivated_at IS NOT NULL)))),
    CONSTRAINT ck_jere_mapping_version CHECK ((config_version > 0))
);

ALTER TABLE ONLY public.jere_platform_tenant_mappings FORCE ROW LEVEL SECURITY;


--
-- Name: matriculas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.matriculas (
    id bigint NOT NULL,
    alumno_id bigint NOT NULL,
    anio integer NOT NULL,
    fecha_emision date NOT NULL,
    estado character varying(10) DEFAULT 'EMITIDA'::character varying NOT NULL,
    version bigint DEFAULT 0 NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_matriculas_anio CHECK (((anio >= 2000) AND (anio <= 9999))),
    CONSTRAINT ck_matriculas_estado CHECK (((estado)::text = ANY ((ARRAY['EMITIDA'::character varying, 'ANULADA'::character varying])::text[])))
);

ALTER TABLE ONLY public.matriculas FORCE ROW LEVEL SECURITY;


--
-- Name: matriculas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.matriculas ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.matriculas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: mensualidades; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mensualidades (
    id bigint NOT NULL,
    inscripcion_id bigint NOT NULL,
    bonificacion_id bigint,
    recargo_id bigint,
    anio integer NOT NULL,
    mes integer NOT NULL,
    fecha_generacion date NOT NULL,
    fecha_vencimiento date NOT NULL,
    descripcion character varying(255) NOT NULL,
    estado character varying(10) DEFAULT 'EMITIDA'::character varying NOT NULL,
    version bigint DEFAULT 0 NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_mensualidades_anio CHECK (((anio >= 2000) AND (anio <= 9999))),
    CONSTRAINT ck_mensualidades_estado CHECK (((estado)::text = ANY ((ARRAY['EMITIDA'::character varying, 'ANULADA'::character varying])::text[]))),
    CONSTRAINT ck_mensualidades_mes CHECK (((mes >= 1) AND (mes <= 12)))
);

ALTER TABLE ONLY public.mensualidades FORCE ROW LEVEL SECURITY;


--
-- Name: mensualidades_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.mensualidades ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.mensualidades_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: metodo_pagos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metodo_pagos (
    id bigint NOT NULL,
    descripcion character varying(100) NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    recargo numeric(7,4) DEFAULT 0 NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_metodos_pago_recargo CHECK (((recargo >= (0)::numeric) AND (recargo <= (100)::numeric)))
);

ALTER TABLE ONLY public.metodo_pagos FORCE ROW LEVEL SECURITY;


--
-- Name: metodo_pagos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.metodo_pagos ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.metodo_pagos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: movimientos_caja; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.movimientos_caja (
    id bigint NOT NULL,
    tipo character varying(15) NOT NULL,
    fecha date NOT NULL,
    importe numeric(19,2) NOT NULL,
    metodo_pago_id bigint NOT NULL,
    pago_id bigint,
    egreso_id bigint,
    movimiento_revertido_id bigint,
    usuario_id bigint NOT NULL,
    idempotency_key character varying(120) NOT NULL,
    motivo character varying(500),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_movimientos_caja_importe CHECK ((importe > (0)::numeric)),
    CONSTRAINT ck_movimientos_caja_origen CHECK (((((tipo)::text = 'INGRESO_PAGO'::text) AND (pago_id IS NOT NULL) AND (egreso_id IS NULL) AND (movimiento_revertido_id IS NULL)) OR (((tipo)::text = 'EGRESO'::text) AND (pago_id IS NULL) AND (egreso_id IS NOT NULL) AND (movimiento_revertido_id IS NULL)) OR (((tipo)::text = 'REVERSO'::text) AND (movimiento_revertido_id IS NOT NULL)) OR (((tipo)::text = ANY ((ARRAY['AJUSTE_INGRESO'::character varying, 'AJUSTE_EGRESO'::character varying])::text[])) AND (pago_id IS NULL) AND (egreso_id IS NULL) AND (movimiento_revertido_id IS NULL) AND (motivo IS NOT NULL)))),
    CONSTRAINT ck_movimientos_caja_tipo CHECK (((tipo)::text = ANY ((ARRAY['INGRESO_PAGO'::character varying, 'EGRESO'::character varying, 'REVERSO'::character varying, 'AJUSTE_INGRESO'::character varying, 'AJUSTE_EGRESO'::character varying])::text[])))
);

ALTER TABLE ONLY public.movimientos_caja FORCE ROW LEVEL SECURITY;


--
-- Name: movimientos_caja_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.movimientos_caja ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.movimientos_caja_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: movimientos_credito; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.movimientos_credito (
    id bigint NOT NULL,
    alumno_id bigint NOT NULL,
    tipo character varying(15) NOT NULL,
    importe numeric(19,2) NOT NULL,
    pago_id bigint,
    cargo_id bigint,
    movimiento_revertido_id bigint,
    usuario_id bigint NOT NULL,
    idempotency_key character varying(120) NOT NULL,
    request_hash character varying(64) NOT NULL,
    motivo character varying(500),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_movimientos_credito_importe CHECK ((importe > (0)::numeric)),
    CONSTRAINT ck_movimientos_credito_origen CHECK (((((tipo)::text = 'GENERACION'::text) AND (pago_id IS NOT NULL) AND (cargo_id IS NULL) AND (movimiento_revertido_id IS NULL)) OR (((tipo)::text = 'CONSUMO'::text) AND (pago_id IS NULL) AND (cargo_id IS NOT NULL) AND (movimiento_revertido_id IS NULL)) OR (((tipo)::text = 'REVERSO'::text) AND (pago_id IS NULL) AND (cargo_id IS NULL) AND (movimiento_revertido_id IS NOT NULL)) OR (((tipo)::text = ANY ((ARRAY['AJUSTE_CREDITO'::character varying, 'AJUSTE_DEBITO'::character varying])::text[])) AND (pago_id IS NULL) AND (cargo_id IS NULL) AND (movimiento_revertido_id IS NULL) AND (motivo IS NOT NULL)))),
    CONSTRAINT ck_movimientos_credito_tipo CHECK (((tipo)::text = ANY ((ARRAY['GENERACION'::character varying, 'CONSUMO'::character varying, 'REVERSO'::character varying, 'AJUSTE_CREDITO'::character varying, 'AJUSTE_DEBITO'::character varying])::text[])))
);

ALTER TABLE ONLY public.movimientos_credito FORCE ROW LEVEL SECURITY;


--
-- Name: movimientos_credito_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.movimientos_credito ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.movimientos_credito_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: movimientos_stock; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.movimientos_stock (
    id bigint NOT NULL,
    stock_id bigint NOT NULL,
    tipo character varying(16) NOT NULL,
    cantidad integer NOT NULL,
    venta_stock_id bigint,
    movimiento_revertido_id bigint,
    usuario_id bigint NOT NULL,
    idempotency_key character varying(120) NOT NULL,
    motivo character varying(500),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_movimientos_stock_cantidad CHECK ((cantidad > 0)),
    CONSTRAINT ck_movimientos_stock_origen CHECK (((((tipo)::text = 'VENTA'::text) AND (venta_stock_id IS NOT NULL) AND (movimiento_revertido_id IS NULL)) OR (((tipo)::text = 'REVERSO'::text) AND (movimiento_revertido_id IS NOT NULL)) OR (((tipo)::text = ANY ((ARRAY['INGRESO'::character varying, 'AJUSTE_POSITIVO'::character varying, 'AJUSTE_NEGATIVO'::character varying])::text[])) AND (venta_stock_id IS NULL) AND (movimiento_revertido_id IS NULL) AND (motivo IS NOT NULL)))),
    CONSTRAINT ck_movimientos_stock_tipo CHECK (((tipo)::text = ANY ((ARRAY['INGRESO'::character varying, 'VENTA'::character varying, 'REVERSO'::character varying, 'AJUSTE_POSITIVO'::character varying, 'AJUSTE_NEGATIVO'::character varying])::text[])))
);

ALTER TABLE ONLY public.movimientos_stock FORCE ROW LEVEL SECURITY;


--
-- Name: movimientos_stock_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.movimientos_stock ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.movimientos_stock_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: notificaciones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notificaciones (
    id bigint NOT NULL,
    usuario_id bigint,
    tipo character varying(50) NOT NULL,
    mensaje character varying(500) NOT NULL,
    fecha_creacion timestamp with time zone NOT NULL,
    fecha_negocio date NOT NULL,
    dedup_key character varying(100) NOT NULL,
    leida boolean DEFAULT false NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL
);

ALTER TABLE ONLY public.notificaciones FORCE ROW LEVEL SECURITY;


--
-- Name: notificaciones_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.notificaciones ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.notificaciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: observaciones_profesores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.observaciones_profesores (
    id bigint NOT NULL,
    profesor_id bigint NOT NULL,
    fecha date NOT NULL,
    observacion text NOT NULL,
    activa boolean DEFAULT true NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL
);

ALTER TABLE ONLY public.observaciones_profesores FORCE ROW LEVEL SECURITY;


--
-- Name: observaciones_profesores_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.observaciones_profesores ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.observaciones_profesores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: pagos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pagos (
    id bigint NOT NULL,
    alumno_id bigint NOT NULL,
    metodo_pago_id bigint NOT NULL,
    usuario_id bigint NOT NULL,
    fecha date NOT NULL,
    monto_recibido numeric(19,2) NOT NULL,
    estado character varying(10) DEFAULT 'REGISTRADO'::character varying NOT NULL,
    idempotency_key character varying(100) NOT NULL,
    request_hash character varying(64) NOT NULL,
    reversal_idempotency_key character varying(100),
    reversal_request_hash character varying(64),
    observaciones character varying(500),
    motivo_anulacion character varying(500),
    fecha_anulacion timestamp with time zone,
    version bigint DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_pagos_anulacion CHECK (((((estado)::text = 'REGISTRADO'::text) AND (fecha_anulacion IS NULL) AND (motivo_anulacion IS NULL) AND (reversal_idempotency_key IS NULL) AND (reversal_request_hash IS NULL)) OR (((estado)::text = 'ANULADO'::text) AND (fecha_anulacion IS NOT NULL) AND (motivo_anulacion IS NOT NULL) AND (reversal_idempotency_key IS NOT NULL) AND (reversal_request_hash IS NOT NULL)))),
    CONSTRAINT ck_pagos_estado CHECK (((estado)::text = ANY ((ARRAY['REGISTRADO'::character varying, 'ANULADO'::character varying])::text[]))),
    CONSTRAINT ck_pagos_monto CHECK ((monto_recibido > (0)::numeric))
);

ALTER TABLE ONLY public.pagos FORCE ROW LEVEL SECURITY;


--
-- Name: pagos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.pagos ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.pagos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: permisos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.permisos (
    id bigint NOT NULL,
    codigo character varying(100) NOT NULL,
    descripcion character varying(255) NOT NULL,
    modulo character varying(50) NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    sistema boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_permisos_codigo_formato CHECK (((codigo)::text ~ '^PERM_[A-Z0-9_]{3,95}$'::text)),
    CONSTRAINT ck_permisos_modulo_formato CHECK (((modulo)::text ~ '^[A-Z][A-Z0-9_]{1,49}$'::text))
);


--
-- Name: permisos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.permisos ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.permisos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: platform_admins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_admins (
    usuario_id bigint NOT NULL,
    active boolean DEFAULT true NOT NULL,
    granted_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    granted_by_usuario_id bigint,
    revoked_at timestamp with time zone,
    security_version bigint DEFAULT 0 NOT NULL,
    mfa_required boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_platform_admin_security_version CHECK ((security_version >= 0)),
    CONSTRAINT ck_platform_admin_state CHECK (((active AND (revoked_at IS NULL)) OR ((NOT active) AND (revoked_at IS NOT NULL))))
);


--
-- Name: platform_audit_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_audit_events (
    id bigint NOT NULL,
    actor_usuario_id bigint,
    actor_username_snapshot character varying(100),
    actor_type character varying(12) NOT NULL,
    session_scope character varying(10),
    mfa_method character varying(10),
    step_up boolean DEFAULT false NOT NULL,
    action character varying(100) NOT NULL,
    target_type character varying(100),
    target_id character varying(100),
    target_tenant_id uuid,
    occurred_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    correlation_id uuid NOT NULL,
    idempotency_key character varying(150),
    result character varying(10) NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT ck_platform_audit_actor_type CHECK (((actor_type)::text = ANY ((ARRAY['PLATFORM'::character varying, 'TENANT'::character varying, 'SYSTEM'::character varying, 'BOOTSTRAP'::character varying])::text[]))),
    CONSTRAINT ck_platform_audit_mfa CHECK (((mfa_method IS NULL) OR ((mfa_method)::text = 'TOTP'::text))),
    CONSTRAINT ck_platform_audit_result CHECK (((result)::text = ANY ((ARRAY['SUCCESS'::character varying, 'DENIED'::character varying, 'FAILED'::character varying])::text[]))),
    CONSTRAINT ck_platform_audit_scope CHECK (((((actor_type)::text = ANY ((ARRAY['SYSTEM'::character varying, 'BOOTSTRAP'::character varying])::text[])) AND (session_scope IS NULL)) OR (((actor_type)::text = 'PLATFORM'::text) AND ((session_scope)::text = 'PLATFORM'::text)) OR (((actor_type)::text = 'TENANT'::text) AND ((session_scope)::text = 'TENANT'::text))))
);


--
-- Name: platform_audit_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.platform_audit_events ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.platform_audit_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: platform_idempotency_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_idempotency_keys (
    id bigint NOT NULL,
    operation character varying(100) NOT NULL,
    idempotency_key character varying(150) NOT NULL,
    actor_usuario_id bigint NOT NULL,
    request_hash character(64) NOT NULL,
    status character varying(12) NOT NULL,
    resource_type character varying(100),
    resource_id character varying(100),
    response_status smallint,
    result_reference jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    completed_at timestamp with time zone,
    CONSTRAINT ck_platform_idempotency_response CHECK (((response_status IS NULL) OR ((response_status >= 100) AND (response_status <= 599)))),
    CONSTRAINT ck_platform_idempotency_state CHECK (((((status)::text = 'PENDING'::text) AND (completed_at IS NULL) AND (response_status IS NULL)) OR (((status)::text = ANY ((ARRAY['SUCCEEDED'::character varying, 'FAILED'::character varying])::text[])) AND (completed_at IS NOT NULL) AND (response_status IS NOT NULL)))),
    CONSTRAINT ck_platform_idempotency_status CHECK (((status)::text = ANY ((ARRAY['PENDING'::character varying, 'SUCCEEDED'::character varying, 'FAILED'::character varying])::text[]))),
    CONSTRAINT ck_platform_idempotency_times CHECK (((updated_at >= created_at) AND ((completed_at IS NULL) OR (completed_at >= created_at))))
);


--
-- Name: platform_idempotency_keys_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.platform_idempotency_keys ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.platform_idempotency_keys_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: platform_mfa_credentials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_mfa_credentials (
    id uuid NOT NULL,
    usuario_id bigint NOT NULL,
    method character varying(10) DEFAULT 'TOTP'::character varying NOT NULL,
    secret_ciphertext bytea NOT NULL,
    key_version smallint NOT NULL,
    last_counter bigint,
    failed_attempts smallint DEFAULT 0 NOT NULL,
    failure_window_started_at timestamp with time zone,
    blocked_until timestamp with time zone,
    verified_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    last_used_at timestamp with time zone,
    revoked_at timestamp with time zone,
    CONSTRAINT ck_platform_mfa_attempts CHECK (((failed_attempts >= 0) AND (failed_attempts <= 5))),
    CONSTRAINT ck_platform_mfa_block CHECK (((blocked_until IS NULL) OR ((failure_window_started_at IS NOT NULL) AND (blocked_until > failure_window_started_at)))),
    CONSTRAINT ck_platform_mfa_counter CHECK (((last_counter IS NULL) OR (last_counter >= 0))),
    CONSTRAINT ck_platform_mfa_failure_window CHECK ((((failed_attempts = 0) AND (failure_window_started_at IS NULL)) OR ((failed_attempts > 0) AND (failure_window_started_at IS NOT NULL)))),
    CONSTRAINT ck_platform_mfa_key_version CHECK ((key_version > 0)),
    CONSTRAINT ck_platform_mfa_method CHECK (((method)::text = 'TOTP'::text)),
    CONSTRAINT ck_platform_mfa_times CHECK ((((verified_at IS NULL) OR (verified_at >= created_at)) AND ((last_used_at IS NULL) OR (last_used_at >= created_at)) AND ((revoked_at IS NULL) OR (revoked_at >= created_at))))
);


--
-- Name: platform_recovery_codes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_recovery_codes (
    id uuid NOT NULL,
    credential_id uuid NOT NULL,
    code_hash character(64) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    used_at timestamp with time zone,
    CONSTRAINT ck_platform_recovery_times CHECK (((used_at IS NULL) OR (used_at >= created_at)))
);


--
-- Name: platform_refresh_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_refresh_sessions (
    id uuid NOT NULL,
    family_id uuid NOT NULL,
    usuario_id bigint NOT NULL,
    session_scope character varying(10) DEFAULT 'PLATFORM'::character varying NOT NULL,
    token_hash character(64) NOT NULL,
    auth_version bigint NOT NULL,
    platform_security_version bigint NOT NULL,
    mfa_verified_at timestamp with time zone NOT NULL,
    issued_at timestamp with time zone NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    family_expires_at timestamp with time zone NOT NULL,
    used_at timestamp with time zone,
    revoked_at timestamp with time zone,
    revoke_reason character varying(100),
    replaced_by_id uuid,
    user_agent_hash character(64),
    ip_hash character(64),
    CONSTRAINT ck_platform_refresh_scope CHECK (((session_scope)::text = 'PLATFORM'::text)),
    CONSTRAINT ck_platform_refresh_times CHECK (((expires_at > issued_at) AND (family_expires_at >= expires_at) AND (family_expires_at > issued_at) AND (mfa_verified_at <= issued_at) AND ((used_at IS NULL) OR (used_at >= issued_at)) AND ((revoked_at IS NULL) OR (revoked_at >= issued_at)))),
    CONSTRAINT ck_platform_refresh_versions CHECK (((auth_version >= 0) AND (platform_security_version >= 0)))
);


--
-- Name: platform_step_up_challenges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_step_up_challenges (
    id uuid NOT NULL,
    usuario_id bigint NOT NULL,
    session_id uuid NOT NULL,
    action character varying(100) NOT NULL,
    target_type character varying(100),
    target_id character varying(100),
    idempotency_key character varying(150) NOT NULL,
    correlation_id uuid NOT NULL,
    mfa_method character varying(10) NOT NULL,
    proof_hash character(64),
    issued_at timestamp with time zone NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    verified_at timestamp with time zone,
    consumed_at timestamp with time zone,
    CONSTRAINT ck_platform_step_up_consumption CHECK (((consumed_at IS NULL) OR ((verified_at IS NOT NULL) AND (consumed_at >= verified_at) AND (consumed_at <= expires_at)))),
    CONSTRAINT ck_platform_step_up_method CHECK (((mfa_method)::text = 'TOTP'::text)),
    CONSTRAINT ck_platform_step_up_verification CHECK ((((proof_hash IS NULL) AND (verified_at IS NULL)) OR ((proof_hash IS NOT NULL) AND (verified_at IS NOT NULL) AND (verified_at >= issued_at) AND (verified_at <= expires_at)))),
    CONSTRAINT ck_platform_step_up_window CHECK ((expires_at > issued_at))
);


--
-- Name: profesores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profesores (
    id bigint NOT NULL,
    nombre character varying(100) NOT NULL,
    apellido character varying(100) NOT NULL,
    fecha_nacimiento date,
    telefono character varying(30),
    usuario_id bigint,
    activo boolean DEFAULT true NOT NULL,
    version bigint DEFAULT 0 NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL
);

ALTER TABLE ONLY public.profesores FORCE ROW LEVEL SECURITY;


--
-- Name: profesores_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.profesores ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.profesores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: recargos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recargos (
    id bigint NOT NULL,
    descripcion character varying(150) NOT NULL,
    porcentaje numeric(7,4) DEFAULT 0 NOT NULL,
    valor_fijo numeric(19,2) DEFAULT 0 NOT NULL,
    dia_del_mes_aplicacion integer,
    activo boolean DEFAULT true NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_recargos_dia CHECK (((dia_del_mes_aplicacion IS NULL) OR ((dia_del_mes_aplicacion >= 1) AND (dia_del_mes_aplicacion <= 31)))),
    CONSTRAINT ck_recargos_porcentaje CHECK (((porcentaje >= (0)::numeric) AND (porcentaje <= (100)::numeric))),
    CONSTRAINT ck_recargos_valor CHECK ((valor_fijo >= (0)::numeric))
);

ALTER TABLE ONLY public.recargos FORCE ROW LEVEL SECURITY;


--
-- Name: recargos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.recargos ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.recargos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: recibos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recibos (
    id bigint NOT NULL,
    pago_id bigint NOT NULL,
    storage_key character varying(500),
    generado_at timestamp with time zone,
    enviado_at timestamp with time zone,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL
);

ALTER TABLE ONLY public.recibos FORCE ROW LEVEL SECURITY;


--
-- Name: recibos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.recibos ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.recibos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: recibos_pendientes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recibos_pendientes (
    id bigint NOT NULL,
    pago_id bigint NOT NULL,
    tipo character varying(20) NOT NULL,
    estado character varying(12) DEFAULT 'PENDIENTE'::character varying NOT NULL,
    intentos integer DEFAULT 0 NOT NULL,
    next_attempt_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    idempotency_key character varying(120) NOT NULL,
    claim_token uuid,
    claimed_at timestamp with time zone,
    lease_until timestamp with time zone,
    ultimo_error character varying(500),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    processed_at timestamp with time zone,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_recibos_pendientes_claim CHECK (((((estado)::text = 'PROCESANDO'::text) AND (claim_token IS NOT NULL) AND (claimed_at IS NOT NULL) AND (lease_until IS NOT NULL)) OR (((estado)::text <> 'PROCESANDO'::text) AND (claim_token IS NULL) AND (claimed_at IS NULL) AND (lease_until IS NULL)))),
    CONSTRAINT ck_recibos_pendientes_estado CHECK (((estado)::text = ANY ((ARRAY['PENDIENTE'::character varying, 'PROCESANDO'::character varying, 'COMPLETADO'::character varying, 'ERROR'::character varying])::text[]))),
    CONSTRAINT ck_recibos_pendientes_intentos CHECK ((intentos >= 0)),
    CONSTRAINT ck_recibos_pendientes_tipo CHECK (((tipo)::text = 'GENERAR_Y_ENVIAR'::text))
);

ALTER TABLE ONLY public.recibos_pendientes FORCE ROW LEVEL SECURITY;


--
-- Name: recibos_pendientes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.recibos_pendientes ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.recibos_pendientes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: refresh_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_sessions (
    id uuid NOT NULL,
    family_id uuid NOT NULL,
    usuario_id bigint NOT NULL,
    token_hash character(64) NOT NULL,
    auth_version bigint NOT NULL,
    issued_at timestamp with time zone NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    used_at timestamp with time zone,
    revoked_at timestamp with time zone,
    revoke_reason character varying(100),
    replaced_by_id uuid,
    user_agent_hash character(64),
    ip_hash character(64),
    tenant_id uuid NOT NULL,
    membership_id uuid NOT NULL,
    tenant_security_version bigint NOT NULL,
    membership_security_version bigint NOT NULL,
    CONSTRAINT ck_refresh_membership_security_version CHECK ((membership_security_version >= 0)),
    CONSTRAINT ck_refresh_tenant_security_version CHECK ((tenant_security_version >= 0)),
    CONSTRAINT ck_refresh_tiempos CHECK ((expires_at > issued_at))
);

ALTER TABLE ONLY public.refresh_sessions FORCE ROW LEVEL SECURITY;


--
-- Name: rol_permisos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rol_permisos (
    rol_id bigint NOT NULL,
    permiso_id bigint NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL
);

ALTER TABLE ONLY public.rol_permisos FORCE ROW LEVEL SECURITY;


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    id bigint NOT NULL,
    descripcion character varying(50) NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    codigo character varying(50) NOT NULL,
    nombre character varying(100) NOT NULL,
    descripcion_funcional character varying(255),
    sistema boolean DEFAULT false NOT NULL,
    editable boolean DEFAULT true NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_roles_codigo_formato CHECK (((codigo)::text ~ '^[A-Z][A-Z0-9_]{2,49}$'::text)),
    CONSTRAINT ck_roles_codigo_sin_prefijo_authority CHECK (((codigo)::text !~ '^ROLE_'::text))
);

ALTER TABLE ONLY public.roles FORCE ROW LEVEL SECURITY;


--
-- Name: roles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.roles ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.roles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: salones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salones (
    id bigint NOT NULL,
    nombre character varying(100) NOT NULL,
    descripcion character varying(255),
    activo boolean DEFAULT true NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL
);

ALTER TABLE ONLY public.salones FORCE ROW LEVEL SECURITY;


--
-- Name: salones_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.salones ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.salones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: stocks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stocks (
    id bigint NOT NULL,
    nombre character varying(150) NOT NULL,
    precio numeric(19,2) NOT NULL,
    cantidad_actual integer DEFAULT 0 NOT NULL,
    requiere_control_de_stock boolean DEFAULT true NOT NULL,
    codigo_barras character varying(100),
    activo boolean DEFAULT true NOT NULL,
    version bigint DEFAULT 0 NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_stocks_cantidad CHECK ((cantidad_actual >= 0)),
    CONSTRAINT ck_stocks_precio CHECK ((precio >= (0)::numeric))
);

ALTER TABLE ONLY public.stocks FORCE ROW LEVEL SECURITY;


--
-- Name: stocks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.stocks ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.stocks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: sub_conceptos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sub_conceptos (
    id bigint NOT NULL,
    descripcion character varying(150) NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL
);

ALTER TABLE ONLY public.sub_conceptos FORCE ROW LEVEL SECURITY;


--
-- Name: sub_conceptos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.sub_conceptos ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.sub_conceptos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tenant_membership_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenant_membership_roles (
    membership_id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    role_id bigint NOT NULL,
    assigned_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    assigned_by_usuario_id bigint
);

ALTER TABLE ONLY public.tenant_membership_roles FORCE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_membership_roles ENABLE ROW LEVEL SECURITY;


--
-- Name: tenant_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenant_memberships (
    id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    usuario_id bigint NOT NULL,
    status character varying(12) NOT NULL,
    security_version bigint DEFAULT 0 NOT NULL,
    valid_from timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    valid_until timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_tenant_memberships_security_version CHECK ((security_version >= 0)),
    CONSTRAINT ck_tenant_memberships_status CHECK (((status)::text = ANY ((ARRAY['ACTIVE'::character varying, 'SUSPENDED'::character varying, 'REVOKED'::character varying])::text[]))),
    CONSTRAINT ck_tenant_memberships_validity CHECK (((valid_until IS NULL) OR (valid_until > valid_from)))
);

ALTER TABLE ONLY public.tenant_memberships FORCE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_memberships ENABLE ROW LEVEL SECURITY;


--
-- Name: tenants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenants (
    id uuid NOT NULL,
    code character varying(50) NOT NULL,
    name character varying(150) NOT NULL,
    status character varying(12) NOT NULL,
    security_version bigint DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_tenants_code CHECK (((code)::text ~ '^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$'::text)),
    CONSTRAINT ck_tenants_name CHECK ((length(btrim((name)::text)) > 0)),
    CONSTRAINT ck_tenants_security_version CHECK ((security_version >= 0)),
    CONSTRAINT ck_tenants_status CHECK (((status)::text = ANY ((ARRAY['ACTIVE'::character varying, 'SUSPENDED'::character varying, 'ARCHIVED'::character varying])::text[])))
);


--
-- Name: usuario_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuario_roles (
    usuario_id bigint NOT NULL,
    rol_id bigint NOT NULL,
    asignado_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    asignado_por_usuario_id bigint
);


--
-- Name: usuarios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuarios (
    id bigint NOT NULL,
    nombre_usuario character varying(100) NOT NULL,
    contrasena character varying(100) NOT NULL,
    rol_id bigint,
    activo boolean DEFAULT true NOT NULL,
    auth_version bigint DEFAULT 0 NOT NULL,
    password_changed_at timestamp with time zone,
    version bigint DEFAULT 0 NOT NULL
);


--
-- Name: usuarios_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.usuarios ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.usuarios_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: v_cuotas_seguimiento; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_cuotas_seguimiento WITH (security_invoker='true') AS
 WITH pagos AS (
         SELECT aplicaciones_pago.tenant_id,
            aplicaciones_pago.cargo_id,
            sum(aplicaciones_pago.importe_aplicado) AS aplicado,
            max(aplicaciones_pago.fecha) AS ultima_fecha
           FROM public.aplicaciones_pago
          WHERE ((aplicaciones_pago.estado)::text = 'APLICADA'::text)
          GROUP BY aplicaciones_pago.tenant_id, aplicaciones_pago.cargo_id
        ), credito AS (
         SELECT neto.tenant_id,
            neto.cargo_id,
            sum(neto.importe) AS aplicado,
            max(neto.fecha) AS ultima_fecha
           FROM ( SELECT movimientos_credito.tenant_id,
                    movimientos_credito.cargo_id,
                    movimientos_credito.importe,
                    (movimientos_credito.created_at)::date AS fecha
                   FROM public.movimientos_credito
                  WHERE ((movimientos_credito.tipo)::text = 'CONSUMO'::text)
                UNION ALL
                 SELECT reverso.tenant_id,
                    original.cargo_id,
                    (- reverso.importe),
                    (reverso.created_at)::date AS created_at
                   FROM (public.movimientos_credito reverso
                     JOIN public.movimientos_credito original ON (((original.tenant_id = reverso.tenant_id) AND (original.id = reverso.movimiento_revertido_id))))
                  WHERE (((reverso.tipo)::text = 'REVERSO'::text) AND ((original.tipo)::text = 'CONSUMO'::text))) neto
          GROUP BY neto.tenant_id, neto.cargo_id
        ), cargos_saldo AS (
         SELECT c_1.id,
            c_1.alumno_id,
            c_1.tipo,
            c_1.descripcion,
            c_1.importe_original,
            c_1.fecha_emision,
            c_1.fecha_vencimiento,
            c_1.estado,
            c_1.mensualidad_id,
            c_1.matricula_id,
            c_1.concepto_id,
            c_1.venta_stock_id,
            c_1.cargo_origen_id,
            c_1.idempotency_key,
            c_1.version,
            c_1.created_at,
            c_1.tenant_id,
            COALESCE(p.aplicado, (0)::numeric) AS aplicado_pagos,
            COALESCE(cr.aplicado, (0)::numeric) AS aplicado_credito,
            ((c_1.importe_original - COALESCE(p.aplicado, (0)::numeric)) - COALESCE(cr.aplicado, (0)::numeric)) AS saldo,
            GREATEST(p.ultima_fecha, cr.ultima_fecha) AS ultima_fecha_aplicacion
           FROM ((public.cargos c_1
             LEFT JOIN pagos p ON (((p.tenant_id = c_1.tenant_id) AND (p.cargo_id = c_1.id))))
             LEFT JOIN credito cr ON (((cr.tenant_id = c_1.tenant_id) AND (cr.cargo_id = c_1.id))))
        ), recargos AS (
         SELECT cargos_saldo.tenant_id,
            cargos_saldo.cargo_origen_id,
            sum(cargos_saldo.importe_original) AS importe_original,
            sum(cargos_saldo.saldo) AS saldo
           FROM cargos_saldo
          WHERE ((cargos_saldo.tipo)::text = 'RECARGO'::text)
          GROUP BY cargos_saldo.tenant_id, cargos_saldo.cargo_origen_id
        )
 SELECT c.tenant_id,
    c.id AS cargo_id,
    i.alumno_id,
    concat_ws(' '::text, a.nombre, a.apellido) AS alumno,
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
    COALESCE(r.importe_original, (0)::numeric) AS recargos_vinculados,
    COALESCE(r.saldo, (0)::numeric) AS saldo_recargos,
    (c.saldo + COALESCE(r.saldo, (0)::numeric)) AS saldo_total_periodo,
    c.estado AS estado_persistido,
        CASE
            WHEN ((c.estado)::text = 'ANULADO'::text) THEN 'ANULADO'::text
            WHEN (c.saldo = (0)::numeric) THEN 'PAGADO'::text
            WHEN (c.saldo < c.importe_original) THEN 'PARCIAL'::text
            ELSE 'PENDIENTE'::text
        END AS estado_esperado,
    c.ultima_fecha_aplicacion,
        CASE
            WHEN (((c.saldo + COALESCE(r.saldo, (0)::numeric)) > (0)::numeric) AND (m.fecha_vencimiento < CURRENT_DATE)) THEN (CURRENT_DATE - m.fecha_vencimiento)
            ELSE 0
        END AS dias_mora,
    l.origen_precio,
    l.formula_version
   FROM (((((((cargos_saldo c
     JOIN public.mensualidades m ON (((m.tenant_id = c.tenant_id) AND (m.id = c.mensualidad_id))))
     JOIN public.inscripciones i ON (((i.tenant_id = m.tenant_id) AND (i.id = m.inscripcion_id))))
     JOIN public.alumnos a ON (((a.tenant_id = i.tenant_id) AND (a.id = i.alumno_id))))
     JOIN public.disciplinas d ON (((d.tenant_id = i.tenant_id) AND (d.id = i.disciplina_id))))
     JOIN public.cargo_liquidaciones l ON (((l.tenant_id = c.tenant_id) AND (l.cargo_id = c.id))))
     LEFT JOIN public.disciplina_tarifas td ON (((td.tenant_id = l.tenant_id) AND (td.id = l.tarifa_disciplina_id))))
     LEFT JOIN recargos r ON (((r.tenant_id = c.tenant_id) AND (r.cargo_origen_id = c.id))))
  WHERE ((c.tipo)::text = 'MENSUALIDAD'::text);


--
-- Name: v_multitenancy_migration_health; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_multitenancy_migration_health WITH (security_invoker='true') AS
 SELECT public.gestudio_multitenancy_health() AS status;


--
-- Name: ventas_stock; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ventas_stock (
    id bigint NOT NULL,
    alumno_id bigint NOT NULL,
    stock_id bigint NOT NULL,
    cantidad integer NOT NULL,
    precio_unitario numeric(19,2) NOT NULL,
    fecha date NOT NULL,
    estado character varying(10) DEFAULT 'REGISTRADA'::character varying NOT NULL,
    idempotency_key character varying(100) NOT NULL,
    request_hash character varying(64) NOT NULL,
    reversal_idempotency_key character varying(100),
    reversal_request_hash character varying(64),
    version bigint DEFAULT 0 NOT NULL,
    tenant_id uuid DEFAULT public.gestudio_current_tenant_id() NOT NULL,
    CONSTRAINT ck_ventas_stock_cantidad CHECK ((cantidad > 0)),
    CONSTRAINT ck_ventas_stock_estado CHECK (((estado)::text = ANY ((ARRAY['REGISTRADA'::character varying, 'ANULADA'::character varying])::text[]))),
    CONSTRAINT ck_ventas_stock_precio CHECK ((precio_unitario >= (0)::numeric)),
    CONSTRAINT ck_ventas_stock_reversion CHECK (((((estado)::text = 'REGISTRADA'::text) AND (reversal_idempotency_key IS NULL) AND (reversal_request_hash IS NULL)) OR (((estado)::text = 'ANULADA'::text) AND (reversal_idempotency_key IS NOT NULL) AND (reversal_request_hash IS NOT NULL))))
);

ALTER TABLE ONLY public.ventas_stock FORCE ROW LEVEL SECURITY;


--
-- Name: ventas_stock_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.ventas_stock ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.ventas_stock_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: alumnos alumnos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alumnos
    ADD CONSTRAINT alumnos_pkey PRIMARY KEY (id);


--
-- Name: aplicaciones_pago aplicaciones_pago_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aplicaciones_pago
    ADD CONSTRAINT aplicaciones_pago_pkey PRIMARY KEY (id);


--
-- Name: asistencias_alumno_mensual asistencias_alumno_mensual_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_alumno_mensual
    ADD CONSTRAINT asistencias_alumno_mensual_pkey PRIMARY KEY (id);


--
-- Name: asistencias_diarias asistencias_diarias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_diarias
    ADD CONSTRAINT asistencias_diarias_pkey PRIMARY KEY (id);


--
-- Name: asistencias_mensuales asistencias_mensuales_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_mensuales
    ADD CONSTRAINT asistencias_mensuales_pkey PRIMARY KEY (id);


--
-- Name: auditoria_eventos auditoria_eventos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria_eventos
    ADD CONSTRAINT auditoria_eventos_pkey PRIMARY KEY (id);


--
-- Name: bonificaciones bonificaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bonificaciones
    ADD CONSTRAINT bonificaciones_pkey PRIMARY KEY (id);


--
-- Name: bootstrap_ejecuciones bootstrap_ejecuciones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bootstrap_ejecuciones
    ADD CONSTRAINT bootstrap_ejecuciones_pkey PRIMARY KEY (tipo);


--
-- Name: cargo_eventos cargo_eventos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargo_eventos
    ADD CONSTRAINT cargo_eventos_pkey PRIMARY KEY (id);


--
-- Name: cargo_liquidaciones cargo_liquidaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargo_liquidaciones
    ADD CONSTRAINT cargo_liquidaciones_pkey PRIMARY KEY (cargo_id);


--
-- Name: cargos cargos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargos
    ADD CONSTRAINT cargos_pkey PRIMARY KEY (id);


--
-- Name: conceptos conceptos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conceptos
    ADD CONSTRAINT conceptos_pkey PRIMARY KEY (id);


--
-- Name: disciplina_horarios disciplina_horarios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disciplina_horarios
    ADD CONSTRAINT disciplina_horarios_pkey PRIMARY KEY (id);


--
-- Name: disciplina_tarifas disciplina_tarifas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disciplina_tarifas
    ADD CONSTRAINT disciplina_tarifas_pkey PRIMARY KEY (id);


--
-- Name: disciplinas disciplinas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disciplinas
    ADD CONSTRAINT disciplinas_pkey PRIMARY KEY (id);


--
-- Name: egresos egresos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.egresos
    ADD CONSTRAINT egresos_pkey PRIMARY KEY (id);


--
-- Name: inscripcion_condiciones_economicas inscripcion_condiciones_economicas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscripcion_condiciones_economicas
    ADD CONSTRAINT inscripcion_condiciones_economicas_pkey PRIMARY KEY (id);


--
-- Name: inscripciones inscripciones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscripciones
    ADD CONSTRAINT inscripciones_pkey PRIMARY KEY (id);


--
-- Name: jere_platform_student_export_pages jere_platform_student_export_pages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jere_platform_student_export_pages
    ADD CONSTRAINT jere_platform_student_export_pages_pkey PRIMARY KEY (snapshot_checkpoint, page_number);


--
-- Name: jere_platform_student_export_snapshots jere_platform_student_export_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jere_platform_student_export_snapshots
    ADD CONSTRAINT jere_platform_student_export_snapshots_pkey PRIMARY KEY (checkpoint);


--
-- Name: jere_platform_tenant_mappings jere_platform_tenant_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jere_platform_tenant_mappings
    ADD CONSTRAINT jere_platform_tenant_mappings_pkey PRIMARY KEY (id);


--
-- Name: matriculas matriculas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.matriculas
    ADD CONSTRAINT matriculas_pkey PRIMARY KEY (id);


--
-- Name: mensualidades mensualidades_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mensualidades
    ADD CONSTRAINT mensualidades_pkey PRIMARY KEY (id);


--
-- Name: metodo_pagos metodo_pagos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metodo_pagos
    ADD CONSTRAINT metodo_pagos_pkey PRIMARY KEY (id);


--
-- Name: movimientos_caja movimientos_caja_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_caja
    ADD CONSTRAINT movimientos_caja_pkey PRIMARY KEY (id);


--
-- Name: movimientos_credito movimientos_credito_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_credito
    ADD CONSTRAINT movimientos_credito_pkey PRIMARY KEY (id);


--
-- Name: movimientos_stock movimientos_stock_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_stock
    ADD CONSTRAINT movimientos_stock_pkey PRIMARY KEY (id);


--
-- Name: notificaciones notificaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notificaciones
    ADD CONSTRAINT notificaciones_pkey PRIMARY KEY (id);


--
-- Name: observaciones_profesores observaciones_profesores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_profesores
    ADD CONSTRAINT observaciones_profesores_pkey PRIMARY KEY (id);


--
-- Name: pagos pagos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT pagos_pkey PRIMARY KEY (id);


--
-- Name: permisos permisos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permisos
    ADD CONSTRAINT permisos_pkey PRIMARY KEY (id);


--
-- Name: rol_permisos pk_rol_permisos; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rol_permisos
    ADD CONSTRAINT pk_rol_permisos PRIMARY KEY (rol_id, permiso_id);


--
-- Name: tenant_membership_roles pk_tenant_membership_roles; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_membership_roles
    ADD CONSTRAINT pk_tenant_membership_roles PRIMARY KEY (membership_id, role_id, tenant_id);


--
-- Name: usuario_roles pk_usuario_roles; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_roles
    ADD CONSTRAINT pk_usuario_roles PRIMARY KEY (usuario_id, rol_id);


--
-- Name: platform_admins platform_admins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_admins
    ADD CONSTRAINT platform_admins_pkey PRIMARY KEY (usuario_id);


--
-- Name: platform_audit_events platform_audit_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_audit_events
    ADD CONSTRAINT platform_audit_events_pkey PRIMARY KEY (id);


--
-- Name: platform_idempotency_keys platform_idempotency_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_idempotency_keys
    ADD CONSTRAINT platform_idempotency_keys_pkey PRIMARY KEY (id);


--
-- Name: platform_mfa_credentials platform_mfa_credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_mfa_credentials
    ADD CONSTRAINT platform_mfa_credentials_pkey PRIMARY KEY (id);


--
-- Name: platform_recovery_codes platform_recovery_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_recovery_codes
    ADD CONSTRAINT platform_recovery_codes_pkey PRIMARY KEY (id);


--
-- Name: platform_refresh_sessions platform_refresh_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_refresh_sessions
    ADD CONSTRAINT platform_refresh_sessions_pkey PRIMARY KEY (id);


--
-- Name: platform_step_up_challenges platform_step_up_challenges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_step_up_challenges
    ADD CONSTRAINT platform_step_up_challenges_pkey PRIMARY KEY (id);


--
-- Name: profesores profesores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profesores
    ADD CONSTRAINT profesores_pkey PRIMARY KEY (id);


--
-- Name: recargos recargos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recargos
    ADD CONSTRAINT recargos_pkey PRIMARY KEY (id);


--
-- Name: recibos_pendientes recibos_pendientes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recibos_pendientes
    ADD CONSTRAINT recibos_pendientes_pkey PRIMARY KEY (id);


--
-- Name: recibos recibos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recibos
    ADD CONSTRAINT recibos_pkey PRIMARY KEY (id);


--
-- Name: refresh_sessions refresh_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_sessions
    ADD CONSTRAINT refresh_sessions_pkey PRIMARY KEY (id);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: salones salones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salones
    ADD CONSTRAINT salones_pkey PRIMARY KEY (id);


--
-- Name: stocks stocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stocks
    ADD CONSTRAINT stocks_pkey PRIMARY KEY (id);


--
-- Name: sub_conceptos sub_conceptos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sub_conceptos
    ADD CONSTRAINT sub_conceptos_pkey PRIMARY KEY (id);


--
-- Name: tenant_memberships tenant_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_memberships
    ADD CONSTRAINT tenant_memberships_pkey PRIMARY KEY (id);


--
-- Name: tenants tenants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenants
    ADD CONSTRAINT tenants_pkey PRIMARY KEY (id);


--
-- Name: alumnos uq_alumnos_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alumnos
    ADD CONSTRAINT uq_alumnos_tenant_id UNIQUE (tenant_id, id);


--
-- Name: aplicaciones_pago uq_aplicaciones_pago_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aplicaciones_pago
    ADD CONSTRAINT uq_aplicaciones_pago_tenant_id UNIQUE (tenant_id, id);


--
-- Name: aplicaciones_pago uq_aplicaciones_tenant_pago_cargo; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aplicaciones_pago
    ADD CONSTRAINT uq_aplicaciones_tenant_pago_cargo UNIQUE (tenant_id, pago_id, cargo_id);


--
-- Name: asistencias_alumno_mensual uq_asistencia_alumno_tenant_periodo; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_alumno_mensual
    ADD CONSTRAINT uq_asistencia_alumno_tenant_periodo UNIQUE (tenant_id, asistencia_mensual_id, inscripcion_id);


--
-- Name: asistencias_alumno_mensual uq_asistencias_alumno_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_alumno_mensual
    ADD CONSTRAINT uq_asistencias_alumno_tenant_id UNIQUE (tenant_id, id);


--
-- Name: asistencias_diarias uq_asistencias_diarias_tenant_fecha; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_diarias
    ADD CONSTRAINT uq_asistencias_diarias_tenant_fecha UNIQUE (tenant_id, asistencia_alumno_mensual_id, fecha);


--
-- Name: asistencias_diarias uq_asistencias_diarias_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_diarias
    ADD CONSTRAINT uq_asistencias_diarias_tenant_id UNIQUE (tenant_id, id);


--
-- Name: asistencias_mensuales uq_asistencias_mensuales_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_mensuales
    ADD CONSTRAINT uq_asistencias_mensuales_tenant_id UNIQUE (tenant_id, id);


--
-- Name: asistencias_mensuales uq_asistencias_mensuales_tenant_periodo; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_mensuales
    ADD CONSTRAINT uq_asistencias_mensuales_tenant_periodo UNIQUE (tenant_id, disciplina_id, anio, mes);


--
-- Name: bonificaciones uq_bonificaciones_tenant_descripcion; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bonificaciones
    ADD CONSTRAINT uq_bonificaciones_tenant_descripcion UNIQUE (tenant_id, descripcion);


--
-- Name: bonificaciones uq_bonificaciones_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bonificaciones
    ADD CONSTRAINT uq_bonificaciones_tenant_id UNIQUE (tenant_id, id);


--
-- Name: cargo_eventos uq_cargo_eventos_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargo_eventos
    ADD CONSTRAINT uq_cargo_eventos_tenant_id UNIQUE (tenant_id, id);


--
-- Name: cargo_eventos uq_cargo_eventos_tenant_idempotency; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargo_eventos
    ADD CONSTRAINT uq_cargo_eventos_tenant_idempotency UNIQUE (tenant_id, idempotency_key);


--
-- Name: cargo_liquidaciones uq_cargo_liquidaciones_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargo_liquidaciones
    ADD CONSTRAINT uq_cargo_liquidaciones_tenant_id UNIQUE (tenant_id, cargo_id);


--
-- Name: cargos uq_cargos_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargos
    ADD CONSTRAINT uq_cargos_tenant_id UNIQUE (tenant_id, id);


--
-- Name: cargos uq_cargos_tenant_idempotency; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargos
    ADD CONSTRAINT uq_cargos_tenant_idempotency UNIQUE (tenant_id, idempotency_key);


--
-- Name: cargos uq_cargos_tenant_matricula; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargos
    ADD CONSTRAINT uq_cargos_tenant_matricula UNIQUE (tenant_id, matricula_id);


--
-- Name: cargos uq_cargos_tenant_mensualidad; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargos
    ADD CONSTRAINT uq_cargos_tenant_mensualidad UNIQUE (tenant_id, mensualidad_id);


--
-- Name: cargos uq_cargos_tenant_venta_stock; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargos
    ADD CONSTRAINT uq_cargos_tenant_venta_stock UNIQUE (tenant_id, venta_stock_id);


--
-- Name: conceptos uq_conceptos_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conceptos
    ADD CONSTRAINT uq_conceptos_tenant_id UNIQUE (tenant_id, id);


--
-- Name: conceptos uq_conceptos_tenant_sub_descripcion; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conceptos
    ADD CONSTRAINT uq_conceptos_tenant_sub_descripcion UNIQUE (tenant_id, sub_concepto_id, descripcion);


--
-- Name: inscripcion_condiciones_economicas uq_condiciones_economicas_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscripcion_condiciones_economicas
    ADD CONSTRAINT uq_condiciones_economicas_tenant_id UNIQUE (tenant_id, id);


--
-- Name: inscripcion_condiciones_economicas uq_condiciones_tenant_inicio; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscripcion_condiciones_economicas
    ADD CONSTRAINT uq_condiciones_tenant_inicio UNIQUE (tenant_id, inscripcion_id, vigente_desde);


--
-- Name: disciplina_horarios uq_disciplina_horarios_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disciplina_horarios
    ADD CONSTRAINT uq_disciplina_horarios_tenant_id UNIQUE (tenant_id, id);


--
-- Name: disciplina_tarifas uq_disciplina_tarifas_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disciplina_tarifas
    ADD CONSTRAINT uq_disciplina_tarifas_tenant_id UNIQUE (tenant_id, id);


--
-- Name: disciplina_tarifas uq_disciplina_tarifas_tenant_inicio; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disciplina_tarifas
    ADD CONSTRAINT uq_disciplina_tarifas_tenant_inicio UNIQUE (tenant_id, disciplina_id, vigente_desde);


--
-- Name: disciplinas uq_disciplinas_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disciplinas
    ADD CONSTRAINT uq_disciplinas_tenant_id UNIQUE (tenant_id, id);


--
-- Name: egresos uq_egresos_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.egresos
    ADD CONSTRAINT uq_egresos_tenant_id UNIQUE (tenant_id, id);


--
-- Name: egresos uq_egresos_tenant_idempotency; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.egresos
    ADD CONSTRAINT uq_egresos_tenant_idempotency UNIQUE (tenant_id, idempotency_key);


--
-- Name: egresos uq_egresos_tenant_reversal; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.egresos
    ADD CONSTRAINT uq_egresos_tenant_reversal UNIQUE (tenant_id, reversal_idempotency_key);


--
-- Name: disciplina_horarios uq_horarios_tenant_disciplina; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disciplina_horarios
    ADD CONSTRAINT uq_horarios_tenant_disciplina UNIQUE (tenant_id, disciplina_id, dia_semana, horario_inicio);


--
-- Name: inscripciones uq_inscripciones_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscripciones
    ADD CONSTRAINT uq_inscripciones_tenant_id UNIQUE (tenant_id, id);


--
-- Name: jere_platform_tenant_mappings uq_jere_mapping_effective_identity; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jere_platform_tenant_mappings
    ADD CONSTRAINT uq_jere_mapping_effective_identity UNIQUE (internal_tenant_id, id, external_organization_id, external_tenant_id, source_type, config_version, signing_key_ref);


--
-- Name: jere_platform_tenant_mappings uq_jere_mapping_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jere_platform_tenant_mappings
    ADD CONSTRAINT uq_jere_mapping_tenant_id UNIQUE (internal_tenant_id, id);


--
-- Name: jere_platform_tenant_mappings uq_jere_mapping_tenant_source_version; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jere_platform_tenant_mappings
    ADD CONSTRAINT uq_jere_mapping_tenant_source_version UNIQUE (internal_tenant_id, source_type, config_version);


--
-- Name: jere_platform_student_export_pages uq_jere_pages_tenant_cursor; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jere_platform_student_export_pages
    ADD CONSTRAINT uq_jere_pages_tenant_cursor UNIQUE (internal_tenant_id, cursor_token);


--
-- Name: jere_platform_student_export_pages uq_jere_pages_tenant_page; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jere_platform_student_export_pages
    ADD CONSTRAINT uq_jere_pages_tenant_page UNIQUE (internal_tenant_id, snapshot_checkpoint, page_number);


--
-- Name: jere_platform_student_export_snapshots uq_jere_snapshots_tenant_checkpoint; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jere_platform_student_export_snapshots
    ADD CONSTRAINT uq_jere_snapshots_tenant_checkpoint UNIQUE (internal_tenant_id, checkpoint);


--
-- Name: matriculas uq_matriculas_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.matriculas
    ADD CONSTRAINT uq_matriculas_tenant_id UNIQUE (tenant_id, id);


--
-- Name: matriculas uq_matriculas_tenant_periodo; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.matriculas
    ADD CONSTRAINT uq_matriculas_tenant_periodo UNIQUE (tenant_id, alumno_id, anio);


--
-- Name: mensualidades uq_mensualidades_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mensualidades
    ADD CONSTRAINT uq_mensualidades_tenant_id UNIQUE (tenant_id, id);


--
-- Name: mensualidades uq_mensualidades_tenant_periodo; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mensualidades
    ADD CONSTRAINT uq_mensualidades_tenant_periodo UNIQUE (tenant_id, inscripcion_id, anio, mes);


--
-- Name: metodo_pagos uq_metodo_pagos_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metodo_pagos
    ADD CONSTRAINT uq_metodo_pagos_tenant_id UNIQUE (tenant_id, id);


--
-- Name: metodo_pagos uq_metodos_pago_tenant_descripcion; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metodo_pagos
    ADD CONSTRAINT uq_metodos_pago_tenant_descripcion UNIQUE (tenant_id, descripcion);


--
-- Name: movimientos_caja uq_movimientos_caja_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_caja
    ADD CONSTRAINT uq_movimientos_caja_tenant_id UNIQUE (tenant_id, id);


--
-- Name: movimientos_caja uq_movimientos_caja_tenant_idempotency; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_caja
    ADD CONSTRAINT uq_movimientos_caja_tenant_idempotency UNIQUE (tenant_id, idempotency_key);


--
-- Name: movimientos_caja uq_movimientos_caja_tenant_reversion; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_caja
    ADD CONSTRAINT uq_movimientos_caja_tenant_reversion UNIQUE (tenant_id, movimiento_revertido_id);


--
-- Name: movimientos_credito uq_movimientos_credito_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_credito
    ADD CONSTRAINT uq_movimientos_credito_tenant_id UNIQUE (tenant_id, id);


--
-- Name: movimientos_credito uq_movimientos_credito_tenant_idempotency; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_credito
    ADD CONSTRAINT uq_movimientos_credito_tenant_idempotency UNIQUE (tenant_id, idempotency_key);


--
-- Name: movimientos_credito uq_movimientos_credito_tenant_reversion; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_credito
    ADD CONSTRAINT uq_movimientos_credito_tenant_reversion UNIQUE (tenant_id, movimiento_revertido_id);


--
-- Name: movimientos_stock uq_movimientos_stock_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_stock
    ADD CONSTRAINT uq_movimientos_stock_tenant_id UNIQUE (tenant_id, id);


--
-- Name: movimientos_stock uq_movimientos_stock_tenant_idempotency; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_stock
    ADD CONSTRAINT uq_movimientos_stock_tenant_idempotency UNIQUE (tenant_id, idempotency_key);


--
-- Name: movimientos_stock uq_movimientos_stock_tenant_reversion; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_stock
    ADD CONSTRAINT uq_movimientos_stock_tenant_reversion UNIQUE (tenant_id, movimiento_revertido_id);


--
-- Name: notificaciones uq_notificaciones_tenant_dedup; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notificaciones
    ADD CONSTRAINT uq_notificaciones_tenant_dedup UNIQUE (tenant_id, dedup_key);


--
-- Name: notificaciones uq_notificaciones_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notificaciones
    ADD CONSTRAINT uq_notificaciones_tenant_id UNIQUE (tenant_id, id);


--
-- Name: observaciones_profesores uq_observaciones_profesores_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_profesores
    ADD CONSTRAINT uq_observaciones_profesores_tenant_id UNIQUE (tenant_id, id);


--
-- Name: pagos uq_pagos_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT uq_pagos_tenant_id UNIQUE (tenant_id, id);


--
-- Name: pagos uq_pagos_tenant_idempotency; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT uq_pagos_tenant_idempotency UNIQUE (tenant_id, idempotency_key);


--
-- Name: pagos uq_pagos_tenant_reversal; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT uq_pagos_tenant_reversal UNIQUE (tenant_id, reversal_idempotency_key);


--
-- Name: permisos uq_permisos_codigo; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permisos
    ADD CONSTRAINT uq_permisos_codigo UNIQUE (codigo);


--
-- Name: platform_idempotency_keys uq_platform_idempotency_operation_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_idempotency_keys
    ADD CONSTRAINT uq_platform_idempotency_operation_key UNIQUE (operation, idempotency_key);


--
-- Name: platform_recovery_codes uq_platform_recovery_code_hash; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_recovery_codes
    ADD CONSTRAINT uq_platform_recovery_code_hash UNIQUE (code_hash);


--
-- Name: platform_refresh_sessions uq_platform_refresh_token_hash; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_refresh_sessions
    ADD CONSTRAINT uq_platform_refresh_token_hash UNIQUE (token_hash);


--
-- Name: platform_refresh_sessions uq_platform_refresh_user_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_refresh_sessions
    ADD CONSTRAINT uq_platform_refresh_user_id UNIQUE (usuario_id, id);


--
-- Name: platform_step_up_challenges uq_platform_step_up_binding; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_step_up_challenges
    ADD CONSTRAINT uq_platform_step_up_binding UNIQUE NULLS NOT DISTINCT (session_id, action, target_type, target_id, idempotency_key);


--
-- Name: platform_step_up_challenges uq_platform_step_up_proof; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_step_up_challenges
    ADD CONSTRAINT uq_platform_step_up_proof UNIQUE (proof_hash);


--
-- Name: profesores uq_profesores_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profesores
    ADD CONSTRAINT uq_profesores_tenant_id UNIQUE (tenant_id, id);


--
-- Name: profesores uq_profesores_tenant_usuario; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profesores
    ADD CONSTRAINT uq_profesores_tenant_usuario UNIQUE (tenant_id, usuario_id);


--
-- Name: recargos uq_recargos_tenant_descripcion; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recargos
    ADD CONSTRAINT uq_recargos_tenant_descripcion UNIQUE (tenant_id, descripcion);


--
-- Name: recargos uq_recargos_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recargos
    ADD CONSTRAINT uq_recargos_tenant_id UNIQUE (tenant_id, id);


--
-- Name: recibos_pendientes uq_recibos_pendientes_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recibos_pendientes
    ADD CONSTRAINT uq_recibos_pendientes_tenant_id UNIQUE (tenant_id, id);


--
-- Name: recibos_pendientes uq_recibos_pendientes_tenant_idempotency; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recibos_pendientes
    ADD CONSTRAINT uq_recibos_pendientes_tenant_idempotency UNIQUE (tenant_id, idempotency_key);


--
-- Name: recibos_pendientes uq_recibos_pendientes_tenant_pago; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recibos_pendientes
    ADD CONSTRAINT uq_recibos_pendientes_tenant_pago UNIQUE (tenant_id, pago_id, tipo);


--
-- Name: recibos uq_recibos_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recibos
    ADD CONSTRAINT uq_recibos_tenant_id UNIQUE (tenant_id, id);


--
-- Name: recibos uq_recibos_tenant_pago; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recibos
    ADD CONSTRAINT uq_recibos_tenant_pago UNIQUE (tenant_id, pago_id);


--
-- Name: refresh_sessions uq_refresh_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_sessions
    ADD CONSTRAINT uq_refresh_tenant_id UNIQUE (tenant_id, id);


--
-- Name: refresh_sessions uq_refresh_token_hash; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_sessions
    ADD CONSTRAINT uq_refresh_token_hash UNIQUE (token_hash);


--
-- Name: roles uq_roles_tenant_codigo; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT uq_roles_tenant_codigo UNIQUE (tenant_id, codigo);


--
-- Name: roles uq_roles_tenant_descripcion; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT uq_roles_tenant_descripcion UNIQUE (tenant_id, descripcion);


--
-- Name: roles uq_roles_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT uq_roles_tenant_id UNIQUE (tenant_id, id);


--
-- Name: salones uq_salones_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salones
    ADD CONSTRAINT uq_salones_tenant_id UNIQUE (tenant_id, id);


--
-- Name: salones uq_salones_tenant_nombre; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salones
    ADD CONSTRAINT uq_salones_tenant_nombre UNIQUE (tenant_id, nombre);


--
-- Name: stocks uq_stocks_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stocks
    ADD CONSTRAINT uq_stocks_tenant_id UNIQUE (tenant_id, id);


--
-- Name: stocks uq_stocks_tenant_nombre; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stocks
    ADD CONSTRAINT uq_stocks_tenant_nombre UNIQUE (tenant_id, nombre);


--
-- Name: sub_conceptos uq_sub_conceptos_tenant_descripcion; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sub_conceptos
    ADD CONSTRAINT uq_sub_conceptos_tenant_descripcion UNIQUE (tenant_id, descripcion);


--
-- Name: sub_conceptos uq_sub_conceptos_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sub_conceptos
    ADD CONSTRAINT uq_sub_conceptos_tenant_id UNIQUE (tenant_id, id);


--
-- Name: tenant_membership_roles uq_tenant_membership_roles_membership_role; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_membership_roles
    ADD CONSTRAINT uq_tenant_membership_roles_membership_role UNIQUE (membership_id, role_id);


--
-- Name: tenant_memberships uq_tenant_memberships_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_memberships
    ADD CONSTRAINT uq_tenant_memberships_tenant_id UNIQUE (tenant_id, id);


--
-- Name: tenant_memberships uq_tenant_memberships_tenant_user; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_memberships
    ADD CONSTRAINT uq_tenant_memberships_tenant_user UNIQUE (tenant_id, usuario_id);


--
-- Name: tenants uq_tenants_code; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenants
    ADD CONSTRAINT uq_tenants_code UNIQUE (code);


--
-- Name: ventas_stock uq_ventas_stock_tenant_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ventas_stock
    ADD CONSTRAINT uq_ventas_stock_tenant_id UNIQUE (tenant_id, id);


--
-- Name: ventas_stock uq_ventas_stock_tenant_idempotency; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ventas_stock
    ADD CONSTRAINT uq_ventas_stock_tenant_idempotency UNIQUE (tenant_id, idempotency_key);


--
-- Name: ventas_stock uq_ventas_stock_tenant_reversal; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ventas_stock
    ADD CONSTRAINT uq_ventas_stock_tenant_reversal UNIQUE (tenant_id, reversal_idempotency_key);


--
-- Name: usuarios usuarios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_pkey PRIMARY KEY (id);


--
-- Name: ventas_stock ventas_stock_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ventas_stock
    ADD CONSTRAINT ventas_stock_pkey PRIMARY KEY (id);


--
-- Name: ix_alumnos_activos_nombre; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_alumnos_activos_nombre ON public.alumnos USING btree (activo, apellido, nombre);


--
-- Name: ix_alumnos_tenant_activo_nombre; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_alumnos_tenant_activo_nombre ON public.alumnos USING btree (tenant_id, activo, apellido, nombre);


--
-- Name: ix_aplicaciones_cargo_estado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_aplicaciones_cargo_estado ON public.aplicaciones_pago USING btree (cargo_id, estado);


--
-- Name: ix_aplicaciones_pago_aplicaciones_tenant_cargo_160636c2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_aplicaciones_pago_aplicaciones_tenant_cargo_160636c2 ON public.aplicaciones_pago USING btree (tenant_id, cargo_id);


--
-- Name: ix_aplicaciones_pago_estado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_aplicaciones_pago_estado ON public.aplicaciones_pago USING btree (pago_id, estado);


--
-- Name: ix_aplicaciones_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_aplicaciones_usuario ON public.aplicaciones_pago USING btree (usuario_id);


--
-- Name: ix_asistencia_alumno_inscripcion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_asistencia_alumno_inscripcion ON public.asistencias_alumno_mensual USING btree (inscripcion_id);


--
-- Name: ix_asistencias_alumno_mensual_asistencia_alumno_tenant_bf60ebca; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_asistencias_alumno_mensual_asistencia_alumno_tenant_bf60ebca ON public.asistencias_alumno_mensual USING btree (tenant_id, inscripcion_id);


--
-- Name: ix_auditoria_actor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_auditoria_actor ON public.auditoria_eventos USING btree (actor_usuario_id, ocurrido_at DESC);


--
-- Name: ix_auditoria_entidad; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_auditoria_entidad ON public.auditoria_eventos USING btree (entidad_tipo, entidad_id, ocurrido_at DESC);


--
-- Name: ix_auditoria_tenant_ocurrido; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_auditoria_tenant_ocurrido ON public.auditoria_eventos USING btree (tenant_id, ocurrido_at DESC, id);


--
-- Name: ix_bootstrap_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_bootstrap_usuario ON public.bootstrap_ejecuciones USING btree (usuario_id);


--
-- Name: ix_cargo_eventos_cargo_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_cargo_eventos_cargo_fecha ON public.cargo_eventos USING btree (cargo_id, ocurrido_at, id);


--
-- Name: ix_cargo_eventos_tenant_cargo_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_cargo_eventos_tenant_cargo_fecha ON public.cargo_eventos USING btree (tenant_id, cargo_id, ocurrido_at, id);


--
-- Name: ix_cargo_eventos_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_cargo_eventos_usuario ON public.cargo_eventos USING btree (usuario_id);


--
-- Name: ix_cargo_liquidaciones_liquidacion_tenant_condicion_4a690a13; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_cargo_liquidaciones_liquidacion_tenant_condicion_4a690a13 ON public.cargo_liquidaciones USING btree (tenant_id, condicion_inscripcion_id);


--
-- Name: ix_cargo_liquidaciones_liquidacion_tenant_tarifa_ddeadcd5; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_cargo_liquidaciones_liquidacion_tenant_tarifa_ddeadcd5 ON public.cargo_liquidaciones USING btree (tenant_id, tarifa_disciplina_id);


--
-- Name: ix_cargos_alumno_pendientes; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_cargos_alumno_pendientes ON public.cargos USING btree (alumno_id, fecha_vencimiento, id) WHERE ((estado)::text = ANY ((ARRAY['PENDIENTE'::character varying, 'PARCIAL'::character varying])::text[]));


--
-- Name: ix_cargos_cargo_origen; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_cargos_cargo_origen ON public.cargos USING btree (cargo_origen_id);


--
-- Name: ix_cargos_cargos_tenant_alumno_a309d4c5; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_cargos_cargos_tenant_alumno_a309d4c5 ON public.cargos USING btree (tenant_id, alumno_id);


--
-- Name: ix_cargos_cargos_tenant_concepto_553d2c49; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_cargos_cargos_tenant_concepto_553d2c49 ON public.cargos USING btree (tenant_id, concepto_id);


--
-- Name: ix_cargos_cargos_tenant_origen_9783a911; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_cargos_cargos_tenant_origen_9783a911 ON public.cargos USING btree (tenant_id, cargo_origen_id);


--
-- Name: ix_cargos_concepto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_cargos_concepto ON public.cargos USING btree (concepto_id);


--
-- Name: ix_cargos_pendientes; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_cargos_pendientes ON public.cargos USING btree (fecha_vencimiento, alumno_id) WHERE ((estado)::text = ANY ((ARRAY['PENDIENTE'::character varying, 'PARCIAL'::character varying])::text[]));


--
-- Name: ix_cargos_tenant_pendientes; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_cargos_tenant_pendientes ON public.cargos USING btree (tenant_id, estado, fecha_vencimiento, alumno_id);


--
-- Name: ix_conceptos_sub_concepto; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_conceptos_sub_concepto ON public.conceptos USING btree (sub_concepto_id);


--
-- Name: ix_condiciones_bonificacion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_condiciones_bonificacion ON public.inscripcion_condiciones_economicas USING btree (bonificacion_id);


--
-- Name: ix_condiciones_inscripcion_vigencia; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_condiciones_inscripcion_vigencia ON public.inscripcion_condiciones_economicas USING btree (inscripcion_id, vigente_desde DESC);


--
-- Name: ix_condiciones_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_condiciones_usuario ON public.inscripcion_condiciones_economicas USING btree (creada_por_usuario_id);


--
-- Name: ix_disciplina_tarifas_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_disciplina_tarifas_usuario ON public.disciplina_tarifas USING btree (creada_por_usuario_id);


--
-- Name: ix_disciplina_tarifas_vigencia; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_disciplina_tarifas_vigencia ON public.disciplina_tarifas USING btree (disciplina_id, vigente_desde DESC);


--
-- Name: ix_disciplinas_activo_nombre; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_disciplinas_activo_nombre ON public.disciplinas USING btree (activo, nombre);


--
-- Name: ix_disciplinas_disciplinas_tenant_profesor_92b1987b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_disciplinas_disciplinas_tenant_profesor_92b1987b ON public.disciplinas USING btree (tenant_id, profesor_id);


--
-- Name: ix_disciplinas_disciplinas_tenant_salon_075ae1fd; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_disciplinas_disciplinas_tenant_salon_075ae1fd ON public.disciplinas USING btree (tenant_id, salon_id);


--
-- Name: ix_disciplinas_profesor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_disciplinas_profesor ON public.disciplinas USING btree (profesor_id);


--
-- Name: ix_disciplinas_salon; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_disciplinas_salon ON public.disciplinas USING btree (salon_id);


--
-- Name: ix_disciplinas_tenant_activo_nombre; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_disciplinas_tenant_activo_nombre ON public.disciplinas USING btree (tenant_id, activo, nombre);


--
-- Name: ix_egresos_egresos_tenant_metodo_7608e57c; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_egresos_egresos_tenant_metodo_7608e57c ON public.egresos USING btree (tenant_id, metodo_pago_id);


--
-- Name: ix_egresos_fecha_metodo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_egresos_fecha_metodo ON public.egresos USING btree (fecha, metodo_pago_id);


--
-- Name: ix_egresos_metodo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_egresos_metodo ON public.egresos USING btree (metodo_pago_id);


--
-- Name: ix_egresos_tenant_fecha_metodo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_egresos_tenant_fecha_metodo ON public.egresos USING btree (tenant_id, fecha, metodo_pago_id);


--
-- Name: ix_egresos_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_egresos_usuario ON public.egresos USING btree (usuario_id);


--
-- Name: ix_inscripcion_condiciones_economicas_condiciones_tena_e3a4c4b7; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inscripcion_condiciones_economicas_condiciones_tena_e3a4c4b7 ON public.inscripcion_condiciones_economicas USING btree (tenant_id, bonificacion_id);


--
-- Name: ix_inscripciones_alumno_estado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inscripciones_alumno_estado ON public.inscripciones USING btree (alumno_id, estado);


--
-- Name: ix_inscripciones_bonificacion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inscripciones_bonificacion ON public.inscripciones USING btree (bonificacion_id);


--
-- Name: ix_inscripciones_disciplina_estado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inscripciones_disciplina_estado ON public.inscripciones USING btree (disciplina_id, estado);


--
-- Name: ix_inscripciones_inscripciones_tenant_bonificacion_012734dd; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inscripciones_inscripciones_tenant_bonificacion_012734dd ON public.inscripciones USING btree (tenant_id, bonificacion_id);


--
-- Name: ix_inscripciones_tenant_alumno_estado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inscripciones_tenant_alumno_estado ON public.inscripciones USING btree (tenant_id, alumno_id, estado);


--
-- Name: ix_inscripciones_tenant_disciplina_estado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_inscripciones_tenant_disciplina_estado ON public.inscripciones USING btree (tenant_id, disciplina_id, estado);


--
-- Name: ix_jere_platform_student_export_snapshots_jere_snapsho_a16b0d53; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_jere_platform_student_export_snapshots_jere_snapsho_a16b0d53 ON public.jere_platform_student_export_snapshots USING btree (internal_tenant_id, mapping_id, external_organization_id, external_tenant_id, source_type, mapping_config_version, signing_key_ref);


--
-- Name: ix_jere_platform_tenant_mappings_jere_mapping_created__87104ad2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_jere_platform_tenant_mappings_jere_mapping_created__87104ad2 ON public.jere_platform_tenant_mappings USING btree (created_by_usuario_id);


--
-- Name: ix_jere_snapshots_tenant_mapping_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_jere_snapshots_tenant_mapping_created ON public.jere_platform_student_export_snapshots USING btree (internal_tenant_id, external_organization_id, external_tenant_id, created_at DESC);


--
-- Name: ix_jere_student_export_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_jere_student_export_created_by ON public.jere_platform_student_export_snapshots USING btree (created_by);


--
-- Name: ix_liquidaciones_condicion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_liquidaciones_condicion ON public.cargo_liquidaciones USING btree (condicion_inscripcion_id);


--
-- Name: ix_liquidaciones_tarifa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_liquidaciones_tarifa ON public.cargo_liquidaciones USING btree (tarifa_disciplina_id);


--
-- Name: ix_liquidaciones_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_liquidaciones_usuario ON public.cargo_liquidaciones USING btree (calculada_por_usuario_id);


--
-- Name: ix_mensualidades_bonificacion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_mensualidades_bonificacion ON public.mensualidades USING btree (bonificacion_id);


--
-- Name: ix_mensualidades_mensualidades_tenant_bonificacion_2206ca15; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_mensualidades_mensualidades_tenant_bonificacion_2206ca15 ON public.mensualidades USING btree (tenant_id, bonificacion_id);


--
-- Name: ix_mensualidades_mensualidades_tenant_recargo_f018125c; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_mensualidades_mensualidades_tenant_recargo_f018125c ON public.mensualidades USING btree (tenant_id, recargo_id);


--
-- Name: ix_mensualidades_recargo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_mensualidades_recargo ON public.mensualidades USING btree (recargo_id);


--
-- Name: ix_mensualidades_tenant_vencimiento; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_mensualidades_tenant_vencimiento ON public.mensualidades USING btree (tenant_id, fecha_vencimiento, estado);


--
-- Name: ix_mensualidades_vencimiento; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_mensualidades_vencimiento ON public.mensualidades USING btree (fecha_vencimiento, estado);


--
-- Name: ix_movimientos_caja_egreso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimientos_caja_egreso ON public.movimientos_caja USING btree (egreso_id);


--
-- Name: ix_movimientos_caja_fecha_metodo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimientos_caja_fecha_metodo ON public.movimientos_caja USING btree (fecha, metodo_pago_id);


--
-- Name: ix_movimientos_caja_metodo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimientos_caja_metodo ON public.movimientos_caja USING btree (metodo_pago_id);


--
-- Name: ix_movimientos_caja_movimientos_caja_tenant_egreso_72c9b595; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimientos_caja_movimientos_caja_tenant_egreso_72c9b595 ON public.movimientos_caja USING btree (tenant_id, egreso_id);


--
-- Name: ix_movimientos_caja_movimientos_caja_tenant_metodo_5039c224; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimientos_caja_movimientos_caja_tenant_metodo_5039c224 ON public.movimientos_caja USING btree (tenant_id, metodo_pago_id);


--
-- Name: ix_movimientos_caja_movimientos_caja_tenant_pago_d1cc58f1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimientos_caja_movimientos_caja_tenant_pago_d1cc58f1 ON public.movimientos_caja USING btree (tenant_id, pago_id);


--
-- Name: ix_movimientos_caja_pago; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimientos_caja_pago ON public.movimientos_caja USING btree (pago_id);


--
-- Name: ix_movimientos_caja_tenant_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimientos_caja_tenant_fecha ON public.movimientos_caja USING btree (tenant_id, fecha, metodo_pago_id);


--
-- Name: ix_movimientos_caja_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimientos_caja_usuario ON public.movimientos_caja USING btree (usuario_id);


--
-- Name: ix_movimientos_credito_alumno_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimientos_credito_alumno_fecha ON public.movimientos_credito USING btree (alumno_id, created_at);


--
-- Name: ix_movimientos_credito_cargo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimientos_credito_cargo ON public.movimientos_credito USING btree (cargo_id);


--
-- Name: ix_movimientos_credito_movimientos_credito_tenant_carg_7e5ae78b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimientos_credito_movimientos_credito_tenant_carg_7e5ae78b ON public.movimientos_credito USING btree (tenant_id, cargo_id);


--
-- Name: ix_movimientos_credito_movimientos_credito_tenant_pago_0bb82dec; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimientos_credito_movimientos_credito_tenant_pago_0bb82dec ON public.movimientos_credito USING btree (tenant_id, pago_id);


--
-- Name: ix_movimientos_credito_pago; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimientos_credito_pago ON public.movimientos_credito USING btree (pago_id);


--
-- Name: ix_movimientos_credito_tenant_alumno; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimientos_credito_tenant_alumno ON public.movimientos_credito USING btree (tenant_id, alumno_id, created_at);


--
-- Name: ix_movimientos_credito_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimientos_credito_usuario ON public.movimientos_credito USING btree (usuario_id);


--
-- Name: ix_movimientos_stock_movimientos_stock_tenant_venta_f42e7fc1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimientos_stock_movimientos_stock_tenant_venta_f42e7fc1 ON public.movimientos_stock USING btree (tenant_id, venta_stock_id);


--
-- Name: ix_movimientos_stock_stock_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimientos_stock_stock_fecha ON public.movimientos_stock USING btree (stock_id, created_at);


--
-- Name: ix_movimientos_stock_tenant_stock; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimientos_stock_tenant_stock ON public.movimientos_stock USING btree (tenant_id, stock_id, created_at);


--
-- Name: ix_movimientos_stock_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimientos_stock_usuario ON public.movimientos_stock USING btree (usuario_id);


--
-- Name: ix_movimientos_stock_venta; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_movimientos_stock_venta ON public.movimientos_stock USING btree (venta_stock_id);


--
-- Name: ix_notificaciones_tenant_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_notificaciones_tenant_usuario ON public.notificaciones USING btree (tenant_id, usuario_id, leida, fecha_creacion DESC);


--
-- Name: ix_notificaciones_usuario_leida; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_notificaciones_usuario_leida ON public.notificaciones USING btree (usuario_id, leida, fecha_creacion DESC);


--
-- Name: ix_observaciones_profesor_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_observaciones_profesor_fecha ON public.observaciones_profesores USING btree (profesor_id, fecha);


--
-- Name: ix_observaciones_profesores_observaciones_tenant_profe_2771c2fc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_observaciones_profesores_observaciones_tenant_profe_2771c2fc ON public.observaciones_profesores USING btree (tenant_id, profesor_id);


--
-- Name: ix_pagos_alumno_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_pagos_alumno_fecha ON public.pagos USING btree (alumno_id, fecha DESC);


--
-- Name: ix_pagos_metodo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_pagos_metodo ON public.pagos USING btree (metodo_pago_id);


--
-- Name: ix_pagos_pagos_tenant_metodo_a00df209; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_pagos_pagos_tenant_metodo_a00df209 ON public.pagos USING btree (tenant_id, metodo_pago_id);


--
-- Name: ix_pagos_tenant_alumno_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_pagos_tenant_alumno_fecha ON public.pagos USING btree (tenant_id, alumno_id, fecha DESC);


--
-- Name: ix_pagos_usuario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_pagos_usuario ON public.pagos USING btree (usuario_id);


--
-- Name: ix_permisos_activo_codigo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_permisos_activo_codigo ON public.permisos USING btree (activo, codigo);


--
-- Name: ix_permisos_modulo_activo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_permisos_modulo_activo ON public.permisos USING btree (modulo, activo);


--
-- Name: ix_platform_admins_platform_admin_granted_by_46552667; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_platform_admins_platform_admin_granted_by_46552667 ON public.platform_admins USING btree (granted_by_usuario_id);


--
-- Name: ix_platform_audit_actor_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_platform_audit_actor_time ON public.platform_audit_events USING btree (actor_usuario_id, occurred_at DESC);


--
-- Name: ix_platform_audit_correlation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_platform_audit_correlation ON public.platform_audit_events USING btree (correlation_id);


--
-- Name: ix_platform_audit_target_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_platform_audit_target_time ON public.platform_audit_events USING btree (target_type, target_id, occurred_at DESC);


--
-- Name: ix_platform_audit_tenant_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_platform_audit_tenant_time ON public.platform_audit_events USING btree (target_tenant_id, occurred_at DESC);


--
-- Name: ix_platform_idempotency_actor_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_platform_idempotency_actor_created ON public.platform_idempotency_keys USING btree (actor_usuario_id, created_at DESC);


--
-- Name: ix_platform_idempotency_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_platform_idempotency_pending ON public.platform_idempotency_keys USING btree (created_at) WHERE ((status)::text = 'PENDING'::text);


--
-- Name: ix_platform_mfa_blocked; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_platform_mfa_blocked ON public.platform_mfa_credentials USING btree (blocked_until) WHERE (blocked_until IS NOT NULL);


--
-- Name: ix_platform_recovery_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_platform_recovery_active ON public.platform_recovery_codes USING btree (credential_id, id) WHERE (used_at IS NULL);
CREATE INDEX ix_platform_recovery_credential ON public.platform_recovery_codes USING btree (credential_id);


--
-- Name: ix_platform_refresh_family; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_platform_refresh_family ON public.platform_refresh_sessions USING btree (family_id, issued_at);


--
-- Name: ix_platform_refresh_replacement; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_platform_refresh_replacement ON public.platform_refresh_sessions USING btree (replaced_by_id);


--
-- Name: ix_platform_refresh_user_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_platform_refresh_user_active ON public.platform_refresh_sessions USING btree (usuario_id, expires_at) WHERE (revoked_at IS NULL);


--
-- Name: ix_platform_step_up_expiry; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_platform_step_up_expiry ON public.platform_step_up_challenges USING btree (expires_at) WHERE (consumed_at IS NULL);


--
-- Name: ix_platform_step_up_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_platform_step_up_user ON public.platform_step_up_challenges USING btree (usuario_id, issued_at DESC);
CREATE INDEX ix_platform_step_up_session ON public.platform_step_up_challenges USING btree (usuario_id, session_id);


--
-- Name: ix_profesores_profesores_usuario_aeffb866; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_profesores_profesores_usuario_aeffb866 ON public.profesores USING btree (usuario_id);


--
-- Name: ix_profesores_tenant_activo_nombre; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_profesores_tenant_activo_nombre ON public.profesores USING btree (tenant_id, activo, apellido, nombre);


--
-- Name: ix_recibos_pendientes_tenant_worker; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_recibos_pendientes_tenant_worker ON public.recibos_pendientes USING btree (tenant_id, estado, next_attempt_at, lease_until, id);


--
-- Name: ix_recibos_pendientes_worker; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_recibos_pendientes_worker ON public.recibos_pendientes USING btree (estado, next_attempt_at, lease_until);


--
-- Name: ix_refresh_membership_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_refresh_membership_active ON public.refresh_sessions USING btree (tenant_id, membership_id, expires_at) WHERE (revoked_at IS NULL);


--
-- Name: ix_refresh_replaced_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_refresh_replaced_by ON public.refresh_sessions USING btree (replaced_by_id);


--
-- Name: ix_refresh_sessions_refresh_membership_ea63a22b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_refresh_sessions_refresh_membership_ea63a22b ON public.refresh_sessions USING btree (tenant_id, membership_id);


--
-- Name: ix_refresh_sessions_refresh_reemplazo_tenant_e744e155; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_refresh_sessions_refresh_reemplazo_tenant_e744e155 ON public.refresh_sessions USING btree (tenant_id, replaced_by_id);


--
-- Name: ix_refresh_sessions_refresh_usuario_fcecd02f; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_refresh_sessions_refresh_usuario_fcecd02f ON public.refresh_sessions USING btree (usuario_id);


--
-- Name: ix_refresh_usuario_activa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_refresh_usuario_activa ON public.refresh_sessions USING btree (usuario_id, expires_at) WHERE (revoked_at IS NULL);


--
-- Name: ix_rol_permisos_permiso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_rol_permisos_permiso ON public.rol_permisos USING btree (permiso_id);


--
-- Name: ix_rol_permisos_tenant_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_rol_permisos_tenant_role ON public.rol_permisos USING btree (tenant_id, rol_id, permiso_id);


--
-- Name: ix_roles_activo_codigo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_roles_activo_codigo ON public.roles USING btree (activo, codigo);


--
-- Name: ix_roles_sistema; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_roles_sistema ON public.roles USING btree (sistema);


--
-- Name: ix_stocks_activos_nombre; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_stocks_activos_nombre ON public.stocks USING btree (activo, nombre);


--
-- Name: ix_tenant_membership_roles_tenant_membership_roles_ass_8abede8d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_tenant_membership_roles_tenant_membership_roles_ass_8abede8d ON public.tenant_membership_roles USING btree (assigned_by_usuario_id);


--
-- Name: ix_tenant_membership_roles_tenant_membership_roles_mem_c7ce8187; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_tenant_membership_roles_tenant_membership_roles_mem_c7ce8187 ON public.tenant_membership_roles USING btree (tenant_id, membership_id);


--
-- Name: ix_tenant_membership_roles_tenant_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_tenant_membership_roles_tenant_role ON public.tenant_membership_roles USING btree (tenant_id, role_id, membership_id);


--
-- Name: ix_tenant_memberships_tenant_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_tenant_memberships_tenant_status ON public.tenant_memberships USING btree (tenant_id, status, usuario_id);


--
-- Name: ix_tenant_memberships_user_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_tenant_memberships_user_status ON public.tenant_memberships USING btree (usuario_id, status, tenant_id);


--
-- Name: ix_usuario_roles_asignado_por; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_usuario_roles_asignado_por ON public.usuario_roles USING btree (asignado_por_usuario_id);


--
-- Name: ix_usuario_roles_rol; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_usuario_roles_rol ON public.usuario_roles USING btree (rol_id);


--
-- Name: ix_usuarios_rol; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_usuarios_rol ON public.usuarios USING btree (rol_id);


--
-- Name: ix_ventas_stock_alumno_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_ventas_stock_alumno_fecha ON public.ventas_stock USING btree (alumno_id, fecha);


--
-- Name: ix_ventas_stock_stock; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_ventas_stock_stock ON public.ventas_stock USING btree (stock_id);


--
-- Name: ix_ventas_stock_ventas_stock_tenant_alumno_c96d9357; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_ventas_stock_ventas_stock_tenant_alumno_c96d9357 ON public.ventas_stock USING btree (tenant_id, alumno_id);


--
-- Name: ix_ventas_stock_ventas_stock_tenant_stock_f067aa68; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_ventas_stock_ventas_stock_tenant_stock_f067aa68 ON public.ventas_stock USING btree (tenant_id, stock_id);


--
-- Name: uq_alumnos_tenant_documento; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_alumnos_tenant_documento ON public.alumnos USING btree (tenant_id, documento) WHERE (documento IS NOT NULL);


--
-- Name: uq_auditoria_global_idempotency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_auditoria_global_idempotency ON public.auditoria_eventos USING btree (idempotency_key) WHERE ((tenant_id IS NULL) AND (idempotency_key IS NOT NULL));


--
-- Name: uq_auditoria_tenant_idempotency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_auditoria_tenant_idempotency ON public.auditoria_eventos USING btree (tenant_id, idempotency_key) WHERE ((tenant_id IS NOT NULL) AND (idempotency_key IS NOT NULL));


--
-- Name: uq_inscripciones_tenant_activas; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_inscripciones_tenant_activas ON public.inscripciones USING btree (tenant_id, alumno_id, disciplina_id) WHERE ((estado)::text = 'ACTIVA'::text);


--
-- Name: uq_jere_mapping_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_jere_mapping_active ON public.jere_platform_tenant_mappings USING btree (internal_tenant_id, source_type) WHERE active;


--
-- Name: uq_jere_pages_tenant_first_page; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_jere_pages_tenant_first_page ON public.jere_platform_student_export_pages USING btree (internal_tenant_id, snapshot_checkpoint) WHERE (cursor_token IS NULL);


--
-- Name: uq_platform_mfa_user_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_platform_mfa_user_active ON public.platform_mfa_credentials USING btree (usuario_id) WHERE (revoked_at IS NULL);
CREATE INDEX ix_platform_mfa_user ON public.platform_mfa_credentials USING btree (usuario_id);


--
-- Name: uq_stocks_tenant_codigo_barras; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_stocks_tenant_codigo_barras ON public.stocks USING btree (tenant_id, codigo_barras) WHERE (codigo_barras IS NOT NULL);


--
-- Name: uq_usuarios_nombre_normalizado; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_usuarios_nombre_normalizado ON public.usuarios USING btree (lower((nombre_usuario)::text));


--
-- Name: auditoria_eventos trg_auditoria_eventos_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_auditoria_eventos_append_only BEFORE DELETE OR UPDATE ON public.auditoria_eventos FOR EACH ROW EXECUTE FUNCTION public.rechazar_mutacion_auditoria();


--
-- Name: cargo_eventos trg_cargo_eventos_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cargo_eventos_append_only BEFORE DELETE OR UPDATE ON public.cargo_eventos FOR EACH ROW EXECUTE FUNCTION public.rechazar_mutacion_cargo_evento();


--
-- Name: jere_platform_tenant_mappings trg_jere_mapping_inmutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_jere_mapping_inmutable BEFORE DELETE OR UPDATE ON public.jere_platform_tenant_mappings FOR EACH ROW EXECUTE FUNCTION public.rechazar_mutacion_jere_mapping();


--
-- Name: jere_platform_student_export_pages trg_jere_pages_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_jere_pages_append_only BEFORE DELETE OR UPDATE ON public.jere_platform_student_export_pages FOR EACH ROW EXECUTE FUNCTION public.rechazar_mutacion_jere_export();


--
-- Name: jere_platform_student_export_snapshots trg_jere_snapshots_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_jere_snapshots_append_only BEFORE DELETE OR UPDATE ON public.jere_platform_student_export_snapshots FOR EACH ROW EXECUTE FUNCTION public.rechazar_mutacion_jere_export();


--
-- Name: permisos trg_permisos_codigo_inmutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_permisos_codigo_inmutable BEFORE UPDATE ON public.permisos FOR EACH ROW EXECUTE FUNCTION public.impedir_cambio_codigo_permisos();


--
-- Name: platform_audit_events trg_platform_audit_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_platform_audit_append_only BEFORE DELETE OR UPDATE ON public.platform_audit_events FOR EACH ROW EXECUTE FUNCTION public.rechazar_mutacion_platform_audit();


--
-- Name: roles trg_roles_codigo_inmutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_roles_codigo_inmutable BEFORE UPDATE ON public.roles FOR EACH ROW EXECUTE FUNCTION public.impedir_cambio_codigo_roles();


--
-- Name: alumnos fk_alumnos_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alumnos
    ADD CONSTRAINT fk_alumnos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: aplicaciones_pago fk_aplicaciones_pago_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aplicaciones_pago
    ADD CONSTRAINT fk_aplicaciones_pago_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: aplicaciones_pago fk_aplicaciones_tenant_cargo; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aplicaciones_pago
    ADD CONSTRAINT fk_aplicaciones_tenant_cargo FOREIGN KEY (tenant_id, cargo_id) REFERENCES public.cargos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: aplicaciones_pago fk_aplicaciones_tenant_pago; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aplicaciones_pago
    ADD CONSTRAINT fk_aplicaciones_tenant_pago FOREIGN KEY (tenant_id, pago_id) REFERENCES public.pagos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: aplicaciones_pago fk_aplicaciones_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aplicaciones_pago
    ADD CONSTRAINT fk_aplicaciones_usuario FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: asistencias_alumno_mensual fk_asistencia_alumno_tenant_inscripcion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_alumno_mensual
    ADD CONSTRAINT fk_asistencia_alumno_tenant_inscripcion FOREIGN KEY (tenant_id, inscripcion_id) REFERENCES public.inscripciones(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: asistencias_alumno_mensual fk_asistencia_alumno_tenant_mensual; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_alumno_mensual
    ADD CONSTRAINT fk_asistencia_alumno_tenant_mensual FOREIGN KEY (tenant_id, asistencia_mensual_id) REFERENCES public.asistencias_mensuales(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: asistencias_alumno_mensual fk_asistencias_alumno_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_alumno_mensual
    ADD CONSTRAINT fk_asistencias_alumno_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: asistencias_diarias fk_asistencias_diarias_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_diarias
    ADD CONSTRAINT fk_asistencias_diarias_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: asistencias_diarias fk_asistencias_diarias_tenant_alumno; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_diarias
    ADD CONSTRAINT fk_asistencias_diarias_tenant_alumno FOREIGN KEY (tenant_id, asistencia_alumno_mensual_id) REFERENCES public.asistencias_alumno_mensual(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: asistencias_mensuales fk_asistencias_mensuales_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_mensuales
    ADD CONSTRAINT fk_asistencias_mensuales_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: asistencias_mensuales fk_asistencias_mensuales_tenant_disciplina; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asistencias_mensuales
    ADD CONSTRAINT fk_asistencias_mensuales_tenant_disciplina FOREIGN KEY (tenant_id, disciplina_id) REFERENCES public.disciplinas(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: auditoria_eventos fk_auditoria_actor; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria_eventos
    ADD CONSTRAINT fk_auditoria_actor FOREIGN KEY (actor_usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: auditoria_eventos fk_auditoria_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditoria_eventos
    ADD CONSTRAINT fk_auditoria_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: bonificaciones fk_bonificaciones_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bonificaciones
    ADD CONSTRAINT fk_bonificaciones_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: bootstrap_ejecuciones fk_bootstrap_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bootstrap_ejecuciones
    ADD CONSTRAINT fk_bootstrap_usuario FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: cargo_eventos fk_cargo_evento_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargo_eventos
    ADD CONSTRAINT fk_cargo_evento_usuario FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: cargo_eventos fk_cargo_eventos_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargo_eventos
    ADD CONSTRAINT fk_cargo_eventos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: cargo_eventos fk_cargo_eventos_tenant_cargo; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargo_eventos
    ADD CONSTRAINT fk_cargo_eventos_tenant_cargo FOREIGN KEY (tenant_id, cargo_id) REFERENCES public.cargos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: cargo_liquidaciones fk_cargo_liquidaciones_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargo_liquidaciones
    ADD CONSTRAINT fk_cargo_liquidaciones_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: cargos fk_cargos_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargos
    ADD CONSTRAINT fk_cargos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: cargos fk_cargos_tenant_alumno; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargos
    ADD CONSTRAINT fk_cargos_tenant_alumno FOREIGN KEY (tenant_id, alumno_id) REFERENCES public.alumnos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: cargos fk_cargos_tenant_concepto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargos
    ADD CONSTRAINT fk_cargos_tenant_concepto FOREIGN KEY (tenant_id, concepto_id) REFERENCES public.conceptos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: cargos fk_cargos_tenant_matricula; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargos
    ADD CONSTRAINT fk_cargos_tenant_matricula FOREIGN KEY (tenant_id, matricula_id) REFERENCES public.matriculas(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: cargos fk_cargos_tenant_mensualidad; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargos
    ADD CONSTRAINT fk_cargos_tenant_mensualidad FOREIGN KEY (tenant_id, mensualidad_id) REFERENCES public.mensualidades(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: cargos fk_cargos_tenant_origen; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargos
    ADD CONSTRAINT fk_cargos_tenant_origen FOREIGN KEY (tenant_id, cargo_origen_id) REFERENCES public.cargos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: cargos fk_cargos_tenant_venta_stock; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargos
    ADD CONSTRAINT fk_cargos_tenant_venta_stock FOREIGN KEY (tenant_id, venta_stock_id) REFERENCES public.ventas_stock(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: conceptos fk_conceptos_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conceptos
    ADD CONSTRAINT fk_conceptos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: conceptos fk_conceptos_tenant_subconcepto; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conceptos
    ADD CONSTRAINT fk_conceptos_tenant_subconcepto FOREIGN KEY (tenant_id, sub_concepto_id) REFERENCES public.sub_conceptos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: inscripcion_condiciones_economicas fk_condicion_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscripcion_condiciones_economicas
    ADD CONSTRAINT fk_condicion_usuario FOREIGN KEY (creada_por_usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: inscripcion_condiciones_economicas fk_condiciones_economicas_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscripcion_condiciones_economicas
    ADD CONSTRAINT fk_condiciones_economicas_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: inscripcion_condiciones_economicas fk_condiciones_tenant_bonificacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscripcion_condiciones_economicas
    ADD CONSTRAINT fk_condiciones_tenant_bonificacion FOREIGN KEY (tenant_id, bonificacion_id) REFERENCES public.bonificaciones(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: inscripcion_condiciones_economicas fk_condiciones_tenant_inscripcion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscripcion_condiciones_economicas
    ADD CONSTRAINT fk_condiciones_tenant_inscripcion FOREIGN KEY (tenant_id, inscripcion_id) REFERENCES public.inscripciones(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: disciplina_horarios fk_disciplina_horarios_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disciplina_horarios
    ADD CONSTRAINT fk_disciplina_horarios_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: disciplina_tarifas fk_disciplina_tarifa_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disciplina_tarifas
    ADD CONSTRAINT fk_disciplina_tarifa_usuario FOREIGN KEY (creada_por_usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: disciplina_tarifas fk_disciplina_tarifas_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disciplina_tarifas
    ADD CONSTRAINT fk_disciplina_tarifas_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: disciplinas fk_disciplinas_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disciplinas
    ADD CONSTRAINT fk_disciplinas_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: disciplinas fk_disciplinas_tenant_profesor; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disciplinas
    ADD CONSTRAINT fk_disciplinas_tenant_profesor FOREIGN KEY (tenant_id, profesor_id) REFERENCES public.profesores(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: disciplinas fk_disciplinas_tenant_salon; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disciplinas
    ADD CONSTRAINT fk_disciplinas_tenant_salon FOREIGN KEY (tenant_id, salon_id) REFERENCES public.salones(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: egresos fk_egresos_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.egresos
    ADD CONSTRAINT fk_egresos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: egresos fk_egresos_tenant_metodo; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.egresos
    ADD CONSTRAINT fk_egresos_tenant_metodo FOREIGN KEY (tenant_id, metodo_pago_id) REFERENCES public.metodo_pagos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: egresos fk_egresos_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.egresos
    ADD CONSTRAINT fk_egresos_usuario FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: disciplina_horarios fk_horarios_tenant_disciplina; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disciplina_horarios
    ADD CONSTRAINT fk_horarios_tenant_disciplina FOREIGN KEY (tenant_id, disciplina_id) REFERENCES public.disciplinas(tenant_id, id) ON DELETE CASCADE;


--
-- Name: inscripciones fk_inscripciones_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscripciones
    ADD CONSTRAINT fk_inscripciones_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: inscripciones fk_inscripciones_tenant_alumno; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscripciones
    ADD CONSTRAINT fk_inscripciones_tenant_alumno FOREIGN KEY (tenant_id, alumno_id) REFERENCES public.alumnos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: inscripciones fk_inscripciones_tenant_bonificacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscripciones
    ADD CONSTRAINT fk_inscripciones_tenant_bonificacion FOREIGN KEY (tenant_id, bonificacion_id) REFERENCES public.bonificaciones(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: inscripciones fk_inscripciones_tenant_disciplina; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inscripciones
    ADD CONSTRAINT fk_inscripciones_tenant_disciplina FOREIGN KEY (tenant_id, disciplina_id) REFERENCES public.disciplinas(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: jere_platform_tenant_mappings fk_jere_mapping_created_by; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jere_platform_tenant_mappings
    ADD CONSTRAINT fk_jere_mapping_created_by FOREIGN KEY (created_by_usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: jere_platform_tenant_mappings fk_jere_mapping_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jere_platform_tenant_mappings
    ADD CONSTRAINT fk_jere_mapping_tenant FOREIGN KEY (internal_tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: jere_platform_student_export_pages fk_jere_pages_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jere_platform_student_export_pages
    ADD CONSTRAINT fk_jere_pages_tenant FOREIGN KEY (internal_tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: jere_platform_student_export_pages fk_jere_pages_tenant_snapshot; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jere_platform_student_export_pages
    ADD CONSTRAINT fk_jere_pages_tenant_snapshot FOREIGN KEY (internal_tenant_id, snapshot_checkpoint) REFERENCES public.jere_platform_student_export_snapshots(internal_tenant_id, checkpoint) ON DELETE RESTRICT;


--
-- Name: jere_platform_student_export_snapshots fk_jere_snapshot_effective_mapping; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jere_platform_student_export_snapshots
    ADD CONSTRAINT fk_jere_snapshot_effective_mapping FOREIGN KEY (internal_tenant_id, mapping_id, external_organization_id, external_tenant_id, source_type, mapping_config_version, signing_key_ref) REFERENCES public.jere_platform_tenant_mappings(internal_tenant_id, id, external_organization_id, external_tenant_id, source_type, config_version, signing_key_ref) ON DELETE RESTRICT;


--
-- Name: jere_platform_student_export_snapshots fk_jere_snapshot_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jere_platform_student_export_snapshots
    ADD CONSTRAINT fk_jere_snapshot_tenant FOREIGN KEY (internal_tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: jere_platform_student_export_snapshots fk_jere_student_export_created_by; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jere_platform_student_export_snapshots
    ADD CONSTRAINT fk_jere_student_export_created_by FOREIGN KEY (created_by) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: cargo_liquidaciones fk_liquidacion_tenant_cargo; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargo_liquidaciones
    ADD CONSTRAINT fk_liquidacion_tenant_cargo FOREIGN KEY (tenant_id, cargo_id) REFERENCES public.cargos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: cargo_liquidaciones fk_liquidacion_tenant_condicion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargo_liquidaciones
    ADD CONSTRAINT fk_liquidacion_tenant_condicion FOREIGN KEY (tenant_id, condicion_inscripcion_id) REFERENCES public.inscripcion_condiciones_economicas(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: cargo_liquidaciones fk_liquidacion_tenant_tarifa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargo_liquidaciones
    ADD CONSTRAINT fk_liquidacion_tenant_tarifa FOREIGN KEY (tenant_id, tarifa_disciplina_id) REFERENCES public.disciplina_tarifas(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: cargo_liquidaciones fk_liquidacion_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cargo_liquidaciones
    ADD CONSTRAINT fk_liquidacion_usuario FOREIGN KEY (calculada_por_usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: matriculas fk_matriculas_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.matriculas
    ADD CONSTRAINT fk_matriculas_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: matriculas fk_matriculas_tenant_alumno; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.matriculas
    ADD CONSTRAINT fk_matriculas_tenant_alumno FOREIGN KEY (tenant_id, alumno_id) REFERENCES public.alumnos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: tenant_membership_roles fk_membership_roles_tenant_role; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_membership_roles
    ADD CONSTRAINT fk_membership_roles_tenant_role FOREIGN KEY (tenant_id, role_id) REFERENCES public.roles(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: mensualidades fk_mensualidades_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mensualidades
    ADD CONSTRAINT fk_mensualidades_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: mensualidades fk_mensualidades_tenant_bonificacion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mensualidades
    ADD CONSTRAINT fk_mensualidades_tenant_bonificacion FOREIGN KEY (tenant_id, bonificacion_id) REFERENCES public.bonificaciones(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: mensualidades fk_mensualidades_tenant_inscripcion; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mensualidades
    ADD CONSTRAINT fk_mensualidades_tenant_inscripcion FOREIGN KEY (tenant_id, inscripcion_id) REFERENCES public.inscripciones(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: mensualidades fk_mensualidades_tenant_recargo; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mensualidades
    ADD CONSTRAINT fk_mensualidades_tenant_recargo FOREIGN KEY (tenant_id, recargo_id) REFERENCES public.recargos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: metodo_pagos fk_metodo_pagos_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metodo_pagos
    ADD CONSTRAINT fk_metodo_pagos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: movimientos_caja fk_movimientos_caja_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_caja
    ADD CONSTRAINT fk_movimientos_caja_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: movimientos_caja fk_movimientos_caja_tenant_egreso; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_caja
    ADD CONSTRAINT fk_movimientos_caja_tenant_egreso FOREIGN KEY (tenant_id, egreso_id) REFERENCES public.egresos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: movimientos_caja fk_movimientos_caja_tenant_metodo; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_caja
    ADD CONSTRAINT fk_movimientos_caja_tenant_metodo FOREIGN KEY (tenant_id, metodo_pago_id) REFERENCES public.metodo_pagos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: movimientos_caja fk_movimientos_caja_tenant_pago; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_caja
    ADD CONSTRAINT fk_movimientos_caja_tenant_pago FOREIGN KEY (tenant_id, pago_id) REFERENCES public.pagos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: movimientos_caja fk_movimientos_caja_tenant_revertido; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_caja
    ADD CONSTRAINT fk_movimientos_caja_tenant_revertido FOREIGN KEY (tenant_id, movimiento_revertido_id) REFERENCES public.movimientos_caja(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: movimientos_caja fk_movimientos_caja_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_caja
    ADD CONSTRAINT fk_movimientos_caja_usuario FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: movimientos_credito fk_movimientos_credito_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_credito
    ADD CONSTRAINT fk_movimientos_credito_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: movimientos_credito fk_movimientos_credito_tenant_alumno; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_credito
    ADD CONSTRAINT fk_movimientos_credito_tenant_alumno FOREIGN KEY (tenant_id, alumno_id) REFERENCES public.alumnos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: movimientos_credito fk_movimientos_credito_tenant_cargo; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_credito
    ADD CONSTRAINT fk_movimientos_credito_tenant_cargo FOREIGN KEY (tenant_id, cargo_id) REFERENCES public.cargos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: movimientos_credito fk_movimientos_credito_tenant_pago; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_credito
    ADD CONSTRAINT fk_movimientos_credito_tenant_pago FOREIGN KEY (tenant_id, pago_id) REFERENCES public.pagos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: movimientos_credito fk_movimientos_credito_tenant_revertido; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_credito
    ADD CONSTRAINT fk_movimientos_credito_tenant_revertido FOREIGN KEY (tenant_id, movimiento_revertido_id) REFERENCES public.movimientos_credito(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: movimientos_credito fk_movimientos_credito_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_credito
    ADD CONSTRAINT fk_movimientos_credito_usuario FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: movimientos_stock fk_movimientos_stock_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_stock
    ADD CONSTRAINT fk_movimientos_stock_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: movimientos_stock fk_movimientos_stock_tenant_revertido; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_stock
    ADD CONSTRAINT fk_movimientos_stock_tenant_revertido FOREIGN KEY (tenant_id, movimiento_revertido_id) REFERENCES public.movimientos_stock(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: movimientos_stock fk_movimientos_stock_tenant_stock; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_stock
    ADD CONSTRAINT fk_movimientos_stock_tenant_stock FOREIGN KEY (tenant_id, stock_id) REFERENCES public.stocks(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: movimientos_stock fk_movimientos_stock_tenant_venta; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_stock
    ADD CONSTRAINT fk_movimientos_stock_tenant_venta FOREIGN KEY (tenant_id, venta_stock_id) REFERENCES public.ventas_stock(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: movimientos_stock fk_movimientos_stock_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimientos_stock
    ADD CONSTRAINT fk_movimientos_stock_usuario FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: notificaciones fk_notificaciones_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notificaciones
    ADD CONSTRAINT fk_notificaciones_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: notificaciones fk_notificaciones_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notificaciones
    ADD CONSTRAINT fk_notificaciones_usuario FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: observaciones_profesores fk_observaciones_profesores_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_profesores
    ADD CONSTRAINT fk_observaciones_profesores_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: observaciones_profesores fk_observaciones_tenant_profesor; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_profesores
    ADD CONSTRAINT fk_observaciones_tenant_profesor FOREIGN KEY (tenant_id, profesor_id) REFERENCES public.profesores(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: pagos fk_pagos_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT fk_pagos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: pagos fk_pagos_tenant_alumno; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT fk_pagos_tenant_alumno FOREIGN KEY (tenant_id, alumno_id) REFERENCES public.alumnos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: pagos fk_pagos_tenant_metodo; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT fk_pagos_tenant_metodo FOREIGN KEY (tenant_id, metodo_pago_id) REFERENCES public.metodo_pagos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: pagos fk_pagos_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT fk_pagos_usuario FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: platform_admins fk_platform_admin_granted_by; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_admins
    ADD CONSTRAINT fk_platform_admin_granted_by FOREIGN KEY (granted_by_usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: platform_admins fk_platform_admin_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_admins
    ADD CONSTRAINT fk_platform_admin_usuario FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: platform_audit_events fk_platform_audit_actor; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_audit_events
    ADD CONSTRAINT fk_platform_audit_actor FOREIGN KEY (actor_usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: platform_audit_events fk_platform_audit_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_audit_events
    ADD CONSTRAINT fk_platform_audit_tenant FOREIGN KEY (target_tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: platform_idempotency_keys fk_platform_idempotency_admin; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_idempotency_keys
    ADD CONSTRAINT fk_platform_idempotency_admin FOREIGN KEY (actor_usuario_id) REFERENCES public.platform_admins(usuario_id) ON DELETE RESTRICT;


--
-- Name: platform_mfa_credentials fk_platform_mfa_admin; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_mfa_credentials
    ADD CONSTRAINT fk_platform_mfa_admin FOREIGN KEY (usuario_id) REFERENCES public.platform_admins(usuario_id) ON DELETE RESTRICT;


--
-- Name: platform_recovery_codes fk_platform_recovery_credential; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_recovery_codes
    ADD CONSTRAINT fk_platform_recovery_credential FOREIGN KEY (credential_id) REFERENCES public.platform_mfa_credentials(id) ON DELETE RESTRICT;


--
-- Name: platform_refresh_sessions fk_platform_refresh_admin; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_refresh_sessions
    ADD CONSTRAINT fk_platform_refresh_admin FOREIGN KEY (usuario_id) REFERENCES public.platform_admins(usuario_id) ON DELETE RESTRICT;


--
-- Name: platform_refresh_sessions fk_platform_refresh_replacement; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_refresh_sessions
    ADD CONSTRAINT fk_platform_refresh_replacement FOREIGN KEY (replaced_by_id) REFERENCES public.platform_refresh_sessions(id) ON DELETE RESTRICT;


--
-- Name: platform_refresh_sessions fk_platform_refresh_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_refresh_sessions
    ADD CONSTRAINT fk_platform_refresh_usuario FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: platform_step_up_challenges fk_platform_step_up_admin; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_step_up_challenges
    ADD CONSTRAINT fk_platform_step_up_admin FOREIGN KEY (usuario_id) REFERENCES public.platform_admins(usuario_id) ON DELETE RESTRICT;


--
-- Name: platform_step_up_challenges fk_platform_step_up_session; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_step_up_challenges
    ADD CONSTRAINT fk_platform_step_up_session FOREIGN KEY (usuario_id, session_id) REFERENCES public.platform_refresh_sessions(usuario_id, id) ON DELETE RESTRICT;


--
-- Name: profesores fk_profesores_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profesores
    ADD CONSTRAINT fk_profesores_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: profesores fk_profesores_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profesores
    ADD CONSTRAINT fk_profesores_usuario FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: recargos fk_recargos_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recargos
    ADD CONSTRAINT fk_recargos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: recibos_pendientes fk_recibos_pendientes_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recibos_pendientes
    ADD CONSTRAINT fk_recibos_pendientes_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: recibos_pendientes fk_recibos_pendientes_tenant_pago; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recibos_pendientes
    ADD CONSTRAINT fk_recibos_pendientes_tenant_pago FOREIGN KEY (tenant_id, pago_id) REFERENCES public.pagos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: recibos fk_recibos_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recibos
    ADD CONSTRAINT fk_recibos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: recibos fk_recibos_tenant_pago; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recibos
    ADD CONSTRAINT fk_recibos_tenant_pago FOREIGN KEY (tenant_id, pago_id) REFERENCES public.pagos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: refresh_sessions fk_refresh_membership; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_sessions
    ADD CONSTRAINT fk_refresh_membership FOREIGN KEY (tenant_id, membership_id) REFERENCES public.tenant_memberships(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: refresh_sessions fk_refresh_reemplazo_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_sessions
    ADD CONSTRAINT fk_refresh_reemplazo_tenant FOREIGN KEY (tenant_id, replaced_by_id) REFERENCES public.refresh_sessions(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: refresh_sessions fk_refresh_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_sessions
    ADD CONSTRAINT fk_refresh_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: refresh_sessions fk_refresh_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_sessions
    ADD CONSTRAINT fk_refresh_usuario FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: rol_permisos fk_rol_permisos_permiso; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rol_permisos
    ADD CONSTRAINT fk_rol_permisos_permiso FOREIGN KEY (permiso_id) REFERENCES public.permisos(id) ON DELETE RESTRICT;


--
-- Name: rol_permisos fk_rol_permisos_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rol_permisos
    ADD CONSTRAINT fk_rol_permisos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: rol_permisos fk_rol_permisos_tenant_role; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rol_permisos
    ADD CONSTRAINT fk_rol_permisos_tenant_role FOREIGN KEY (tenant_id, rol_id) REFERENCES public.roles(tenant_id, id) ON DELETE CASCADE;


--
-- Name: roles fk_roles_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT fk_roles_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: salones fk_salones_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salones
    ADD CONSTRAINT fk_salones_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: stocks fk_stocks_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stocks
    ADD CONSTRAINT fk_stocks_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: sub_conceptos fk_sub_conceptos_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sub_conceptos
    ADD CONSTRAINT fk_sub_conceptos_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: disciplina_tarifas fk_tarifas_tenant_disciplina; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.disciplina_tarifas
    ADD CONSTRAINT fk_tarifas_tenant_disciplina FOREIGN KEY (tenant_id, disciplina_id) REFERENCES public.disciplinas(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: tenant_membership_roles fk_tenant_membership_roles_assigned_by; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_membership_roles
    ADD CONSTRAINT fk_tenant_membership_roles_assigned_by FOREIGN KEY (assigned_by_usuario_id) REFERENCES public.usuarios(id) ON DELETE SET NULL;


--
-- Name: tenant_membership_roles fk_tenant_membership_roles_membership; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_membership_roles
    ADD CONSTRAINT fk_tenant_membership_roles_membership FOREIGN KEY (tenant_id, membership_id) REFERENCES public.tenant_memberships(tenant_id, id) ON DELETE CASCADE;


--
-- Name: tenant_memberships fk_tenant_memberships_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_memberships
    ADD CONSTRAINT fk_tenant_memberships_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: tenant_memberships fk_tenant_memberships_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_memberships
    ADD CONSTRAINT fk_tenant_memberships_usuario FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE RESTRICT;


--
-- Name: usuario_roles fk_usuario_roles_asignado_por; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_roles
    ADD CONSTRAINT fk_usuario_roles_asignado_por FOREIGN KEY (asignado_por_usuario_id) REFERENCES public.usuarios(id) ON DELETE SET NULL;


--
-- Name: usuario_roles fk_usuario_roles_rol; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_roles
    ADD CONSTRAINT fk_usuario_roles_rol FOREIGN KEY (rol_id) REFERENCES public.roles(id) ON DELETE RESTRICT;


--
-- Name: usuario_roles fk_usuario_roles_usuario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_roles
    ADD CONSTRAINT fk_usuario_roles_usuario FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE CASCADE;


--
-- Name: usuarios fk_usuarios_rol; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT fk_usuarios_rol FOREIGN KEY (rol_id) REFERENCES public.roles(id) ON DELETE RESTRICT;


--
-- Name: ventas_stock fk_ventas_stock_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ventas_stock
    ADD CONSTRAINT fk_ventas_stock_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE RESTRICT;


--
-- Name: ventas_stock fk_ventas_stock_tenant_alumno; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ventas_stock
    ADD CONSTRAINT fk_ventas_stock_tenant_alumno FOREIGN KEY (tenant_id, alumno_id) REFERENCES public.alumnos(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: ventas_stock fk_ventas_stock_tenant_stock; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ventas_stock
    ADD CONSTRAINT fk_ventas_stock_tenant_stock FOREIGN KEY (tenant_id, stock_id) REFERENCES public.stocks(tenant_id, id) ON DELETE RESTRICT;


--
-- Name: alumnos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.alumnos ENABLE ROW LEVEL SECURITY;

--
-- Name: aplicaciones_pago; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.aplicaciones_pago ENABLE ROW LEVEL SECURITY;

--
-- Name: asistencias_alumno_mensual; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.asistencias_alumno_mensual ENABLE ROW LEVEL SECURITY;

--
-- Name: asistencias_diarias; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.asistencias_diarias ENABLE ROW LEVEL SECURITY;

--
-- Name: asistencias_mensuales; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.asistencias_mensuales ENABLE ROW LEVEL SECURITY;

--
-- Name: auditoria_eventos audit_tenant_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_tenant_insert ON public.auditoria_eventos FOR INSERT TO gestudio_app WITH CHECK (
CASE
    WHEN (public.gestudio_optional_tenant_id() IS NULL) THEN (tenant_id IS NULL)
    ELSE (tenant_id = public.gestudio_optional_tenant_id())
END);


--
-- Name: auditoria_eventos audit_tenant_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_tenant_select ON public.auditoria_eventos FOR SELECT TO gestudio_app USING ((tenant_id = public.gestudio_optional_tenant_id()));


--
-- Name: auditoria_eventos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.auditoria_eventos ENABLE ROW LEVEL SECURITY;

--
-- Name: bonificaciones; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bonificaciones ENABLE ROW LEVEL SECURITY;

--
-- Name: cargo_eventos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cargo_eventos ENABLE ROW LEVEL SECURITY;

--
-- Name: cargo_liquidaciones; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cargo_liquidaciones ENABLE ROW LEVEL SECURITY;

--
-- Name: cargos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cargos ENABLE ROW LEVEL SECURITY;

--
-- Name: conceptos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.conceptos ENABLE ROW LEVEL SECURITY;

--
-- Name: disciplina_horarios; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.disciplina_horarios ENABLE ROW LEVEL SECURITY;

--
-- Name: disciplina_tarifas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.disciplina_tarifas ENABLE ROW LEVEL SECURITY;

--
-- Name: disciplinas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.disciplinas ENABLE ROW LEVEL SECURITY;

--
-- Name: egresos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.egresos ENABLE ROW LEVEL SECURITY;

--
-- Name: inscripcion_condiciones_economicas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inscripcion_condiciones_economicas ENABLE ROW LEVEL SECURITY;

--
-- Name: inscripciones; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inscripciones ENABLE ROW LEVEL SECURITY;

--
-- Name: jere_platform_student_export_pages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.jere_platform_student_export_pages ENABLE ROW LEVEL SECURITY;

--
-- Name: jere_platform_student_export_snapshots; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.jere_platform_student_export_snapshots ENABLE ROW LEVEL SECURITY;

--
-- Name: jere_platform_tenant_mappings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.jere_platform_tenant_mappings ENABLE ROW LEVEL SECURITY;

--
-- Name: matriculas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.matriculas ENABLE ROW LEVEL SECURITY;

--
-- Name: mensualidades; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.mensualidades ENABLE ROW LEVEL SECURITY;

--
-- Name: metodo_pagos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.metodo_pagos ENABLE ROW LEVEL SECURITY;

--
-- Name: movimientos_caja; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.movimientos_caja ENABLE ROW LEVEL SECURITY;

--
-- Name: movimientos_credito; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.movimientos_credito ENABLE ROW LEVEL SECURITY;

--
-- Name: movimientos_stock; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.movimientos_stock ENABLE ROW LEVEL SECURITY;

--
-- Name: notificaciones; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notificaciones ENABLE ROW LEVEL SECURITY;

--
-- Name: observaciones_profesores; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.observaciones_profesores ENABLE ROW LEVEL SECURITY;

--
-- Name: pagos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pagos ENABLE ROW LEVEL SECURITY;

--
-- Name: rol_permisos platform_target_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY platform_target_tenant ON public.rol_permisos TO gestudio_platform USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: roles platform_target_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY platform_target_tenant ON public.roles TO gestudio_platform USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: tenant_memberships membership_global_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY membership_global_select ON public.tenant_memberships FOR SELECT TO gestudio_app, gestudio_platform, gestudio_health USING (true);


--
-- Name: tenant_memberships membership_target_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY membership_target_insert ON public.tenant_memberships FOR INSERT TO gestudio_app, gestudio_platform WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: tenant_memberships membership_target_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY membership_target_update ON public.tenant_memberships FOR UPDATE TO gestudio_app, gestudio_platform USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: tenant_membership_roles membership_target_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY membership_target_select ON public.tenant_membership_roles FOR SELECT TO gestudio_app, gestudio_platform USING ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: tenant_membership_roles membership_target_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY membership_target_insert ON public.tenant_membership_roles FOR INSERT TO gestudio_app, gestudio_platform WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: tenant_membership_roles membership_target_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY membership_target_update ON public.tenant_membership_roles FOR UPDATE TO gestudio_app, gestudio_platform USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: tenant_membership_roles membership_target_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY membership_target_delete ON public.tenant_membership_roles FOR DELETE TO gestudio_app, gestudio_platform USING ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: profesores; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profesores ENABLE ROW LEVEL SECURITY;

--
-- Name: recargos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.recargos ENABLE ROW LEVEL SECURITY;

--
-- Name: recibos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.recibos ENABLE ROW LEVEL SECURITY;

--
-- Name: recibos_pendientes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.recibos_pendientes ENABLE ROW LEVEL SECURITY;

--
-- Name: refresh_sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.refresh_sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: rol_permisos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rol_permisos ENABLE ROW LEVEL SECURITY;

--
-- Name: roles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;

--
-- Name: salones; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.salones ENABLE ROW LEVEL SECURITY;

--
-- Name: stocks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stocks ENABLE ROW LEVEL SECURITY;

--
-- Name: sub_conceptos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sub_conceptos ENABLE ROW LEVEL SECURITY;

--
-- Name: alumnos tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.alumnos TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: aplicaciones_pago tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.aplicaciones_pago TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: asistencias_alumno_mensual tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.asistencias_alumno_mensual TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: asistencias_diarias tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.asistencias_diarias TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: asistencias_mensuales tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.asistencias_mensuales TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: bonificaciones tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.bonificaciones TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: cargo_eventos tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.cargo_eventos TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: cargo_liquidaciones tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.cargo_liquidaciones TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: cargos tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.cargos TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: conceptos tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.conceptos TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: disciplina_horarios tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.disciplina_horarios TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: disciplina_tarifas tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.disciplina_tarifas TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: disciplinas tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.disciplinas TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: egresos tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.egresos TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: inscripcion_condiciones_economicas tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.inscripcion_condiciones_economicas TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: inscripciones tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.inscripciones TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: jere_platform_student_export_pages tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.jere_platform_student_export_pages TO gestudio_app USING ((internal_tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((internal_tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: jere_platform_student_export_snapshots tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.jere_platform_student_export_snapshots TO gestudio_app USING ((internal_tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((internal_tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: jere_platform_tenant_mappings tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.jere_platform_tenant_mappings TO gestudio_app USING ((internal_tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((internal_tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: matriculas tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.matriculas TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: mensualidades tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.mensualidades TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: metodo_pagos tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.metodo_pagos TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: movimientos_caja tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.movimientos_caja TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: movimientos_credito tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.movimientos_credito TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: movimientos_stock tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.movimientos_stock TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: notificaciones tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.notificaciones TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: observaciones_profesores tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.observaciones_profesores TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: pagos tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.pagos TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: profesores tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.profesores TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: recargos tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.recargos TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: recibos tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.recibos TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: recibos_pendientes tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.recibos_pendientes TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: refresh_sessions tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.refresh_sessions TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: rol_permisos tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.rol_permisos TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: roles tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.roles TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: salones tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.salones TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: stocks tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.stocks TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: sub_conceptos tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.sub_conceptos TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: ventas_stock tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.ventas_stock TO gestudio_app USING ((tenant_id = public.gestudio_current_tenant_id())) WITH CHECK ((tenant_id = public.gestudio_current_tenant_id()));


--
-- Name: ventas_stock; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ventas_stock ENABLE ROW LEVEL SECURITY;

-- Activaciones globales de identidad. Se crean vacías; el token persistido
-- es exclusivamente su hash SHA-256 y nunca una contraseña temporal.
CREATE TABLE public.platform_identity_activations (
    id UUID PRIMARY KEY,
    usuario_id BIGINT NOT NULL,
    purpose VARCHAR(30) NOT NULL,
    token_hash CHAR(64) NOT NULL,
    issued_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_by_usuario_id BIGINT NOT NULL,
    CONSTRAINT uq_platform_identity_activation_token UNIQUE (token_hash),
    CONSTRAINT ck_platform_identity_activation_purpose CHECK (
        purpose IN ('IDENTITY_ACTIVATION', 'PLATFORM_MFA_ENROLLMENT', 'PLATFORM_MFA_RESET')
    ),
    CONSTRAINT ck_platform_identity_activation_times CHECK (
        expires_at > issued_at
        AND (consumed_at IS NULL OR consumed_at >= issued_at)
    ),
    CONSTRAINT fk_platform_identity_activation_user FOREIGN KEY (usuario_id)
        REFERENCES public.usuarios(id) ON DELETE RESTRICT,
    CONSTRAINT fk_platform_identity_activation_creator FOREIGN KEY (created_by_usuario_id)
        REFERENCES public.platform_admins(usuario_id) ON DELETE RESTRICT
);

CREATE INDEX ix_platform_identity_activation_active
    ON public.platform_identity_activations (expires_at)
    WHERE consumed_at IS NULL;
CREATE UNIQUE INDEX uq_platform_identity_activation_user_active
    ON public.platform_identity_activations (usuario_id)
    WHERE consumed_at IS NULL;
CREATE INDEX ix_platform_identity_activation_user
    ON public.platform_identity_activations (usuario_id);
CREATE INDEX ix_platform_identity_activation_creator
    ON public.platform_identity_activations (created_by_usuario_id);

--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO gestudio_app;
GRANT USAGE ON SCHEMA public TO gestudio_health;
GRANT USAGE ON SCHEMA public TO gestudio_platform;

GRANT SELECT, INSERT, UPDATE ON TABLE public.platform_identity_activations TO gestudio_platform;
GRANT SELECT, INSERT, UPDATE ON TABLE public.bootstrap_ejecuciones TO gestudio_platform;


--
-- Name: FUNCTION gestudio_current_tenant_id(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.gestudio_current_tenant_id() FROM PUBLIC;
GRANT ALL ON FUNCTION public.gestudio_current_tenant_id() TO gestudio_app;
GRANT ALL ON FUNCTION public.gestudio_current_tenant_id() TO gestudio_platform;


--
-- Name: FUNCTION gestudio_multitenancy_health(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.gestudio_multitenancy_health() FROM PUBLIC;
GRANT ALL ON FUNCTION public.gestudio_multitenancy_health() TO gestudio_app;
GRANT ALL ON FUNCTION public.gestudio_multitenancy_health() TO gestudio_platform;


--
-- Name: FUNCTION gestudio_optional_tenant_id(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.gestudio_optional_tenant_id() FROM PUBLIC;
GRANT ALL ON FUNCTION public.gestudio_optional_tenant_id() TO gestudio_app;


--
-- Name: TABLE alumnos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.alumnos TO gestudio_app;


--
-- Name: SEQUENCE alumnos_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.alumnos_id_seq TO gestudio_app;


--
-- Name: TABLE aplicaciones_pago; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.aplicaciones_pago TO gestudio_app;


--
-- Name: SEQUENCE aplicaciones_pago_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.aplicaciones_pago_id_seq TO gestudio_app;


--
-- Name: TABLE asistencias_alumno_mensual; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.asistencias_alumno_mensual TO gestudio_app;


--
-- Name: SEQUENCE asistencias_alumno_mensual_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.asistencias_alumno_mensual_id_seq TO gestudio_app;


--
-- Name: TABLE asistencias_diarias; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.asistencias_diarias TO gestudio_app;


--
-- Name: SEQUENCE asistencias_diarias_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.asistencias_diarias_id_seq TO gestudio_app;


--
-- Name: TABLE asistencias_mensuales; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.asistencias_mensuales TO gestudio_app;


--
-- Name: SEQUENCE asistencias_mensuales_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.asistencias_mensuales_id_seq TO gestudio_app;


--
-- Name: TABLE auditoria_eventos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT ON TABLE public.auditoria_eventos TO gestudio_app;


--
-- Name: SEQUENCE auditoria_eventos_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.auditoria_eventos_id_seq TO gestudio_app;


--
-- Name: TABLE bonificaciones; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.bonificaciones TO gestudio_app;


--
-- Name: SEQUENCE bonificaciones_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.bonificaciones_id_seq TO gestudio_app;


--
-- Name: TABLE bootstrap_ejecuciones; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.bootstrap_ejecuciones TO gestudio_app;


--
-- Name: TABLE cargo_eventos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.cargo_eventos TO gestudio_app;


--
-- Name: SEQUENCE cargo_eventos_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.cargo_eventos_id_seq TO gestudio_app;


--
-- Name: TABLE cargo_liquidaciones; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.cargo_liquidaciones TO gestudio_app;


--
-- Name: TABLE cargos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.cargos TO gestudio_app;


--
-- Name: SEQUENCE cargos_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.cargos_id_seq TO gestudio_app;


--
-- Name: TABLE conceptos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.conceptos TO gestudio_app;


--
-- Name: SEQUENCE conceptos_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.conceptos_id_seq TO gestudio_app;


--
-- Name: TABLE disciplina_horarios; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.disciplina_horarios TO gestudio_app;


--
-- Name: SEQUENCE disciplina_horarios_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.disciplina_horarios_id_seq TO gestudio_app;


--
-- Name: TABLE disciplina_tarifas; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.disciplina_tarifas TO gestudio_app;


--
-- Name: SEQUENCE disciplina_tarifas_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.disciplina_tarifas_id_seq TO gestudio_app;


--
-- Name: TABLE disciplinas; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.disciplinas TO gestudio_app;


--
-- Name: SEQUENCE disciplinas_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.disciplinas_id_seq TO gestudio_app;


--
-- Name: TABLE egresos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.egresos TO gestudio_app;


--
-- Name: SEQUENCE egresos_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.egresos_id_seq TO gestudio_app;


--
-- Name: TABLE inscripcion_condiciones_economicas; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.inscripcion_condiciones_economicas TO gestudio_app;


--
-- Name: SEQUENCE inscripcion_condiciones_economicas_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.inscripcion_condiciones_economicas_id_seq TO gestudio_app;


--
-- Name: TABLE inscripciones; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.inscripciones TO gestudio_app;


--
-- Name: SEQUENCE inscripciones_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.inscripciones_id_seq TO gestudio_app;


--
-- Name: TABLE jere_platform_student_export_pages; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.jere_platform_student_export_pages TO gestudio_app;


--
-- Name: TABLE jere_platform_student_export_snapshots; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.jere_platform_student_export_snapshots TO gestudio_app;


--
-- Name: TABLE jere_platform_tenant_mappings; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.jere_platform_tenant_mappings TO gestudio_app;


--
-- Name: TABLE matriculas; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.matriculas TO gestudio_app;


--
-- Name: SEQUENCE matriculas_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.matriculas_id_seq TO gestudio_app;


--
-- Name: TABLE mensualidades; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.mensualidades TO gestudio_app;


--
-- Name: SEQUENCE mensualidades_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.mensualidades_id_seq TO gestudio_app;


--
-- Name: TABLE metodo_pagos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.metodo_pagos TO gestudio_app;


--
-- Name: SEQUENCE metodo_pagos_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.metodo_pagos_id_seq TO gestudio_app;


--
-- Name: TABLE movimientos_caja; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.movimientos_caja TO gestudio_app;


--
-- Name: SEQUENCE movimientos_caja_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.movimientos_caja_id_seq TO gestudio_app;


--
-- Name: TABLE movimientos_credito; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.movimientos_credito TO gestudio_app;


--
-- Name: SEQUENCE movimientos_credito_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.movimientos_credito_id_seq TO gestudio_app;


--
-- Name: TABLE movimientos_stock; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.movimientos_stock TO gestudio_app;


--
-- Name: SEQUENCE movimientos_stock_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.movimientos_stock_id_seq TO gestudio_app;


--
-- Name: TABLE notificaciones; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.notificaciones TO gestudio_app;


--
-- Name: SEQUENCE notificaciones_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.notificaciones_id_seq TO gestudio_app;


--
-- Name: TABLE observaciones_profesores; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.observaciones_profesores TO gestudio_app;


--
-- Name: SEQUENCE observaciones_profesores_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.observaciones_profesores_id_seq TO gestudio_app;


--
-- Name: TABLE pagos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.pagos TO gestudio_app;


--
-- Name: SEQUENCE pagos_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.pagos_id_seq TO gestudio_app;


--
-- Name: TABLE permisos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.permisos TO gestudio_app;
GRANT SELECT ON TABLE public.permisos TO gestudio_platform;


--
-- Name: SEQUENCE permisos_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.permisos_id_seq TO gestudio_app;


--
-- Name: TABLE platform_admins; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.platform_admins TO gestudio_app;
GRANT SELECT,INSERT,UPDATE ON TABLE public.platform_admins TO gestudio_platform;
GRANT SELECT ON TABLE public.platform_admins TO gestudio_health;


--
-- Name: TABLE platform_audit_events; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT ON TABLE public.platform_audit_events TO gestudio_platform;


--
-- Name: SEQUENCE platform_audit_events_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.platform_audit_events_id_seq TO gestudio_platform;


--
-- Name: TABLE platform_idempotency_keys; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.platform_idempotency_keys TO gestudio_platform;


--
-- Name: SEQUENCE platform_idempotency_keys_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.platform_idempotency_keys_id_seq TO gestudio_platform;


--
-- Name: TABLE platform_mfa_credentials; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.platform_mfa_credentials TO gestudio_platform;


--
-- Name: TABLE platform_recovery_codes; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.platform_recovery_codes TO gestudio_platform;


--
-- Name: TABLE platform_refresh_sessions; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.platform_refresh_sessions TO gestudio_platform;


--
-- Name: TABLE platform_step_up_challenges; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.platform_step_up_challenges TO gestudio_platform;


--
-- Name: TABLE profesores; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.profesores TO gestudio_app;


--
-- Name: SEQUENCE profesores_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.profesores_id_seq TO gestudio_app;


--
-- Name: TABLE recargos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.recargos TO gestudio_app;


--
-- Name: SEQUENCE recargos_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.recargos_id_seq TO gestudio_app;


--
-- Name: TABLE recibos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.recibos TO gestudio_app;


--
-- Name: SEQUENCE recibos_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.recibos_id_seq TO gestudio_app;


--
-- Name: TABLE recibos_pendientes; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.recibos_pendientes TO gestudio_app;


--
-- Name: SEQUENCE recibos_pendientes_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.recibos_pendientes_id_seq TO gestudio_app;


--
-- Name: TABLE refresh_sessions; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.refresh_sessions TO gestudio_app;


--
-- Name: TABLE rol_permisos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.rol_permisos TO gestudio_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.rol_permisos TO gestudio_platform;


--
-- Name: TABLE roles; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.roles TO gestudio_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.roles TO gestudio_platform;


--
-- Name: SEQUENCE roles_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.roles_id_seq TO gestudio_app;
GRANT SELECT,USAGE ON SEQUENCE public.roles_id_seq TO gestudio_platform;


--
-- Name: TABLE salones; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.salones TO gestudio_app;


--
-- Name: SEQUENCE salones_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.salones_id_seq TO gestudio_app;


--
-- Name: TABLE stocks; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.stocks TO gestudio_app;


--
-- Name: SEQUENCE stocks_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.stocks_id_seq TO gestudio_app;


--
-- Name: TABLE sub_conceptos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.sub_conceptos TO gestudio_app;


--
-- Name: SEQUENCE sub_conceptos_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.sub_conceptos_id_seq TO gestudio_app;


--
-- Name: TABLE tenant_membership_roles; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.tenant_membership_roles TO gestudio_app;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.tenant_membership_roles TO gestudio_platform;


--
-- Name: TABLE tenant_memberships; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.tenant_memberships TO gestudio_app;
GRANT SELECT ON TABLE public.tenant_memberships TO gestudio_health;
GRANT SELECT,INSERT,UPDATE ON TABLE public.tenant_memberships TO gestudio_platform;


--
-- Name: TABLE tenants; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.tenants TO gestudio_app;
GRANT SELECT ON TABLE public.tenants TO gestudio_health;
GRANT SELECT,INSERT,UPDATE ON TABLE public.tenants TO gestudio_platform;


--
-- Name: TABLE usuario_roles; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.usuario_roles TO gestudio_app;


--
-- Name: TABLE usuarios; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.usuarios TO gestudio_app;
GRANT SELECT ON TABLE public.usuarios TO gestudio_health;
GRANT SELECT,INSERT,UPDATE ON TABLE public.usuarios TO gestudio_platform;


--
-- Name: SEQUENCE usuarios_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.usuarios_id_seq TO gestudio_app;
GRANT SELECT,USAGE ON SEQUENCE public.usuarios_id_seq TO gestudio_platform;


--
-- Name: TABLE v_cuotas_seguimiento; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.v_cuotas_seguimiento TO gestudio_app;


--
-- Name: TABLE v_multitenancy_migration_health; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.v_multitenancy_migration_health TO gestudio_app;
GRANT SELECT ON TABLE public.v_multitenancy_migration_health TO gestudio_platform;


--
-- Name: TABLE ventas_stock; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.ventas_stock TO gestudio_app;


--
-- Name: SEQUENCE ventas_stock_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE public.ventas_stock_id_seq TO gestudio_app;


-- Catálogo de referencia global. No crea roles ni asignaciones funcionales.
INSERT INTO public.permisos (codigo, descripcion, modulo, activo, sistema)
VALUES
    ('PERM_APP_ACCESO', 'Acceso general a la aplicación', 'APP', TRUE, TRUE),
    ('PERM_USUARIOS_ADMIN', 'Administrar usuarios', 'USUARIOS', TRUE, TRUE),
    ('PERM_ROLES_ADMIN', 'Administrar roles y permisos', 'ROLES', TRUE, TRUE),
    ('PERM_AUDITORIA_SEGURIDAD_LEER', 'Consultar auditoría de seguridad', 'AUDITORIA', TRUE, TRUE),
    ('PERM_MENSUALIDADES_GENERAR_MANUAL', 'Generar mensualidades manualmente', 'MENSUALIDADES', TRUE, TRUE),
    ('PERM_PAGOS_REGISTRAR', 'Registrar pagos y cargos', 'PAGOS', TRUE, TRUE),
    ('PERM_PAGOS_ANULAR', 'Anular pagos, mensualidades y matrículas', 'PAGOS', TRUE, TRUE),
    ('PERM_EGRESOS_ADMIN', 'Administrar egresos', 'EGRESOS', TRUE, TRUE),
    ('PERM_STOCK_ADMIN', 'Administrar inventario', 'STOCK', TRUE, TRUE),
    ('PERM_STOCK_VENDER', 'Registrar ventas de inventario', 'STOCK', TRUE, TRUE),
    ('PERM_CREDITOS_ADMIN', 'Administrar créditos de alumnos', 'CREDITOS', TRUE, TRUE),
    ('PERM_CREDITOS_CONSUMIR', 'Consumir crédito de alumnos', 'CREDITOS', TRUE, TRUE),
    ('PERM_TARIFAS_ADMIN', 'Administrar tarifas', 'TARIFAS', TRUE, TRUE),
    ('PERM_TARIFAS_HISTORICAS', 'Administrar vigencias históricas de tarifas y condiciones', 'TARIFAS', TRUE, TRUE),
    ('PERM_CONDICIONES_ECONOMICAS_ADMIN', 'Administrar condiciones económicas', 'CONDICIONES', TRUE, TRUE),
    ('PERM_ALUMNOS_LEER', 'Consultar alumnos', 'ALUMNOS', TRUE, TRUE),
    ('PERM_ALUMNOS_ADMIN', 'Administrar alumnos', 'ALUMNOS', TRUE, TRUE),
    ('PERM_INSCRIPCIONES_LEER', 'Consultar inscripciones y matrículas', 'INSCRIPCIONES', TRUE, TRUE),
    ('PERM_INSCRIPCIONES_ADMIN', 'Administrar inscripciones', 'INSCRIPCIONES', TRUE, TRUE),
    ('PERM_DISCIPLINAS_LEER', 'Consultar disciplinas', 'DISCIPLINAS', TRUE, TRUE),
    ('PERM_DISCIPLINAS_ADMIN', 'Administrar disciplinas', 'DISCIPLINAS', TRUE, TRUE),
    ('PERM_PROFESORES_LEER', 'Consultar profesores', 'PROFESORES', TRUE, TRUE),
    ('PERM_PROFESORES_ADMIN', 'Administrar profesores', 'PROFESORES', TRUE, TRUE),
    ('PERM_ASISTENCIAS_LEER', 'Consultar asistencias', 'ASISTENCIAS', TRUE, TRUE),
    ('PERM_ASISTENCIAS_REGISTRAR', 'Registrar asistencias', 'ASISTENCIAS', TRUE, TRUE),
    ('PERM_PAGOS_LEER', 'Consultar pagos, cargos, mensualidades y recibos', 'PAGOS', TRUE, TRUE),
    ('PERM_CAJA_LEER', 'Consultar caja', 'CAJA', TRUE, TRUE),
    ('PERM_STOCK_LEER', 'Consultar inventario', 'STOCK', TRUE, TRUE),
    ('PERM_REPORTES_LEER', 'Consultar reportes', 'REPORTES', TRUE, TRUE),
    ('PERM_REPORTES_EXPORTAR', 'Exportar reportes', 'REPORTES', TRUE, TRUE),
    ('PERM_CONFIG_LEER', 'Consultar configuración', 'CONFIG', TRUE, TRUE),
    ('PERM_CONFIG_ADMIN', 'Administrar configuración', 'CONFIG', TRUE, TRUE);

-- El owner SECURITY DEFINER carece de LOGIN, ownership de tablas y BYPASSRLS.
ALTER FUNCTION public.gestudio_multitenancy_health() OWNER TO gestudio_health;

-- pg_dump establece row_security=off al comienzo para detectar dumps parciales.
-- El health se ejecuta como gestudio_health sobre tablas con FORCE RLS, por lo
-- que esa sesión debe volver al modo fail-closed normal antes del autochequeo.
SET row_security = on;

DO $$
DECLARE
    populated_table TEXT;
    has_rows BOOLEAN;
BEGIN
    IF (SELECT count(*) FROM public.permisos) <> 32 OR EXISTS (
        SELECT 1
        FROM (VALUES
            ('PERM_APP_ACCESO', 'Acceso general a la aplicación', 'APP'),
            ('PERM_USUARIOS_ADMIN', 'Administrar usuarios', 'USUARIOS'),
            ('PERM_ROLES_ADMIN', 'Administrar roles y permisos', 'ROLES'),
            ('PERM_AUDITORIA_SEGURIDAD_LEER', 'Consultar auditoría de seguridad', 'AUDITORIA'),
            ('PERM_MENSUALIDADES_GENERAR_MANUAL', 'Generar mensualidades manualmente', 'MENSUALIDADES'),
            ('PERM_PAGOS_REGISTRAR', 'Registrar pagos y cargos', 'PAGOS'),
            ('PERM_PAGOS_ANULAR', 'Anular pagos, mensualidades y matrículas', 'PAGOS'),
            ('PERM_EGRESOS_ADMIN', 'Administrar egresos', 'EGRESOS'),
            ('PERM_STOCK_ADMIN', 'Administrar inventario', 'STOCK'),
            ('PERM_STOCK_VENDER', 'Registrar ventas de inventario', 'STOCK'),
            ('PERM_CREDITOS_ADMIN', 'Administrar créditos de alumnos', 'CREDITOS'),
            ('PERM_CREDITOS_CONSUMIR', 'Consumir crédito de alumnos', 'CREDITOS'),
            ('PERM_TARIFAS_ADMIN', 'Administrar tarifas', 'TARIFAS'),
            ('PERM_TARIFAS_HISTORICAS', 'Administrar vigencias históricas de tarifas y condiciones', 'TARIFAS'),
            ('PERM_CONDICIONES_ECONOMICAS_ADMIN', 'Administrar condiciones económicas', 'CONDICIONES'),
            ('PERM_ALUMNOS_LEER', 'Consultar alumnos', 'ALUMNOS'),
            ('PERM_ALUMNOS_ADMIN', 'Administrar alumnos', 'ALUMNOS'),
            ('PERM_INSCRIPCIONES_LEER', 'Consultar inscripciones y matrículas', 'INSCRIPCIONES'),
            ('PERM_INSCRIPCIONES_ADMIN', 'Administrar inscripciones', 'INSCRIPCIONES'),
            ('PERM_DISCIPLINAS_LEER', 'Consultar disciplinas', 'DISCIPLINAS'),
            ('PERM_DISCIPLINAS_ADMIN', 'Administrar disciplinas', 'DISCIPLINAS'),
            ('PERM_PROFESORES_LEER', 'Consultar profesores', 'PROFESORES'),
            ('PERM_PROFESORES_ADMIN', 'Administrar profesores', 'PROFESORES'),
            ('PERM_ASISTENCIAS_LEER', 'Consultar asistencias', 'ASISTENCIAS'),
            ('PERM_ASISTENCIAS_REGISTRAR', 'Registrar asistencias', 'ASISTENCIAS'),
            ('PERM_PAGOS_LEER', 'Consultar pagos, cargos, mensualidades y recibos', 'PAGOS'),
            ('PERM_CAJA_LEER', 'Consultar caja', 'CAJA'),
            ('PERM_STOCK_LEER', 'Consultar inventario', 'STOCK'),
            ('PERM_REPORTES_LEER', 'Consultar reportes', 'REPORTES'),
            ('PERM_REPORTES_EXPORTAR', 'Exportar reportes', 'REPORTES'),
            ('PERM_CONFIG_LEER', 'Consultar configuración', 'CONFIG'),
            ('PERM_CONFIG_ADMIN', 'Administrar configuración', 'CONFIG')
        ) expected(codigo, descripcion, modulo)
        FULL JOIN public.permisos actual USING (codigo)
        WHERE actual.codigo IS NULL
           OR expected.codigo IS NULL
           OR actual.descripcion <> expected.descripcion
           OR actual.modulo <> expected.modulo
           OR NOT actual.activo
           OR NOT actual.sistema
    ) THEN
        RAISE EXCEPTION 'B12 baseline: el catálogo global de permisos no coincide con el canónico';
    END IF;

    FOR populated_table IN
        SELECT c.relname
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relkind IN ('r', 'p')
          AND c.relname NOT IN ('permisos', 'flyway_schema_history')
        ORDER BY c.relname
    LOOP
        EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I)', populated_table)
        INTO has_rows;
        IF has_rows THEN
            RAISE EXCEPTION 'B12 baseline: la tabla % contiene datos funcionales', populated_table;
        END IF;
    END LOOP;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint con
        JOIN pg_catalog.pg_class c ON c.oid = con.conrelid
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND NOT con.convalidated
    ) THEN
        RAISE EXCEPTION 'B12 baseline: existen constraints sin validar';
    END IF;

    IF public.gestudio_multitenancy_health() <> 'GREEN' THEN
        RAISE EXCEPTION 'B12 baseline: health estructural no es GREEN';
    END IF;
END;
$$;
