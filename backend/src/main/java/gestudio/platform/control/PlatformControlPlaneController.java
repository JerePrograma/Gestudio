package gestudio.platform.control;

import gestudio.infra.observabilidad.RequestCorrelationFilter;
import gestudio.platform.security.PlatformPrincipal;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.List;
import java.util.UUID;
import java.util.function.Function;

@RestController
@RequestMapping("/api/platform")
@Validated
public class PlatformControlPlaneController {
    private static final String IDEMPOTENCY = "Idempotency-Key";
    private static final String STEP_UP = "X-Step-Up-Token";
    private static final String NO_CACHE = "no-cache";

    private final PlatformControlPlaneService service;

    public PlatformControlPlaneController(PlatformControlPlaneService service) {
        this.service = service;
    }

    @GetMapping("/tenants")
    public PageResponse<TenantResponse> tenants(
            @RequestParam(required = false) String q,
            @RequestParam(required = false) String status,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return page(service.tenants(q, status, page, size), PlatformControlPlaneController::tenant);
    }

    @GetMapping("/tenants/{tenantId}")
    public TenantResponse tenant(@PathVariable UUID tenantId) {
        return tenant(service.tenant(tenantId));
    }

    @PostMapping("/tenants")
    public ResponseEntity<ProvisionedTenantResponse> createTenant(
            @RequestBody @Valid CreateTenantRequest request,
            @AuthenticationPrincipal PlatformPrincipal actor,
            @RequestHeader(name = IDEMPOTENCY, required = false) String idempotencyKey,
            @RequestHeader(name = STEP_UP, required = false) String stepUp,
            @RequestAttribute(name = RequestCorrelationFilter.ATTRIBUTE_NAME) UUID correlationId) {
        var result = service.createTenant(new PlatformControlPlaneService.CreateTenant(
                        request.code(), request.name(), identity(request.initialAdmin())), actor,
                idempotencyKey, stepUp, correlationId);
        var response = new ProvisionedTenantResponse(tenant(result.tenant()),
                membership(result.initialAdmin()), activation(result.activation()), result.replayed());
        return ResponseEntity.status(result.replayed() ? HttpStatus.OK : HttpStatus.CREATED)
                .cacheControl(CacheControl.noStore()).header(HttpHeaders.PRAGMA, NO_CACHE)
                .body(response);
    }

    @PatchMapping("/tenants/{tenantId}")
    public TenantResponse updateTenant(
            @PathVariable UUID tenantId, @RequestBody @Valid UpdateTenantRequest request,
            @AuthenticationPrincipal PlatformPrincipal actor,
            @RequestHeader(name = IDEMPOTENCY, required = false) String idempotencyKey,
            @RequestHeader(name = STEP_UP, required = false) String stepUp,
            @RequestAttribute(name = RequestCorrelationFilter.ATTRIBUTE_NAME) UUID correlationId) {
        return tenant(service.updateTenant(tenantId, request.name(), request.expectedVersion(),
                actor, idempotencyKey, stepUp, correlationId));
    }

    @PatchMapping("/tenants/{tenantId}/status")
    public TenantResponse changeTenantStatus(
            @PathVariable UUID tenantId, @RequestBody @Valid StatusRequest request,
            @AuthenticationPrincipal PlatformPrincipal actor,
            @RequestHeader(name = IDEMPOTENCY, required = false) String idempotencyKey,
            @RequestHeader(name = STEP_UP, required = false) String stepUp,
            @RequestAttribute(name = RequestCorrelationFilter.ATTRIBUTE_NAME) UUID correlationId) {
        return tenant(service.changeTenantStatus(tenantId, request.status(), request.expectedVersion(),
                request.reason(), actor, idempotencyKey, stepUp, correlationId));
    }

    @GetMapping("/tenants/{tenantId}/memberships")
    public PageResponse<MembershipResponse> memberships(
            @PathVariable UUID tenantId,
            @RequestParam(required = false) String q,
            @RequestParam(required = false) String status,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return page(service.memberships(tenantId, q, status, page, size),
                PlatformControlPlaneController::membership);
    }

    @PostMapping("/tenants/{tenantId}/memberships")
    public ResponseEntity<ProvisionedMembershipResponse> createMembership(
            @PathVariable UUID tenantId, @RequestBody @Valid CreateMembershipRequest request,
            @AuthenticationPrincipal PlatformPrincipal actor,
            @RequestHeader(name = IDEMPOTENCY, required = false) String idempotencyKey,
            @RequestHeader(name = STEP_UP, required = false) String stepUp,
            @RequestAttribute(name = RequestCorrelationFilter.ATTRIBUTE_NAME) UUID correlationId) {
        var result = service.createMembership(tenantId,
                new PlatformControlPlaneService.CreateMembership(identity(request.identity()),
                        request.roles(), request.validUntil()), actor, idempotencyKey, stepUp,
                correlationId);
        return ResponseEntity.status(result.replayed() ? HttpStatus.OK : HttpStatus.CREATED)
                .cacheControl(CacheControl.noStore()).header(HttpHeaders.PRAGMA, NO_CACHE)
                .body(new ProvisionedMembershipResponse(membership(result.membership()),
                        activation(result.activation()), result.replayed()));
    }

