-- Catálogo RBAC productivo y matriz canónica de roles base.
-- Forward-only: V1-V5 permanecen inmutables. Una corrección posterior debe
-- publicarse como una migración nueva; ante datos incompatibles esta V6 falla
-- antes de reconciliar y exige intervención explícita.

-- ============================================================
-- 1. Precondiciones: no ocultar identidades técnicas ambiguas
-- ============================================================

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.roles WHERE codigo ~ '^ROLE_') THEN
        RAISE EXCEPTION
            'V6 RBAC: existen roles con prefijo reservado ROLE_; corrija esos códigos antes de migrar';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.roles WHERE codigo = 'ADMINISTRADOR') THEN
        RAISE EXCEPTION
            'V6 RBAC: falta el rol legacy ADMINISTRADOR; no se crea automáticamente porque debe preservarse su identidad';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.roles r
        JOIN (VALUES
                  ('SUPERADMIN'),
                  ('DIRECCION'),
                  ('ADMINISTRADOR'),
                  ('SECRETARIA'),
                  ('CAJA'),
                  ('PROFESOR')
             ) AS base(codigo)
          ON upper(btrim(r.descripcion)) = base.codigo
        WHERE r.codigo <> base.codigo
    ) THEN
        RAISE EXCEPTION
            'V6 RBAC: una descripción reservada de rol base pertenece a otro código; reconciliación ambigua';
    END IF;
END;
$$;

ALTER TABLE public.roles
    ADD CONSTRAINT ck_roles_codigo_sin_prefijo_authority
        CHECK (codigo !~ '^ROLE_');

-- ============================================================
-- 2. Catálogo cerrado de 32 permisos
-- ============================================================

CREATE TEMP TABLE _v6_permission_catalog (
    codigo VARCHAR(100) PRIMARY KEY,
    descripcion VARCHAR(255) NOT NULL,
    modulo VARCHAR(50) NOT NULL
) ON COMMIT DROP;

INSERT INTO _v6_permission_catalog (codigo, descripcion, modulo)
VALUES
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
    ('PERM_CONFIG_ADMIN', 'Administrar configuración', 'CONFIG');

DO $$
BEGIN
    IF (SELECT count(*) FROM _v6_permission_catalog) <> 32 THEN
        RAISE EXCEPTION 'V6 RBAC: el catálogo debe contener exactamente 32 permisos únicos';
    END IF;
END;
$$;

-- Captura los usuarios cuyas autoridades pueden cambiar. Incluye roles base
-- y roles personalizados que ya reutilizan un permiso canónico.
CREATE TEMP TABLE _v6_affected_users (
    usuario_id BIGINT PRIMARY KEY
) ON COMMIT DROP;

INSERT INTO _v6_affected_users (usuario_id)
SELECT usuario_id
FROM (
    SELECT u.id AS usuario_id
    FROM public.usuarios u
    JOIN public.roles r ON r.id = u.rol_id
    WHERE r.codigo IN ('SUPERADMIN', 'DIRECCION', 'ADMINISTRADOR', 'SECRETARIA', 'CAJA', 'PROFESOR')

    UNION

    SELECT ur.usuario_id
    FROM public.usuario_roles ur
    JOIN public.roles r ON r.id = ur.rol_id
    WHERE r.codigo IN ('SUPERADMIN', 'DIRECCION', 'ADMINISTRADOR', 'SECRETARIA', 'CAJA', 'PROFESOR')

    UNION

    SELECT u.id
    FROM public.usuarios u
    JOIN public.rol_permisos rp ON rp.rol_id = u.rol_id
    JOIN public.permisos p ON p.id = rp.permiso_id
    JOIN _v6_permission_catalog c ON c.codigo = p.codigo

    UNION

    SELECT ur.usuario_id
    FROM public.usuario_roles ur
    JOIN public.rol_permisos rp ON rp.rol_id = ur.rol_id
    JOIN public.permisos p ON p.id = rp.permiso_id
    JOIN _v6_permission_catalog c ON c.codigo = p.codigo
) afectados;

