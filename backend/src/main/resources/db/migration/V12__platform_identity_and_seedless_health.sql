-- Control plane de plataforma y health compatible con instalaciones sin tenants.
--
-- Esta migracion es estrictamente forward-only. Conserva todas las filas de
-- V1-V11, incluido el tenant historico academia-inicial. Las instalaciones
-- nuevas usan B12 y no ejecutan este archivo.

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.usuarios u
        WHERE NOT EXISTS (
            SELECT 1
            FROM public.tenant_memberships m
            WHERE m.usuario_id = u.id
        )
          AND NOT EXISTS (
            SELECT 1
            FROM public.platform_admins pa
            WHERE pa.usuario_id = u.id
        )
    ) THEN
        RAISE EXCEPTION
            'V12 platform: existen usuarios historicos sin membership ni capacidad platform; reconcilie antes del upgrade';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.platform_admins pa
        LEFT JOIN public.usuarios u ON u.id = pa.usuario_id
        WHERE u.id IS NULL
    ) THEN
        RAISE EXCEPTION
            'V12 platform: existen platform admins sin identidad';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.tenant_membership_roles tmr
        JOIN public.tenant_memberships tm ON tm.id = tmr.membership_id
        JOIN public.roles r ON r.id = tmr.role_id
        WHERE tmr.tenant_id <> tm.tenant_id
           OR tmr.tenant_id <> r.tenant_id
    ) THEN
        RAISE EXCEPTION
            'V12 platform: memberships y roles pertenecen a tenants distintos';
    END IF;
END;
$$;

-- usuarios.rol_id queda solo como compatibilidad legacy. La autorizacion nueva
-- proviene de tenant_membership_roles o platform_admins.
ALTER TABLE public.usuarios
    ALTER COLUMN rol_id DROP NOT NULL;

ALTER TABLE public.platform_admins
    ADD COLUMN security_version BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN mfa_required BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ADD CONSTRAINT ck_platform_admin_security_version CHECK (security_version >= 0);

CREATE TABLE public.platform_refresh_sessions (
    id UUID PRIMARY KEY,
    family_id UUID NOT NULL,
    usuario_id BIGINT NOT NULL,
    session_scope VARCHAR(10) NOT NULL DEFAULT 'PLATFORM',
    token_hash CHAR(64) NOT NULL,
    auth_version BIGINT NOT NULL,
    platform_security_version BIGINT NOT NULL,
    mfa_verified_at TIMESTAMPTZ NOT NULL,
    issued_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    family_expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    revoke_reason VARCHAR(100),
    replaced_by_id UUID,
    user_agent_hash CHAR(64),
    ip_hash CHAR(64),
    CONSTRAINT uq_platform_refresh_token_hash UNIQUE (token_hash),
    CONSTRAINT uq_platform_refresh_user_id UNIQUE (usuario_id, id),
    CONSTRAINT ck_platform_refresh_scope CHECK (session_scope = 'PLATFORM'),
    CONSTRAINT ck_platform_refresh_versions CHECK (
        auth_version >= 0 AND platform_security_version >= 0
    ),
    CONSTRAINT ck_platform_refresh_times CHECK (
        expires_at > issued_at
        AND family_expires_at >= expires_at
        AND family_expires_at > issued_at
        AND mfa_verified_at <= issued_at
        AND (used_at IS NULL OR used_at >= issued_at)
        AND (revoked_at IS NULL OR revoked_at >= issued_at)
    ),
    CONSTRAINT fk_platform_refresh_usuario FOREIGN KEY (usuario_id)
        REFERENCES public.usuarios(id) ON DELETE RESTRICT,
    CONSTRAINT fk_platform_refresh_admin FOREIGN KEY (usuario_id)
        REFERENCES public.platform_admins(usuario_id) ON DELETE RESTRICT,
    CONSTRAINT fk_platform_refresh_replacement FOREIGN KEY (replaced_by_id)
        REFERENCES public.platform_refresh_sessions(id) ON DELETE RESTRICT
);

CREATE INDEX ix_platform_refresh_user_active
    ON public.platform_refresh_sessions (usuario_id, expires_at)
    WHERE revoked_at IS NULL;
