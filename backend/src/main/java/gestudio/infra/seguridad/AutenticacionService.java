package gestudio.infra.seguridad;

import gestudio.auditoria.application.AuditFailureService;
import gestudio.dto.request.LoginRequest;
import gestudio.dto.usuario.response.UsuarioResponse;
import gestudio.entidades.Usuario;
import gestudio.repositorios.UsuarioRepositorio;
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
    private final UsuarioRepositorio usuarios;

    public AutenticacionService(AuthenticationManager authenticationManager,
                                RefreshSessionService sessions,
                                AuditFailureService auditFailures,
                                UsuarioRepositorio usuarios) {
        this.authenticationManager = authenticationManager;
        this.sessions = sessions;
        this.auditFailures = auditFailures;
        this.usuarios = usuarios;
    }

    public Resultado login(LoginRequest request, String userAgent, String ip) {
        String username = request.nombreUsuario().trim();

        final org.springframework.security.core.Authentication authentication;

        try {
            authentication = authenticationManager.authenticate(
                    new UsernamePasswordAuthenticationToken(username, request.contrasena()));
        } catch (AuthenticationException exception) {
            auditFailures.registrarAnonimo(
                    "LOGIN_RECHAZADO",
                    username,
                    Map.of("motivo", "CREDENCIALES_INVALIDAS")
            );
            throw exception;
        }

        Usuario usuario = (Usuario) authentication.getPrincipal();

        Usuario usuarioCompleto = usuarios.findByIdConRolesYPermisos(usuario.getId())
                .filter(Usuario::isEnabled)
                .filter(user -> user.rolesEfectivos().stream().anyMatch(rol -> Boolean.TRUE.equals(rol.getActivo())))
                .orElseThrow(() -> {
                    auditFailures.registrarAnonimo(
                            "LOGIN_RECHAZADO",
                            username,
                            Map.of("motivo", "USUARIO_INACTIVO")
                    );
                    return new BadCredentialsException("Credenciales inválidas");
                });

        return resultado(sessions.iniciar(usuarioCompleto, userAgent, ip));
    }

    public Resultado refresh(String refreshToken, String userAgent, String ip) {
        try {
            return resultado(sessions.rotar(refreshToken, userAgent, ip));
        } catch (RefreshTokenReuseException exception) {
            throw exception;
        } catch (InvalidTokenException exception) {
            auditFailures.registrarAnonimo(
                    "REFRESH_RECHAZADO",
                    null,
                    Map.of("motivo", "TOKEN_INVALIDO")
            );
            throw exception;
        }
    }

    public void logout(String refreshToken) {
        sessions.logout(refreshToken);
    }

    private Resultado resultado(RefreshSessionService.Emision emision) {
        Usuario user = emision.usuario();

        return new Resultado(
                emision.accessToken(),
                emision.refreshToken(),
                emision.session().getExpiresAt(),
                new UsuarioResponse(
                        user.getId(),
                        user.getNombreUsuario(),
                        user.codigosRolesActivos().stream().toList(),
                        user.codigosPermisosActivos().stream().toList(),
                        user.getActivo()
                )
        );
    }

    public record Resultado(
            String accessToken,
            String refreshToken,
            java.time.Instant refreshExpiresAt,
            UsuarioResponse usuario
    ) {
    }
}