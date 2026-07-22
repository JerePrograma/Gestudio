package gestudio.infra.seguridad;

import com.fasterxml.jackson.databind.ObjectMapper;
import gestudio.infra.errores.ApiErrorResponse;
import gestudio.infra.observabilidad.MetricsTokenAuthorizationManager;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.security.authorization.AuthorizationManager;
import org.springframework.security.authorization.AuthorizationManagers;
import org.springframework.security.authorization.AuthorityAuthorizationManager;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.authentication.configuration.AuthenticationConfiguration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.access.intercept.RequestAuthorizationContext;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.security.web.servlet.util.matcher.PathPatternRequestMatcher;

import java.io.IOException;
import java.time.Clock;
import java.util.List;

import static gestudio.infra.seguridad.PermissionCodes.*;

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
    public MetricsTokenAuthorizationManager metricsTokenAuthorizationManager(
            @Value("${app.observability.metrics-token:}") String configuredToken) {
        return new MetricsTokenAuthorizationManager(configuredToken);
    }

    @Bean
    @Order(1)
    public SecurityFilterChain observabilitySecurityFilterChain(
            HttpSecurity http,
            MetricsTokenAuthorizationManager metricsTokenAuthorizationManager) throws Exception {
        PathPatternRequestMatcher.Builder paths = PathPatternRequestMatcher.withDefaults();
        return http
                .securityMatcher(paths.matcher("/actuator/**"))
                .csrf(AbstractHttpConfigurer::disable)
                .cors(AbstractHttpConfigurer::disable)
                .formLogin(AbstractHttpConfigurer::disable)
                .httpBasic(AbstractHttpConfigurer::disable)
                .sessionManagement(sm -> sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .exceptionHandling(errors -> errors
                        .authenticationEntryPoint((request, response, exception) ->
                                response.sendError(HttpStatus.UNAUTHORIZED.value()))
                        .accessDeniedHandler((request, response, exception) ->
                                response.sendError(HttpStatus.UNAUTHORIZED.value())))
                .authorizeHttpRequests(req -> req
                        .requestMatchers(
                                paths.matcher(HttpMethod.GET, "/actuator/health"),
                                paths.matcher(HttpMethod.GET, "/actuator/health/**"))
                        .permitAll()
                        .requestMatchers(paths.matcher(HttpMethod.GET, "/actuator/prometheus"))
                        .access(metricsTokenAuthorizationManager)
                        .anyRequest().denyAll())
                .build();
    }

    @Bean
    @Order(2)
    public SecurityFilterChain securityFilterChain(HttpSecurity http,
                                                    SecurityFilter securityFilter,
                                                    AuthenticationEntryPoint authenticationEntryPoint) throws Exception {
        return http
                .csrf(AbstractHttpConfigurer::disable)
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

                    req.requestMatchers("/api/observaciones-profesores/**").denyAll();

                    req.requestMatchers(HttpMethod.GET, "/api/usuarios/**").access(appAnd(PERM_USUARIOS_ADMIN));
                    req.requestMatchers(HttpMethod.POST, "/api/usuarios/**").access(appAnd(PERM_USUARIOS_ADMIN));
                    req.requestMatchers(HttpMethod.PUT, "/api/usuarios/**").access(appAnd(PERM_USUARIOS_ADMIN));
                    req.requestMatchers(HttpMethod.DELETE, "/api/usuarios/**").access(appAnd(PERM_USUARIOS_ADMIN));
                    req.requestMatchers(HttpMethod.GET, "/api/roles/**", "/api/permisos/**")
                            .access(appAnd(PERM_ROLES_ADMIN));
                    req.requestMatchers(HttpMethod.POST, "/api/roles/**").access(appAnd(PERM_ROLES_ADMIN));
                    req.requestMatchers(HttpMethod.PUT, "/api/roles/**").access(appAnd(PERM_ROLES_ADMIN));
                    req.requestMatchers(HttpMethod.DELETE, "/api/roles/**").access(appAnd(PERM_ROLES_ADMIN));

                    req.requestMatchers(HttpMethod.GET, "/api/alumnos/**").access(appAnd(PERM_ALUMNOS_LEER));
                    req.requestMatchers(HttpMethod.POST, "/api/alumnos/**").access(appAnd(PERM_ALUMNOS_ADMIN));
                    req.requestMatchers(HttpMethod.PUT, "/api/alumnos/**").access(appAnd(PERM_ALUMNOS_ADMIN));
                    req.requestMatchers(HttpMethod.DELETE, "/api/alumnos/**").access(appAnd(PERM_ALUMNOS_ADMIN));

                    req.requestMatchers(HttpMethod.GET, "/api/inscripciones/{inscripcionId}/condiciones-economicas")
                            .access(appAnd(PERM_CONDICIONES_ECONOMICAS_ADMIN));
                    req.requestMatchers(HttpMethod.POST, "/api/inscripciones/{inscripcionId}/condiciones-economicas")
                            .access(appAnd(PERM_CONDICIONES_ECONOMICAS_ADMIN));
                    req.requestMatchers(HttpMethod.GET, "/api/inscripciones/**")
                            .access(appAnd(PERM_INSCRIPCIONES_LEER));
                    req.requestMatchers(HttpMethod.POST, "/api/inscripciones/**")
                            .access(appAnd(PERM_INSCRIPCIONES_ADMIN));
                    req.requestMatchers(HttpMethod.PUT, "/api/inscripciones/**")
                            .access(appAnd(PERM_INSCRIPCIONES_ADMIN));
                    req.requestMatchers(HttpMethod.DELETE, "/api/inscripciones/**")
                            .access(appAnd(PERM_INSCRIPCIONES_ADMIN));

                    req.requestMatchers(HttpMethod.GET, "/api/disciplinas/{disciplinaId}/tarifas")
                            .access(appAnd(PERM_TARIFAS_ADMIN));
                    req.requestMatchers(HttpMethod.POST, "/api/disciplinas/{disciplinaId}/tarifas")
                            .access(appAnd(PERM_TARIFAS_ADMIN));
                    req.requestMatchers(HttpMethod.GET, "/api/disciplinas/{disciplinaId}/alumnos/pdf")
                            .access(appAndBoth(PERM_DISCIPLINAS_LEER, PERM_REPORTES_EXPORTAR));
                    req.requestMatchers(HttpMethod.GET, "/api/disciplinas/**")
                            .access(appAnd(PERM_DISCIPLINAS_LEER));
                    req.requestMatchers(HttpMethod.POST, "/api/disciplinas/**")
                            .access(appAnd(PERM_DISCIPLINAS_ADMIN));
                    req.requestMatchers(HttpMethod.PUT, "/api/disciplinas/**")
                            .access(appAnd(PERM_DISCIPLINAS_ADMIN));
                    req.requestMatchers(HttpMethod.DELETE, "/api/disciplinas/**")
                            .access(appAnd(PERM_DISCIPLINAS_ADMIN));

                    req.requestMatchers(HttpMethod.GET, "/api/profesores/**")
                            .access(appAnd(PERM_PROFESORES_LEER));
                    req.requestMatchers(HttpMethod.POST, "/api/profesores/**")
                            .access(appAnd(PERM_PROFESORES_ADMIN));
                    req.requestMatchers(HttpMethod.PUT, "/api/profesores/**")
                            .access(appAnd(PERM_PROFESORES_ADMIN));
                    req.requestMatchers(HttpMethod.DELETE, "/api/profesores/**")
                            .access(appAnd(PERM_PROFESORES_ADMIN));

                    req.requestMatchers(HttpMethod.GET, "/api/asistencias-diarias/**", "/api/asistencias-mensuales/**")
                            .access(appAnd(PERM_ASISTENCIAS_LEER));
                    req.requestMatchers(HttpMethod.POST, "/api/asistencias-diarias/**", "/api/asistencias-mensuales/**")
                            .access(appAnd(PERM_ASISTENCIAS_REGISTRAR));
                    req.requestMatchers(HttpMethod.PUT, "/api/asistencias-diarias/**", "/api/asistencias-mensuales/**")
                            .access(appAnd(PERM_ASISTENCIAS_REGISTRAR));
                    req.requestMatchers(HttpMethod.DELETE, "/api/asistencias-diarias/**", "/api/asistencias-mensuales/**")
                            .access(appAnd(PERM_ASISTENCIAS_REGISTRAR));

                    req.requestMatchers(HttpMethod.POST, "/api/mensualidades", "/api/mensualidades/generar-mensualidades")
                            .access(appAnd(PERM_MENSUALIDADES_GENERAR_MANUAL));
                    req.requestMatchers(HttpMethod.DELETE, "/api/mensualidades/**")
                            .access(appAnd(PERM_PAGOS_ANULAR));
                    req.requestMatchers(HttpMethod.GET, "/api/mensualidades/**")
                            .access(appAnd(PERM_PAGOS_LEER));

                    req.requestMatchers(HttpMethod.POST, "/api/matriculas/{id}/anulacion")
                            .access(appAnd(PERM_PAGOS_ANULAR));
                    req.requestMatchers(HttpMethod.POST, "/api/matriculas/alumno/{alumnoId}")
                            .access(appAnd(PERM_INSCRIPCIONES_ADMIN));
                    req.requestMatchers(HttpMethod.GET, "/api/matriculas/**")
                            .access(appAnd(PERM_PAGOS_LEER));

                    req.requestMatchers(HttpMethod.POST, "/api/cargos/concepto")
                            .access(appAnd(PERM_PAGOS_REGISTRAR));
                    req.requestMatchers(HttpMethod.GET, "/api/cargos/**").access(appAnd(PERM_PAGOS_LEER));

                    req.requestMatchers(HttpMethod.POST, "/api/pagos/{id}/anulacion")
                            .access(appAnd(PERM_PAGOS_ANULAR));
                    req.requestMatchers(HttpMethod.POST, "/api/pagos").access(appAnd(PERM_PAGOS_REGISTRAR));
                    req.requestMatchers(HttpMethod.GET, "/api/pagos/**").access(appAnd(PERM_PAGOS_LEER));

                    req.requestMatchers(HttpMethod.GET, "/api/caja/**").access(appAnd(PERM_CAJA_LEER));
                    req.requestMatchers(HttpMethod.GET, "/api/egresos/**").access(appAnd(PERM_EGRESOS_ADMIN));
                    req.requestMatchers(HttpMethod.POST, "/api/egresos/**").access(appAnd(PERM_EGRESOS_ADMIN));

                    req.requestMatchers(HttpMethod.POST, "/api/stocks/ventas")
                            .access(appAnd(PERM_STOCK_VENDER));
                    req.requestMatchers(HttpMethod.POST, "/api/stocks/ventas/{id}/reversion")
                            .access(appAnd(PERM_STOCK_ADMIN));
                    req.requestMatchers(HttpMethod.GET, "/api/stocks/**").access(appAnd(PERM_STOCK_LEER));
                    req.requestMatchers(HttpMethod.POST, "/api/stocks/**").access(appAnd(PERM_STOCK_ADMIN));
                    req.requestMatchers(HttpMethod.PUT, "/api/stocks/**").access(appAnd(PERM_STOCK_ADMIN));
                    req.requestMatchers(HttpMethod.DELETE, "/api/stocks/**").access(appAnd(PERM_STOCK_ADMIN));

                    req.requestMatchers(HttpMethod.POST, "/api/creditos/consumos")
                            .access(appAnd(PERM_CREDITOS_CONSUMIR));
                    req.requestMatchers(HttpMethod.POST, "/api/creditos/consumos/{id}/reversion", "/api/creditos/ajustes")
                            .access(appAnd(PERM_CREDITOS_ADMIN));
                    req.requestMatchers(HttpMethod.GET, "/api/creditos/alumno/{alumnoId}/saldo")
                            .access(appAnd(PERM_PAGOS_LEER));

                    req.requestMatchers(HttpMethod.POST, "/api/reportes/**")
                            .access(appAnd(PERM_REPORTES_EXPORTAR));
                    req.requestMatchers(HttpMethod.GET, "/api/reportes/**")
                            .access(appAnd(PERM_REPORTES_LEER));

                    req.requestMatchers(HttpMethod.GET, "/api/notificaciones/**")
                            .access(appAnd(PERM_ALUMNOS_LEER));

                    req.requestMatchers("/api/integraciones/jere-platform/estudiantes/**")
                            .access(appAndBoth(PERM_CONFIG_ADMIN, PERM_REPORTES_EXPORTAR));

                    String[] configuracion = {
                            "/api/metodos-pago/**",
                            "/api/conceptos/**",
                            "/api/sub-conceptos/**",
                            "/api/salones/**",
                            "/api/bonificaciones/**",
                            "/api/recargos/**"
                    };
                    req.requestMatchers(HttpMethod.GET, configuracion).access(appAnd(PERM_CONFIG_LEER));
                    req.requestMatchers(HttpMethod.POST, configuracion).access(appAnd(PERM_CONFIG_ADMIN));
                    req.requestMatchers(HttpMethod.PUT, configuracion).access(appAnd(PERM_CONFIG_ADMIN));
                    req.requestMatchers(HttpMethod.DELETE, configuracion).access(appAnd(PERM_CONFIG_ADMIN));

                    req.requestMatchers("/api/**").denyAll();

                    req.anyRequest().denyAll();
                })
                .addFilterBefore(securityFilter, UsernamePasswordAuthenticationFilter.class)
                .build();
    }

    private static AuthorizationManager<RequestAuthorizationContext> appAnd(String permission) {
        return AuthorizationManagers.allOf(
                AuthorityAuthorizationManager.hasAuthority(PERM_APP_ACCESO),
                AuthorityAuthorizationManager.hasAuthority(permission)
        );
    }

    private static AuthorizationManager<RequestAuthorizationContext> appAndBoth(String first, String second) {
        return AuthorizationManagers.allOf(
                AuthorityAuthorizationManager.hasAuthority(PERM_APP_ACCESO),
                AuthorityAuthorizationManager.hasAuthority(first),
                AuthorityAuthorizationManager.hasAuthority(second)
        );
    }

    @Bean
    public AuthenticationEntryPoint authenticationEntryPoint() {
        return (request, response, exception) ->
                writeError(response, HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "Autenticación requerida");
    }

    private void writeError(jakarta.servlet.http.HttpServletResponse response,
                            HttpStatus status,
                            String code,
                            String message) throws IOException {
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
    public PasswordEncoder passwordEncoder(SecurityProperties properties) {
        return new BCryptPasswordEncoder(properties.bcryptStrength());
    }
}