INSERT INTO public.permisos (codigo, descripcion, modulo, activo, sistema)
SELECT codigo, descripcion, modulo, TRUE, TRUE
FROM _v6_permission_catalog
ON CONFLICT (codigo) DO UPDATE
SET descripcion = EXCLUDED.descripcion,
    modulo = EXCLUDED.modulo,
    activo = TRUE,
    sistema = TRUE;

-- ============================================================
-- 3. Roles base: IDs existentes se preservan
-- ============================================================

UPDATE public.roles
SET descripcion = 'ADMINISTRADOR',
    activo = TRUE,
    nombre = 'Administrador',
    descripcion_funcional = 'Rol legacy compatible con la matriz de Dirección',
    sistema = TRUE,
    editable = TRUE
WHERE codigo = 'ADMINISTRADOR';

INSERT INTO public.roles
    (descripcion, activo, codigo, nombre, descripcion_funcional, sistema, editable)
VALUES
    ('SUPERADMIN', TRUE, 'SUPERADMIN', 'Superadministración',
     'Administración técnica completa del sistema', TRUE, FALSE),
    ('DIRECCION', TRUE, 'DIRECCION', 'Dirección',
     'Dirección operativa y administrativa', TRUE, TRUE),
    ('SECRETARIA', TRUE, 'SECRETARIA', 'Secretaría',
     'Operación académica y cobros de Secretaría', TRUE, TRUE),
    ('CAJA', TRUE, 'CAJA', 'Caja',
     'Consulta y registro de cobros en Caja', TRUE, TRUE),
    ('PROFESOR', FALSE, 'PROFESOR', 'Profesor',
     'Rol diferido hasta implementar ownership por profesor', TRUE, FALSE)
ON CONFLICT (codigo) DO UPDATE
SET descripcion = EXCLUDED.descripcion,
    activo = EXCLUDED.activo,
    nombre = EXCLUDED.nombre,
    descripcion_funcional = EXCLUDED.descripcion_funcional,
    sistema = EXCLUDED.sistema,
    editable = EXCLUDED.editable;

-- ============================================================
-- 4. Matriz exacta de roles base
-- ============================================================

CREATE TEMP TABLE _v6_base_role_matrix (
    rol_codigo VARCHAR(50) NOT NULL,
    permiso_codigo VARCHAR(100) NOT NULL,
    PRIMARY KEY (rol_codigo, permiso_codigo)
) ON COMMIT DROP;

INSERT INTO _v6_base_role_matrix (rol_codigo, permiso_codigo)
SELECT 'SUPERADMIN', codigo
FROM _v6_permission_catalog;

INSERT INTO _v6_base_role_matrix (rol_codigo, permiso_codigo)
SELECT base.rol_codigo, catalogo.codigo
FROM (VALUES ('DIRECCION'), ('ADMINISTRADOR')) AS base(rol_codigo)
CROSS JOIN _v6_permission_catalog catalogo
WHERE catalogo.codigo <> 'PERM_ROLES_ADMIN';