CREATE INDEX ix_platform_refresh_family
    ON public.platform_refresh_sessions (family_id, issued_at);
CREATE INDEX ix_platform_refresh_replacement
    ON public.platform_refresh_sessions (replaced_by_id);

CREATE TABLE public.platform_mfa_credentials (
    id UUID PRIMARY KEY,
    usuario_id BIGINT NOT NULL,
    method VARCHAR(10) NOT NULL DEFAULT 'TOTP',
    secret_ciphertext BYTEA NOT NULL,
    key_version SMALLINT NOT NULL,
    last_counter BIGINT,
    failed_attempts SMALLINT NOT NULL DEFAULT 0,
    failure_window_started_at TIMESTAMPTZ,
    blocked_until TIMESTAMPTZ,
    verified_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_used_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    CONSTRAINT ck_platform_mfa_method CHECK (method = 'TOTP'),
    CONSTRAINT ck_platform_mfa_key_version CHECK (key_version > 0),
    CONSTRAINT ck_platform_mfa_counter CHECK (last_counter IS NULL OR last_counter >= 0),
    CONSTRAINT ck_platform_mfa_attempts CHECK (failed_attempts BETWEEN 0 AND 5),
    CONSTRAINT ck_platform_mfa_failure_window CHECK (
        (failed_attempts = 0 AND failure_window_started_at IS NULL)
        OR (failed_attempts > 0 AND failure_window_started_at IS NOT NULL)
    ),
    CONSTRAINT ck_platform_mfa_block CHECK (
        blocked_until IS NULL
        OR (failure_window_started_at IS NOT NULL AND blocked_until > failure_window_started_at)
    ),
    CONSTRAINT ck_platform_mfa_times CHECK (
        (verified_at IS NULL OR verified_at >= created_at)
        AND (last_used_at IS NULL OR last_used_at >= created_at)
        AND (revoked_at IS NULL OR revoked_at >= created_at)
    ),
    CONSTRAINT fk_platform_mfa_admin FOREIGN KEY (usuario_id)
        REFERENCES public.platform_admins(usuario_id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_platform_mfa_user_active
    ON public.platform_mfa_credentials (usuario_id)
    WHERE revoked_at IS NULL;
CREATE INDEX ix_platform_mfa_user
    ON public.platform_mfa_credentials (usuario_id);
CREATE INDEX ix_platform_mfa_blocked
    ON public.platform_mfa_credentials (blocked_until)
    WHERE blocked_until IS NOT NULL;

CREATE TABLE public.platform_recovery_codes (
    id UUID PRIMARY KEY,
    credential_id UUID NOT NULL,
    code_hash CHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    used_at TIMESTAMPTZ,
    CONSTRAINT uq_platform_recovery_code_hash UNIQUE (code_hash),
    CONSTRAINT ck_platform_recovery_times CHECK (used_at IS NULL OR used_at >= created_at),
    CONSTRAINT fk_platform_recovery_credential FOREIGN KEY (credential_id)
        REFERENCES public.platform_mfa_credentials(id) ON DELETE RESTRICT
);

CREATE INDEX ix_platform_recovery_active
    ON public.platform_recovery_codes (credential_id, id)
    WHERE used_at IS NULL;
CREATE INDEX ix_platform_recovery_credential
    ON public.platform_recovery_codes (credential_id);

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

CREATE TABLE public.platform_step_up_challenges (
    id UUID PRIMARY KEY,
    usuario_id BIGINT NOT NULL,
    session_id UUID NOT NULL,
    action VARCHAR(100) NOT NULL,
    target_type VARCHAR(100),
    target_id VARCHAR(100),
    idempotency_key VARCHAR(150) NOT NULL,
    correlation_id UUID NOT NULL,
    mfa_method VARCHAR(10) NOT NULL,
    proof_hash CHAR(64),
    issued_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    verified_at TIMESTAMPTZ,
    consumed_at TIMESTAMPTZ,
    CONSTRAINT uq_platform_step_up_proof UNIQUE (proof_hash),
    CONSTRAINT uq_platform_step_up_binding UNIQUE NULLS NOT DISTINCT (
        session_id, action, target_type, target_id, idempotency_key
    ),
    CONSTRAINT ck_platform_step_up_method CHECK (mfa_method = 'TOTP'),
    CONSTRAINT ck_platform_step_up_window CHECK (expires_at > issued_at),
    CONSTRAINT ck_platform_step_up_verification CHECK (
        (proof_hash IS NULL AND verified_at IS NULL)
        OR (
            proof_hash IS NOT NULL
            AND verified_at IS NOT NULL
            AND verified_at >= issued_at
            AND verified_at <= expires_at
        )
    ),
    CONSTRAINT ck_platform_step_up_consumption CHECK (
        consumed_at IS NULL
        OR (
            verified_at IS NOT NULL
            AND consumed_at >= verified_at
            AND consumed_at <= expires_at
        )
    ),
    CONSTRAINT fk_platform_step_up_admin FOREIGN KEY (usuario_id)
        REFERENCES public.platform_admins(usuario_id) ON DELETE RESTRICT,
    CONSTRAINT fk_platform_step_up_session FOREIGN KEY (usuario_id, session_id)
        REFERENCES public.platform_refresh_sessions(usuario_id, id) ON DELETE RESTRICT
);

CREATE INDEX ix_platform_step_up_expiry
    ON public.platform_step_up_challenges (expires_at)
    WHERE consumed_at IS NULL;
CREATE INDEX ix_platform_step_up_user
    ON public.platform_step_up_challenges (usuario_id, issued_at DESC);
CREATE INDEX ix_platform_step_up_session
    ON public.platform_step_up_challenges (usuario_id, session_id);

CREATE TABLE public.platform_idempotency_keys (
    id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    operation VARCHAR(100) NOT NULL,
    idempotency_key VARCHAR(150) NOT NULL,
    actor_usuario_id BIGINT NOT NULL,
    request_hash CHAR(64) NOT NULL,
    status VARCHAR(12) NOT NULL,
    resource_type VARCHAR(100),
    resource_id VARCHAR(100),
    response_status SMALLINT,
    result_reference JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,
    CONSTRAINT uq_platform_idempotency_operation_key UNIQUE (operation, idempotency_key),
    CONSTRAINT ck_platform_idempotency_status CHECK (status IN ('PENDING', 'SUCCEEDED', 'FAILED')),
    CONSTRAINT ck_platform_idempotency_response CHECK (
        response_status IS NULL OR response_status BETWEEN 100 AND 599
    ),
    CONSTRAINT ck_platform_idempotency_state CHECK (
        (status = 'PENDING' AND completed_at IS NULL AND response_status IS NULL)
        OR (status IN ('SUCCEEDED', 'FAILED') AND completed_at IS NOT NULL AND response_status IS NOT NULL)
    ),
    CONSTRAINT ck_platform_idempotency_times CHECK (
        updated_at >= created_at AND (completed_at IS NULL OR completed_at >= created_at)
    ),
    CONSTRAINT fk_platform_idempotency_admin FOREIGN KEY (actor_usuario_id)
        REFERENCES public.platform_admins(usuario_id) ON DELETE RESTRICT
);

CREATE INDEX ix_platform_idempotency_actor_created
    ON public.platform_idempotency_keys (actor_usuario_id, created_at DESC);
CREATE INDEX ix_platform_idempotency_pending
    ON public.platform_idempotency_keys (created_at)
    WHERE status = 'PENDING';

CREATE TABLE public.platform_audit_events (
    id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    actor_usuario_id BIGINT,
    actor_username_snapshot VARCHAR(100),
    actor_type VARCHAR(12) NOT NULL,
    session_scope VARCHAR(10),
    mfa_method VARCHAR(10),
    step_up BOOLEAN NOT NULL DEFAULT FALSE,
    action VARCHAR(100) NOT NULL,
    target_type VARCHAR(100),
    target_id VARCHAR(100),
    target_tenant_id UUID,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    correlation_id UUID NOT NULL,
    idempotency_key VARCHAR(150),
    result VARCHAR(10) NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT ck_platform_audit_actor_type CHECK (
        actor_type IN ('PLATFORM', 'TENANT', 'SYSTEM', 'BOOTSTRAP')
    ),
    CONSTRAINT ck_platform_audit_scope CHECK (
        (actor_type IN ('SYSTEM', 'BOOTSTRAP') AND session_scope IS NULL)
        OR (actor_type = 'PLATFORM' AND session_scope = 'PLATFORM')
        OR (actor_type = 'TENANT' AND session_scope = 'TENANT')
    ),
    CONSTRAINT ck_platform_audit_mfa CHECK (
        mfa_method IS NULL OR mfa_method = 'TOTP'
    ),
    CONSTRAINT ck_platform_audit_result CHECK (result IN ('SUCCESS', 'DENIED', 'FAILED')),
    CONSTRAINT fk_platform_audit_actor FOREIGN KEY (actor_usuario_id)
        REFERENCES public.usuarios(id) ON DELETE RESTRICT,
    CONSTRAINT fk_platform_audit_tenant FOREIGN KEY (target_tenant_id)
        REFERENCES public.tenants(id) ON DELETE RESTRICT
);

CREATE INDEX ix_platform_audit_correlation
    ON public.platform_audit_events (correlation_id);
CREATE INDEX ix_platform_audit_actor_time
    ON public.platform_audit_events (actor_usuario_id, occurred_at DESC);
CREATE INDEX ix_platform_audit_tenant_time
    ON public.platform_audit_events (target_tenant_id, occurred_at DESC);
CREATE INDEX ix_platform_audit_target_time
    ON public.platform_audit_events (target_type, target_id, occurred_at DESC);

CREATE FUNCTION public.rechazar_mutacion_platform_audit()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
    RAISE EXCEPTION 'platform_audit_events es append-only' USING ERRCODE = '55000';
END;
$$;

CREATE TRIGGER trg_platform_audit_append_only
    BEFORE UPDATE OR DELETE ON public.platform_audit_events
    FOR EACH ROW EXECUTE FUNCTION public.rechazar_mutacion_platform_audit();

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'gestudio_platform') THEN
        EXECUTE 'CREATE ROLE gestudio_platform NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles
        WHERE rolname IN ('gestudio_app', 'gestudio_health', 'gestudio_platform')
          AND (
              rolsuper OR rolcreaterole OR rolcreatedb OR rolcanlogin
              OR rolinherit OR rolreplication OR rolbypassrls
          )
    ) THEN
        RAISE EXCEPTION 'V12 platform: un rol tecnico posee atributos inseguros';
    END IF;
