package gestudio.platform.control;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.platform.PlatformMetrics;
import gestudio.platform.control.PlatformControlPlaneService.Activation;
import gestudio.platform.control.PlatformControlPlaneService.CreatedIdentity;
import gestudio.platform.control.PlatformControlPlaneService.IdentityRequest;
import gestudio.platform.security.PlatformPrincipal;
import gestudio.platform.security.PlatformStepUpService;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Pattern;

import static gestudio.platform.control.PlatformControlPlaneService.ACTIVE;
import static gestudio.platform.control.PlatformControlPlaneService.ARCHIVED;
import static gestudio.platform.control.PlatformControlPlaneService.REVOKED;
import static gestudio.platform.control.PlatformControlPlaneService.SUSPENDED;

final class PlatformControlPlaneCommandSupport {
    private static final String EXISTING_IDENTITY = "EXISTING";
    private static final String NEW_IDENTITY = "NEW";
    private static final String IDENTITY_ACTIVATION_PURPOSE = "IDENTITY_ACTIVATION";
    private static final Pattern TENANT_CODE =
            Pattern.compile("^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$");
    private static final Pattern USERNAME = Pattern.compile("^[A-Za-z0-9._@+-]{3,100}$");
    private static final Duration ACTIVATION_TTL = Duration.ofHours(24);

    private final PlatformControlPlaneRepository repository;
    private final PasswordEncoder passwordEncoder;
    private final ObjectMapper objectMapper;
    private final Clock clock;
    private final SecureRandom random = new SecureRandom();

    PlatformControlPlaneCommandSupport(PlatformControlPlaneRepository repository,
                                       PasswordEncoder passwordEncoder,
                                       ObjectMapper objectMapper,
                                       Clock clock) {
        this.repository = repository;
        this.passwordEncoder = passwordEncoder;
        this.objectMapper = objectMapper;
        this.clock = clock;
    }

    CreatedIdentity resolveIdentity(IdentityRequest request, long actorId, Instant now) {
        if (EXISTING_IDENTITY.equals(request.mode())) {
            var identity = repository.identity(request.userId())
                    .filter(PlatformControlPlaneRepository.IdentityView::active)
                    .orElseThrow(() -> new IllegalArgumentException("Identidad activa no encontrada"));
            return new CreatedIdentity(identity.id(), null);
        }
        String username = request.username().trim();
        String unavailable = passwordEncoder.encode(randomToken());
        long userId = repository.insertInactiveIdentity(username, unavailable);
        String token = randomToken();
        Instant expiresAt = now.plus(ACTIVATION_TTL);
        repository.insertActivation(UUID.randomUUID(), userId, IDENTITY_ACTIVATION_PURPOSE,
                PlatformStepUpService.hash(token), now, expiresAt, actorId);
        return new CreatedIdentity(userId, new Activation(token, expiresAt));
    }

    Activation activation(long userId, String purpose, long actorId, Instant now) {
        String token = randomToken();
        Instant expiresAt = now.plus(ACTIVATION_TTL);
        repository.insertActivation(UUID.randomUUID(), userId, purpose,
                PlatformStepUpService.hash(token), now, expiresAt, actorId);
        return new Activation(token, expiresAt);
    }

    void verifyClaim(PlatformIdempotencyRepository.Claim claim,
                     PlatformPrincipal actor, String requestHash) {
        if (claim.actorId() != actor.userId() || !claim.requestHash().equals(requestHash)) {
            throw new OperacionNoPermitidaException(
                    "La idempotency key ya fue usada por otra identidad o con otro contenido");
        }
        if (!claim.created() && !claim.succeeded()) {
            throw new OperacionNoPermitidaException(
                    "La idempotency key pertenece a una operación incompleta");
        }
    }

    IdentityRequest validateIdentity(IdentityRequest request) {
        if (request == null || request.mode() == null) {
            throw new IllegalArgumentException("La identidad administradora es obligatoria");
        }
        String mode = request.mode().trim().toUpperCase(Locale.ROOT);
        if (isExistingIdentity(request, mode)) {
            return new IdentityRequest(mode, request.userId(), null);
        }
        if (isNewIdentity(request, mode)) {
            return new IdentityRequest(mode, null, request.username().trim());
        }
        throw new IllegalArgumentException(
                "La identidad debe ser EXISTING con usuarioId o NEW con nombreUsuario");
    }

