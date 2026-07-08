package ledance.infra.seguridad;

import com.fasterxml.jackson.databind.ObjectMapper;
import ledance.infra.errores.ApiErrorResponse;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.config.annotation.authentication.configuration.AuthenticationConfiguration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.http.HttpStatus;

import java.io.IOException;
import java.time.Clock;
import java.util.List;

@Configuration
@EnableWebSecurity
public class SecurityConfigurations {

    private final ObjectMapper objectMapper;
    private final Clock clock;

    public SecurityConfigurations(ObjectMapper objectMapper, Clock clock) {
        this.objectMapper = objectMapper;
        this.clock = clock;
    }

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http,
                                                   SecurityFilter securityFilter,
                                                   AuthenticationEntryPoint authenticationEntryPoint) throws Exception {
        return http
                .csrf(AbstractHttpConfigurer::disable)  // ✅ Desactiva CSRF
                .cors(Customizer.withDefaults())
                .formLogin(AbstractHttpConfigurer::disable)
                .httpBasic(AbstractHttpConfigurer::disable)
                .sessionManagement(sm -> sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .exceptionHandling(errors -> errors
                        .authenticationEntryPoint(authenticationEntryPoint)
                        .accessDeniedHandler((request, response, exception) ->
                                writeError(response, HttpStatus.FORBIDDEN, "FORBIDDEN", "Permisos insuficientes")))
                .authorizeHttpRequests(req -> {
                    req.requestMatchers(HttpMethod.OPTIONS, "/**").permitAll();
                    req.requestMatchers(HttpMethod.POST, "/api/login").permitAll();
                    req.requestMatchers(HttpMethod.POST, "/api/login/refresh").permitAll();
                    req.requestMatchers(HttpMethod.POST, "/api/login/logout").permitAll();
                    req.requestMatchers(HttpMethod.GET, "/api/usuarios/perfil").authenticated();
                    req.requestMatchers(HttpMethod.GET, "/api/usuarios/**").hasAuthority("PERM_USUARIOS_READ");
                    req.requestMatchers("/api/usuarios/**").hasAuthority("PERM_USUARIOS_WRITE");
                    req.requestMatchers(HttpMethod.GET, "/api/roles/**").hasAuthority("PERM_ROLES_READ");
                    req.requestMatchers("/api/roles/**").hasAuthority("PERM_ROLES_WRITE");
                    req.requestMatchers(HttpMethod.GET, "/api/permisos/**").hasAuthority("PERM_PERMISOS_READ");
                    req.requestMatchers("/api/permisos/**").denyAll();
                    req.requestMatchers(HttpMethod.GET, "/api/auditoria/seguridad/**").hasAuthority("PERM_AUDITORIA_READ");

                    readWrite(req, "/api/alumnos/**", "ALUMNOS");
                    readWrite(req, "/api/profesores/**", "PROFESORES");
                    readWrite(req, "/api/disciplinas/**", "DISCIPLINAS");
                    readWrite(req, "/api/inscripciones/**", "INSCRIPCIONES");
                    readWrite(req, "/api/asistencias-diarias/**", "ASISTENCIAS");
                    readWrite(req, "/api/asistencias-mensuales/**", "ASISTENCIAS");

                    req.requestMatchers(HttpMethod.POST, "/api/pagos/*/anulacion").hasAuthority("PERM_PAGOS_ANULAR");
                    readWrite(req, "/api/pagos/**", "PAGOS");
                    req.requestMatchers(HttpMethod.GET, "/api/caja/**").hasAuthority("PERM_CAJA_READ");
                    req.requestMatchers(HttpMethod.POST, "/api/egresos/*/anulacion").hasAuthority("PERM_EGRESOS_ANULAR");
                    readWrite(req, "/api/egresos/**", "EGRESOS");
                    readWrite(req, "/api/cargos/**", "CARGOS");
                    readWrite(req, "/api/creditos/**", "CREDITOS");

                    readWrite(req, "/api/conceptos/**", "CONCEPTOS");
                    readWrite(req, "/api/sub-conceptos/**", "CONCEPTOS");
                    readWrite(req, "/api/bonificaciones/**", "BONIFICACIONES");
                    readWrite(req, "/api/recargos/**", "RECARGOS");
                    readWrite(req, "/api/metodos-pago/**", "METODOS_PAGO");
                    readWrite(req, "/api/stocks/**", "STOCK");

                    req.requestMatchers(HttpMethod.POST, "/api/reportes/**").hasAuthority("PERM_REPORTES_EXPORT");
                    req.requestMatchers(HttpMethod.GET, "/api/reportes/**").hasAuthority("PERM_REPORTES_READ");

                    readWrite(req, "/api/matriculas/**", "INSCRIPCIONES");
                    req.requestMatchers("/api/mensualidades/generar-periodo/manual")
                            .hasAuthority("PERM_ROLES_WRITE");
                    readWrite(req, "/api/mensualidades/**", "CARGOS");
                    readWrite(req, "/api/salones/**", "DISCIPLINAS");
                    readWrite(req, "/api/observaciones-profesores/**", "PROFESORES");
                    req.requestMatchers(HttpMethod.GET, "/api/notificaciones/**").hasAuthority("PERM_ALUMNOS_READ");
                    req.requestMatchers("/api/**").denyAll();
                    req.anyRequest().denyAll();
                })
                .addFilterBefore(securityFilter, UsernamePasswordAuthenticationFilter.class)
                .build();
    }

    @Bean
    public AuthenticationEntryPoint authenticationEntryPoint() {
        return (request, response, exception) ->
                writeError(response, HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "Autenticación requerida");
    }

    private void writeError(jakarta.servlet.http.HttpServletResponse response, HttpStatus status,
                            String code, String message) throws IOException {
        response.setStatus(status.value());
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        objectMapper.writeValue(response.getWriter(),
                new ApiErrorResponse(clock.instant(), status.value(), code, message, List.of()));
    }

    @Bean
    public AuthenticationManager authenticationManager(AuthenticationConfiguration configuration) throws Exception {
        return configuration.getAuthenticationManager();
    }

    private static void readWrite(
            org.springframework.security.config.annotation.web.configurers.AuthorizeHttpRequestsConfigurer<HttpSecurity>
                    .AuthorizationManagerRequestMatcherRegistry requests,
            String pattern,
            String permission) {
        requests.requestMatchers(HttpMethod.GET, pattern).hasAuthority("PERM_" + permission + "_READ");
        requests.requestMatchers(pattern).hasAuthority("PERM_" + permission + "_WRITE");
    }

    @Bean
    public PasswordEncoder passwordEncoder(SecurityProperties properties) {
        return new BCryptPasswordEncoder(properties.bcryptStrength());
    }
}
