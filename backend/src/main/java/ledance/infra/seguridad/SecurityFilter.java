package ledance.infra.seguridad;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import ledance.repositorios.UsuarioRepositorio;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import java.io.IOException;
import java.util.Objects;

@Component
public class SecurityFilter extends OncePerRequestFilter {

    private final TokenService tokenService;
    private final UsuarioRepositorio usuarioRepositorio;
    private final AuthenticationEntryPoint authenticationEntryPoint;

    public SecurityFilter(TokenService tokenService, UsuarioRepositorio usuarioRepositorio,
                          AuthenticationEntryPoint authenticationEntryPoint) {
        this.tokenService = tokenService;
        this.usuarioRepositorio = usuarioRepositorio;
        this.authenticationEntryPoint = authenticationEntryPoint;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain)
            throws ServletException, IOException {
        String authHeader = request.getHeader("Authorization");
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            String token = authHeader.substring("Bearer ".length());
            try {
                VerifiedToken verified = tokenService.verify(token, TokenType.ACCESS);
                var userEntity = usuarioRepositorio.findById(verified.userId())
                        .filter(user -> Objects.equals(user.getNombreUsuario(), verified.subject()))
                        .filter(user -> Boolean.TRUE.equals(user.getActivo()))
                        .filter(user -> user.getRol() != null && Boolean.TRUE.equals(user.getRol().getActivo()))
                        .filter(user -> Objects.equals(user.getRol().getDescripcion(), verified.role()))
                        .filter(user -> Objects.equals(user.getAuthVersion(), verified.authVersion()))
                        .orElseThrow(InvalidTokenException::new);
                var authentication = new UsernamePasswordAuthenticationToken(
                        userEntity, null, userEntity.getAuthorities());
                SecurityContextHolder.getContext().setAuthentication(authentication);
            } catch (InvalidTokenException ex) {
                SecurityContextHolder.clearContext();
                authenticationEntryPoint.commence(request, response,
                        new BadCredentialsException("Token inválido", ex));
                return;
            }
        }
        filterChain.doFilter(request, response);
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return request.getRequestURI().startsWith("/api/login");
    }
}
