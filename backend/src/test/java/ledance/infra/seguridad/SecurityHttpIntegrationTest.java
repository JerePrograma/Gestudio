package ledance.infra.seguridad;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import ledance.controladores.PagoControlador;
import ledance.controladores.UsuarioControlador;
import ledance.controladores.AutenticacionControlador;
import ledance.controladores.RolControlador;
import ledance.dto.usuario.response.UsuarioResponse;
import ledance.entidades.Rol;
import ledance.entidades.Usuario;
import ledance.infra.configuracion.AppProperties;
import ledance.infra.configuracion.ConfiguracionCors;
import ledance.infra.errores.TratadorDeErrores;
import ledance.repositorios.UsuarioRepositorio;
import ledance.repositorios.ReciboRepositorio;
import ledance.servicios.pago.PagoServicio;
import ledance.servicios.usuario.UsuarioServicio;
import ledance.servicios.rol.RolServicio;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.nio.file.Path;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.util.Date;
import java.util.List;
import java.util.Optional;
import java.time.Duration;
import java.util.UUID;
import jakarta.servlet.http.Cookie;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.nullable;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.containsString;
import static org.assertj.core.api.Assertions.assertThat;

@WebMvcTest(controllers = {
        AutenticacionControlador.class,
        UsuarioControlador.class,
        RolControlador.class,
        PagoControlador.class
})
@Import({
        SecurityConfigurations.class,
        SecurityFilter.class,
        TokenService.class,
        ConfiguracionCors.class,
        TratadorDeErrores.class,
        SecurityHttpIntegrationTest.SecurityTestConfiguration.class
})
class SecurityHttpIntegrationTest {

    private static final String SECRET = "security-http-test-secret-with-at-least-32-characters";
    private static final String ISSUER = "security-http-test";

    @MockitoBean
    private UsuarioRepositorio usuarioRepositorio;
    @MockitoBean
    private AutenticacionService autenticacionService;
    @MockitoBean
    private UsuarioServicio usuarioServicio;
    @MockitoBean
    private RolServicio rolServicio;
    @MockitoBean
    private PagoServicio pagoServicio;
    @MockitoBean
    private ReciboRepositorio reciboRepositorio;

    private final MockMvc mockMvc;
    private final TokenService tokenService;

    @Autowired
    SecurityHttpIntegrationTest(MockMvc mockMvc, TokenService tokenService) {
        this.mockMvc = mockMvc;
        this.tokenService = tokenService;
    }

    @BeforeEach
    void configureControllerMocks() {
        when(usuarioServicio.convertirAUsuarioResponse(any(Usuario.class)))
                .thenAnswer(invocation -> {
                    Usuario user = invocation.getArgument(0);
                    return new UsuarioResponse(
                            user.getId(),
                            user.getNombreUsuario(),
                            user.getRol().getDescripcion(),
                            user.getActivo()
                    );
                });
        when(usuarioServicio.listarUsuarios(isNull(), isNull())).thenReturn(List.of());
        when(rolServicio.listarRoles()).thenReturn(List.of());
    }

    @Test
    void accessValidoAutenticaUsuarioActivo() throws Exception {
        Usuario user = usuario(1L, "admin", "ADMINISTRADOR", true);
        when(usuarioRepositorio.findById(1L)).thenReturn(Optional.of(user));

        mockMvc.perform(get("/api/usuarios/perfil")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(user))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombreUsuario").value("admin"));
    }

    @Test
    void loginValidoEntregaAmbosTokensYLoginInvalidoDevuelve401() throws Exception {
        Usuario user = usuario(1L, "admin", "ADMINISTRADOR", true);
        when(autenticacionService.login(any(), nullable(String.class), anyString()))
                .thenReturn(resultado(user))
                .thenThrow(new BadCredentialsException("detalle interno que no debe exponerse"));

        String loginJson = """
                {"nombreUsuario":"admin","contrasena":"correcta"}
                """;
        mockMvc.perform(post("/api/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(loginJson))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accessToken").isString())
                .andExpect(jsonPath("$.refreshToken").doesNotExist())
                .andExpect(header().string(HttpHeaders.SET_COOKIE, containsString("HttpOnly")));

        mockMvc.perform(post("/api/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(loginJson))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.status").value(401))
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"))
                .andExpect(jsonPath("$.message").value("Credenciales inválidas"));
    }

