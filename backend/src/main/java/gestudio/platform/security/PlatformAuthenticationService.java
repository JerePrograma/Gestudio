package gestudio.platform.security;

import gestudio.infra.seguridad.InvalidTokenException;
import gestudio.platform.PlatformMetrics;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.AuthenticationException;
import org.springframework.stereotype.Service;

import java.time.Instant;

@Service
public class PlatformAuthenticationService {
    private final AuthenticationManager authenticationManager;
    private final PlatformIdentityRepository identities;
    private final PlatformMfaService mfa;
    private final PlatformRefreshSessionService sessions;
    private final PlatformMetrics metrics;

    public PlatformAuthenticationService(AuthenticationManager authenticationManager,
                                         PlatformIdentityRepository identities,
                                         PlatformMfaService mfa,
                                         PlatformRefreshSessionService sessions,
                                         PlatformMetrics metrics) {
        this.authenticationManager = authenticationManager;
        this.identities = identities;
        this.mfa = mfa;
        this.sessions = sessions;
        this.metrics = metrics;
    }

    public PlatformRefreshSessionService.Emission login(String rawUsername, String password,
                                                         MfaMethod method, String code,
                                                         String userAgent, String ip) {
        String username = rawUsername == null ? "" : rawUsername.trim();
        try {
            authenticationManager.authenticate(
                    new UsernamePasswordAuthenticationToken(username, password));
            var identity = identities.findActiveByUsername(username)
                    .orElseThrow(() -> new BadCredentialsException("Credenciales inválidas"));
            Instant mfaAt = switch (method) {
                case TOTP -> mfa.verifyTotp(identity.userId(), code);
                case RECOVERY -> mfa.verifyRecovery(identity.userId(), code);
            };
            return sessions.start(identity, mfaAt, userAgent, ip);
        } catch (PlatformMfaRateLimitedException exception) {
            metrics.authFailure(PlatformMetrics.AuthOperation.LOGIN,
                    PlatformMetrics.AuthFailureReason.MFA_RATE_LIMITED);
            throw exception;
        } catch (AuthenticationException exception) {
            metrics.authFailure(PlatformMetrics.AuthOperation.LOGIN,
                    PlatformMetrics.AuthFailureReason.INVALID_CREDENTIALS);
            throw new BadCredentialsException("Credenciales inválidas");
        }
    }

    public PlatformRefreshSessionService.Emission refresh(String refreshToken,
                                                           String userAgent, String ip) {
        try {
            return sessions.rotate(refreshToken, userAgent, ip);
        } catch (InvalidTokenException exception) {
            metrics.authFailure(PlatformMetrics.AuthOperation.REFRESH,
                    PlatformMetrics.AuthFailureReason.INVALID_SESSION);
            throw exception;
        }
    }

    public void logout(String refreshToken) {
        sessions.logout(refreshToken);
    }

    public PlatformPrincipal revalidate(PlatformVerifiedToken token) {
        var identity = identities.findActiveById(token.userId())
                .filter(value -> value.username().equals(token.subject()))
                .filter(value -> value.authVersion() == token.authVersion())
                .filter(value -> value.platformSecurityVersion() == token.platformSecurityVersion())
                .orElseThrow(InvalidTokenException::new);
        return new PlatformPrincipal(identity.userId(), identity.username(), identity.authVersion(),
                identity.platformSecurityVersion(), token.sessionId(), token.mfaVerifiedAt());
    }

    public enum MfaMethod {
        TOTP,
        RECOVERY
    }
}
