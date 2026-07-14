package gestudio.infra.seguridad;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import jakarta.servlet.http.Cookie;
import jakarta.validation.Constraint;
import jakarta.validation.Valid;
import gestudio.dto.usuario.response.UsuarioResponse;
import gestudio.entidades.Permiso;
import gestudio.entidades.Recibo;
import gestudio.entidades.Rol;
import gestudio.entidades.Usuario;
import gestudio.infra.configuracion.AppProperties;
import gestudio.infra.configuracion.ConfiguracionCors;
import gestudio.infra.errores.TratadorDeErrores;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
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
import org.springframework.context.annotation.ClassPathScanningCandidateComponentProvider;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.core.annotation.AnnotatedElementUtils;
import org.springframework.core.type.filter.AnnotationTypeFilter;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.data.domain.Page;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.io.IOException;
import java.lang.annotation.Annotation;
import java.lang.reflect.AnnotatedElement;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.Date;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.ArgumentMatchers.nullable;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static gestudio.infra.seguridad.PermissionCodes.*;

@WebMvcTest
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
    @MockitoBean private gestudio.servicios.alumno.AlumnoServicio alumnoServicio;
    @MockitoBean private gestudio.servicios.asistencia.AsistenciaDiariaServicio asistenciaDiariaServicio;
    @MockitoBean private gestudio.servicios.asistencia.AsistenciaMensualServicio asistenciaMensualServicio;
    @MockitoBean private gestudio.servicios.bonificacion.BonificacionServicio bonificacionServicio;
    @MockitoBean private gestudio.servicios.caja.CajaServicio cajaServicio;
    @MockitoBean private gestudio.servicios.cargo.CargoServicio cargoServicio;
    @MockitoBean private gestudio.servicios.concepto.ConceptoServicio conceptoServicio;
    @MockitoBean private gestudio.servicios.concepto.SubConceptoServicio subConceptoServicio;
    @MockitoBean private gestudio.servicios.credito.CreditoServicio creditoServicio;
    @MockitoBean private gestudio.servicios.disciplina.DisciplinaServicio disciplinaServicio;
    @MockitoBean private gestudio.servicios.egreso.EgresoServicio egresoServicio;
    @MockitoBean private gestudio.servicios.inscripcion.InscripcionServicio inscripcionServicio;
    @MockitoBean private gestudio.servicios.matricula.MatriculaServicio matriculaServicio;
    @MockitoBean private gestudio.servicios.mensualidad.MensualidadServicio mensualidadServicio;
    @MockitoBean private gestudio.servicios.notificaciones.NotificacionService notificacionService;
    @MockitoBean private gestudio.servicios.observaciones.ObservacionProfesorServicio observacionProfesorServicio;
    @MockitoBean private gestudio.servicios.pago.MetodoPagoServicio metodoPagoServicio;
    @MockitoBean private gestudio.servicios.pdfs.PdfService pdfService;
    @MockitoBean private gestudio.servicios.profesor.ProfesorServicio profesorServicio;
    @MockitoBean private gestudio.servicios.recargo.RecargoServicio recargoServicio;
    @MockitoBean private gestudio.servicios.reporte.ReporteServicio reporteServicio;
    @MockitoBean private gestudio.servicios.salon.SalonServicio salonServicio;
    @MockitoBean private gestudio.servicios.stock.StockServicio stockServicio;
    @MockitoBean private gestudio.tarifas.application.CondicionEconomicaServicio condicionEconomicaServicio;
    @MockitoBean private gestudio.tarifas.application.TarifaDisciplinaServicio tarifaDisciplinaServicio;
    @MockitoBean private gestudio.repositorios.ConceptoRepositorio conceptoRepositorio;
    @MockitoBean private gestudio.dto.concepto.ConceptoMapper conceptoMapper;

    private final MockMvc mockMvc;
    private final TokenService tokenService;

    @Autowired
    SecurityHttpIntegrationTest(MockMvc mockMvc, TokenService tokenService) {
        this.mockMvc = mockMvc;
        this.tokenService = tokenService;
    }

    @BeforeEach
    void configureControllerMocks() throws IOException {
        when(usuarioServicio.convertirAUsuarioResponse(any(Usuario.class)))
                .thenAnswer(invocation -> usuarioResponse(invocation.getArgument(0)));

        when(usuarioServicio.listarUsuarios(isNull(), isNull()))
                .thenReturn(List.of());

        when(rolServicio.listarRoles())
                .thenReturn(List.of());

        when(permisoServicio.listarPermisos(isNull()))
                .thenReturn(List.of());

        when(alumnoServicio.listarAlumnos(any())).thenReturn(Page.empty());
        when(inscripcionServicio.listarInscripciones(anyString(), any())).thenReturn(Page.empty());
        when(egresoServicio.listarEgresos(any())).thenReturn(Page.empty());
        when(cargoServicio.listarVencidos(any())).thenReturn(Page.empty());
        when(cargoServicio.listarPendientes(anyLong(), any())).thenReturn(Page.empty());
        when(pagoServicio.listarPagosPorAlumno(anyLong(), any())).thenReturn(Page.empty());
        when(stockServicio.listarStocks(any())).thenReturn(Page.empty());

        var subConcepto = new gestudio.entidades.SubConcepto(1L, "Test", true);
        when(subConceptoServicio.findByDescripcionIgnoreCase(anyString())).thenReturn(subConcepto);
        when(conceptoRepositorio.findBySubConceptoId(1L)).thenReturn(List.of());

        Path reciboPath = Path.of("target", "security-test-receipts", "matrix.pdf");
        Files.createDirectories(reciboPath.getParent());
        Files.write(reciboPath, new byte[]{1});
        Recibo recibo = new Recibo();
        recibo.setStorageKey("matrix.pdf");
        when(reciboRepositorio.findByPagoId(anyLong())).thenReturn(Optional.of(recibo));
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
    void usuariosRequierePermisoYRolesBaseConservanSuMatriz() throws Exception {
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
                .andExpect(status().isOk());

        mockMvc.perform(get("/api/usuarios/roles-asignables")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(admin))))
                .andExpect(status().isOk());

        mockMvc.perform(get("/api/roles")
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

        Rol acceso = new Rol(11L, "ACCESO", true);
        acceso.getPermisos().add(permiso(PERM_APP_ACCESO));

        Rol cobranzas = new Rol(12L, "COBRANZAS", true);
        cobranzas.getPermisos().add(permiso(PERM_PAGOS_LEER));

        user.setRol(acceso);
        user.setRoles(new LinkedHashSet<>(List.of(acceso, cobranzas)));

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
        activeWithoutPermission.getPermisos().add(permiso(PERM_APP_ACCESO));

        Rol disabled = new Rol(12L, "COBRANZAS", false);
        disabled.getPermisos().add(permiso(PERM_PAGOS_LEER));

        inactiveRole.setRoles(new LinkedHashSet<>(List.of(activeWithoutPermission, disabled)));

        when(usuarioRepositorio.findByIdConRolesYPermisos(11L))
                .thenReturn(Optional.of(inactiveRole));

        mockMvc.perform(get("/api/pagos/999")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(inactiveRole))))
                .andExpect(status().isForbidden());

        Usuario inactivePermission = usuario(12L, "inactive-permission", "LECTURA", true);

        inactivePermission.getRol().getPermisos().add(permiso(PERM_APP_ACCESO));

        Permiso permiso = permiso(PERM_PAGOS_LEER);
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
    void todosLosEndpointsRealesTienenPoliticaYExigenAppMasPermisoFuncional() throws Exception {
        List<DiscoveredEndpoint> endpoints = discoverEndpoints();
        List<String> mismatches = new ArrayList<>();

        assertThat(endpoints).hasSize(144);

        for (DiscoveredEndpoint endpoint : endpoints) {
            if (endpoint.path().startsWith("/api/login")
                    || endpoint.path().equals("/api/usuarios/perfil")) {
                continue;
            }

            EndpointPolicy policy = expectedPolicy(endpoint);
            EndpointPolicyRow row = new EndpointPolicyRow(
                    endpoint.method(),
                    endpoint.path(),
                    policy.permissions(),
                    endpoint.allowedStatus(),
                    policy.denied()
            );
            String label = row.method() + " " + row.path();

            int anonymous = mockMvc.perform(matrixRequest(endpoint))
                    .andReturn()
                    .getResponse()
                    .getStatus();
            recordMismatch(mismatches, label, "anónimo", 401, anonymous);

            if (row.denied()) {
                Usuario superadmin = usuario(24L, "root-matrix", "SUPERADMIN", true);
                when(usuarioRepositorio.findByIdConRolesYPermisos(24L)).thenReturn(Optional.of(superadmin));

                int denied = mockMvc.perform(matrixRequest(endpoint)
                                .header(HttpHeaders.AUTHORIZATION,
                                        bearer(tokenService.generarAccessToken(superadmin))))
                        .andReturn()
                        .getResponse()
                        .getStatus();
                recordMismatch(mismatches, label, "fuera de alcance", 403, denied);
                continue;
            }

            Usuario functionalOnly = usuarioConPermisos(21L, "functional-only", row.requiredPermissions());
            when(usuarioRepositorio.findByIdConRolesYPermisos(21L)).thenReturn(Optional.of(functionalOnly));

            int withoutApp = mockMvc.perform(matrixRequest(endpoint)
                            .header(HttpHeaders.AUTHORIZATION,
                                    bearer(tokenService.generarAccessToken(functionalOnly))))
                    .andReturn()
                    .getResponse()
                    .getStatus();
            recordMismatch(mismatches, label, "sin APP", 403, withoutApp);

            Usuario appOnly = usuarioConPermisos(22L, "app-only", Set.of(PERM_APP_ACCESO));
            when(usuarioRepositorio.findByIdConRolesYPermisos(22L)).thenReturn(Optional.of(appOnly));

            int withoutFunctional = mockMvc.perform(matrixRequest(endpoint)
                            .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(appOnly))))
                    .andReturn()
                    .getResponse()
                    .getStatus();
            recordMismatch(mismatches, label, "sin permiso funcional", 403, withoutFunctional);

            Set<String> granted = new LinkedHashSet<>(row.requiredPermissions());
            granted.add(PERM_APP_ACCESO);
            Usuario allowed = usuarioConPermisos(23L, "allowed", granted);
            when(usuarioRepositorio.findByIdConRolesYPermisos(23L)).thenReturn(Optional.of(allowed));

            int allowedStatus = mockMvc.perform(matrixRequest(endpoint)
                            .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(allowed))))
                    .andReturn()
                    .getResponse()
                    .getStatus();
            recordMismatch(mismatches, label, "autorizado", row.allowedStatus(), allowedStatus);
            if (allowedStatus == 404 || allowedStatus == 500) {
                mismatches.add(label + " no alcanzó un controller funcional: status=" + allowedStatus);
            }
        }

        assertThat(mismatches)
                .as("mismatches de la matriz HTTP real")
                .isEmpty();
    }

    private static void recordMismatch(
            List<String> mismatches,
            String endpoint,
            String scenario,
            int expected,
            int actual
    ) {
        if (actual != expected) {
            mismatches.add(endpoint + " " + scenario + ": esperado=" + expected + ", actual=" + actual);
        }
    }

    @Test
    void rutaDesconocidaYCondicionesConSoloTarifasQuedanDenegadas() throws Exception {
        Usuario superadmin = usuario(25L, "root-unknown", "SUPERADMIN", true);
        when(usuarioRepositorio.findByIdConRolesYPermisos(25L)).thenReturn(Optional.of(superadmin));

        mockMvc.perform(post("/api/nueva-mutacion-no-declarada")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(superadmin))))
                .andExpect(status().isForbidden());

        Usuario tarifas = usuarioConPermisos(
                26L,
                "tarifas-only",
                Set.of(PERM_APP_ACCESO, PERM_TARIFAS_ADMIN)
        );
        when(usuarioRepositorio.findByIdConRolesYPermisos(26L)).thenReturn(Optional.of(tarifas));

        mockMvc.perform(get("/api/inscripciones/1/condiciones-economicas")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(tarifas))))
                .andExpect(status().isForbidden());
    }

    @Test
    void conflictoDeDominioAutorizadoConserva409YCodigoFuncional() throws Exception {
        Usuario admin = usuario(27L, "admin-conflict", "ADMINISTRADOR", true);
        when(usuarioRepositorio.findByIdConRolesYPermisos(27L)).thenReturn(Optional.of(admin));
        when(pagoServicio.registrarPago(any(), any()))
                .thenThrow(new OperacionNoPermitidaException("La idempotency key ya fue usada"));

        String body = """
                {"alumnoId":1,"metodoPagoId":1,"montoRecibido":"10.00",
                 "idempotencyKey":"security-conflict","aplicaciones":[],"generarCredito":true}
                """;

        mockMvc.perform(post("/api/pagos")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(admin)))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("IDEMPOTENCY_CONFLICT"));
    }

    @Test
    void denegacionDeServicioAutorizadoEnHttpConserva403Json() throws Exception {
        Usuario cajero = usuarioConPermisos(
                28L,
                "cajero-denied",
                Set.of(PERM_APP_ACCESO, PERM_PAGOS_REGISTRAR)
        );
        when(usuarioRepositorio.findByIdConRolesYPermisos(28L)).thenReturn(Optional.of(cajero));
        when(pagoServicio.registrarPago(any(), any()))
                .thenThrow(new AccessDeniedException("detalle interno de autorización"));

        String body = """
                {"alumnoId":1,"metodoPagoId":1,"montoRecibido":"10.00",
                 "idempotencyKey":"security-denied","aplicaciones":[],"generarCredito":true}
                """;

        mockMvc.perform(post("/api/pagos")
                        .header(HttpHeaders.AUTHORIZATION, bearer(tokenService.generarAccessToken(cajero)))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.status").value(403))
                .andExpect(jsonPath("$.code").value("FORBIDDEN"))
                .andExpect(jsonPath("$.message").value("Permisos insuficientes"));
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

    private static List<DiscoveredEndpoint> discoverEndpoints() {
        var scanner = new ClassPathScanningCandidateComponentProvider(false);
        scanner.addIncludeFilter(new AnnotationTypeFilter(RestController.class));

        List<DiscoveredEndpoint> endpoints = new ArrayList<>();

        for (var candidate : scanner.findCandidateComponents("gestudio")) {
            try {
                Class<?> controller = Class.forName(candidate.getBeanClassName());
                RequestMapping base = AnnotatedElementUtils.findMergedAnnotation(controller, RequestMapping.class);
                String[] basePaths = paths(base);

                for (var method : controller.getDeclaredMethods()) {
                    RequestMapping mapping = AnnotatedElementUtils.findMergedAnnotation(method, RequestMapping.class);
                    if (mapping == null) {
                        continue;
                    }

                    for (String basePath : basePaths) {
                        for (String methodPath : paths(mapping)) {
                            for (RequestMethod requestMethod : mapping.method()) {
                                String template = joinedPath(basePath, methodPath);
                                endpoints.add(new DiscoveredEndpoint(
                                        requestMethod,
                                        concretePath(template),
                                        expectedAllowedStatus(method, template)
                                ));
                            }
                        }
                    }
                }
            } catch (ClassNotFoundException exception) {
                throw new IllegalStateException("No se pudo inventariar " + candidate.getBeanClassName(), exception);
            }
        }

        return endpoints.stream()
                .distinct()
                .sorted(Comparator.comparing(DiscoveredEndpoint::path)
                        .thenComparing(endpoint -> endpoint.method().name()))
                .toList();
    }

    private static MockHttpServletRequestBuilder matrixRequest(DiscoveredEndpoint endpoint) {
        return request(HttpMethod.valueOf(endpoint.method().name()), endpoint.path())
                .contentType(MediaType.APPLICATION_JSON)
                .content("{}");
    }

    private static String[] paths(RequestMapping mapping) {
        if (mapping == null) {
            return new String[]{""};
        }
        if (mapping.path().length > 0) {
            return mapping.path();
        }
        return mapping.value().length == 0 ? new String[]{""} : mapping.value();
    }

    private static String joinedPath(String base, String path) {
        String joined = (base + "/" + path).replaceAll("/{2,}", "/");
        return joined.length() > 1 && joined.endsWith("/")
                ? joined.substring(0, joined.length() - 1)
                : joined;
    }

    private static String concretePath(String template) {
        return template.replaceAll("\\{[^/]+}", "1");
    }

    private static int expectedAllowedStatus(java.lang.reflect.Method method, String template) {
        if (template.startsWith("/api/observaciones-profesores")) return 403;
        if (Arrays.stream(method.getParameters()).anyMatch(parameter ->
                parameter.isAnnotationPresent(RequestBody.class)
                        && (parameter.isAnnotationPresent(Valid.class)
                        || parameter.isAnnotationPresent(org.springframework.validation.annotation.Validated.class))
                        && hasValidationConstraint(parameter.getType()))) {
            return 400;
        }
        if (Arrays.stream(method.getParameters()).anyMatch(parameter -> {
            RequestParam requestParam = parameter.getAnnotation(RequestParam.class);
            return requestParam != null
                    && requestParam.required()
                    && org.springframework.web.bind.annotation.ValueConstants.DEFAULT_NONE.equals(requestParam.defaultValue());
        })) {
            return 400;
        }
        if (template.equals("/api/mensualidades/generar-mensualidades")) return 201;
        if (template.equals("/api/disciplinas/listado")) return 204;
        if (template.equals("/api/profesores/{profesorId}/alumnos")) return 204;
        if (method.isAnnotationPresent(org.springframework.web.bind.annotation.DeleteMapping.class)) {
            return template.equals("/api/stocks/{id}") || template.equals("/api/inscripciones/{id}")
                    ? 200
                    : 204;
        }
        return 200;
    }

    private static boolean hasValidationConstraint(Class<?> requestType) {
        if (hasConstraintAnnotation(requestType)) {
            return true;
        }
        if (Arrays.stream(requestType.getDeclaredFields()).anyMatch(SecurityHttpIntegrationTest::hasConstraintAnnotation)) {
            return true;
        }
        return requestType.isRecord()
                && Arrays.stream(requestType.getRecordComponents())
                .anyMatch(SecurityHttpIntegrationTest::hasConstraintAnnotation);
    }

    private static boolean hasConstraintAnnotation(AnnotatedElement element) {
        return Arrays.stream(element.getAnnotations())
                .map(Annotation::annotationType)
                .anyMatch(annotationType -> annotationType.isAnnotationPresent(Constraint.class));
    }

    private static EndpointPolicy expectedPolicy(DiscoveredEndpoint endpoint) {
        RequestMethod method = endpoint.method();
        String path = endpoint.path();

        if (path.startsWith("/api/observaciones-profesores")) return EndpointPolicy.disabled();
        if (path.startsWith("/api/usuarios")) return EndpointPolicy.required(PERM_USUARIOS_ADMIN);
        if (path.startsWith("/api/roles") || path.startsWith("/api/permisos")) {
            return EndpointPolicy.required(PERM_ROLES_ADMIN);
        }
        if (path.equals("/api/inscripciones/1/condiciones-economicas")) {
            return EndpointPolicy.required(PERM_CONDICIONES_ECONOMICAS_ADMIN);
        }
        if (path.startsWith("/api/inscripciones")) {
            return readOrWrite(method, PERM_INSCRIPCIONES_LEER, PERM_INSCRIPCIONES_ADMIN);
        }
        if (path.equals("/api/disciplinas/1/tarifas")) {
            return EndpointPolicy.required(PERM_TARIFAS_ADMIN);
        }
        if (path.equals("/api/disciplinas/1/alumnos/pdf")) {
            return EndpointPolicy.required(PERM_DISCIPLINAS_LEER, PERM_REPORTES_EXPORTAR);
        }
        if (path.startsWith("/api/disciplinas")) {
            return readOrWrite(method, PERM_DISCIPLINAS_LEER, PERM_DISCIPLINAS_ADMIN);
        }
        if (path.startsWith("/api/alumnos")) {
            return readOrWrite(method, PERM_ALUMNOS_LEER, PERM_ALUMNOS_ADMIN);
        }
        if (path.startsWith("/api/profesores")) {
            return readOrWrite(method, PERM_PROFESORES_LEER, PERM_PROFESORES_ADMIN);
        }
        if (path.startsWith("/api/asistencias-diarias") || path.startsWith("/api/asistencias-mensuales")) {
            return readOrWrite(method, PERM_ASISTENCIAS_LEER, PERM_ASISTENCIAS_REGISTRAR);
        }
        if (path.startsWith("/api/mensualidades")) {
            return switch (method) {
                case GET -> EndpointPolicy.required(PERM_PAGOS_LEER);
                case POST -> EndpointPolicy.required(PERM_MENSUALIDADES_GENERAR_MANUAL);
                case DELETE -> EndpointPolicy.required(PERM_PAGOS_ANULAR);
                default -> unsupported(endpoint);
            };
        }
        if (path.startsWith("/api/matriculas")) {
            if (method == RequestMethod.GET) return EndpointPolicy.required(PERM_PAGOS_LEER);
            if (path.endsWith("/anulacion")) return EndpointPolicy.required(PERM_PAGOS_ANULAR);
            if (method == RequestMethod.POST) return EndpointPolicy.required(PERM_INSCRIPCIONES_ADMIN);
            return unsupported(endpoint);
        }
        if (path.startsWith("/api/cargos")) {
            return method == RequestMethod.GET
                    ? EndpointPolicy.required(PERM_PAGOS_LEER)
                    : method == RequestMethod.POST
                    ? EndpointPolicy.required(PERM_PAGOS_REGISTRAR)
                    : unsupported(endpoint);
        }
        if (path.startsWith("/api/pagos")) {
            if (method == RequestMethod.GET) return EndpointPolicy.required(PERM_PAGOS_LEER);
            if (path.endsWith("/anulacion")) return EndpointPolicy.required(PERM_PAGOS_ANULAR);
            if (method == RequestMethod.POST) return EndpointPolicy.required(PERM_PAGOS_REGISTRAR);
            return unsupported(endpoint);
        }
        if (path.startsWith("/api/caja")) return EndpointPolicy.required(PERM_CAJA_LEER);
        if (path.startsWith("/api/egresos")) return EndpointPolicy.required(PERM_EGRESOS_ADMIN);
        if (path.startsWith("/api/stocks")) {
            if (method == RequestMethod.GET) return EndpointPolicy.required(PERM_STOCK_LEER);
            if (path.equals("/api/stocks/ventas")) return EndpointPolicy.required(PERM_STOCK_VENDER);
            return EndpointPolicy.required(PERM_STOCK_ADMIN);
        }
        if (path.startsWith("/api/creditos")) {
            if (method == RequestMethod.GET) return EndpointPolicy.required(PERM_PAGOS_LEER);
            if (path.equals("/api/creditos/consumos")) return EndpointPolicy.required(PERM_CREDITOS_CONSUMIR);
            return EndpointPolicy.required(PERM_CREDITOS_ADMIN);
        }
        if (path.startsWith("/api/reportes")) {
            return method == RequestMethod.GET
                    ? EndpointPolicy.required(PERM_REPORTES_LEER)
                    : EndpointPolicy.required(PERM_REPORTES_EXPORTAR);
        }
        if (path.startsWith("/api/notificaciones")) return EndpointPolicy.required(PERM_ALUMNOS_LEER);
        if (isConfigurationPath(path)) {
            return readOrWrite(method, PERM_CONFIG_LEER, PERM_CONFIG_ADMIN);
        }

        return unsupported(endpoint);
    }

    private static boolean isConfigurationPath(String path) {
        return path.startsWith("/api/metodos-pago")
                || path.startsWith("/api/conceptos")
                || path.startsWith("/api/sub-conceptos")
                || path.startsWith("/api/salones")
                || path.startsWith("/api/bonificaciones")
                || path.startsWith("/api/recargos");
    }

    private static EndpointPolicy readOrWrite(RequestMethod method, String read, String write) {
        return method == RequestMethod.GET
                ? EndpointPolicy.required(read)
                : EndpointPolicy.required(write);
    }

    private static EndpointPolicy unsupported(DiscoveredEndpoint endpoint) {
        throw new IllegalStateException("Endpoint sin política declarada: "
                + endpoint.method() + " " + endpoint.path());
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

    private Usuario usuarioConPermisos(Long id, String username, Set<String> permissions) {
        Usuario usuario = usuario(id, username, "TEST", true);
        usuario.getRol().getPermisos().clear();
        permissions.forEach(code -> usuario.getRol().getPermisos().add(permiso(code)));
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
            return ALL.stream().toList();
        }

        if ("ADMINISTRADOR".equals(role)) {
            return ALL.stream()
                    .filter(permission -> !PERM_ROLES_ADMIN.equals(permission))
                    .toList();
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

    private record DiscoveredEndpoint(RequestMethod method, String path, int allowedStatus) {
    }

    private record EndpointPolicy(boolean denied, Set<String> permissions) {

        private static EndpointPolicy required(String... permissions) {
            return new EndpointPolicy(false, Set.of(permissions));
        }

        private static EndpointPolicy disabled() {
            return new EndpointPolicy(true, Set.of());
        }
    }

    private record EndpointPolicyRow(
            RequestMethod method,
            String path,
            Set<String> requiredPermissions,
            int allowedStatus,
            boolean denied
    ) {
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