INSERT INTO _v6_base_role_matrix (rol_codigo, permiso_codigo)
VALUES
    ('SECRETARIA', 'PERM_APP_ACCESO'),
    ('SECRETARIA', 'PERM_PAGOS_REGISTRAR'),
    ('SECRETARIA', 'PERM_CREDITOS_CONSUMIR'),
    ('SECRETARIA', 'PERM_CONDICIONES_ECONOMICAS_ADMIN'),
    ('SECRETARIA', 'PERM_ALUMNOS_LEER'),
    ('SECRETARIA', 'PERM_ALUMNOS_ADMIN'),
    ('SECRETARIA', 'PERM_INSCRIPCIONES_LEER'),
    ('SECRETARIA', 'PERM_INSCRIPCIONES_ADMIN'),
    ('SECRETARIA', 'PERM_DISCIPLINAS_LEER'),
    ('SECRETARIA', 'PERM_PROFESORES_LEER'),
    ('SECRETARIA', 'PERM_ASISTENCIAS_LEER'),
    ('SECRETARIA', 'PERM_ASISTENCIAS_REGISTRAR'),
    ('SECRETARIA', 'PERM_PAGOS_LEER'),
    ('SECRETARIA', 'PERM_CAJA_LEER'),
    ('SECRETARIA', 'PERM_STOCK_LEER'),
    ('SECRETARIA', 'PERM_REPORTES_LEER'),
    ('SECRETARIA', 'PERM_CONFIG_LEER'),
    ('CAJA', 'PERM_APP_ACCESO'),
    ('CAJA', 'PERM_ALUMNOS_LEER'),
    ('CAJA', 'PERM_PAGOS_LEER'),
    ('CAJA', 'PERM_PAGOS_REGISTRAR'),
    ('CAJA', 'PERM_CAJA_LEER'),
    ('CAJA', 'PERM_STOCK_LEER'),
    ('CAJA', 'PERM_CONFIG_LEER'),
    ('CAJA', 'PERM_CREDITOS_CONSUMIR');

DELETE FROM public.rol_permisos rp
USING public.roles r
WHERE r.id = rp.rol_id
  AND r.codigo IN ('SUPERADMIN', 'DIRECCION', 'ADMINISTRADOR', 'SECRETARIA', 'CAJA', 'PROFESOR');

INSERT INTO public.rol_permisos (rol_id, permiso_id)
SELECT r.id, p.id
FROM _v6_base_role_matrix matriz
JOIN public.roles r ON r.codigo = matriz.rol_codigo
JOIN public.permisos p ON p.codigo = matriz.permiso_codigo;

-- ============================================================
-- 5. Validación final e invalidación de sesiones afectadas
-- ============================================================

DO $$
BEGIN
    IF (SELECT count(*)
        FROM public.permisos p
        JOIN _v6_permission_catalog c ON c.codigo = p.codigo
        WHERE p.activo AND p.sistema) <> 32 THEN
        RAISE EXCEPTION 'V6 RBAC: el catálogo productivo no quedó activo y de sistema';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM _v6_base_role_matrix esperada
        WHERE NOT EXISTS (
            SELECT 1
            FROM public.rol_permisos rp
            JOIN public.roles r ON r.id = rp.rol_id
            JOIN public.permisos p ON p.id = rp.permiso_id
            WHERE r.codigo = esperada.rol_codigo
              AND p.codigo = esperada.permiso_codigo
        )
    ) OR EXISTS (
        SELECT 1
        FROM public.rol_permisos rp
        JOIN public.roles r ON r.id = rp.rol_id
        JOIN public.permisos p ON p.id = rp.permiso_id
        WHERE r.codigo IN ('SUPERADMIN', 'DIRECCION', 'ADMINISTRADOR', 'SECRETARIA', 'CAJA', 'PROFESOR')
          AND NOT EXISTS (
              SELECT 1
              FROM _v6_base_role_matrix esperada
              WHERE esperada.rol_codigo = r.codigo
                AND esperada.permiso_codigo = p.codigo
          )
    ) THEN
        RAISE EXCEPTION 'V6 RBAC: la matriz de roles base no coincide con el contrato';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.roles
        WHERE (codigo = 'SUPERADMIN' AND (NOT activo OR NOT sistema OR editable))
           OR (codigo IN ('DIRECCION', 'ADMINISTRADOR', 'SECRETARIA', 'CAJA')
               AND (NOT activo OR NOT sistema OR NOT editable))
           OR (codigo = 'PROFESOR' AND (activo OR NOT sistema OR editable))
    ) THEN
        RAISE EXCEPTION 'V6 RBAC: los estados de roles base no coinciden con el contrato';
    END IF;
END;
$$;

UPDATE public.usuarios u
SET auth_version = u.auth_version + 1
FROM _v6_affected_users afectados
WHERE afectados.usuario_id = u.id;