    @PutMapping("/tenants/{tenantId}/memberships/{membershipId}/roles")
    public MembershipResponse updateMembershipRoles(
            @PathVariable UUID tenantId, @PathVariable UUID membershipId,
            @RequestBody @Valid RolesRequest request,
            @AuthenticationPrincipal PlatformPrincipal actor,
            @RequestHeader(name = IDEMPOTENCY, required = false) String idempotencyKey,
            @RequestHeader(name = STEP_UP, required = false) String stepUp,
            @RequestAttribute(name = RequestCorrelationFilter.ATTRIBUTE_NAME) UUID correlationId) {
        return membership(service.updateMembershipRoles(tenantId, membershipId, request.roles(),
                request.expectedVersion(), actor, idempotencyKey, stepUp, correlationId));
    }

    @PatchMapping("/tenants/{tenantId}/memberships/{membershipId}/status")
    public MembershipResponse changeMembershipStatus(
            @PathVariable UUID tenantId, @PathVariable UUID membershipId,
            @RequestBody @Valid StatusRequest request,
            @AuthenticationPrincipal PlatformPrincipal actor,
            @RequestHeader(name = IDEMPOTENCY, required = false) String idempotencyKey,
            @RequestHeader(name = STEP_UP, required = false) String stepUp,
            @RequestAttribute(name = RequestCorrelationFilter.ATTRIBUTE_NAME) UUID correlationId) {
        return membership(service.changeMembershipStatus(tenantId, membershipId, request.status(),
                request.expectedVersion(), request.reason(), actor, idempotencyKey, stepUp,
                correlationId));
    }

    @GetMapping("/tenants/{tenantId}/roles")
    public List<RoleResponse> roles(@PathVariable UUID tenantId) {
        return service.roles(tenantId).stream()
                .map(role -> new RoleResponse(role.code(), role.name(), role.active())).toList();
    }

    @GetMapping("/identities")
    public List<IdentityResponse> identities(@RequestParam(required = false) String q) {
        return service.identities(q).stream()
                .map(identity -> new IdentityResponse(identity.id(), identity.username(), identity.active()))
                .toList();
    }

    @GetMapping("/admins")
    public PageResponse<AdminResponse> admins(
            @RequestParam(required = false) String q,
            @RequestParam(required = false) String status,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return page(service.admins(q, status, page, size), PlatformControlPlaneController::admin);
    }

    @PostMapping("/admins")
    public ResponseEntity<GrantedAdminResponse> grantAdmin(
            @RequestBody @Valid GrantAdminRequest request,
            @AuthenticationPrincipal PlatformPrincipal actor,
            @RequestHeader(name = IDEMPOTENCY, required = false) String idempotencyKey,
            @RequestHeader(name = STEP_UP, required = false) String stepUp,
            @RequestAttribute(name = RequestCorrelationFilter.ATTRIBUTE_NAME) UUID correlationId) {
        var result = service.grantAdmin(request.usuarioId(), actor, idempotencyKey,
                stepUp, correlationId);
        return ResponseEntity.status(HttpStatus.CREATED).cacheControl(CacheControl.noStore())
                .header(HttpHeaders.PRAGMA, NO_CACHE)
                .body(new GrantedAdminResponse(admin(result.admin()), activation(result.activation())));
    }

    @PatchMapping("/admins/{userId}/status")
    public AdminResponse changeAdminStatus(
            @PathVariable long userId, @RequestBody @Valid StatusRequest request,
            @AuthenticationPrincipal PlatformPrincipal actor,
            @RequestHeader(name = IDEMPOTENCY, required = false) String idempotencyKey,
            @RequestHeader(name = STEP_UP, required = false) String stepUp,
            @RequestAttribute(name = RequestCorrelationFilter.ATTRIBUTE_NAME) UUID correlationId) {
        return admin(service.changeAdminStatus(userId, request.status(), request.expectedVersion(),
                request.reason(), actor, idempotencyKey, stepUp, correlationId));
    }