EXCEPTION
    WHEN insufficient_privilege THEN
        RAISE EXCEPTION
            'V12 platform requiere que Flyway pueda crear/verificar gestudio_platform NOLOGIN';
END;
$$;

GRANT USAGE ON SCHEMA public TO gestudio_platform;
GRANT SELECT, INSERT, UPDATE ON
    public.usuarios,
    public.tenants,
    public.tenant_memberships,
    public.platform_admins,
    public.bootstrap_ejecuciones,
    public.platform_refresh_sessions,
    public.platform_mfa_credentials,
    public.platform_recovery_codes,
    public.platform_identity_activations,
    public.platform_step_up_challenges,
    public.platform_idempotency_keys
TO gestudio_platform;
GRANT SELECT ON public.permisos TO gestudio_platform;
GRANT SELECT, INSERT, UPDATE, DELETE ON
    public.roles,
    public.rol_permisos,
    public.tenant_membership_roles
TO gestudio_platform;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tenant_membership_roles TO gestudio_app;
GRANT SELECT, INSERT ON public.platform_audit_events TO gestudio_platform;
GRANT USAGE, SELECT ON SEQUENCE public.usuarios_id_seq TO gestudio_platform;
GRANT USAGE, SELECT ON SEQUENCE public.roles_id_seq TO gestudio_platform;
GRANT USAGE, SELECT ON SEQUENCE public.platform_idempotency_keys_id_seq TO gestudio_platform;
GRANT USAGE, SELECT ON SEQUENCE public.platform_audit_events_id_seq TO gestudio_platform;

