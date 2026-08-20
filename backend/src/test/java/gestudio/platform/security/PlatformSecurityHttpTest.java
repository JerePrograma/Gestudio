package gestudio.platform.security;

import gestudio.entidades.Rol;
import gestudio.entidades.Usuario;
import gestudio.infra.configuracion.AppProperties;
import gestudio.infra.configuracion.ConfiguracionCors;
import gestudio.infra.errores.TratadorDeErrores;
import gestudio.infra.observabilidad.RequestCorrelationFilter;
import gestudio.infra.seguridad.JwtProperties;
import gestudio.infra.seguridad.SecurityConfigurations;
import gestudio.infra.seguridad.SecurityFilter;
import gestudio.infra.seguridad.SecurityProperties;
import gestudio.infra.seguridad.TokenService;
import gestudio.platform.PlatformMetrics;
import gestudio.platform.control.PlatformIdentityActivationController;
import gestudio.platform.control.PlatformIdentityActivationService;
import gestudio.tenancy.Tenant;
import gestudio.tenancy.TenantAccess;
import gestudio.tenancy.TenantAccessService;
import gestudio.tenancy.TenantMembership;
import gestudio.tenancy.TenantMembershipRole;
import gestudio.tenancy.TenantMembershipStatus;
import gestudio.tenancy.TenantMetrics;
import gestudio.tenancy.TenantStatus;
import jakarta.servlet.http.Cookie;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.hamcrest.Matchers.allOf;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(controllers = {
        PlatformAuthController.class,
        PlatformStepUpController.class,
        PlatformIdentityActivationController.class,
        PlatformSecurityHttpTest.ProbeController.class
})
@Import({
        SecurityConfigurations.class,
        SecurityFilter.class,
        PlatformSecurityFilter.class,
        TokenService.class,
        PlatformTokenService.class,
        ConfiguracionCors.class,
        RequestCorrelationFilter.class,
        TratadorDeErrores.class,
        PlatformSecurityHttpTest.PlatformHttpTestConfiguration.class
})
class PlatformSecurityHttpTest {
    private static final String ORIGIN = "https://app.example.test";
    private static final Instant NOW = Instant.now().minusSeconds(60).truncatedTo(ChronoUnit.SECONDS);
    private static final UUID PLATFORM_SESSION =
            UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");

    @MockitoBean private PlatformAuthenticationService authentication;
    @MockitoBean private PlatformStepUpService stepUp;
    @MockitoBean private PlatformIdentityActivationService identityActivation;
    @MockitoBean private TenantAccessService tenantAccessService;
    @MockitoBean private TenantMetrics tenantMetrics;
    @MockitoBean private PlatformMetrics platformMetrics;

    private final MockMvc mockMvc;
    private final PlatformTokenService platformTokens;
    private final TokenService tenantTokens;
    private TenantAccess tenantAccess;

    @Autowired
    PlatformSecurityHttpTest(MockMvc mockMvc, PlatformTokenService platformTokens,
                             TokenService tenantTokens) {
        this.mockMvc = mockMvc;
        this.platformTokens = platformTokens;
        this.tenantTokens = tenantTokens;
    }

    @BeforeEach
    void setUp() {
        tenantAccess = tenantAccess();
        when(tenantAccessService.revalidate(anyLong(), any(UUID.class), any(UUID.class),
                anyLong(), anyLong())).thenReturn(Optional.of(tenantAccess));
        when(authentication.revalidate(any(PlatformVerifiedToken.class))).thenAnswer(invocation -> {
            PlatformVerifiedToken verified = invocation.getArgument(0);
            return new PlatformPrincipal(verified.userId(), verified.subject(), verified.authVersion(),
                    verified.platformSecurityVersion(), verified.sessionId(), verified.mfaVerifiedAt());
        });
    }