    @PostMapping("/admins/{userId}/mfa/reset")
    public ResponseEntity<ActivationResponse> resetMfa(
            @PathVariable long userId, @AuthenticationPrincipal PlatformPrincipal actor,
            @RequestHeader(name = IDEMPOTENCY, required = false) String idempotencyKey,
            @RequestHeader(name = STEP_UP, required = false) String stepUp,
            @RequestAttribute(name = RequestCorrelationFilter.ATTRIBUTE_NAME) UUID correlationId) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .header(HttpHeaders.PRAGMA, NO_CACHE)
                .body(activation(service.resetAdminMfa(
                        userId, actor, idempotencyKey, stepUp, correlationId)));
    }

    @GetMapping("/audit")
    public PageResponse<AuditResponse> audit(
            @RequestParam(required = false) UUID tenantId,
            @RequestParam(required = false) String actor,
            @RequestParam(required = false) String action,
            @RequestParam(required = false) String result,
            @RequestParam(required = false) Instant from,
            @RequestParam(required = false) Instant to,
            @RequestParam(required = false) UUID correlationId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        var filter = new PlatformControlPlaneRepository.AuditFilter(
                tenantId, actor, action, result, from, to, correlationId);
        return page(service.audit(filter, page, size), PlatformControlPlaneController::audit);
    }

    private static PlatformControlPlaneService.IdentityRequest identity(IdentityRequest request) {
        return request == null ? null : new PlatformControlPlaneService.IdentityRequest(
                request.mode(), request.usuarioId(), request.nombreUsuario());
    }

    private static TenantResponse tenant(PlatformControlPlaneRepository.TenantView value) {
        return new TenantResponse(value.id(), value.code(), value.name(), value.status(), value.version(),
                value.createdAt(), value.updatedAt(), value.membershipCount(),
                value.activeMembershipCount(), value.roleCount());
    }

    private static MembershipResponse membership(PlatformControlPlaneRepository.MembershipView value) {
        return new MembershipResponse(value.id(), value.tenantId(), value.userId(), value.username(),
                value.status(), value.roles(), value.validFrom(), value.validUntil(), value.version());
    }

    private static AdminResponse admin(PlatformControlPlaneRepository.AdminView value) {
        return new AdminResponse(value.userId(), value.username(), value.status(), value.mfaEnabled(),
                value.createdAt(), value.revokedAt(), value.version());
    }

    private static AuditResponse audit(PlatformControlPlaneRepository.AuditView value) {
        return new AuditResponse(Long.toString(value.id()), value.occurredAt(), value.actorId(),
                value.actorUsername(), value.action(), value.result(), value.targetType(), value.targetId(),
                value.tenantId(), value.correlationId(), value.detail());
    }

    private static ActivationResponse activation(PlatformControlPlaneService.Activation value) {
        return value == null ? null : new ActivationResponse(value.token(), value.expiresAt());
    }

    private static <S, T> PageResponse<T> page(PlatformControlPlaneRepository.PageData<S> value,
                                               Function<S, T> mapper) {
        return new PageResponse<>(value.content().stream().map(mapper).toList(), value.totalElements(),
                value.totalPages(), value.size(), value.number(), value.first(), value.last());
    }

    public record PageResponse<T>(List<T> content, long totalElements, long totalPages,
                                  int size, int number, boolean first, boolean last) {
    }

    public record TenantResponse(UUID id, String code, String name, String status, long version,
                                 Instant createdAt, Instant updatedAt, long membershipCount,
                                 long activeMembershipCount, long roleCount) {
    }

    public record MembershipResponse(UUID id, UUID tenantId, long usuarioId, String nombreUsuario,
                                     String status, List<String> roles, Instant validFrom,
                                     Instant validUntil, long version) {
    }

    public record RoleResponse(String code, String name, boolean active) {
    }

    public record IdentityResponse(long id, String nombreUsuario, boolean active) {
    }

    public record AdminResponse(long usuarioId, String nombreUsuario, String status,
                                boolean mfaEnabled, Instant createdAt, Instant revokedAt,
                                long version) {
    }

    public record GrantedAdminResponse(AdminResponse admin, ActivationResponse activation) {
    }

    public record AuditResponse(String id, Instant occurredAt, Long actorId, String actorUsername,
                                String action, String result, String targetType, String targetId,
                                UUID tenantId, UUID correlationId, String detail) {
    }

    public record ProvisionedTenantResponse(TenantResponse tenant, MembershipResponse initialAdmin,
                                            ActivationResponse activation, boolean replayed) {
    }

    public record ProvisionedMembershipResponse(MembershipResponse membership,
                                                ActivationResponse activation,
                                                boolean replayed) {
    }

    public record ActivationResponse(String token, Instant expiresAt) {
    }

    public record IdentityRequest(@NotBlank String mode, Long usuarioId,
                                  @Size(max = 100) String nombreUsuario) {
    }

    public record CreateTenantRequest(@NotBlank @Size(max = 50) String code,
                                      @NotBlank @Size(max = 150) String name,
                                      @NotNull @Valid IdentityRequest initialAdmin) {
    }

    public record UpdateTenantRequest(@NotBlank @Size(max = 150) String name,
                                      @NotNull @PositiveOrZero Long expectedVersion) {
    }

    public record StatusRequest(@NotBlank String status,
                                @NotNull @PositiveOrZero Long expectedVersion,
                                @NotBlank @Size(max = 250) String reason) {
    }

    public record CreateMembershipRequest(@NotNull @Valid IdentityRequest identity,
                                          @NotEmpty List<@NotBlank @Size(max = 50) String> roles,
                                          Instant validUntil) {
    }

    public record RolesRequest(@NotEmpty List<@NotBlank @Size(max = 50) String> roles,
                               @NotNull @PositiveOrZero Long expectedVersion) {
    }

    public record GrantAdminRequest(@NotNull Long usuarioId) {
    }
}
