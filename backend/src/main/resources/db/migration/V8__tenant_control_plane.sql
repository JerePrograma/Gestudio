-- Control plane multitenant de Gestudio.
-- El UUID inicial es estable para que upgrades, restores y verificadores puedan
-- reconciliar el deployment single-tenant previo sin depender de IDs generados.

CREATE TABLE public.tenants (
    id UUID PRIMARY KEY,
    code VARCHAR(50) NOT NULL,
    name VARCHAR(150) NOT NULL,
    status VARCHAR(12) NOT NULL,
    security_version BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_tenants_code UNIQUE (code),
    CONSTRAINT ck_tenants_code CHECK (code ~ '^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$'),
    CONSTRAINT ck_tenants_name CHECK (length(btrim(name)) > 0),
    CONSTRAINT ck_tenants_status CHECK (status IN ('ACTIVE', 'SUSPENDED', 'ARCHIVED')),
    CONSTRAINT ck_tenants_security_version CHECK (security_version >= 0)
);

INSERT INTO public.tenants (id, code, name, status)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'academia-inicial',
    'Academia inicial',
    'ACTIVE'
);

CREATE TABLE public.tenant_memberships (
    id UUID PRIMARY KEY,
    tenant_id UUID NOT NULL,
    usuario_id BIGINT NOT NULL,
    status VARCHAR(12) NOT NULL,
    security_version BIGINT NOT NULL DEFAULT 0,
    valid_from TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_tenant_memberships_tenant_user UNIQUE (tenant_id, usuario_id),
    CONSTRAINT uq_tenant_memberships_tenant_id UNIQUE (tenant_id, id),
    CONSTRAINT ck_tenant_memberships_status CHECK (status IN ('ACTIVE', 'SUSPENDED', 'REVOKED')),
    CONSTRAINT ck_tenant_memberships_security_version CHECK (security_version >= 0),
    CONSTRAINT ck_tenant_memberships_validity CHECK (valid_until IS NULL OR valid_until > valid_from),
    CONSTRAINT fk_tenant_memberships_tenant FOREIGN KEY (tenant_id)
        REFERENCES public.tenants(id) ON DELETE RESTRICT,
    CONSTRAINT fk_tenant_memberships_usuario FOREIGN KEY (usuario_id)
        REFERENCES public.usuarios(id) ON DELETE RESTRICT
);

CREATE INDEX ix_tenant_memberships_user_status
    ON public.tenant_memberships (usuario_id, status, tenant_id);
CREATE INDEX ix_tenant_memberships_tenant_status
    ON public.tenant_memberships (tenant_id, status, usuario_id);

-- UUID v5 determinista, calculado en SQL sólo con primitivas built-in. La
-- identidad es estable por usuario y tenant, sin requerir extensiones.
INSERT INTO public.tenant_memberships (
    id, tenant_id, usuario_id, status, security_version, valid_from)
SELECT (
           substr(md5('gestudio-membership:' || u.id), 1, 8) || '-' ||
           substr(md5('gestudio-membership:' || u.id), 9, 4) || '-5' ||
           substr(md5('gestudio-membership:' || u.id), 14, 3) || '-a' ||
           substr(md5('gestudio-membership:' || u.id), 18, 3) || '-' ||
           substr(md5('gestudio-membership:' || u.id), 21, 12)
       )::uuid,
       '00000000-0000-0000-0000-000000000001',
       u.id,
       CASE WHEN u.activo THEN 'ACTIVE' ELSE 'REVOKED' END,
       0,
       COALESCE(u.password_changed_at, CURRENT_TIMESTAMP)
FROM public.usuarios u;

