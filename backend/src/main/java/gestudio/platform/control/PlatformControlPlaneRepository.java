package gestudio.platform.control;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.sql.Array;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.UUID;

@Repository
public class PlatformControlPlaneRepository {
    private static final String PLATFORM_ADMIN_INVARIANT_LOCK_SQL =
            "SELECT pg_advisory_xact_lock(1195725908, 1347174733)";

    private final JdbcTemplate jdbc;

    public PlatformControlPlaneRepository(@Qualifier("platformJdbcTemplate") JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public PageData<TenantView> tenants(String query, String status, int page, int size) {
        String q = normalizedQuery(query);
        String state = blankToNull(status);
        String where = "WHERE (? IS NULL OR lower(t.code) LIKE ? OR lower(t.name) LIKE ?) "
                + "AND (? IS NULL OR t.status = ?)";
        Object[] filters = {q, like(q), like(q), state, state};
        long total = count("SELECT count(*) FROM tenants t " + where, filters);
        List<Object> args = new ArrayList<>(List.of(filters));
        args.add(size);
        args.add(page * size);
        List<TenantView> content = jdbc.query("""
                SELECT t.id, t.code, t.name, t.status, t.security_version, t.created_at,
                       t.updated_at,
                       (SELECT count(*) FROM tenant_memberships m WHERE m.tenant_id = t.id) membership_count,
                       (SELECT count(*) FROM tenant_memberships m
                        WHERE m.tenant_id = t.id AND m.status = 'ACTIVE') active_membership_count,
                       (SELECT count(*) FROM roles r WHERE r.tenant_id = t.id) role_count
                FROM tenants t
                """ + where + " ORDER BY t.created_at DESC, t.id LIMIT ? OFFSET ?",
                PlatformControlPlaneRepository::tenant, args.toArray());
        return page(content, total, page, size);
    }

    public Optional<TenantView> tenant(UUID tenantId) {
        return jdbc.query("""
                SELECT t.id, t.code, t.name, t.status, t.security_version, t.created_at,
                       t.updated_at,
                       (SELECT count(*) FROM tenant_memberships m WHERE m.tenant_id = t.id) membership_count,
                       (SELECT count(*) FROM tenant_memberships m
                        WHERE m.tenant_id = t.id AND m.status = 'ACTIVE') active_membership_count,
                       (SELECT count(*) FROM roles r WHERE r.tenant_id = t.id) role_count
                FROM tenants t WHERE t.id = ?
                """, PlatformControlPlaneRepository::tenant, tenantId).stream().findFirst();
    }

    public void insertTenant(UUID tenantId, String code, String name, Instant now) {
        jdbc.update("""
                INSERT INTO tenants(id, code, name, status, security_version, created_at, updated_at)
                VALUES (?, ?, ?, 'ACTIVE', 0, ?, ?)
                """, tenantId, code, name, Timestamp.from(now), Timestamp.from(now));
    }

    public boolean updateTenantName(UUID tenantId, String name, long expectedVersion, Instant now) {
        return jdbc.update("""
                UPDATE tenants
                SET name = ?, security_version = security_version + 1, updated_at = ?
                WHERE id = ? AND security_version = ?
                """, name, Timestamp.from(now), tenantId, expectedVersion) == 1;
    }

    public boolean updateTenantStatus(UUID tenantId, String status, long expectedVersion, Instant now) {
        return jdbc.update("""
                UPDATE tenants
                SET status = ?, security_version = security_version + 1, updated_at = ?
                WHERE id = ? AND security_version = ?
                """, status, Timestamp.from(now), tenantId, expectedVersion) == 1;
    }

    public long materializeBaseRoles(UUID tenantId) {
        jdbc.batchUpdate("""
                INSERT INTO roles(tenant_id, descripcion, activo, codigo, nombre,
                                  descripcion_funcional, sistema, editable)
                VALUES (?, ?, ?, ?, ?, ?, TRUE, ?)
                """, List.of(
                new Object[]{tenantId, "SUPERADMIN", true, "SUPERADMIN", "Superadministración",
                        "Administración técnica completa dentro del tenant", false},
                new Object[]{tenantId, "DIRECCION", true, "DIRECCION", "Dirección",
                        "Dirección operativa y administrativa", true},
                new Object[]{tenantId, "ADMINISTRADOR", true, "ADMINISTRADOR", "Administrador",
                        "Administración del tenant", true},
                new Object[]{tenantId, "SECRETARIA", true, "SECRETARIA", "Secretaría",
                        "Operación académica y cobros", true},
                new Object[]{tenantId, "CAJA", true, "CAJA", "Caja",
                        "Consulta y registro de cobros", true},
                new Object[]{tenantId, "PROFESOR", false, "PROFESOR", "Profesor",
                        "Rol diferido hasta implementar ownership por profesor", false}
        ));
        jdbc.update("""
                INSERT INTO rol_permisos(tenant_id, rol_id, permiso_id)
                SELECT ?, r.id, p.id
                FROM roles r CROSS JOIN permisos p
                WHERE r.tenant_id = ? AND p.activo
                  AND (
                    r.codigo = 'SUPERADMIN'
                    OR (r.codigo IN ('DIRECCION', 'ADMINISTRADOR') AND p.codigo <> 'PERM_ROLES_ADMIN')
                    OR (r.codigo = 'SECRETARIA' AND p.codigo IN (
                        'PERM_APP_ACCESO','PERM_PAGOS_REGISTRAR','PERM_CREDITOS_CONSUMIR',
                        'PERM_CONDICIONES_ECONOMICAS_ADMIN','PERM_ALUMNOS_LEER','PERM_ALUMNOS_ADMIN',
                        'PERM_INSCRIPCIONES_LEER','PERM_INSCRIPCIONES_ADMIN','PERM_DISCIPLINAS_LEER',
                        'PERM_PROFESORES_LEER','PERM_ASISTENCIAS_LEER','PERM_ASISTENCIAS_REGISTRAR',
                        'PERM_PAGOS_LEER','PERM_CAJA_LEER','PERM_STOCK_LEER','PERM_REPORTES_LEER',
                        'PERM_CONFIG_LEER'))
                    OR (r.codigo = 'CAJA' AND p.codigo IN (
                        'PERM_APP_ACCESO','PERM_ALUMNOS_LEER','PERM_PAGOS_LEER',
                        'PERM_PAGOS_REGISTRAR','PERM_CAJA_LEER','PERM_STOCK_LEER',
                        'PERM_CONFIG_LEER','PERM_CREDITOS_CONSUMIR'))
                  )
                """, tenantId, tenantId);
        return jdbc.queryForObject(
                "SELECT id FROM roles WHERE tenant_id = ? AND codigo = 'ADMINISTRADOR'",
                Long.class, tenantId);
    }

    public Optional<IdentityView> identity(long userId) {
        return jdbc.query("""
                SELECT id, nombre_usuario, activo FROM usuarios WHERE id = ?
                """, PlatformControlPlaneRepository::identity, userId).stream().findFirst();
    }

    public List<IdentityView> identities(String query) {
        String q = normalizedQuery(query);
        return jdbc.query("""
                SELECT id, nombre_usuario, activo FROM usuarios
                WHERE ? IS NULL OR lower(nombre_usuario) LIKE ?
                ORDER BY lower(nombre_usuario), id LIMIT 25
                """, PlatformControlPlaneRepository::identity, q, like(q));
    }

    public long insertInactiveIdentity(String username, String unavailablePasswordHash) {
        Long id = jdbc.queryForObject("""
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo,
                                     auth_version, password_changed_at, version)
                VALUES (?, ?, NULL, FALSE, 0, NULL, 0)
                RETURNING id
                """, Long.class, username, unavailablePasswordHash);
        if (id == null) throw new IllegalStateException("No se pudo crear la identidad");
        return id;
    }

    public void insertActivation(UUID activationId, long userId, String purpose, String tokenHash,
                                 Instant issuedAt, Instant expiresAt, long actorId) {
        jdbc.update("""
                INSERT INTO platform_identity_activations(
                    id, usuario_id, purpose, token_hash, issued_at, expires_at, created_by_usuario_id)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, activationId, userId, purpose, tokenHash,
                Timestamp.from(issuedAt), Timestamp.from(expiresAt), actorId);
    }

    public UUID insertMembership(UUID tenantId, long userId, Instant validUntil, Instant now) {
        UUID id = UUID.randomUUID();
        jdbc.update("""
                INSERT INTO tenant_memberships(
                    id, tenant_id, usuario_id, status, security_version,
                    valid_from, valid_until, created_at, updated_at)
                VALUES (?, ?, ?, 'ACTIVE', 0, ?, ?, ?, ?)
                """, id, tenantId, userId, Timestamp.from(now), sqlTimestamp(validUntil),
                Timestamp.from(now), Timestamp.from(now));
        return id;
    }

    public void assignRoles(UUID tenantId, UUID membershipId, List<String> roleCodes, long actorId) {
        List<RoleView> roles = rolesByCodes(tenantId, roleCodes);
        if (roles.size() != roleCodes.stream().map(code -> code.toUpperCase(Locale.ROOT)).distinct().count()) {
            throw new IllegalArgumentException("Uno o más roles no existen o están inactivos en el tenant");
        }
        jdbc.batchUpdate("""
                INSERT INTO tenant_membership_roles(
                    membership_id, tenant_id, role_id, assigned_by_usuario_id)
                VALUES (?, ?, ?, ?)
                """, roles.stream().map(role -> new Object[]{membershipId, tenantId, role.id(), actorId}).toList());
    }

    public PageData<MembershipView> memberships(UUID tenantId, String query, String status,
                                                 int page, int size) {
        String q = normalizedQuery(query);
        String state = blankToNull(status);
        String where = "WHERE m.tenant_id = ? AND (? IS NULL OR lower(u.nombre_usuario) LIKE ?) "
                + "AND (? IS NULL OR m.status = ?)";
        Object[] filters = {tenantId, q, like(q), state, state};
        long total = count("SELECT count(*) FROM tenant_memberships m JOIN usuarios u ON u.id=m.usuario_id "
                + where, filters);
        List<Object> args = new ArrayList<>(List.of(filters));
        args.add(size);
        args.add(page * size);
        List<MembershipView> content = jdbc.query("""
                SELECT m.id, m.tenant_id, m.usuario_id, u.nombre_usuario, m.status,
                       m.security_version, m.valid_from, m.valid_until,
                       COALESCE(array_agg(r.codigo ORDER BY r.codigo)
                         FILTER (WHERE r.id IS NOT NULL), ARRAY[]::varchar[]) roles
                FROM tenant_memberships m
                JOIN usuarios u ON u.id = m.usuario_id
                LEFT JOIN tenant_membership_roles mr ON mr.membership_id = m.id
                LEFT JOIN roles r ON r.id = mr.role_id AND r.tenant_id = m.tenant_id
                """ + where + " GROUP BY m.id, u.nombre_usuario "
                + "ORDER BY lower(u.nombre_usuario), m.id LIMIT ? OFFSET ?",
                PlatformControlPlaneRepository::membership, args.toArray());
        return page(content, total, page, size);
    }

    public Optional<MembershipView> membership(UUID tenantId, UUID membershipId) {
        return jdbc.query("""
                SELECT m.id, m.tenant_id, m.usuario_id, u.nombre_usuario, m.status,
                       m.security_version, m.valid_from, m.valid_until,
                       COALESCE(array_agg(r.codigo ORDER BY r.codigo)
                         FILTER (WHERE r.id IS NOT NULL), ARRAY[]::varchar[]) roles
                FROM tenant_memberships m
                JOIN usuarios u ON u.id = m.usuario_id
                LEFT JOIN tenant_membership_roles mr ON mr.membership_id = m.id
                LEFT JOIN roles r ON r.id = mr.role_id AND r.tenant_id = m.tenant_id
                WHERE m.tenant_id = ? AND m.id = ?
                GROUP BY m.id, u.nombre_usuario
                """, PlatformControlPlaneRepository::membership, tenantId, membershipId)
                .stream().findFirst();
    }

    public Optional<MembershipView> membershipByUser(UUID tenantId, long userId) {
        UUID id = jdbc.query("SELECT id FROM tenant_memberships WHERE tenant_id = ? AND usuario_id = ?",
                (rs, row) -> (UUID) rs.getObject(1), tenantId, userId).stream().findFirst().orElse(null);
        return id == null ? Optional.empty() : membership(tenantId, id);
    }

    public boolean updateMembershipStatus(UUID tenantId, UUID membershipId, String status,
                                          long expectedVersion, Instant validUntil, Instant now) {
        return jdbc.update("""
                UPDATE tenant_memberships
                SET status = ?, security_version = security_version + 1,
                    valid_until = ?, updated_at = ?
                WHERE tenant_id = ? AND id = ? AND security_version = ?
                """, status, sqlTimestamp(validUntil), Timestamp.from(now), tenantId, membershipId,
                expectedVersion) == 1;
    }

    public boolean bumpMembershipVersion(UUID tenantId, UUID membershipId,
                                         long expectedVersion, Instant now) {
        return jdbc.update("""
                UPDATE tenant_memberships
                SET security_version = security_version + 1, updated_at = ?
                WHERE tenant_id = ? AND id = ? AND security_version = ?
                """, Timestamp.from(now), tenantId, membershipId,
                expectedVersion) == 1;
    }

    public void replaceMembershipRoles(UUID tenantId, UUID membershipId,
                                       List<String> roleCodes, long actorId) {
        jdbc.update("DELETE FROM tenant_membership_roles WHERE tenant_id = ? AND membership_id = ?",
                tenantId, membershipId);
        assignRoles(tenantId, membershipId, roleCodes, actorId);
    }

    public long activeAdministrators(UUID tenantId, UUID excludingMembership) {
        Long value = jdbc.queryForObject("""
                SELECT count(DISTINCT m.id)
                FROM tenant_memberships m
                JOIN tenant_membership_roles mr ON mr.membership_id = m.id AND mr.tenant_id = m.tenant_id
                JOIN roles r ON r.id = mr.role_id AND r.tenant_id = m.tenant_id
                WHERE m.tenant_id = ? AND m.status = 'ACTIVE' AND r.codigo = 'ADMINISTRADOR'
                  AND (? IS NULL OR m.id <> ?)
                """, Long.class, tenantId, excludingMembership, excludingMembership);
        return value == null ? 0 : value;
    }

    public void lockTenantAdministratorInvariant(UUID tenantId) {
        requireActiveTransaction();
        jdbc.queryForObject("SELECT id FROM tenants WHERE id = ? FOR UPDATE",
                (result, row) -> (UUID) result.getObject(1), tenantId);
    }

    public List<RoleView> roles(UUID tenantId) {
        return jdbc.query("""
                SELECT id, codigo, nombre, activo FROM roles
                WHERE tenant_id = ? ORDER BY codigo
                """, PlatformControlPlaneRepository::role, tenantId);
    }

    public PageData<AdminView> admins(String query, String status, int page, int size) {
        String q = normalizedQuery(query);
        String state = blankToNull(status);
        String where = "WHERE (? IS NULL OR lower(u.nombre_usuario) LIKE ?) "
                + "AND (? IS NULL OR (CASE WHEN pa.active THEN 'ACTIVE' ELSE 'REVOKED' END) = ?)";
        Object[] filters = {q, like(q), state, state};
        long total = count("SELECT count(*) FROM platform_admins pa JOIN usuarios u ON u.id=pa.usuario_id "
                + where, filters);
        List<Object> args = new ArrayList<>(List.of(filters));
        args.add(size);
        args.add(page * size);
        List<AdminView> content = jdbc.query("""
                SELECT pa.usuario_id, u.nombre_usuario, pa.active, pa.security_version,
                       pa.granted_at, pa.revoked_at,
                       EXISTS(SELECT 1 FROM platform_mfa_credentials mc
                              WHERE mc.usuario_id=pa.usuario_id AND mc.verified_at IS NOT NULL
                                AND mc.revoked_at IS NULL) mfa_enabled
                FROM platform_admins pa JOIN usuarios u ON u.id=pa.usuario_id
                """ + where + " ORDER BY pa.granted_at DESC, pa.usuario_id LIMIT ? OFFSET ?",
                PlatformControlPlaneRepository::admin, args.toArray());
        return page(content, total, page, size);
    }

    public Optional<AdminView> admin(long userId) {
        return jdbc.query("""
                SELECT pa.usuario_id, u.nombre_usuario, pa.active, pa.security_version,
                       pa.granted_at, pa.revoked_at,
                       EXISTS(SELECT 1 FROM platform_mfa_credentials mc
                              WHERE mc.usuario_id=pa.usuario_id AND mc.verified_at IS NOT NULL
                                AND mc.revoked_at IS NULL) mfa_enabled
                FROM platform_admins pa JOIN usuarios u ON u.id=pa.usuario_id
                WHERE pa.usuario_id = ?
                """, PlatformControlPlaneRepository::admin, userId).stream().findFirst();
    }

    public void grantAdmin(long userId, long actorId, Instant now, boolean active) {
        jdbc.update("""
                INSERT INTO platform_admins(usuario_id, active, granted_at, granted_by_usuario_id,
                    revoked_at, security_version, mfa_required, updated_at)
                VALUES (?, ?, ?, ?, CASE WHEN ? THEN NULL ELSE ? END, 0, TRUE, ?)
                ON CONFLICT (usuario_id) DO UPDATE
                SET active=EXCLUDED.active, granted_at=EXCLUDED.granted_at,
                    granted_by_usuario_id=EXCLUDED.granted_by_usuario_id, revoked_at=EXCLUDED.revoked_at,
                    security_version=platform_admins.security_version+1, updated_at=EXCLUDED.updated_at
                """, userId, active, Timestamp.from(now), actorId, active,
                Timestamp.from(now), Timestamp.from(now));
    }

    public boolean changeAdminStatus(long userId, boolean active, long expectedVersion, Instant now) {
        return jdbc.update("""
                UPDATE platform_admins
                SET active = ?, revoked_at = CASE WHEN ? THEN NULL ELSE ? END,
                    security_version = security_version + 1, updated_at = ?
                WHERE usuario_id = ? AND security_version = ?
                """, active, active, Timestamp.from(now), Timestamp.from(now), userId,
                expectedVersion) == 1;
    }

    public void revokeAdminSessions(long userId, Instant now, String reason) {
        jdbc.update("""
                UPDATE platform_refresh_sessions
                SET revoked_at = COALESCE(revoked_at, ?), revoke_reason = ?
                WHERE usuario_id = ? AND revoked_at IS NULL
                """, Timestamp.from(now), reason, userId);
    }

    public long activeAdminCount() {
        Long value = jdbc.queryForObject("SELECT count(*) FROM platform_admins WHERE active", Long.class);
        return value == null ? 0 : value;
    }

    public void lockPlatformAdministratorInvariant() {
        requireActiveTransaction();
        jdbc.execute(PLATFORM_ADMIN_INVARIANT_LOCK_SQL);
    }

    public void resetMfa(long userId, Instant now) {
        jdbc.update("""
                UPDATE platform_mfa_credentials
                SET revoked_at = COALESCE(revoked_at, ?), blocked_until = NULL,
                    failed_attempts = 0, failure_window_started_at = NULL
                WHERE usuario_id = ? AND revoked_at IS NULL
                """, Timestamp.from(now), userId);
        jdbc.update("""
                UPDATE platform_refresh_sessions
                SET revoked_at = COALESCE(revoked_at, ?), revoke_reason = 'MFA_RESET'
                WHERE usuario_id = ? AND revoked_at IS NULL
                """, Timestamp.from(now), userId);
        jdbc.update("""
                UPDATE platform_admins SET active=FALSE, revoked_at=?,
                    security_version=security_version+1, updated_at=?
                WHERE usuario_id=?
                """, Timestamp.from(now), Timestamp.from(now), userId);
    }

    public void consumePendingActivation(long userId, Instant now) {
        jdbc.update("""
                UPDATE platform_identity_activations SET consumed_at = ?
                WHERE usuario_id = ? AND consumed_at IS NULL
                """, Timestamp.from(now), userId);
    }

    public PageData<AuditView> audit(AuditFilter filter, int page, int size) {
        StringBuilder where = new StringBuilder(" WHERE 1=1");
        List<Object> args = new ArrayList<>();
        add(where, args, " AND e.target_tenant_id = ?", filter.tenantId());
        if (notBlank(filter.actor())) {
            where.append(" AND lower(coalesce(e.actor_username_snapshot,'')) LIKE ?");
            args.add(like(filter.actor().trim().toLowerCase(Locale.ROOT)));
        }
        if (notBlank(filter.action())) {
            where.append(" AND e.action = ?");
            args.add(filter.action().trim());
        }
        if (notBlank(filter.result())) {
            where.append(" AND e.result = ?");
            args.add(filter.result().trim().toUpperCase(Locale.ROOT));
        }
        add(where, args, " AND e.occurred_at >= ?", sqlTimestamp(filter.from()));
        add(where, args, " AND e.occurred_at <= ?", sqlTimestamp(filter.to()));
        add(where, args, " AND e.correlation_id = ?", filter.correlationId());
        long total = count("SELECT count(*) FROM platform_audit_events e" + where, args.toArray());
        args.add(size);
        args.add(page * size);
        List<AuditView> content = jdbc.query("""
                SELECT e.id, e.occurred_at, e.actor_usuario_id, e.actor_username_snapshot,
                       e.action, e.result, e.target_type, e.target_id, e.target_tenant_id,
                       e.correlation_id, e.metadata::text detail
                FROM platform_audit_events e
                """ + where + " ORDER BY e.occurred_at DESC, e.id DESC LIMIT ? OFFSET ?",
                PlatformControlPlaneRepository::audit, args.toArray());
        return page(content, total, page, size);
    }

    private List<RoleView> rolesByCodes(UUID tenantId, List<String> roleCodes) {
        if (roleCodes == null || roleCodes.isEmpty()) {
            throw new IllegalArgumentException("Se requiere al menos un rol");
        }
        String placeholders = String.join(",", roleCodes.stream().map(ignored -> "?").toList());
        List<Object> args = new ArrayList<>();
        args.add(tenantId);
        roleCodes.stream().map(code -> code.trim().toUpperCase(Locale.ROOT)).distinct().forEach(args::add);
        return jdbc.query("SELECT id, codigo, nombre, activo FROM roles WHERE tenant_id=? "
                        + "AND activo AND codigo IN (" + placeholders + ")",
                PlatformControlPlaneRepository::role, args.toArray());
    }

    private long count(String sql, Object[] args) {
        Long result = jdbc.queryForObject(sql, Long.class, args);
        return result == null ? 0 : result;
    }

    private static <T> PageData<T> page(List<T> content, long total, int page, int size) {
        long totalPages = size == 0 ? 0 : Math.ceilDiv(total, size);
        return new PageData<>(content, total, totalPages, size, page, page == 0,
                totalPages == 0 || page >= totalPages - 1);
    }

    private static String normalizedQuery(String value) {
        return notBlank(value) ? value.trim().toLowerCase(Locale.ROOT) : null;
    }

    private static String blankToNull(String value) {
        return notBlank(value) ? value.trim().toUpperCase(Locale.ROOT) : null;
    }

    private static void requireActiveTransaction() {
        if (!TransactionSynchronizationManager.isActualTransactionActive()) {
            throw new IllegalStateException(
                    "La protección de último administrador requiere una transacción activa");
        }
    }

    private static String like(String value) {
        return value == null ? null : "%" + value.replace("\\", "\\\\")
                .replace("%", "\\%").replace("_", "\\_") + "%";
    }

    private static boolean notBlank(String value) {
        return value != null && !value.isBlank();
    }

    private static void add(StringBuilder where, List<Object> args, String sql, Object value) {
        if (value != null) {
            where.append(sql);
            args.add(value);
        }
    }

    private static TenantView tenant(ResultSet rs, int row) throws SQLException {
        return new TenantView((UUID) rs.getObject("id"), rs.getString("code"), rs.getString("name"),
                rs.getString("status"), rs.getLong("security_version"),
                rs.getTimestamp("created_at").toInstant(), rs.getTimestamp("updated_at").toInstant(),
                rs.getLong("membership_count"), rs.getLong("active_membership_count"),
                rs.getLong("role_count"));
    }

    private static IdentityView identity(ResultSet rs, int row) throws SQLException {
        return new IdentityView(rs.getLong("id"), rs.getString("nombre_usuario"), rs.getBoolean("activo"));
    }

    private static MembershipView membership(ResultSet rs, int row) throws SQLException {
        return new MembershipView((UUID) rs.getObject("id"), (UUID) rs.getObject("tenant_id"),
                rs.getLong("usuario_id"), rs.getString("nombre_usuario"), rs.getString("status"),
                sqlArray(rs.getArray("roles")), rs.getTimestamp("valid_from").toInstant(),
                instant(rs, "valid_until"), rs.getLong("security_version"));
    }

    private static RoleView role(ResultSet rs, int row) throws SQLException {
        return new RoleView(rs.getLong("id"), rs.getString("codigo"),
                rs.getString("nombre"), rs.getBoolean("activo"));
    }

    private static AdminView admin(ResultSet rs, int row) throws SQLException {
        return new AdminView(rs.getLong("usuario_id"), rs.getString("nombre_usuario"),
                rs.getBoolean("active") ? "ACTIVE" : "REVOKED", rs.getBoolean("mfa_enabled"),
                rs.getTimestamp("granted_at").toInstant(), instant(rs, "revoked_at"),
                rs.getLong("security_version"));
    }

    private static AuditView audit(ResultSet rs, int row) throws SQLException {
        return new AuditView(rs.getLong("id"), rs.getTimestamp("occurred_at").toInstant(),
                (Long) rs.getObject("actor_usuario_id"), rs.getString("actor_username_snapshot"),
                rs.getString("action"), rs.getString("result"), rs.getString("target_type"),
                rs.getString("target_id"), (UUID) rs.getObject("target_tenant_id"),
                (UUID) rs.getObject("correlation_id"), rs.getString("detail"));
    }

    private static List<String> sqlArray(Array array) throws SQLException {
        if (array == null) return List.of();
        Object raw = array.getArray();
        if (raw instanceof String[] values) return List.of(values);
        Object[] values = (Object[]) raw;
        return java.util.Arrays.stream(values).map(String::valueOf).toList();
    }

    private static Instant instant(ResultSet rs, String column) throws SQLException {
        var value = rs.getTimestamp(column);
        return value == null ? null : value.toInstant();
    }

    private static Timestamp sqlTimestamp(Instant value) {
        return value == null ? null : Timestamp.from(value);
    }

    public record PageData<T>(List<T> content, long totalElements, long totalPages, int size,
                              int number, boolean first, boolean last) {
    }

    public record TenantView(UUID id, String code, String name, String status, long version,
                             Instant createdAt, Instant updatedAt, long membershipCount,
                             long activeMembershipCount, long roleCount) {
    }

    public record IdentityView(long id, String username, boolean active) {
    }

    public record MembershipView(UUID id, UUID tenantId, long userId, String username,
                                 String status, List<String> roles, Instant validFrom,
                                 Instant validUntil, long version) {
    }

    public record RoleView(long id, String code, String name, boolean active) {
    }

    public record AdminView(long userId, String username, String status, boolean mfaEnabled,
                            Instant createdAt, Instant revokedAt, long version) {
    }

    public record AuditView(long id, Instant occurredAt, Long actorId, String actorUsername,
                            String action, String result, String targetType, String targetId,
                            UUID tenantId, UUID correlationId, String detail) {
    }

    public record AuditFilter(UUID tenantId, String actor, String action, String result,
                              Instant from, Instant to, UUID correlationId) {
    }
}
