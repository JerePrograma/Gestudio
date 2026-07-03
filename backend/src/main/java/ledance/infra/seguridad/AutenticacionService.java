package ledance.infra.seguridad;

import ledance.auditoria.application.AuditFailureService;
import ledance.dto.request.LoginRequest;
import ledance.dto.usuario.response.UsuarioResponse;
import ledance.entidades.Usuario;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.AuthenticationException;
import org.springframework.stereotype.Service;

import java.util.Map;

@Service
public class AutenticacionService {
    private final AuthenticationManager authenticationManager;
    private final RefreshSessionService sessions;
    private final AuditFailureService auditFailures;

    public AutenticacionService(AuthenticationManager authenticationManager, RefreshSessionService sessions,
                                AuditFailureService auditFailures) {
        this.authenticationManager = authenticationManager;
        this.sessions = sessions;
        this.auditFailures = auditFailures;
    }

    public Resultado login(LoginRequest request, String userAgent, String ip) {
        String username = request.nombreUsuario().trim();
        final org.springframework.security.core.Authentication authentication;
        try {
            authentication = authenticationManager.authenticate(
                    new UsernamePasswordAuthenticationToken(username, request.contrasena()));
        } catch (AuthenticationException exception) {
            auditFailures.registrarAnonimo("LOGIN_RECHAZADO", username, Map.of("motivo", "CREDENCIALES_INVALIDAS"));
            throw exception;
        }
        Usuario usuario = (Usuario) authentication.getPrincipal();
        if (!usuario.isEnabled() || usuario.getRol() == null || !Boolean.TRUE.equals(usuario.getRol().getActivo())) {
            auditFailures.registrarAnonimo("LOGIN_RECHAZADO", username, Map.of("motivo", "USUARIO_INACTIVO"));
            throw new BadCredentialsException("Credenciales inválidas");
        }
        return resultado(sessions.iniciar(usuario, userAgent, ip));
    }

    public Resultado refresh(String refreshToken, String userAgent, String ip) {
        try {
            return resultado(sessions.rotar(refreshToken, userAgent, ip));
        } catch (RefreshTokenReuseException exception) {
            throw exception;
        } catch (InvalidTokenException exception) {
            auditFailures.registrarAnonimo("REFRESH_RECHAZADO", null, Map.of("motivo", "TOKEN_INVALIDO"));
            throw exception;
        }
    }

    public void logout(String refreshToken) {
        sessions.logout(refreshToken);
    }

    private Resultado resultado(RefreshSessionService.Emision emision) {
        Usuario user = emision.usuario();
        return new Resultado(emision.accessToken(), emision.refreshToken(), emision.session().getExpiresAt(),
                new UsuarioResponse(user.getId(), user.getNombreUsuario(), user.getRol().getDescripcion(), user.getActivo()));
    }

    public record Resultado(String accessToken, String refreshToken, java.time.Instant refreshExpiresAt,
                            UsuarioResponse usuario) {
    }
}
