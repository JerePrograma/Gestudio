package gestudio.platform;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.stereotype.Component;

@Component
public class PlatformMetrics {
    private static final String EVENT_TAG = "event";
    private static final String RESULT_TAG = "result";
    private static final String REASON_TAG = "reason";

    public static final String TENANT_EVENTS = "gestudio_platform_tenant_events_total";
    public static final String MEMBERSHIP_EVENTS = "gestudio_platform_membership_events_total";
    public static final String BOOTSTRAP_EVENTS = "gestudio_platform_bootstrap_events_total";
    public static final String MFA_EVENTS = "gestudio_platform_mfa_events_total";
    public static final String AUTH_FAILURES = "gestudio_platform_auth_failures_total";
    public static final String AUTHORIZATION_DENIALS =
            "gestudio_platform_authorization_denials_total";
    public static final String PROVISIONING_FAILURES =
            "gestudio_platform_provisioning_failures_total";

    private final MeterRegistry registry;

    public PlatformMetrics(MeterRegistry registry) {
        this.registry = registry;
        registerBoundedSeries();
    }

    public void tenantEvent(TenantEvent event) {
        counter(TENANT_EVENTS, EVENT_TAG, event.tagValue()).increment();
    }

    public void membershipEvent(MembershipEvent event) {
        counter(MEMBERSHIP_EVENTS, EVENT_TAG, event.tagValue()).increment();
    }

    public void bootstrap(BootstrapResult result) {
        counter(BOOTSTRAP_EVENTS, RESULT_TAG, result.tagValue()).increment();
    }

    public void mfa(MfaMethod method, MfaResult result) {
        counter(MFA_EVENTS, "method", method.tagValue(), RESULT_TAG, result.tagValue()).increment();
    }

    public void authFailure(AuthOperation operation, AuthFailureReason reason) {
        counter(AUTH_FAILURES, "operation", operation.tagValue(), REASON_TAG, reason.tagValue()).increment();
    }

    public void authorizationDenied(AuthorizationReason reason,
                                    Scope sourceScope, Scope targetScope) {
        counter(AUTHORIZATION_DENIALS,
                REASON_TAG, reason.tagValue(),
                "source_scope", sourceScope.tagValue(),
                "target_scope", targetScope.tagValue()).increment();
    }

    public void provisioningFailure(ProvisioningResource resource,
                                    ProvisioningFailureReason reason) {
        counter(PROVISIONING_FAILURES,
                "resource", resource.tagValue(), REASON_TAG, reason.tagValue()).increment();
    }

    private void registerBoundedSeries() {
        registerTenantSeries();
        registerMembershipSeries();
        registerBootstrapSeries();
        registerMfaSeries();
        registerAuthenticationFailureSeries();
        registerAuthorizationDenialSeries();
        registerProvisioningFailureSeries();
    }

    private void registerTenantSeries() {
        for (TenantEvent event : TenantEvent.values()) tenantEventSeries(event);
    }

    private void registerMembershipSeries() {
        for (MembershipEvent event : MembershipEvent.values()) membershipEventSeries(event);
    }

    private void registerBootstrapSeries() {
        for (BootstrapResult result : BootstrapResult.values()) bootstrapSeries(result);
    }

    private void registerMfaSeries() {
        for (MfaMethod method : MfaMethod.values()) {
            for (MfaResult result : MfaResult.values()) mfaSeries(method, result);
        }
    }

    private void registerAuthenticationFailureSeries() {
        for (AuthOperation operation : AuthOperation.values()) {
            for (AuthFailureReason reason : AuthFailureReason.values()) {
                authFailureSeries(operation, reason);
            }
        }
    }

    private void registerAuthorizationDenialSeries() {
        authorizationDeniedSeries(AuthorizationReason.CROSS_SCOPE, Scope.TENANT, Scope.PLATFORM);
        authorizationDeniedSeries(AuthorizationReason.CROSS_SCOPE, Scope.PLATFORM, Scope.TENANT);
        authorizationDeniedSeries(AuthorizationReason.OPERATION_DENIED,
                Scope.PLATFORM, Scope.PLATFORM);
    }

    private void registerProvisioningFailureSeries() {
        for (ProvisioningResource resource : ProvisioningResource.values()) {
            for (ProvisioningFailureReason reason : ProvisioningFailureReason.values()) {
                provisioningFailureSeries(resource, reason);
            }
        }
    }

    private Counter tenantEventSeries(TenantEvent event) {
        return counter(TENANT_EVENTS, EVENT_TAG, event.tagValue());
    }