CREATE TABLE public.tenant_membership_roles (
    membership_id UUID NOT NULL,
    tenant_id UUID NOT NULL,
    role_id BIGINT NOT NULL,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    assigned_by_usuario_id BIGINT,
    CONSTRAINT pk_tenant_membership_roles PRIMARY KEY (membership_id, role_id, tenant_id),
    CONSTRAINT uq_tenant_membership_roles_membership_role UNIQUE (membership_id, role_id),
    CONSTRAINT fk_tenant_membership_roles_membership FOREIGN KEY (tenant_id, membership_id)
        REFERENCES public.tenant_memberships(tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT fk_tenant_membership_roles_role FOREIGN KEY (role_id)
        REFERENCES public.roles(id) ON DELETE RESTRICT,
    CONSTRAINT fk_tenant_membership_roles_assigned_by FOREIGN KEY (assigned_by_usuario_id)
        REFERENCES public.usuarios(id) ON DELETE SET NULL
);

CREATE INDEX ix_tenant_membership_roles_tenant_role
    ON public.tenant_membership_roles (tenant_id, role_id, membership_id);

INSERT INTO public.tenant_membership_roles (
    membership_id, tenant_id, role_id, assigned_at, assigned_by_usuario_id)
SELECT m.id, m.tenant_id, assigned.role_id, assigned.assigned_at, assigned.assigned_by_usuario_id
FROM public.tenant_memberships m
JOIN (
    SELECT ur.usuario_id, ur.rol_id AS role_id, ur.asignado_at AS assigned_at,
           ur.asignado_por_usuario_id AS assigned_by_usuario_id
    FROM public.usuario_roles ur
    UNION
    SELECT u.id, u.rol_id, CURRENT_TIMESTAMP, NULL::BIGINT
    FROM public.usuarios u
) assigned ON assigned.usuario_id = m.usuario_id
ON CONFLICT (membership_id, role_id) DO NOTHING;

-- Capacidad global explícita. SUPERADMIN continúa siendo un rol local; sólo
-- esta tabla autoriza el control plane y no concede acceso implícito a filas.
CREATE TABLE public.platform_admins (
    usuario_id BIGINT PRIMARY KEY,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    granted_by_usuario_id BIGINT,
    revoked_at TIMESTAMPTZ,
    CONSTRAINT ck_platform_admin_state CHECK (
        (active AND revoked_at IS NULL) OR (NOT active AND revoked_at IS NOT NULL)
    ),
    CONSTRAINT fk_platform_admin_usuario FOREIGN KEY (usuario_id)
        REFERENCES public.usuarios(id) ON DELETE RESTRICT,
    CONSTRAINT fk_platform_admin_granted_by FOREIGN KEY (granted_by_usuario_id)
        REFERENCES public.usuarios(id) ON DELETE RESTRICT
);

INSERT INTO public.platform_admins (usuario_id)
SELECT u.id
FROM public.usuarios u
WHERE u.activo
  AND (
      EXISTS (
          SELECT 1
          FROM public.roles r
          WHERE r.id = u.rol_id
            AND r.codigo = 'SUPERADMIN'
      )
      OR EXISTS (
          SELECT 1
          FROM public.usuario_roles ur
          JOIN public.roles r ON r.id = ur.rol_id
          WHERE ur.usuario_id = u.id
            AND r.codigo = 'SUPERADMIN'
      )
  );

-- El mapping externo queda versionado e inmutable. signing_key_ref es sólo un
-- identificador de configuración; jamás almacena material criptográfico.
CREATE TABLE public.jere_platform_tenant_mappings (
    id UUID PRIMARY KEY,
    internal_tenant_id UUID NOT NULL,
    external_organization_id VARCHAR(100) NOT NULL,
    external_tenant_id UUID NOT NULL,
    source_type VARCHAR(50) NOT NULL,
    config_version BIGINT NOT NULL,
    signing_key_ref VARCHAR(150) NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deactivated_at TIMESTAMPTZ,
    created_by_usuario_id BIGINT,
    CONSTRAINT uq_jere_mapping_tenant_source_version
        UNIQUE (internal_tenant_id, source_type, config_version),
    CONSTRAINT uq_jere_mapping_tenant_id UNIQUE (internal_tenant_id, id),
    CONSTRAINT uq_jere_mapping_effective_identity UNIQUE (
        internal_tenant_id, id, external_organization_id, external_tenant_id,
        source_type, config_version, signing_key_ref
    ),
    CONSTRAINT ck_jere_mapping_organization CHECK (length(btrim(external_organization_id)) > 0),
    CONSTRAINT ck_jere_mapping_source_type CHECK (source_type ~ '^[A-Z][A-Z0-9_]{2,49}$'),
    CONSTRAINT ck_jere_mapping_version CHECK (config_version > 0),
    CONSTRAINT ck_jere_mapping_signing_ref CHECK (length(btrim(signing_key_ref)) > 0),
    CONSTRAINT ck_jere_mapping_state CHECK (
        (active AND deactivated_at IS NULL) OR (NOT active AND deactivated_at IS NOT NULL)
    ),
    CONSTRAINT fk_jere_mapping_tenant FOREIGN KEY (internal_tenant_id)
        REFERENCES public.tenants(id) ON DELETE RESTRICT,
    CONSTRAINT fk_jere_mapping_created_by FOREIGN KEY (created_by_usuario_id)
        REFERENCES public.usuarios(id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_jere_mapping_active
    ON public.jere_platform_tenant_mappings (internal_tenant_id, source_type)
    WHERE active;

CREATE FUNCTION public.rechazar_mutacion_jere_mapping()
RETURNS trigger
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

CREATE TRIGGER trg_jere_mapping_inmutable
    BEFORE UPDATE OR DELETE ON public.jere_platform_tenant_mappings
    FOR EACH ROW EXECUTE FUNCTION public.rechazar_mutacion_jere_mapping();

-- V7 no versionaba cambios de mapping. Más de una combinación histórica no
-- puede normalizarse sin decisión humana, por lo que el upgrade falla seguro.
DO $$
BEGIN
    IF (
        SELECT count(*)
        FROM (
            SELECT DISTINCT organization_id, tenant_id
            FROM public.jere_platform_student_export_snapshots
        ) mappings
    ) > 1 THEN
        RAISE EXCEPTION
            'V8 multitenancy: snapshots V7 contienen mappings externos ambiguos; reconcílielos antes del upgrade';
    END IF;
END;
$$;

INSERT INTO public.jere_platform_tenant_mappings (
    id, internal_tenant_id, external_organization_id, external_tenant_id,
    source_type, config_version, signing_key_ref, active)
SELECT '00000000-0000-0000-0000-000000000101',
       '00000000-0000-0000-0000-000000000001',
       s.organization_id,
       s.tenant_id,
       'GESTUDIO_STUDENT',
       1,
       'deployment-env-v7',
       TRUE
FROM public.jere_platform_student_export_snapshots s
GROUP BY s.organization_id, s.tenant_id;

-- Las sesiones existentes se atan al tenant y membership iniciales antes de
-- volver obligatorias las columnas. Una identidad inactiva ya posee membership
-- REVOKED, por lo que sus refresh quedan persistidos pero no son autorizables.
ALTER TABLE public.refresh_sessions
    ADD COLUMN tenant_id UUID,
    ADD COLUMN membership_id UUID,
    ADD COLUMN tenant_security_version BIGINT,
    ADD COLUMN membership_security_version BIGINT;

UPDATE public.refresh_sessions rs
SET tenant_id = m.tenant_id,
    membership_id = m.id,
    tenant_security_version = t.security_version,
    membership_security_version = m.security_version
FROM public.tenant_memberships m
JOIN public.tenants t ON t.id = m.tenant_id
WHERE m.usuario_id = rs.usuario_id;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.refresh_sessions
        WHERE tenant_id IS NULL OR membership_id IS NULL
           OR tenant_security_version IS NULL OR membership_security_version IS NULL
    ) THEN
        RAISE EXCEPTION 'V8 multitenancy: existen refresh sessions sin membership reconciliable';
    END IF;
END;
$$;

ALTER TABLE public.refresh_sessions
    ALTER COLUMN tenant_id SET NOT NULL,
    ALTER COLUMN membership_id SET NOT NULL,
    ALTER COLUMN tenant_security_version SET NOT NULL,
    ALTER COLUMN membership_security_version SET NOT NULL,
    ADD CONSTRAINT ck_refresh_tenant_security_version CHECK (tenant_security_version >= 0),
    ADD CONSTRAINT ck_refresh_membership_security_version CHECK (membership_security_version >= 0),
    ADD CONSTRAINT uq_refresh_tenant_id UNIQUE (tenant_id, id),
    ADD CONSTRAINT fk_refresh_tenant FOREIGN KEY (tenant_id)
        REFERENCES public.tenants(id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_refresh_membership FOREIGN KEY (tenant_id, membership_id)
        REFERENCES public.tenant_memberships(tenant_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_refresh_reemplazo_tenant FOREIGN KEY (tenant_id, replaced_by_id)
        REFERENCES public.refresh_sessions(tenant_id, id) ON DELETE RESTRICT;

CREATE INDEX ix_refresh_membership_active
    ON public.refresh_sessions (tenant_id, membership_id, expires_at)
    WHERE revoked_at IS NULL;

-- Auditoría admite NULL sólo para autenticación/control plane previo a una
-- selección. Los eventos de negocio nuevos deben persistir tenant explícito.
ALTER TABLE public.auditoria_eventos
    ADD COLUMN tenant_id UUID,
    ADD CONSTRAINT fk_auditoria_tenant FOREIGN KEY (tenant_id)
        REFERENCES public.tenants(id) ON DELETE RESTRICT;

CREATE INDEX ix_auditoria_tenant_ocurrido
    ON public.auditoria_eventos (tenant_id, ocurrido_at DESC, id);

DO $$
BEGIN
    IF (SELECT count(*) FROM public.tenant_memberships) <> (SELECT count(*) FROM public.usuarios) THEN
        RAISE EXCEPTION 'V8 multitenancy: no se creó exactamente una membership inicial por usuario';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.tenant_membership_roles tmr
        JOIN public.tenant_memberships tm ON tm.id = tmr.membership_id
        WHERE tm.tenant_id <> tmr.tenant_id
    ) THEN
        RAISE EXCEPTION 'V8 multitenancy: membership roles con tenant inconsistente';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.tenants
        WHERE id = '00000000-0000-0000-0000-000000000001'
          AND code = 'academia-inicial'
          AND status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION 'V8 multitenancy: tenant inicial ausente o inconsistente';
    END IF;
END;
$$;