    @Test
    void refreshSinCookieDevuelve401() throws Exception {
        when(autenticacionService.refresh(anyString(), nullable(String.class), anyString()))
                .thenThrow(new InvalidTokenException());
        mockMvc.perform(post("/api/login/refresh")
                        .header(HttpHeaders.ORIGIN, "https://app.example.test"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void refreshValidoRotaAccessYRefresh() throws Exception {
        Usuario active = usuario(1L, "admin", "ADMINISTRADOR", true);
        when(autenticacionService.refresh(anyString(), nullable(String.class), anyString()))
                .thenReturn(resultado(active));

        mockMvc.perform(post("/api/login/refresh")
                        .header(HttpHeaders.ORIGIN, "https://app.example.test")
                        .cookie(new Cookie("ledance_refresh", "refresh-raw")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accessToken").isString())
                .andExpect(jsonPath("$.refreshToken").doesNotExist())
                .andExpect(jsonPath("$.usuario.activo").value(true));
    }

    @Test
    void accessVencidoFirmaInvalidaEIssuerInvalidoDevuelven401() throws Exception {
        Instant now = Instant.now();
        String expired = rawToken(SECRET, ISSUER, now.minusSeconds(120), now.minusSeconds(60), "ACCESS", 1L, "ADMINISTRADOR");
        String wrongSignature = rawToken("another-security-test-secret-with-at-least-32-chars", ISSUER, now, now.plusSeconds(60), "ACCESS", 1L, "ADMINISTRADOR");
        String wrongIssuer = rawToken(SECRET, "wrong-issuer", now, now.plusSeconds(60), "ACCESS", 1L, "ADMINISTRADOR");

        assertUnauthorized(expired);
        assertUnauthorized(wrongSignature);
        assertUnauthorized(wrongIssuer);
    }

    @Test
    void refreshUsadoComoAccessDevuelve401() throws Exception {
        Usuario user = usuario(1L, "admin", "ADMINISTRADOR", true);

        assertUnauthorized(tokenService.generarRefreshToken(user, UUID.randomUUID()));
    }

    @Test
    void usuarioInactivoYSinRolNoQuedanAutorizados() throws Exception {
        Usuario inactive = usuario(1L, "inactive", "ADMINISTRADOR", false);
        when(usuarioRepositorio.findById(1L)).thenReturn(Optional.of(inactive));
        assertUnauthorized(tokenService.generarAccessToken(inactive));

        Usuario withoutRole = usuario(2L, "without-role", "OPERADOR", true);
        String token = tokenService.generarAccessToken(withoutRole);
        withoutRole.setRol(null);
        when(usuarioRepositorio.findById(2L)).thenReturn(Optional.of(withoutRole));
        assertUnauthorized(token);
    }

    @Test
    void usuariosRequiereSuperadminYLaJerarquiaConservaAccesoAdministrativo() throws Exception {
        Usuario operator = usuario(2L, "operator", "OPERADOR", true);
        when(usuarioRepositorio.findById(2L)).thenReturn(Optional.of(operator));
        String operatorToken = tokenService.generarAccessToken(operator);

        mockMvc.perform(get("/api/usuarios")
                        .header(HttpHeaders.AUTHORIZATION, bearer(operatorToken)))
                .andExpect(status().isForbidden());
        mockMvc.perform(get("/api/pagos/recibo/999")
                        .header(HttpHeaders.AUTHORIZATION, bearer(operatorToken)))
                .andExpect(status().isForbidden());

        Usuario admin = usuario(1L, "admin", "ADMINISTRADOR", true);
        when(usuarioRepositorio.findById(1L)).thenReturn(Optional.of(admin));
        mockMvc.perform(get("/api/usuarios")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(admin))))
                .andExpect(status().isForbidden());

        Usuario superadmin = usuario(3L, "root", "SUPERADMIN", true);
        when(usuarioRepositorio.findById(3L)).thenReturn(Optional.of(superadmin));
        mockMvc.perform(get("/api/usuarios")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(superadmin))))
                .andExpect(status().isOk());
        mockMvc.perform(get("/api/pagos/recibo/999")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(superadmin))))
                .andExpect(result -> assertThat(result.getResponse().getStatus()).isNotIn(401, 403));
    }

    @Test
    void registroDeUsuariosYRolesNoSonPublicos() throws Exception {
        String registration = """
                {"nombreUsuario":"nuevo","contrasena":"una-clave-segura","rol":"ADMINISTRADOR"}
                """;
        mockMvc.perform(post("/api/usuarios/registro")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(registration))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(get("/api/roles"))
                .andExpect(status().isUnauthorized());

        Usuario operator = usuario(2L, "operator", "OPERADOR", true);
        when(usuarioRepositorio.findById(2L)).thenReturn(Optional.of(operator));
        String token = tokenService.generarAccessToken(operator);
        mockMvc.perform(post("/api/usuarios/registro")
                        .header(HttpHeaders.AUTHORIZATION, bearer(token))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(registration))
                .andExpect(status().isForbidden());
        mockMvc.perform(get("/api/roles")
                        .header(HttpHeaders.AUTHORIZATION, bearer(token)))
                .andExpect(status().isForbidden());
    }

    @Test
    void operacionFinancieraRequiereAdministrador() throws Exception {
        String body = """
                {"alumnoId":1,"metodoPagoId":1,"montoRecibido":"10.00",
                 "idempotencyKey":"security-test","aplicaciones":[],"generarCredito":true}
                """;
        mockMvc.perform(post("/api/pagos").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"));

        Usuario operator = usuario(2L, "operator", "OPERADOR", true);
        when(usuarioRepositorio.findById(2L)).thenReturn(Optional.of(operator));
        mockMvc.perform(post("/api/pagos")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(operator)))
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isForbidden());
    }

    @Test
    void matrizFinancieraExplicitaRechazaAnonimoYOperador() throws Exception {
        Usuario operator = usuario(2L, "operator", "OPERADOR", true);
        Usuario admin = usuario(1L, "admin", "ADMINISTRADOR", true);
        String[] endpoints = {
                "/api/cargos/1", "/api/pagos/1", "/api/creditos/alumno/1/saldo",
                "/api/caja/resumen", "/api/egresos/1", "/api/stocks/1",
                "/api/pagos/recibo/1", "/api/reportes/mensualidades"
        };

        for (String endpoint : endpoints) {
            mockMvc.perform(get(endpoint)).andExpect(status().isUnauthorized());
            when(usuarioRepositorio.findById(2L)).thenReturn(Optional.of(operator));
            mockMvc.perform(get(endpoint).header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(operator))))
                    .andExpect(status().isForbidden());
            when(usuarioRepositorio.findById(1L)).thenReturn(Optional.of(admin));
            mockMvc.perform(get(endpoint).header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(admin))))
                    .andExpect(result -> assertThat(result.getResponse().getStatus()).isNotIn(401, 403));
        }
    }

    @Test
    void pagoConIdempotencyKeyInvalidaDevuelve400() throws Exception {
        Usuario admin = usuario(1L, "admin", "ADMINISTRADOR", true);
        when(usuarioRepositorio.findById(1L)).thenReturn(Optional.of(admin));
        String body = """
                {"alumnoId":1,"metodoPagoId":1,"montoRecibido":"10.00",
                 "idempotencyKey":"","aplicaciones":[],"generarCredito":true}
                """;
        mockMvc.perform(post("/api/pagos")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(admin)))
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest());
    }

    @Test
    void corsPreflightConOrigenPermitidoPasaPorLaCadenaReal() throws Exception {
        mockMvc.perform(options("/api/usuarios")
                        .header(HttpHeaders.ORIGIN, "https://app.example.test")
                        .header(HttpHeaders.ACCESS_CONTROL_REQUEST_METHOD, "GET"))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "https://app.example.test"));
    }

    @Test
    void errorInternoNoExponeDetalleDeLaExcepcion() throws Exception {
        Usuario superadmin = usuario(1L, "root", "SUPERADMIN", true);
        when(usuarioRepositorio.findById(1L)).thenReturn(Optional.of(superadmin));
        when(usuarioServicio.listarUsuarios(isNull(), isNull()))
                .thenThrow(new RuntimeException("cadena interna sensible"));

        mockMvc.perform(get("/api/usuarios")
                        .header(HttpHeaders.AUTHORIZATION,
                                bearer(tokenService.generarAccessToken(superadmin))))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.status").value(500))
                .andExpect(jsonPath("$.code").value("INTERNAL_ERROR"))
                .andExpect(jsonPath("$.message").value("Ocurrió un error inesperado"))
                .andExpect(jsonPath("$.fieldErrors").isEmpty())
                .andExpect(content().string(not(containsString("cadena interna sensible"))));
    }

    private void assertUnauthorized(String token) throws Exception {
        mockMvc.perform(get("/api/usuarios/perfil")
                        .header(HttpHeaders.AUTHORIZATION, bearer(token)))
                .andExpect(status().isUnauthorized());
    }

    private String bearer(String token) {
        return "Bearer " + token;
    }

    private Usuario usuario(Long id, String username, String role, boolean active) {
        Usuario usuario = new Usuario();
        usuario.setId(id);
        usuario.setNombreUsuario(username);
        usuario.setContrasena("encoded-password");
        usuario.setRol(new Rol(id, role, true));
        usuario.setActivo(active);
        usuario.setAuthVersion(0L);
        return usuario;
    }

    private String rawToken(
            String secret,
            String issuer,
            Instant issuedAt,
            Instant expiresAt,
            String type,
            Long userId,
            String role) {
        return JWT.create()
                .withIssuer(issuer)
                .withAudience("le-dance-web")
                .withSubject("admin")
                .withClaim("id", userId)
                .withClaim("rol", role)
                .withClaim("type", type)
                .withClaim("auth_version", 0L)
                .withJWTId(UUID.randomUUID().toString())
                .withIssuedAt(Date.from(issuedAt))
                .withExpiresAt(Date.from(expiresAt))
                .sign(Algorithm.HMAC256(secret));
    }

    @TestConfiguration(proxyBeanMethods = false)
    static class SecurityTestConfiguration {

        @Bean
        JwtProperties jwtProperties() {
            return new JwtProperties(SECRET, ISSUER, "le-dance-web", Duration.ofHours(1), Duration.ofHours(24));
        }

        @Bean
        SecurityProperties securityProperties() {
            return new SecurityProperties(4,
                    new SecurityProperties.RefreshCookie("ledance_refresh", true, "Strict", "", "/api/login"));
        }

        @Bean
        Clock clock() {
            return Clock.systemUTC();
        }

        @Bean
        AppProperties appProperties() {
            return new AppProperties(
                    ZoneId.of("America/Argentina/Buenos_Aires"),
                    Path.of("target", "security-test-receipts"),
                    List.of("https://app.example.test")
            );
        }
    }

    private AutenticacionService.Resultado resultado(Usuario user) {
        return new AutenticacionService.Resultado("access-token", "refresh-token",
                Instant.now().plusSeconds(3600),
                new UsuarioResponse(user.getId(), user.getNombreUsuario(), user.getRol().getDescripcion(), user.getActivo()));
    }
}