GRANT SELECT ON public.platform_admins TO gestudio_health;

-- El runtime tenant deja de poseer DML sobre el control plane. Conserva SELECT
-- minimo para autenticacion y resolucion de sus propias memberships.
REVOKE INSERT, UPDATE ON public.tenants, public.platform_admins FROM gestudio_app;
REVOKE INSERT, UPDATE ON public.bootstrap_ejecuciones FROM gestudio_app;
REVOKE INSERT ON public.usuario_roles FROM gestudio_app;
GRANT SELECT ON public.platform_admins TO gestudio_app;

-- A partir de V12 la ausencia de contexto siempre falla cerrado, incluso para
-- el migrador. Las migraciones futuras deben declarar el tenant de forma
-- explicita cuando escriban objetos tenant-owned.
CREATE OR REPLACE FUNCTION public.gestudio_current_tenant_id()
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
    IF configured IS NOT NULL AND btrim(configured) <> '' THEN
        RETURN configured::UUID;
    END IF;

    RAISE EXCEPTION 'tenant context missing'
        USING ERRCODE = '42501';
END;
$$;

REVOKE ALL ON FUNCTION public.gestudio_current_tenant_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gestudio_current_tenant_id() TO gestudio_app, gestudio_platform;

-- gestudio_platform puede materializar roles y su matriz solo dentro del
-- TenantContext objetivo. No recibe acceso a tablas funcionales.
CREATE POLICY platform_target_tenant ON public.roles TO gestudio_platform
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY platform_target_tenant ON public.rol_permisos TO gestudio_platform
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());