    String normalizedCode(String code) {
        String normalized = code == null ? "" : code.trim().toLowerCase(Locale.ROOT);
        if (!TENANT_CODE.matcher(normalized).matches()) {
            throw new IllegalArgumentException("Código de tenant inválido");
        }
        return normalized;
    }

    String validatedName(String name) {
        String value = name == null ? "" : name.trim();
        if (value.isEmpty() || value.length() > 150 || hasControl(value)) {
            throw new IllegalArgumentException("Nombre de tenant inválido");
        }
        return value;
    }

    List<String> normalizedRoles(List<String> requested) {
        if (requested == null || requested.isEmpty()) {
            throw new IllegalArgumentException("Se requiere al menos un rol");
        }
        LinkedHashSet<String> result = new LinkedHashSet<>();
        for (String role : requested) {
            String value = role == null ? "" : role.trim().toUpperCase(Locale.ROOT);
            if (!value.matches("^[A-Z][A-Z0-9_]{2,49}$")) {
                throw new IllegalArgumentException("Código de rol inválido");
            }
            result.add(value);
        }
        return result.stream().sorted().toList();
    }

    Instant validateValidUntil(Instant value) {
        if (value != null && !value.isAfter(clock.instant())) {
            throw new IllegalArgumentException("validUntil debe ser futuro");
        }
        return value;
    }

    String validateKey(String key) {
        String value = key == null ? "" : key.trim();
        if (value.isEmpty() || value.length() > 150 || hasControl(value)) {
            throw new IllegalArgumentException("Idempotency-Key es obligatoria e inválida");
        }
        return value;
    }

    String reason(String reason) {
        String value = reason == null ? "" : reason.trim();
        if (value.length() < 3 || value.length() > 250 || hasControl(value)) {
            throw new IllegalArgumentException("Se requiere un motivo válido");
        }
        return value;
    }

    String requiredStatus(String value, List<String> allowed) {
        String state = value == null ? "" : value.trim().toUpperCase(Locale.ROOT);
        if (!allowed.contains(state)) throw new IllegalArgumentException("Estado inválido");
        return state;
    }

    String json(Map<String, ?> value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException(
                    "No se pudo serializar el resultado idempotente", exception);
        }
    }

    OperacionNoPermitidaException concurrencyConflict() {
        return new OperacionNoPermitidaException(
                "El recurso fue modificado por otra operación; vuelva a cargarlo");
    }

    PlatformMetrics.TenantEvent tenantEvent(String state) {
        return switch (state) {
            case SUSPENDED -> PlatformMetrics.TenantEvent.SUSPENDED;
            case ACTIVE -> PlatformMetrics.TenantEvent.REACTIVATED;
            case ARCHIVED -> PlatformMetrics.TenantEvent.ARCHIVED;
            default -> throw new IllegalArgumentException("Estado de tenant no instrumentado");
        };
    }

    PlatformMetrics.MembershipEvent membershipEvent(String state) {
        return switch (state) {
            case SUSPENDED -> PlatformMetrics.MembershipEvent.SUSPENDED;
            case ACTIVE -> PlatformMetrics.MembershipEvent.REACTIVATED;
            case REVOKED -> PlatformMetrics.MembershipEvent.REVOKED;
            default -> throw new IllegalArgumentException(
                    "Estado de membership no instrumentado");
        };
    }

    private static boolean isExistingIdentity(IdentityRequest request, String mode) {
        return mode.equals(EXISTING_IDENTITY)
                && request.userId() != null
                && request.userId() > 0
                && (request.username() == null || request.username().isBlank());
    }

    private static boolean isNewIdentity(IdentityRequest request, String mode) {
        return mode.equals(NEW_IDENTITY)
                && request.userId() == null
                && request.username() != null
                && USERNAME.matcher(request.username().trim()).matches();
    }

    private static boolean hasControl(String value) {
        return value.chars().anyMatch(Character::isISOControl);
    }

    private String randomToken() {
        byte[] bytes = new byte[32];
        random.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }
}