    @Test
    void platformHttpMatrixSeparatesAnonymousTenantAndPlatformScopes() throws Exception {
        String platform = platformAccessToken();
        String tenant = tenantTokens.generarAccessToken(tenantAccess.usuario(), tenantAccess);

        mockMvc.perform(get("/api/platform/me"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"));
        mockMvc.perform(get("/api/usuarios/perfil"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"));

        MockMvc ordered = orderedFilterMockMvc();
        ordered.perform(get("/api/platform/me").servletPath("/api/platform/me")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer invalid"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("INVALID_TOKEN"));
        ordered.perform(get("/api/platform/me").servletPath("/api/platform/me")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + tenant))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("TOKEN_SCOPE_FORBIDDEN"));
        ordered.perform(get("/api/platform/me").servletPath("/api/platform/me")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + platform))
                .andExpect(status().isOk())
                .andExpect(content().string("platform-root"));

        ordered.perform(get("/api/usuarios/perfil").servletPath("/api/usuarios/perfil")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + platform))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("TOKEN_SCOPE_FORBIDDEN"));
        ordered.perform(get("/api/usuarios/perfil").servletPath("/api/usuarios/perfil")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + tenant))
                .andExpect(status().isOk())
                .andExpect(content().string("tenant-user"));
        verify(platformMetrics).authorizationDenied(
                PlatformMetrics.AuthorizationReason.CROSS_SCOPE,
                PlatformMetrics.Scope.TENANT, PlatformMetrics.Scope.PLATFORM);
        verify(platformMetrics).authorizationDenied(
                PlatformMetrics.AuthorizationReason.CROSS_SCOPE,
                PlatformMetrics.Scope.PLATFORM, PlatformMetrics.Scope.TENANT);
        verify(platformMetrics).authFailure(PlatformMetrics.AuthOperation.ACCESS,
                PlatformMetrics.AuthFailureReason.INVALID_TOKEN);
    }

    @Test
    void loginSetsOnlyHardenedRefreshCookieAndNeverReturnsRefreshTokenInJson() throws Exception {
        var emission = emission("access-1", "refresh-1");
        when(authentication.login(eq("root"), eq("strong-password"),
                eq(PlatformAuthenticationService.MfaMethod.TOTP), eq("123456"),
                eq("Browser/1.0"), anyString())).thenReturn(emission);

        mockMvc.perform(post("/api/platform/auth/login")
                        .header(HttpHeaders.ORIGIN, ORIGIN)
                        .header("User-Agent", "Browser/1.0")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"nombreUsuario":"root","contrasena":"strong-password",
                                 "metodo":"TOTP","codigo":"123456"}
                                """))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.SET_COOKIE, allOf(
                        containsString("gestudio_platform_refresh=refresh-1"),
                        containsString("Path=/api/platform/auth"),
                        containsString("Secure"), containsString("HttpOnly"),
                        containsString("SameSite=Strict"))))
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, containsString("no-store")))
                .andExpect(header().string(HttpHeaders.PRAGMA, "no-cache"))
                .andExpect(jsonPath("$.accessToken").value("access-1"))
                .andExpect(jsonPath("$.refreshToken").doesNotExist())
                .andExpect(jsonPath("$.profile.scope").value("PLATFORM"))
                .andExpect(jsonPath("$.profile.authorities[0]").value(PlatformPrincipal.AUTHORITY));
    }

    @Test
    void refreshRequiresCookieRotatesItAndLogoutClearsItIdempotently() throws Exception {
        mockMvc.perform(post("/api/platform/auth/refresh")
                        .header(HttpHeaders.ORIGIN, ORIGIN))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("INVALID_TOKEN"));
        verifyNoInteractions(authentication);

        when(authentication.refresh(eq("refresh-old"), eq("Browser/1.0"), anyString()))
                .thenReturn(emission("access-2", "refresh-new"));
        mockMvc.perform(post("/api/platform/auth/refresh")
                        .header(HttpHeaders.ORIGIN, ORIGIN)
                        .header("User-Agent", "Browser/1.0")
                        .cookie(new Cookie("gestudio_platform_refresh", "refresh-old")))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.SET_COOKIE,
                        containsString("gestudio_platform_refresh=refresh-new")))
                .andExpect(jsonPath("$.accessToken").value("access-2"));

        mockMvc.perform(post("/api/platform/auth/logout")
                        .header(HttpHeaders.ORIGIN, ORIGIN)
                        .cookie(new Cookie("gestudio_platform_refresh", "refresh-new")))
                .andExpect(status().isNoContent())
                .andExpect(header().string(HttpHeaders.SET_COOKIE, allOf(
                        containsString("gestudio_platform_refresh="), containsString("Max-Age=0"),
                        containsString("HttpOnly"), containsString("SameSite=Strict"))));
        verify(authentication).logout("refresh-new");
    }

    @Test
    void loginOriginValidationCredentialFailureAndMfaRateLimitUseStableStatuses() throws Exception {
        String body = """
                {"nombreUsuario":"root","contrasena":"strong-password",
                 "metodo":"TOTP","codigo":"123456"}
                """;
        mockMvc.perform(post("/api/platform/auth/login")
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("FORBIDDEN"));

        when(authentication.login(anyString(), anyString(), any(), anyString(), isNull(), anyString()))
                .thenThrow(new org.springframework.security.authentication.BadCredentialsException("secret detail"))
                .thenThrow(new PlatformMfaRateLimitedException(Duration.ofSeconds(45)));
        mockMvc.perform(post("/api/platform/auth/login")
                        .header(HttpHeaders.ORIGIN, ORIGIN)
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"))
                .andExpect(jsonPath("$.message").value("Credenciales inválidas"))
                .andExpect(content().string(not(containsString("secret detail"))));

        mockMvc.perform(post("/api/platform/auth/login")
                        .header(HttpHeaders.ORIGIN, ORIGIN)
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isTooManyRequests())
                .andExpect(header().string(HttpHeaders.RETRY_AFTER, "45"))
                .andExpect(jsonPath("$.code").value("MFA_RATE_LIMITED"));
    }

    @Test
    void publicActivationRequiresAllowedOriginAndReturnsRecoveryCodesOnlyForMfaPurpose() throws Exception {
        UUID correlationId = UUID.fromString("cccccccc-cccc-4ccc-8ccc-cccccccccccc");
        when(identityActivation.activate(eq("activation-token"), isNull(), eq("totp-secret"),
                eq("123456"), eq(correlationId)))
                .thenReturn(new PlatformIdentityActivationService.ActivationResult(
                        List.of("AAAAAAAA-BBBBBBBB-CCCCCCCC-DD")));
        String body = """
                {"token":"activation-token","totpSecret":"totp-secret","totpCode":"123456"}
                """;

        mockMvc.perform(post("/api/platform/identity/activate")
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isForbidden());
        mockMvc.perform(post("/api/platform/identity/activate")
                        .header(HttpHeaders.ORIGIN, ORIGIN)
                        .header(RequestCorrelationFilter.HEADER_NAME, correlationId.toString())
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk())
                .andExpect(header().string(
                        RequestCorrelationFilter.HEADER_NAME, correlationId.toString()))
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, containsString("no-store")))
                .andExpect(header().string(HttpHeaders.PRAGMA, "no-cache"))
                .andExpect(jsonPath("$.recoveryCodes[0]").value("AAAAAAAA-BBBBBBBB-CCCCCCCC-DD"));
    }

    @Test
    void stepUpChallengeAndProofAreNeverCacheable() throws Exception {
        UUID challengeId = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
        UUID correlationId = UUID.fromString("dddddddd-dddd-4ddd-8ddd-dddddddddddd");
        when(stepUp.challenge(any(PlatformPrincipal.class), eq("TENANT_STATUS"), eq("TENANT"),
                eq("tenant-42"), eq("request-1"), eq(correlationId)))
                .thenReturn(new PlatformStepUpService.ChallengeEmission(
                        challengeId, NOW.plusSeconds(180)));
        when(stepUp.verify(any(PlatformPrincipal.class), eq(challengeId), eq("123456")))
                .thenReturn(new PlatformStepUpService.ProofEmission(
                        "one-time-step-up-proof", NOW.plusSeconds(180)));

        mockMvc.perform(post("/api/platform/auth/step-up/challenges")
                        .with(org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors
                                .authentication(new org.springframework.security.authentication.UsernamePasswordAuthenticationToken(
                                        new PlatformPrincipal(91L, "platform-root", 2L, 7L,
                                                PLATFORM_SESSION, NOW.minusSeconds(30)), null,
                                        List.of(new org.springframework.security.core.authority.SimpleGrantedAuthority(
                                                PlatformPrincipal.AUTHORITY)))))
                        .header(RequestCorrelationFilter.HEADER_NAME, correlationId.toString())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"action":"TENANT_STATUS","targetType":"TENANT",
                                 "targetId":"tenant-42","idempotencyKey":"request-1"}
                                """))
                .andExpect(status().isOk())
                .andExpect(header().string(
                        RequestCorrelationFilter.HEADER_NAME, correlationId.toString()))
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, containsString("no-store")))
                .andExpect(header().string(HttpHeaders.PRAGMA, "no-cache"))
                .andExpect(jsonPath("$.challengeId").value(challengeId.toString()));

        mockMvc.perform(post("/api/platform/auth/step-up/challenges/{id}/verify", challengeId)
                        .with(org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors
                                .authentication(new org.springframework.security.authentication.UsernamePasswordAuthenticationToken(
                                        new PlatformPrincipal(91L, "platform-root", 2L, 7L,
                                                PLATFORM_SESSION, NOW.minusSeconds(30)), null,
                                        List.of(new org.springframework.security.core.authority.SimpleGrantedAuthority(
                                                PlatformPrincipal.AUTHORITY)))))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"code\":\"123456\"}"))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, containsString("no-store")))
                .andExpect(header().string(HttpHeaders.PRAGMA, "no-cache"))
                .andExpect(jsonPath("$.stepUpToken").value("one-time-step-up-proof"));
    }

    @Test
    void platformProfileIsNoStoreAndRevalidatedOnEveryRequest() throws Exception {
        mockMvc.perform(get("/api/platform/me")
                        .with(org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors
                                .authentication(new org.springframework.security.authentication.UsernamePasswordAuthenticationToken(
                                        new PlatformPrincipal(91L, "platform-root", 2L, 7L,
                                                PLATFORM_SESSION, NOW.minusSeconds(30)), null,
                                        List.of(new org.springframework.security.core.authority.SimpleGrantedAuthority(
                                                PlatformPrincipal.AUTHORITY))))))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, containsString("no-store")))
                .andExpect(jsonPath("$.nombreUsuario").value("platform-root"))
                .andExpect(jsonPath("$.mfaEnabled").value(true));
    }

    private MockMvc orderedFilterMockMvc() {
        com.fasterxml.jackson.databind.ObjectMapper mapper =
                new com.fasterxml.jackson.databind.ObjectMapper().findAndRegisterModules();
        PlatformSecurityFilter platform = new PlatformSecurityFilter(
                platformTokens, tenantTokens, authentication, platformMetrics, mapper,
                PlatformHttpTestConfiguration.clockStatic());
        org.springframework.security.web.AuthenticationEntryPoint entryPoint =
                (request, response, exception) -> {
                    response.setStatus(401);
                    response.setContentType(MediaType.APPLICATION_JSON_VALUE);
                    mapper.writeValue(response.getWriter(), new gestudio.infra.errores.ApiErrorResponse(
                            NOW, 401, "UNAUTHORIZED", "Autenticación requerida", List.of()));
                };
        SecurityFilter tenant = new SecurityFilter(tenantTokens, platformTokens, entryPoint,
                tenantAccessService, tenantMetrics, platformMetrics, mapper,
                PlatformHttpTestConfiguration.clockStatic());
        return org.springframework.test.web.servlet.setup.MockMvcBuilders
                .standaloneSetup(new OrderedProbeController())
                .addFilters(platform, tenant)
                .build();
    }

    private String platformAccessToken() {
        return platformTokens.issue(91L, "platform-root", 2L, 7L,
                PLATFORM_SESSION, NOW.minusSeconds(30)).accessToken();
    }

    private PlatformRefreshSessionService.Emission emission(String access, String refresh) {
        return new PlatformRefreshSessionService.Emission(access, refresh,
                NOW.plus(Duration.ofHours(8)), PLATFORM_SESSION, 91L, "platform-root",
                NOW.minusSeconds(30));
    }

    private TenantAccess tenantAccess() {
        Usuario user = new Usuario();
        user.setId(51L);
        user.setNombreUsuario("tenant-user");
        user.setContrasena("encoded");
        user.setActivo(true);
        user.setAuthVersion(0L);
        Rol role = new Rol(61L, "ADMINISTRADOR", true);
        user.setRol(role);
        user.setRoles(new LinkedHashSet<>(List.of(role)));

        Tenant tenant = new Tenant();
        tenant.setId(UUID.fromString("10000000-0000-0000-0000-000000000001"));
        tenant.setCode("tenant-test");
        tenant.setName("Tenant Test");
        tenant.setStatus(TenantStatus.ACTIVE);
        tenant.setSecurityVersion(3L);

        TenantMembership membership = new TenantMembership();
        membership.setId(UUID.fromString("20000000-0000-0000-0000-000000000001"));
        membership.setTenant(tenant);
        membership.setUsuario(user);
        membership.setStatus(TenantMembershipStatus.ACTIVE);
        membership.setSecurityVersion(4L);
        membership.setValidFrom(NOW.minusSeconds(3600));
        membership.getRoleAssignments().add(new TenantMembershipRole(membership, tenant, role));
        return new TenantAccess(membership);
    }

    @RestController
    static class ProbeController {
        @GetMapping("/api/platform/probe")
        String platform(@AuthenticationPrincipal PlatformPrincipal principal) {
            return principal.username();
        }

        @GetMapping("/api/usuarios/perfil")
        String tenant(@AuthenticationPrincipal Usuario principal) {
            return principal.getNombreUsuario();
        }
    }

    @RestController
    static class OrderedProbeController {
        @GetMapping("/api/platform/me")
        String platform() {
            Object principal = org.springframework.security.core.context.SecurityContextHolder
                    .getContext().getAuthentication().getPrincipal();
            return ((PlatformPrincipal) principal).username();
        }

        @GetMapping("/api/usuarios/perfil")
        String tenant() {
            Object principal = org.springframework.security.core.context.SecurityContextHolder
                    .getContext().getAuthentication().getPrincipal();
            return ((Usuario) principal).getNombreUsuario();
        }
    }

    @TestConfiguration(proxyBeanMethods = false)
    static class PlatformHttpTestConfiguration {
        @Bean
        Clock clock() {
            return clockStatic();
        }

        static Clock clockStatic() {
            return Clock.fixed(NOW, ZoneOffset.UTC);
        }

        @Bean
        JwtProperties jwtProperties() {
            return new JwtProperties("platform-http-test-secret-with-more-than-32-bytes",
                    "gestudio-http-test", "gestudio-web", Duration.ofMinutes(10), Duration.ofHours(8));
        }

        @Bean
        PlatformSecurityProperties platformSecurityProperties() {
            return new PlatformSecurityProperties("gestudio-platform", Duration.ofMinutes(5),
                    Duration.ofHours(8), Duration.ofMinutes(3),
                    Base64.getEncoder().encodeToString(
                            "0123456789abcdef0123456789abcdef".getBytes(StandardCharsets.US_ASCII)),
                    1, new PlatformSecurityProperties.RefreshCookie(
                    "gestudio_platform_refresh", true, "Strict", null, "/api/platform/auth"));
        }

        @Bean
        SecurityProperties securityProperties() {
            return new SecurityProperties(10, new SecurityProperties.RefreshCookie(
                    "gestudio_refresh", true, "Strict", null, "/api/login"));
        }

        @Bean
        AppProperties appProperties() {
            return new AppProperties(ZoneId.of("America/Argentina/Buenos_Aires"),
                    Path.of("target", "platform-http-test"), List.of(ORIGIN));
        }

    }
}
