package gestudio.platform.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import gestudio.infra.seguridad.TokenService;
import gestudio.platform.PlatformMetrics;
import jakarta.servlet.FilterChain;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.mock.web.MockHttpServletRequest;

import java.time.Clock;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class PlatformSecurityFilterTest {
    @Mock private PlatformTokenService tokens;
    @Mock private TokenService tenantTokens;
    @Mock private PlatformAuthenticationService authentication;
    @Mock private PlatformMetrics metrics;

    private PlatformSecurityFilter filter;

    @BeforeEach
    void setUp() {
        filter = new PlatformSecurityFilter(tokens, tenantTokens, authentication, metrics,
                new ObjectMapper(), Clock.systemUTC());
    }

    @Test
    void nonBearerAuthorizationIsLeftToTheSecurityChain() throws Exception {
        HttpServletRequest request = mock(HttpServletRequest.class);
        HttpServletResponse response = mock(HttpServletResponse.class);
        FilterChain chain = mock(FilterChain.class);
        when(request.getHeader("Authorization")).thenReturn("Basic credentials");

        filter.doFilterInternal(request, response, chain);

        verify(chain).doFilter(request, response);
    }

    @Test
    void pathFallbackHandlesNullBlankPublicAndProtectedPaths() {
        HttpServletRequest nullPath = mock(HttpServletRequest.class);
        when(nullPath.getServletPath()).thenReturn(null);
        when(nullPath.getRequestURI()).thenReturn(null);
        assertThat(filter.shouldNotFilter(nullPath)).isTrue();

        MockHttpServletRequest protectedRequest = new MockHttpServletRequest();
        protectedRequest.setServletPath("");
        protectedRequest.setRequestURI("/api/platform/tenants");
        assertThat(filter.shouldNotFilter(protectedRequest)).isFalse();

        for (String publicPath : new String[]{
                "/api/login", "/api/platform/auth/login", "/api/platform/auth/refresh",
                "/api/platform/auth/logout", "/api/platform/identity/activate"}) {
            MockHttpServletRequest request = new MockHttpServletRequest();
            request.setServletPath(publicPath);
            assertThat(filter.shouldNotFilter(request)).as(publicPath).isTrue();
        }
    }
}
