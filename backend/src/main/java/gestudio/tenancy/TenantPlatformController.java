package gestudio.tenancy;

import gestudio.entidades.Usuario;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.Set;
import java.util.UUID;

@RestController
@RequestMapping("/api/platform/tenants")
@Validated
public class TenantPlatformController {
    private final TenantProvisioningService provisioning;

    public TenantPlatformController(TenantProvisioningService provisioning) {
        this.provisioning = provisioning;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public ProvisionedTenantResponse create(@RequestBody @Valid CreateTenantRequest request,
                                            @AuthenticationPrincipal Usuario actor) {
        var result = provisioning.createTenant(
                request.codigo(), request.nombre(), request.initialAdminUserId(), actor);
        return new ProvisionedTenantResponse(
                result.tenant().getId(),
                result.tenant().getCode(),
                result.tenant().getName(),
                result.tenant().getStatus(),
                result.initialAdminMembership().getId()
        );
    }

    @PatchMapping("/{tenantId}/status")
    public TenantSummaryResponse status(@PathVariable UUID tenantId,
                                        @RequestBody @Valid TenantStatusRequest request,
                                        @AuthenticationPrincipal Usuario actor) {
        Tenant tenant = provisioning.changeTenantStatus(tenantId, request.estado(), actor);
        return new TenantSummaryResponse(tenant.getId(), tenant.getCode(), tenant.getName(), tenant.getStatus());
    }

    @PostMapping("/{tenantId}/memberships")
    @ResponseStatus(HttpStatus.CREATED)
    public MembershipResponse grant(@PathVariable UUID tenantId,
                                    @RequestBody @Valid GrantMembershipRequest request,
                                    @AuthenticationPrincipal Usuario actor) {
        return membership(provisioning.grantMembership(
                tenantId, request.usuarioId(), request.roles(), request.validUntil(), actor));
    }

    @PatchMapping("/{tenantId}/memberships/{membershipId}/status")
    public MembershipResponse membershipStatus(@PathVariable UUID tenantId,
                                               @PathVariable UUID membershipId,
                                               @RequestBody @Valid MembershipStatusRequest request,
                                               @AuthenticationPrincipal Usuario actor) {
        return membership(provisioning.changeMembershipStatus(
                tenantId, membershipId, request.estado(), actor));
    }

    private static MembershipResponse membership(TenantMembership value) {
        return new MembershipResponse(
                value.getId(),
                value.getTenant().getId(),
                value.getUsuario().getId(),
                value.getStatus(),
                value.getValidFrom(),
                value.getValidUntil()
        );
    }

    public record CreateTenantRequest(
            @NotBlank @Size(max = 50)
            @Pattern(regexp = "^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$") String codigo,
            @NotBlank @Size(max = 150) String nombre,
            @NotNull Long initialAdminUserId
    ) {
    }

    public record TenantStatusRequest(@NotNull TenantStatus estado) {
    }

    public record GrantMembershipRequest(
            @NotNull Long usuarioId,
            @NotEmpty Set<@NotBlank @Size(max = 50) String> roles,
            Instant validUntil
    ) {
    }

    public record MembershipStatusRequest(@NotNull TenantMembershipStatus estado) {
    }

    public record ProvisionedTenantResponse(
            UUID id,
            String codigo,
            String nombre,
            TenantStatus estado,
            UUID initialAdminMembershipId
    ) {
    }

    public record MembershipResponse(
            UUID id,
            UUID tenantId,
            Long usuarioId,
            TenantMembershipStatus estado,
            Instant validFrom,
            Instant validUntil
    ) {
    }
}
