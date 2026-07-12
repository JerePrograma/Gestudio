package gestudio.infra.seguridad;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import jakarta.servlet.http.Cookie;
import gestudio.controladores.AutenticacionControlador;
import gestudio.controladores.PagoControlador;
import gestudio.controladores.PermisoControlador;
import gestudio.controladores.RolControlador;
import gestudio.controladores.UsuarioControlador;
import gestudio.dto.usuario.response.UsuarioResponse;
import gestudio.entidades.Permiso;
import gestudio.entidades.Rol;
import gestudio.entidades.Usuario;
import gestudio.infra.configuracion.AppProperties;
import gestudio.infra.configuracion.ConfiguracionCors;
import gestudio.infra.errores.TratadorDeErrores;
import gestudio.repositorios.ReciboRepositorio;
import gestudio.repositorios.UsuarioRepositorio;
import gestudio.servicios.pago.PagoServicio;
import gestudio.servicios.permiso.PermisoServicio;
import gestudio.servicios.rol.RolServicio;
import gestudio.servicios.usuario.UsuarioServicio;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.nio.file.Path;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.util.Date;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.ArgumentMatchers.nullable;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(controllers = {
        AutenticacionControlador.class,
        UsuarioControlador.class,
        RolControlador.class,
        PermisoControlador.class,
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

    @MockitoBean private UsuarioRepositorio usuarioRepositorio;
    @MockitoBean private AutenticacionService autenticacionService;
    @MockitoBean private UsuarioServicio usuarioServicio;
    @MockitoBean private RolServicio rolServicio;
    @MockitoBean private PermisoServicio permisoServicio;
    @MockitoBean private PagoServicio pagoServicio;
    @MockitoBean private ReciboRepositorio reciboRepositorio;

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
                .thenAnswer(invocation -> usuarioResponse(invocation.getArgument(0)));

        when(usuarioServicio.listarUsuarios(isNull(), isNull()))
                .thenReturn(List.of());

        when(rolServicio.listarRoles())
                .thenReturn(List.of());

        when(permisoServicio.listarPermisos(isNull()))
                .thenReturn(List.of());
    }

    @Test
    void accessValidoAutenticaUsuarioActivo() throws Exception {
        Usuario user = usuario(1L, "admin", "ADMINISTRADOR", true);

        when(usuarioRepositorio.findByIdConRolesYPermisos(1L))
                .thenReturn(Optional.of(user));

        mockMvc.perform(get("/api/usuarios/perfil")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(user))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombreUsuario").value("admin"));
    }

    @Test
    void loginSinJwtNoEsBloqueadoYCredencialesInvalidasDevuelven401() throws Exception {
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
                        .cookie(new Cookie("gestudio_refresh", "refresh-raw")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accessToken").isString())
                .andExpect(jsonPath("$.refreshToken").doesNotExist())
                .andExpect(jsonPath("$.usuario.activo").value(true));
    }

    @Test
    void accessVencidoFirmaInvalidaEIssuerInvalidoDevuelven401() throws Exception {
        Instant now = Instant.now();

        String expired = rawToken(SECRET, ISSUER, now.minusSeconds(120), now.minusSeconds(60), "ACCESS", 1L);
        String wrongSignature = rawToken(
                "another-security-test-secret-with-at-least-32-chars",
                ISSUER,
                now,
                now.plusSeconds(60),
                "ACCESS",
                1L
        );
        String wrongIssuer = rawToken(SECRET, "wrong-issuer", now, now.plusSeconds(60), "ACCESS", 1L);

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

        when(usuarioRepositorio.findByIdConRolesYPermisos(1L))
                .thenReturn(Optional.of(inactive));

        assertUnauthorized(tokenService.generarAccessToken(inactive));

        Usuario withoutRole = usuario(2L, "without-role", "OPERADOR", true);
        String token = tokenService.generarAccessToken(withoutRole);

        withoutRole.setRol(null);
        withoutRole.getRoles().clear();

        when(usuarioRepositorio.findByIdConRolesYPermisos(2L))
                .thenReturn(Optional.of(withoutRole));

        assertUnauthorized(token);
    }

    @Test
    void usuariosRequierePermisoYRolConPermisosConservaAccesoOperativo() throws Exception {
        Usuario operator = usuario(2L, "operator", "OPERADOR", true);

        when(usuarioRepositorio.findByIdConRolesYPermisos(2L))
                .thenReturn(Optional.of(operator));

        String operatorToken = tokenService.generarAccessToken(operator);

        mockMvc.perform(get("/api/usuarios")
                        .header(HttpHeaders.AUTHORIZATION, bearer(operatorToken)))
                .andExpect(status().isForbidden());

        mockMvc.perform(get("/api/pagos/recibo/999")
                        .header(HttpHeaders.AUTHORIZATION, bearer(operatorToken)))
                .andExpect(status().isForbidden());

        Usuario admin = usuario(1L, "admin", "ADMINISTRADOR", true);

        when(usuarioRepositorio.findByIdConRolesYPermisos(1L))
                .thenReturn(Optional.of(admin));

        mockMvc.perform(get("/api/usuarios")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(admin))))
                .andExpect(status().isForbidden());

        Usuario superadmin = usuario(3L, "root", "SUPERADMIN", true);

        when(usuarioRepositorio.findByIdConRolesYPermisos(3L))
                .thenReturn(Optional.of(superadmin));

        mockMvc.perform(get("/api/usuarios")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(superadmin))))
                .andExpect(status().isOk());

        mockMvc.perform(get("/api/pagos/recibo/999")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(superadmin))))
                .andExpect(result -> assertThat(result.getResponse().getStatus()).isNotIn(401, 403));
    }

    @Test
    void multiplesRolesSumanPermisosActivos() throws Exception {
        Usuario user = usuario(10L, "multi", "RECEPCION", true);

        Rol cobranzas = new Rol(11L, "COBRANZAS", true);
        cobranzas.getPermisos().add(permiso("PERM_APP_ACCESO"));

        user.getRoles().add(cobranzas);

        when(usuarioRepositorio.findByIdConRolesYPermisos(10L))
                .thenReturn(Optional.of(user));

        mockMvc.perform(get("/api/pagos/999")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(user))))
                .andExpect(result -> assertThat(result.getResponse().getStatus()).isNotIn(401, 403));
    }

    @Test
    void rolInactivoYPermisoInactivoNoAutorizan() throws Exception {
        Usuario inactiveRole = usuario(11L, "inactive-role", "LECTURA", true);

        Rol activeWithoutPermission = inactiveRole.getRol();

        Rol disabled = new Rol(12L, "COBRANZAS", false);
        disabled.getPermisos().add(permiso("PERM_APP_ACCESO"));

        inactiveRole.setRoles(new LinkedHashSet<>(List.of(activeWithoutPermission, disabled)));

        when(usuarioRepositorio.findByIdConRolesYPermisos(11L))
                .thenReturn(Optional.of(inactiveRole));

        mockMvc.perform(get("/api/pagos/999")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(inactiveRole))))
                .andExpect(status().isForbidden());

        Usuario inactivePermission = usuario(12L, "inactive-permission", "LECTURA", true);

        Permiso permiso = permiso("PERM_APP_ACCESO");
        permiso.setActivo(false);

        inactivePermission.getRol().getPermisos().add(permiso);

        when(usuarioRepositorio.findByIdConRolesYPermisos(12L))
                .thenReturn(Optional.of(inactivePermission));

        mockMvc.perform(get("/api/pagos/999")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(inactivePermission))))
                .andExpect(status().isForbidden());
    }

    @Test
    void cambioDeAuthVersionInvalidaElAccessToken() throws Exception {
        Usuario user = usuario(13L, "versioned", "ADMINISTRADOR", true);
        String token = tokenService.generarAccessToken(user);

        user.setAuthVersion(1L);

        when(usuarioRepositorio.findByIdConRolesYPermisos(13L))
                .thenReturn(Optional.of(user));

        assertUnauthorized(token);
    }

    @Test
    void registroDeUsuariosYRolesNoSonPublicos() throws Exception {
        String registration = """
                {"nombreUsuario":"nuevo","contrasena":"una-clave-segura","roles":["ADMINISTRADOR"]}
                """;

        mockMvc.perform(post("/api/usuarios/registro")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(registration))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/api/roles"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/api/permisos"))
                .andExpect(status().isUnauthorized());

        Usuario operator = usuario(2L, "operator", "OPERADOR", true);

        when(usuarioRepositorio.findByIdConRolesYPermisos(2L))
                .thenReturn(Optional.of(operator));

        String token = tokenService.generarAccessToken(operator);

        mockMvc.perform(post("/api/usuarios/registro")
                        .header(HttpHeaders.AUTHORIZATION, bearer(token))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(registration))
                .andExpect(status().isForbidden());

        mockMvc.perform(get("/api/roles")
                        .header(HttpHeaders.AUTHORIZATION, bearer(token)))
                .andExpect(status().isForbidden());

        mockMvc.perform(get("/api/permisos")
                        .header(HttpHeaders.AUTHORIZATION, bearer(token)))
                .andExpect(status().isForbidden());

        Usuario superadmin = usuario(3L, "root", "SUPERADMIN", true);

        when(usuarioRepositorio.findByIdConRolesYPermisos(3L))
                .thenReturn(Optional.of(superadmin));

        String superadminToken = tokenService.generarAccessToken(superadmin);

        mockMvc.perform(get("/api/roles")
                        .header(HttpHeaders.AUTHORIZATION, bearer(superadminToken)))
                .andExpect(status().isOk());

        mockMvc.perform(get("/api/permisos")
                        .header(HttpHeaders.AUTHORIZATION, bearer(superadminToken)))
                .andExpect(status().isOk());
    }

    @Test
    void operacionFinancieraRequiereUsuarioConAccesoApp() throws Exception {
        String body = """
                {"alumnoId":1,"metodoPagoId":1,"montoRecibido":"10.00",
                 "idempotencyKey":"security-test","aplicaciones":[],"generarCredito":true}
                """;

        mockMvc.perform(post("/api/pagos").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"));

        Usuario operator = usuario(2L, "operator", "OPERADOR", true);

        when(usuarioRepositorio.findByIdConRolesYPermisos(2L))
                .thenReturn(Optional.of(operator));

        mockMvc.perform(post("/api/pagos")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(operator)))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isForbidden());
    }

    @Test
    void matrizFinancieraExplicitaRechazaAnonimoYOperador() throws Exception {
        Usuario operator = usuario(2L, "operator", "OPERADOR", true);
        Usuario admin = usuario(1L, "admin", "ADMINISTRADOR", true);

        String[] endpoints = {
                "/api/cargos/1",
                "/api/pagos/1",
                "/api/creditos/alumno/1/saldo",
                "/api/caja/resumen",
                "/api/egresos/1",
                "/api/stocks/1",
                "/api/pagos/recibo/1",
                "/api/reportes/mensualidades"
        };

        for (String endpoint : endpoints) {
            mockMvc.perform(get(endpoint))
                    .andExpect(status().isUnauthorized());

            when(usuarioRepositorio.findByIdConRolesYPermisos(2L))
                    .thenReturn(Optional.of(operator));

            mockMvc.perform(get(endpoint)
                            .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(operator))))
                    .andExpect(status().isForbidden());

            when(usuarioRepositorio.findByIdConRolesYPermisos(1L))
                    .thenReturn(Optional.of(admin));

            mockMvc.perform(get(endpoint)
                            .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(admin))))
                    .andExpect(result -> assertThat(result.getResponse().getStatus()).isNotIn(401, 403));
        }
    }

    @Test
    void pagoConIdempotencyKeyInvalidaDevuelve400() throws Exception {
        Usuario admin = usuario(1L, "admin", "ADMINISTRADOR", true);

        when(usuarioRepositorio.findByIdConRolesYPermisos(1L))
                .thenReturn(Optional.of(admin));

        String body = """
                {"alumnoId":1,"metodoPagoId":1,"montoRecibido":"10.00",
                 "idempotencyKey":"","aplicaciones":[],"generarCredito":true}
                """;

        mockMvc.perform(post("/api/pagos")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(admin)))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
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

        when(usuarioRepositorio.findByIdConRolesYPermisos(1L))
                .thenReturn(Optional.of(superadmin));

        when(usuarioServicio.listarUsuarios(isNull(), isNull()))
                .thenThrow(new RuntimeException("cadena interna sensible"));

        mockMvc.perform(get("/api/usuarios")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(superadmin))))
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
                .andExpect(status().isUnauthorized())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.status").value(401))
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"))
                .andExpect(jsonPath("$.message").value("Autenticación requerida"))
                .andExpect(jsonPath("$.fieldErrors").isEmpty());
    }

    private String bearer(String token) {
        return "Bearer " + token;
    }

    private Usuario usuario(Long id, String username, String role, boolean active) {
        Rol rol = new Rol(id, role, true);
        defaultPermissions(role).forEach(code -> rol.getPermisos().add(permiso(code)));

        Usuario usuario = new Usuario();
        usuario.setId(id);
        usuario.setNombreUsuario(username);
        usuario.setContrasena("encoded-password");
        usuario.setRol(rol);
        usuario.setRoles(new LinkedHashSet<>(List.of(rol)));
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
            Long userId
    ) {
        return JWT.create()
                .withIssuer(issuer)
                .withAudience("gestudio-web")
                .withSubject("admin")
                .withClaim("id", userId)
                .withClaim("type", type)
                .withClaim("rol", "ADMINISTRADOR")
                .withClaim("auth_version", 0L)
                .withJWTId(UUID.randomUUID().toString())
                .withIssuedAt(Date.from(issuedAt))
                .withExpiresAt(Date.from(expiresAt))
                .sign(Algorithm.HMAC256(secret));
    }

    private List<String> defaultPermissions(String role) {
        if ("SUPERADMIN".equals(role)) {
            return List.of(
                    "PERM_APP_ACCESO",
                    "PERM_USUARIOS_ADMIN",
                    "PERM_ROLES_ADMIN",
                    "PERM_AUDITORIA_SEGURIDAD_LEER",
                    "PERM_MENSUALIDADES_GENERAR_MANUAL"
            );
        }

        if ("ADMINISTRADOR".equals(role)) {
            return List.of("PERM_APP_ACCESO");
        }

        return List.of();
    }

    private Permiso permiso(String code) {
        Permiso permiso = new Permiso();
        permiso.setCodigo(code);
        permiso.setDescripcion(code);
        permiso.setModulo("TEST");
        permiso.setActivo(true);
        permiso.setSistema(true);
        return permiso;
    }

    private UsuarioResponse usuarioResponse(Usuario user) {
        return new UsuarioResponse(
                user.getId(),
                user.getNombreUsuario(),
                user.codigosRolesActivos().stream().toList(),
                user.codigosPermisosActivos().stream().toList(),
                user.getActivo()
        );
    }

    private AutenticacionService.Resultado resultado(Usuario user) {
        return new AutenticacionService.Resultado(
                "access-token",
                "refresh-token",
                Instant.now().plusSeconds(3600),
                usuarioResponse(user)
        );
    }

    @TestConfiguration(proxyBeanMethods = false)
    static class SecurityTestConfiguration {

        @Bean
        JwtProperties jwtProperties() {
            return new JwtProperties(
                    SECRET,
                    ISSUER,
                    "gestudio-web",
                    Duration.ofHours(1),
                    Duration.ofHours(24)
            );
        }

        @Bean
        SecurityProperties securityProperties() {
            return new SecurityProperties(
                    4,
                    new SecurityProperties.RefreshCookie(
                            "gestudio_refresh",
                            true,
                            "Strict",
                            "",
                            "/api/login"
                    )
            );
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
}
