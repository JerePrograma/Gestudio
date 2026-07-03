package ledance.infra.seguridad;

import com.fasterxml.jackson.databind.ObjectMapper;
import ledance.infra.errores.ApiErrorResponse;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authorization.AuthorityAuthorizationManager;
import org.springframework.security.config.annotation.authentication.configuration.AuthenticationConfiguration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.access.hierarchicalroles.RoleHierarchy;
import org.springframework.security.access.hierarchicalroles.RoleHierarchyImpl;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.access.intercept.RequestAuthorizationContext;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.http.HttpStatus;

import java.io.IOException;
import java.time.Clock;
import java.util.List;

@Configuration
@EnableWebSecurity
public class SecurityConfigurations {

    private final SecurityFilter securityFilter;
    private final ObjectMapper objectMapper;
    private final Clock clock;

    public SecurityConfigurations(SecurityFilter securityFilter, ObjectMapper objectMapper, Clock clock) {
        this.securityFilter = securityFilter;
        this.objectMapper = objectMapper;
        this.clock = clock;
    }

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http, RoleHierarchy roleHierarchy) throws Exception {
        AuthorityAuthorizationManager<RequestAuthorizationContext> administrador =
                AuthorityAuthorizationManager.hasRole("ADMINISTRADOR");
        administrador.setRoleHierarchy(roleHierarchy);
        return http
                .csrf(AbstractHttpConfigurer::disable)  // ✅ Desactiva CSRF
                .cors(Customizer.withDefaults())
                .formLogin(AbstractHttpConfigurer::disable)
                .httpBasic(AbstractHttpConfigurer::disable)
                .sessionManagement(sm -> sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .exceptionHandling(errors -> errors
                        .authenticationEntryPoint((request, response, exception) ->
                                writeError(response, HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "Autenticación requerida"))
                        .accessDeniedHandler((request, response, exception) ->
                                writeError(response, HttpStatus.FORBIDDEN, "FORBIDDEN", "Permisos insuficientes")))
                .authorizeHttpRequests(req -> {
                    req.requestMatchers(HttpMethod.OPTIONS, "/**").permitAll();
                    req.requestMatchers(HttpMethod.POST, "/api/login").permitAll();
                    req.requestMatchers(HttpMethod.POST, "/api/login/refresh").permitAll();
                    req.requestMatchers(HttpMethod.POST, "/api/login/logout").permitAll();
                    req.requestMatchers(HttpMethod.GET, "/api/usuarios/perfil").authenticated();
                    req.requestMatchers("/api/usuarios/**").hasRole("SUPERADMIN");
                    req.requestMatchers("/api/roles/**").hasRole("SUPERADMIN");
                    req.requestMatchers("/api/auditoria/seguridad/**").hasRole("SUPERADMIN");
                    req.requestMatchers("/api/mensualidades/generar-periodo/manual").hasRole("SUPERADMIN");
                    req.requestMatchers("/api/**").access(administrador);
                    req.anyRequest().denyAll();
                })
                .addFilterBefore(securityFilter, UsernamePasswordAuthenticationFilter.class)
                .build();
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

    @Bean
    public RoleHierarchy roleHierarchy() {
        return RoleHierarchyImpl.fromHierarchy("ROLE_SUPERADMIN > ROLE_ADMINISTRADOR");
    }

    @Bean
    public PasswordEncoder passwordEncoder(SecurityProperties properties) {
        return new BCryptPasswordEncoder(properties.bcryptStrength());
    }
}
