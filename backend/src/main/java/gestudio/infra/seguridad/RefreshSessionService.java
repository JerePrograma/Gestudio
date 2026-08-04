package gestudio.infra.seguridad;

import gestudio.auditoria.application.AuditService;
import gestudio.entidades.RefreshSession;
import gestudio.entidades.Usuario;
import gestudio.repositorios.RefreshSessionRepositorio;
import gestudio.repositorios.UsuarioRepositorio;
import gestudio.tenancy.TenantAccess;
import gestudio.tenancy.TenantAccessService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Clock;
import java.time.Instant;
import java.util.HexFormat;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;

@Service
public class RefreshSessionService {

    private final RefreshSessionRepositorio sessions;
    private final UsuarioRepositorio usuarios;
    private final TokenService tokens;
    private final Clock clock;
    private final AuditService audit;
    private final TenantAccessService tenantAccess;

    public RefreshSessionService(RefreshSessionRepositorio sessions,
                                 UsuarioRepositorio usuarios,
                                 TokenService tokens,
                                 Clock clock,
                                 AuditService audit,
                                 TenantAccessService tenantAccess) {
        this.sessions = sessions;
        this.usuarios = usuarios;
        this.tokens = tokens;
        this.clock = clock;
        this.audit = audit;
        this.tenantAccess = tenantAccess;
    }

    @Transactional
    public Emision iniciar(Usuario usuario, TenantAccess access, String userAgent, String ip) {
        Emision emision = emitir(usuario, access, UUID.randomUUID(), userAgent, ip);

        audit.registrar(
                "SEGURIDAD",
                "LOGIN_EXITOSO",
                "REFRESH_SESSION",
                emision.session().getId().toString(),
                usuario,
                null,
                Map.of("familyId", emision.session().getFamilyId().toString())
        );

        return emision;
    }

    @Transactional(noRollbackFor = RefreshTokenReuseException.class)
    public Emision rotar(String rawToken, String userAgent, String ip) {
        VerifiedToken verified = tokens.verify(rawToken, TokenType.REFRESH);

        RefreshSession actual = sessions.findByTokenHashForUpdate(hash(rawToken))
                .orElseThrow(InvalidTokenException::new);

        if (!actual.getId().toString().equals(verified.jwtId())) {
            throw new InvalidTokenException();
        }

        Instant now = clock.instant();

        if (actual.getUsedAt() != null) {
            sessions.revokeFamily(actual.getFamilyId(), now, "REUSE_DETECTED");

            audit.registrar(
                    "SEGURIDAD",
                    "REFRESH_TOKEN_REUSE_DETECTED",
                    "REFRESH_SESSION",
                    actual.getId().toString(),
                    actual.getUsuario(),
                    null,
                    Map.of("familyId", actual.getFamilyId().toString())
            );

            throw new RefreshTokenReuseException();
        }

        if (actual.getRevokedAt() != null || !actual.getExpiresAt().isAfter(now)) {
            throw new InvalidTokenException();
        }

        Usuario usuario = usuarios.findById(actual.getUsuario().getId())
                .filter(Usuario::isEnabled)
                .filter(user -> Objects.equals(user.getNombreUsuario(), verified.subject()))
                .filter(user -> Objects.equals(user.getAuthVersion(), verified.authVersion()))
                .filter(user -> Objects.equals(user.getAuthVersion(), actual.getAuthVersion()))
                .orElseThrow(InvalidTokenException::new);

        validarBinding(actual, verified);
        TenantAccess access = tenantAccess.revalidate(
                        usuario.getId(), verified.membershipId(), verified.tenantId(),
                        verified.tenantSecurityVersion(), verified.membershipSecurityVersion())
                .orElseThrow(InvalidTokenException::new);

        actual.setUsedAt(now);

        Emision nueva = emitir(usuario, access, actual.getFamilyId(), userAgent, ip);
        actual.setReplacedBy(nueva.session());

        audit.registrar(
                "SEGURIDAD",
                "REFRESH_EXITOSO",
                "REFRESH_SESSION",
                nueva.session().getId().toString(),
                usuario,
                null,
                Map.of(
                        "familyId", actual.getFamilyId().toString(),
                        "reemplazaSessionId", actual.getId().toString()
                )
        );

        return nueva;
    }

