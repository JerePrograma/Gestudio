package gestudio.infra.seguridad;

import com.fasterxml.jackson.databind.ObjectMapper;
import gestudio.entidades.Usuario;
import gestudio.platform.PlatformMetrics;
import gestudio.platform.security.PlatformTokenService;
import gestudio.tenancy.Tenant;
import gestudio.tenancy.TenantAccess;
import gestudio.tenancy.TenantAccessService;
import gestudio.tenancy.TenantContext;
import gestudio.tenancy.TenantMembership;
import gestudio.tenancy.TenantMetrics;
import gestudio.tenancy.TenantStatus;
import jakarta.servlet.FilterChain;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.AuthenticationEntryPoint;

import java.time.Clock;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class SecurityFilterTest {
    private static final Instant NOW = Instant.parse("2026-08-21T12:00:00Z");
    private static final UUID TENANT_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID MEMBERSHIP_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");

    @Mock private TokenService tokenService;
    @Mock private PlatformTokenService platformTokenService;
    @Mock private AuthenticationEntryPoint authenticationEntryPoint;
    @Mock private TenantAccessService tenantAccess;
    @Mock private TenantMetrics tenantMetrics;
    @Mock private PlatformMetrics platformMetrics;

    private SecurityFilter filter;

    @BeforeEach
    void setUp() {
        filter = new SecurityFilter(tokenService, platformTokenService, authenticationEntryPoint,
                tenantAccess, tenantMetrics, platformMetrics, new ObjectMapper(), Clock.systemUTC());
    }

    @AfterEach
    void clearContexts() {
        TenantContext.clear();
        SecurityContextHolder.clearContext();
    }

    @Test
    void nonBearerHeaderPreservesPreauthenticatedContextForTheChain() throws Exception {
        HttpServletRequest request = mock(HttpServletRequest.class);
        HttpServletResponse response = mock(HttpServletResponse.class);
        FilterChain chain = mock(FilterChain.class);
        when(request.getHeader("Authorization")).thenReturn("Basic credentials");
        var existing = new UsernamePasswordAuthenticationToken("trusted", null);
        SecurityContextHolder.getContext().setAuthentication(existing);

        try (TenantContext.Scope ignored = TenantContext.open(TENANT_ID, MEMBERSHIP_ID)) {
            filter.doFilterInternal(request, response, chain);

            assertThat(SecurityContextHolder.getContext().getAuthentication()).isSameAs(existing);
            assertThat(TenantContext.currentTenantId()).contains(TENANT_ID);
            verify(chain).doFilter(request, response);
        }
    }

    @Test
    void tokenSubjectMismatchIsRejectedBeforeAuthentication() throws Exception {
        Usuario user = new Usuario();
        user.setId(9L);
        user.setNombreUsuario("actual-user");
        user.setActivo(true);
        user.setAuthVersion(4L);
        TenantMembership membership = membership(user);
        TenantAccess access = new TenantAccess(membership);
        VerifiedToken verified = new VerifiedToken("token-user", 9L, "OPERADOR", 4L,
                TENANT_ID, MEMBERSHIP_ID, 3L, 5L, "jwt-1", TokenType.ACCESS,
                NOW.minusSeconds(30), NOW.plusSeconds(300));
        when(tokenService.verify("tenant-token", TokenType.ACCESS)).thenReturn(verified);
        when(tenantAccess.revalidate(9L, MEMBERSHIP_ID, TENANT_ID, 3L, 5L))
                .thenReturn(Optional.of(access));
        when(platformTokenService.verify("tenant-token", TokenType.ACCESS))
                .thenThrow(new InvalidTokenException());
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("Authorization", "Bearer tenant-token");
        MockHttpServletResponse response = new MockHttpServletResponse();
        FilterChain chain = mock(FilterChain.class);

        filter.doFilterInternal(request, response, chain);

        verify(authenticationEntryPoint).commence(any(), any(), any());
        verify(chain, never()).doFilter(any(), any());
        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
        assertThat(TenantContext.currentTenantId()).isEmpty();
    }

    @Test
    void pathFallbackHandlesNullBlankPlatformAndTenantPaths() {
        HttpServletRequest nullPath = mock(HttpServletRequest.class);
        when(nullPath.getServletPath()).thenReturn(null);
        when(nullPath.getRequestURI()).thenReturn(null);
        assertThat(filter.shouldNotFilter(nullPath)).isFalse();

        MockHttpServletRequest platformRequest = new MockHttpServletRequest();
        platformRequest.setServletPath("");
        platformRequest.setRequestURI("/api/platform/tenants");
        assertThat(filter.shouldNotFilter(platformRequest)).isTrue();

        for (String publicPath : new String[]{
                "/api/login", "/api/login/refresh", "/api/login/logout"}) {
            MockHttpServletRequest request = new MockHttpServletRequest();
            request.setServletPath(publicPath);
            assertThat(filter.shouldNotFilter(request)).as(publicPath).isTrue();
        }

        MockHttpServletRequest tenantRequest = new MockHttpServletRequest();
        tenantRequest.setServletPath("/api/alumnos");
        assertThat(filter.shouldNotFilter(tenantRequest)).isFalse();
    }

    private static TenantMembership membership(Usuario user) {
        Tenant tenant = new Tenant();
        tenant.setId(TENANT_ID);
        tenant.setStatus(TenantStatus.ACTIVE);
        tenant.setSecurityVersion(3L);
        TenantMembership membership = new TenantMembership();
        membership.setId(MEMBERSHIP_ID);
        membership.setTenant(tenant);
        membership.setUsuario(user);
        membership.setSecurityVersion(5L);
        return membership;
    }
}
