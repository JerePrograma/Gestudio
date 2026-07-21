package gestudio.infra.observabilidad;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.authorization.AuthorizationDecision;
import org.springframework.security.authorization.AuthorizationManager;
import org.springframework.security.core.Authentication;
import org.springframework.security.web.access.intercept.RequestAuthorizationContext;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.function.Supplier;

@Component
public final class MetricsTokenAuthorizationManager
        implements AuthorizationManager<RequestAuthorizationContext> {

    public static final String HEADER_NAME = "X-Gestudio-Metrics-Token";
    private static final int MAX_TOKEN_LENGTH = 512;

    private final byte[] expectedToken;

    public MetricsTokenAuthorizationManager(
            @Value("${app.observability.metrics-token:}") String configuredToken) {
        String normalized = configuredToken == null ? "" : configuredToken.trim();
        this.expectedToken = normalized.getBytes(StandardCharsets.UTF_8);
    }

    @Override
    public AuthorizationDecision check(Supplier<Authentication> authentication,
                                       RequestAuthorizationContext context) {
        return new AuthorizationDecision(matches(context.getRequest().getHeader(HEADER_NAME)));
    }

    boolean matches(String candidate) {
        if (expectedToken.length == 0 || candidate == null || candidate.isBlank()) {
            return false;
        }
        if (candidate.length() > MAX_TOKEN_LENGTH) {
            return false;
        }

        byte[] candidateBytes = candidate.getBytes(StandardCharsets.UTF_8);
        return MessageDigest.isEqual(expectedToken, candidateBytes);
    }
}