    @Transactional
    public void revocarParaCambio(String rawToken, Usuario authenticatedUser) {
        VerifiedToken verified = tokens.verify(rawToken, TokenType.REFRESH);
        RefreshSession actual = sessions.findByTokenHashForUpdate(hash(rawToken))
                .orElseThrow(InvalidTokenException::new);
        validarBinding(actual, verified);
        if (authenticatedUser == null
                || !Objects.equals(authenticatedUser.getId(), verified.userId())
                || actual.getUsedAt() != null
                || actual.getRevokedAt() != null
                || !actual.getExpiresAt().isAfter(clock.instant())) {
            throw new InvalidTokenException();
        }
        tenantAccess.revalidate(
                        verified.userId(), verified.membershipId(), verified.tenantId(),
                        verified.tenantSecurityVersion(), verified.membershipSecurityVersion())
                .orElseThrow(InvalidTokenException::new);
        sessions.revokeFamily(actual.getFamilyId(), clock.instant(), "TENANT_SWITCH");
    }

    @Transactional
    public Emision iniciarCambio(Usuario usuario, TenantAccess access, String userAgent, String ip) {
        Emision emission = emitir(usuario, access, UUID.randomUUID(), userAgent, ip);
        audit.registrar(
                "SEGURIDAD",
                "TENANT_SWITCH_COMPLETED",
                "REFRESH_SESSION",
                emission.session().getId().toString(),
                usuario,
                null,
                Map.of("familyId", emission.session().getFamilyId().toString())
        );
        return emission;
    }

    @Transactional
    public void logout(String rawToken) {
        if (rawToken == null || rawToken.isBlank()) {
            return;
        }

        try {
            tokens.verify(rawToken, TokenType.REFRESH);

            sessions.findByTokenHashForUpdate(hash(rawToken)).ifPresent(session -> {
                sessions.revokeFamily(session.getFamilyId(), clock.instant(), "LOGOUT");

                audit.registrar(
                        "SEGURIDAD",
                        "LOGOUT",
                        "REFRESH_SESSION",
                        session.getId().toString(),
                        session.getUsuario(),
                        null,
                        Map.of("familyId", session.getFamilyId().toString())
                );
            });
        } catch (InvalidTokenException ignored) {
            // El borde HTTP limpia cookies/tokens inválidos.
        }
    }

    private Emision emitir(Usuario usuario, TenantAccess access, UUID familyId, String userAgent, String ip) {
        Instant now = clock.instant();
        UUID id = UUID.randomUUID();

        String raw = tokens.generarRefreshToken(usuario, access, id);

        RefreshSession session = new RefreshSession();
        session.setId(id);
        session.setFamilyId(familyId);
        session.setUsuario(usuario);
        session.setTenant(access.membership().getTenant());
        session.setMembership(access.membership());
        session.setTokenHash(hash(raw));
        session.setAuthVersion(usuario.getAuthVersion());
        session.setTenantSecurityVersion(access.tenantSecurityVersion());
        session.setMembershipSecurityVersion(access.membershipSecurityVersion());
        session.setIssuedAt(now);
        session.setExpiresAt(tokens.refreshExpiresAt(now));
        session.setUserAgentHash(hashNullable(userAgent));
        session.setIpHash(hashNullable(ip));

        session = sessions.save(session);

        return new Emision(usuario, access, tokens.generarAccessToken(usuario, access), raw, session);
    }

    private static void validarBinding(RefreshSession session, VerifiedToken token) {
        if (!session.getId().toString().equals(token.jwtId())
                || !Objects.equals(session.getUsuario().getId(), token.userId())
                || !Objects.equals(session.getAuthVersion(), token.authVersion())
                || !Objects.equals(session.getTenant().getId(), token.tenantId())
                || !Objects.equals(session.getMembership().getId(), token.membershipId())
                || !Objects.equals(session.getTenantSecurityVersion(), token.tenantSecurityVersion())
                || !Objects.equals(session.getMembershipSecurityVersion(), token.membershipSecurityVersion())) {
            throw new InvalidTokenException();
        }
    }

    static String hash(String value) {
        try {
            return HexFormat.of().formatHex(
                    MessageDigest.getInstance("SHA-256")
                            .digest(value.getBytes(StandardCharsets.UTF_8))
            );
        } catch (Exception e) {
            throw new IllegalStateException("SHA-256 no disponible", e);
        }
    }

    private static String hashNullable(String value) {
        return value == null || value.isBlank() ? null : hash(value);
    }

    public record Emision(
            Usuario usuario,
            TenantAccess access,
            String accessToken,
            String refreshToken,
            RefreshSession session
    ) {
    }
}