-- La selección de memberships es global sólo porque forma parte del flujo de
-- autenticación previo a elegir tenant. Todo DML queda limitado al target
-- explícito. Las asignaciones de rol ni siquiera se leen sin contexto.
ALTER TABLE public.tenant_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_memberships FORCE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_membership_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_membership_roles FORCE ROW LEVEL SECURITY;

CREATE POLICY membership_global_select ON public.tenant_memberships
    FOR SELECT TO gestudio_app, gestudio_platform, gestudio_health
    USING (TRUE);
CREATE POLICY membership_target_insert ON public.tenant_memberships
    FOR INSERT TO gestudio_app, gestudio_platform
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY membership_target_update ON public.tenant_memberships
    FOR UPDATE TO gestudio_app, gestudio_platform
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());

CREATE POLICY membership_target_select ON public.tenant_membership_roles
    FOR SELECT TO gestudio_app, gestudio_platform
    USING (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY membership_target_insert ON public.tenant_membership_roles
    FOR INSERT TO gestudio_app, gestudio_platform
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY membership_target_update ON public.tenant_membership_roles
    FOR UPDATE TO gestudio_app, gestudio_platform
    USING (tenant_id = public.gestudio_current_tenant_id())
    WITH CHECK (tenant_id = public.gestudio_current_tenant_id());
CREATE POLICY membership_target_delete ON public.tenant_membership_roles
    FOR DELETE TO gestudio_app, gestudio_platform
    USING (tenant_id = public.gestudio_current_tenant_id());

-- Health estructural seedless. Cero tenants y cero identidades es un estado
-- valido. Si existen identidades, solo se exige membership a las que no sean
-- platform-only.
CREATE OR REPLACE FUNCTION public.gestudio_multitenancy_health()
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
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

ALTER FUNCTION public.gestudio_multitenancy_health() OWNER TO gestudio_health;
REVOKE ALL ON FUNCTION public.gestudio_multitenancy_health() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gestudio_multitenancy_health() TO gestudio_app, gestudio_platform;
GRANT SELECT ON public.v_multitenancy_migration_health TO gestudio_platform;

DO $$
DECLARE
    denied_without_context BOOLEAN := FALSE;
BEGIN
    BEGIN
        PERFORM pg_catalog.set_config('app.current_tenant_id', '', TRUE);
        PERFORM public.gestudio_current_tenant_id();
    EXCEPTION
        WHEN insufficient_privilege THEN
            denied_without_context := TRUE;
    END;

    IF NOT denied_without_context THEN
        RAISE EXCEPTION 'V12 platform: contexto tenant ausente no falla cerrado';
    END IF;

    IF public.gestudio_multitenancy_health() <> 'GREEN' THEN
        RAISE EXCEPTION 'V12 platform: health estructural no es GREEN';
    END IF;
END;
$$;