    private Counter membershipEventSeries(MembershipEvent event) {
        return counter(MEMBERSHIP_EVENTS, EVENT_TAG, event.tagValue());
    }

    private Counter bootstrapSeries(BootstrapResult result) {
        return counter(BOOTSTRAP_EVENTS, RESULT_TAG, result.tagValue());
    }

    private Counter mfaSeries(MfaMethod method, MfaResult result) {
        return counter(MFA_EVENTS, "method", method.tagValue(), RESULT_TAG, result.tagValue());
    }

    private Counter authFailureSeries(AuthOperation operation, AuthFailureReason reason) {
        return counter(AUTH_FAILURES,
                "operation", operation.tagValue(), REASON_TAG, reason.tagValue());
    }

    private Counter authorizationDeniedSeries(AuthorizationReason reason,
                                              Scope sourceScope, Scope targetScope) {
        return counter(AUTHORIZATION_DENIALS,
                REASON_TAG, reason.tagValue(),
                "source_scope", sourceScope.tagValue(),
                "target_scope", targetScope.tagValue());
    }

    private Counter provisioningFailureSeries(ProvisioningResource resource,
                                              ProvisioningFailureReason reason) {
        return counter(PROVISIONING_FAILURES,
                "resource", resource.tagValue(), REASON_TAG, reason.tagValue());
    }

    private Counter counter(String name, String... tags) {
        return Counter.builder(name).tags(tags).register(registry);
    }

    public enum TenantEvent {
        CREATED("created"), SUSPENDED("suspended"), REACTIVATED("reactivated"),
        ARCHIVED("archived");

        private final String wireValue;
        TenantEvent(String tagValue) { this.wireValue = tagValue; }
        String tagValue() { return wireValue; }
    }

    public enum MembershipEvent {
        CREATED("created"), SUSPENDED("suspended"), REACTIVATED("reactivated"),
        REVOKED("revoked"), ROLES_CHANGED("roles_changed");

        private final String wireValue;
        MembershipEvent(String tagValue) { this.wireValue = tagValue; }
        String tagValue() { return wireValue; }
    }

    public enum BootstrapResult {
        SUCCESS("success"), FAILED("failed");

        private final String wireValue;
        BootstrapResult(String tagValue) { this.wireValue = tagValue; }
        String tagValue() { return wireValue; }
    }

    public enum MfaMethod {
        TOTP("totp"), RECOVERY("recovery"), ENROLLMENT("enrollment");

        private final String wireValue;
        MfaMethod(String tagValue) { this.wireValue = tagValue; }
        String tagValue() { return wireValue; }
    }

    public enum MfaResult {
        SUCCESS("success"), FAILURE("failure"), RATE_LIMITED("rate_limited");

        private final String wireValue;
        MfaResult(String tagValue) { this.wireValue = tagValue; }
        String tagValue() { return wireValue; }
    }

    public enum AuthOperation {
        LOGIN("login"), REFRESH("refresh"), ACCESS("access");

        private final String wireValue;
        AuthOperation(String tagValue) { this.wireValue = tagValue; }
        String tagValue() { return wireValue; }
    }

    public enum AuthFailureReason {
        INVALID_CREDENTIALS("invalid_credentials"), MFA_RATE_LIMITED("mfa_rate_limited"),
        INVALID_SESSION("invalid_session"), INVALID_TOKEN("invalid_token");

        private final String wireValue;
        AuthFailureReason(String tagValue) { this.wireValue = tagValue; }
        String tagValue() { return wireValue; }
    }

    public enum AuthorizationReason {
        CROSS_SCOPE("cross_scope"), OPERATION_DENIED("operation_denied");

        private final String wireValue;
        AuthorizationReason(String tagValue) { this.wireValue = tagValue; }
        String tagValue() { return wireValue; }
    }

    public enum Scope {
        TENANT("tenant"), PLATFORM("platform");

        private final String wireValue;
        Scope(String tagValue) { this.wireValue = tagValue; }
        String tagValue() { return wireValue; }
    }

    public enum ProvisioningResource {
        TENANT("tenant"), MEMBERSHIP("membership"), BOOTSTRAP("bootstrap");

        private final String wireValue;
        ProvisioningResource(String tagValue) { this.wireValue = tagValue; }
        String tagValue() { return wireValue; }
    }

    public enum ProvisioningFailureReason {
        INVALID_REQUEST("invalid_request"), DENIED("denied"), DATABASE("database"),
        INTERNAL("internal");

        private final String wireValue;
        ProvisioningFailureReason(String tagValue) { this.wireValue = tagValue; }
        String tagValue() { return wireValue; }
    }
}
