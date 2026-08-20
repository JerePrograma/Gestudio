package gestudio.platform.security;

import gestudio.infra.observabilidad.RequestCorrelationFilter;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.http.ResponseEntity;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
@RequestMapping("/api/platform/auth/step-up/challenges")
@Validated
public class PlatformStepUpController {
    private final PlatformStepUpService stepUp;

    public PlatformStepUpController(PlatformStepUpService stepUp) {
        this.stepUp = stepUp;
    }

    @PostMapping
    public ResponseEntity<PlatformStepUpService.ChallengeEmission> challenge(
            @AuthenticationPrincipal PlatformPrincipal principal,
            @RequestBody @Valid ChallengeRequest request,
            @RequestAttribute(name = RequestCorrelationFilter.ATTRIBUTE_NAME) UUID correlationId) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .header(HttpHeaders.PRAGMA, "no-cache")
                .body(stepUp.challenge(principal, request.action(), request.targetType(),
                        request.targetId(), request.idempotencyKey(), correlationId));
    }

    @PostMapping("/{challengeId}/verify")
    public ResponseEntity<PlatformStepUpService.ProofEmission> verify(
            @AuthenticationPrincipal PlatformPrincipal principal,
            @PathVariable UUID challengeId,
            @RequestBody @Valid VerifyRequest request) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .header(HttpHeaders.PRAGMA, "no-cache")
                .body(stepUp.verify(principal, challengeId, request.code()));
    }

    public record ChallengeRequest(
            @NotBlank @Size(max = 100) String action,
            @NotBlank @Size(max = 100) String targetType,
            @NotBlank @Size(max = 100) String targetId,
            @NotBlank @Size(max = 150) String idempotencyKey) {
    }

    public record VerifyRequest(@NotBlank @Size(max = 80) String code) {
    }
}
