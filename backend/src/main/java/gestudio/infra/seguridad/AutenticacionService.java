package gestudio.infra.seguridad;

import gestudio.auditoria.application.AuditFailureService;
import gestudio.dto.request.LoginRequest;
import gestudio.dto.usuario.response.UsuarioResponse;
import gestudio.entidades.Usuario;
import gestudio.tenancy.TenantAccess;
import gestudio.tenancy.TenantAccessService;
import gestudio.tenancy.TenantContext;
import gestudio.tenancy.TenantSelection;
import gestudio.tenancy.TenantSummaryResponse;
import gestudio.tenancy.TenantMetrics;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.AuthenticationException;
import org.springframework.stereotype.Service;

import java.util.Map;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

@Service
public class AutenticacionService {

    private final AuthenticationManager authenticationManager;
    private final RefreshSessionService sessions;
    private final AuditFailureService auditFailures;
    private final TenantAccessService tenantAccess;
    private final TokenService tokens;
    private final TenantMetrics tenantMetrics;

    public AutenticacionService(AuthenticationManager authenticationManager,
                                RefreshSessionService sessions,
                                AuditFailureService auditFailures,
                                TenantAccessService tenantAccess,
                                TokenService tokens,
                                TenantMetrics tenantMetrics) {
        this.authenticationManager = authenticationManager;
        this.sessions = sessions;
        this.auditFailures = auditFailures;
        this.tenantAccess = tenantAccess;
        this.tokens = tokens;
        this.tenantMetrics = tenantMetrics;
    }

    public Resultado login(LoginRequest request, String userAgent, String ip) {
        String username = request.nombreUsuario().trim();

        final org.springframework.security.core.Authentication authentication;

        try {
            authentication = authenticationManager.authenticate(
                    new UsernamePasswordAuthenticationToken(username, request.contrasena()));
        } catch (AuthenticationException exception) {
            tenantMetrics.resolution("denied", "identity_invalid");
            tenantMetrics.accessDenied("identity_invalid", "login");
            auditFailures.registrarAnonimo(
                    "LOGIN_RECHAZADO",
                    username,
                    Map.of("motivo", "CREDENCIALES_INVALIDAS")
            );
            throw exception;
        }

        Usuario usuario = (Usuario) authentication.getPrincipal();
        Long userId = usuario.getId();

        List<TenantSelection> available = tenantAccess.activeSelections(userId);
        if (request.tenantId() == null && available.size() > 1) {
            tenantMetrics.resolution("selection_required", "multiple_memberships");
            return Resultado.seleccion(available.stream().map(TenantSummaryResponse::from).toList());
        }

        TenantAccess access;
        try {
            access = tenantAccess.requireSelected(userId, request.tenantId());
        } catch (AccessDeniedException exception) {
            tenantMetrics.resolution("denied", "membership_invalid");
            tenantMetrics.accessDenied("membership_invalid", "login");
            auditFailures.registrarAnonimo(
                    "LOGIN_RECHAZADO",
                    username,
                    Map.of("motivo", "TENANT_NO_AUTORIZADO")
            );
            throw new BadCredentialsException("Credenciales inválidas");
        }

        Usuario usuarioCompleto = access.usuario();
        if (!usuarioCompleto.isEnabled()
                || !Objects.equals(usuario.getAuthVersion(), usuarioCompleto.getAuthVersion())
                || !Objects.equals(usuario.getNombreUsuario(), usuarioCompleto.getNombreUsuario())) {
            auditFailures.registrarAnonimo(
                    "LOGIN_RECHAZADO",
                    username,
                    Map.of("motivo", usuarioCompleto.isEnabled()
                            ? "IDENTIDAD_DESACTUALIZADA"
                            : "USUARIO_INACTIVO")
            );
            throw new BadCredentialsException("Credenciales inválidas");
        }

        try (TenantContext.Scope ignored = TenantContext.open(access.tenantId(), access.membershipId())) {
            tenantMetrics.resolution("success", "login_bound");
            return resultado(sessions.iniciar(usuarioCompleto, access, userAgent, ip), available);
        }
    }

    public Resultado refresh(String refreshToken, String userAgent, String ip) {
        try {
            VerifiedToken verified = tokens.verify(refreshToken, TokenType.REFRESH);
            try (TenantContext.Scope ignored = TenantContext.open(verified.tenantId(), verified.membershipId())) {
                RefreshSessionService.Emision emission = sessions.rotar(refreshToken, userAgent, ip);
                return resultado(emission, tenantAccess.activeSelections(emission.usuario().getId()));
            }
        } catch (RefreshTokenReuseException exception) {
            throw exception;
        } catch (InvalidTokenException exception) {
            tenantMetrics.resolution("denied", "refresh_invalid");
            tenantMetrics.accessDenied("refresh_invalid", "refresh");
            auditFailures.registrarAnonimo(
                    "REFRESH_RECHAZADO",
                    null,
                    Map.of("motivo", "TOKEN_INVALIDO")
            );
            throw exception;
        }
    }

    public void logout(String refreshToken) {
        if (refreshToken == null || refreshToken.isBlank()) {
            return;
        }
        try {
            VerifiedToken verified = tokens.verify(refreshToken, TokenType.REFRESH);
            try (TenantContext.Scope ignored = TenantContext.open(verified.tenantId(), verified.membershipId())) {
                sessions.logout(refreshToken);
            }
        } catch (InvalidTokenException ignored) {
            // Logout remains idempotent and the HTTP boundary clears the cookie.
        }
    }

    public Resultado switchTenant(Usuario usuario, UUID tenantId, String refreshToken,
                                  String userAgent, String ip) {
        TenantAccess target = tenantAccess.findActiveAccess(usuario.getId(), tenantId)
                .orElseThrow(() -> new AccessDeniedException("Tenant no autorizado"));

        sessions.revocarParaCambio(refreshToken, usuario);

        try (TenantContext.Scope ignored = TenantContext.open(target.tenantId(), target.membershipId())) {
            RefreshSessionService.Emision emission = sessions.iniciarCambio(usuario, target, userAgent, ip);
            return resultado(emission, tenantAccess.activeSelections(usuario.getId()));
        }
    }

    private Resultado resultado(RefreshSessionService.Emision emision, List<TenantSelection> available) {
        Usuario user = emision.usuario();
        TenantAccess access = emision.access();

        return new Resultado(
                emision.accessToken(),
                emision.refreshToken(),
                emision.session().getExpiresAt(),
                new UsuarioResponse(
                        user.getId(),
                        user.getNombreUsuario(),
                        access.roleCodes().stream().sorted().toList(),
                        access.permissionCodes().stream().sorted().toList(),
                        user.getActivo(),
                        TenantSummaryResponse.from(access.tenant()),
                        available.stream().map(TenantSummaryResponse::from).toList()
                ),
                false,
                List.of()
        );
    }

    public record Resultado(
            String accessToken,
            String refreshToken,
            java.time.Instant refreshExpiresAt,
            UsuarioResponse usuario,
            boolean selectionRequired,
            List<TenantSummaryResponse> tenants
    ) {
        public Resultado(String accessToken, String refreshToken, java.time.Instant refreshExpiresAt,
                         UsuarioResponse usuario) {
            this(accessToken, refreshToken, refreshExpiresAt, usuario, false, List.of());
        }

        static Resultado seleccion(List<TenantSummaryResponse> tenants) {
            return new Resultado(null, null, null, null, true, List.copyOf(tenants));
        }
    }
}
