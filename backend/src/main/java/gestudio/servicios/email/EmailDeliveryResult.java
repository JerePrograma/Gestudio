package gestudio.servicios.email;

public record EmailDeliveryResult(Status status, String reason) {
    public EmailDeliveryResult {
        if (status == null) throw new IllegalArgumentException("Email delivery status is required");
        reason = sanitize(reason);
    }

    public static EmailDeliveryResult of(Status status) {
        return new EmailDeliveryResult(status, "");
    }

    public static EmailDeliveryResult of(Status status, String reason) {
        return new EmailDeliveryResult(status, reason);
    }

    public boolean providerAccepted() {
        return status == Status.PROVIDER_ACCEPTED || status == Status.SENT_COPY_FAILED;
    }

    public boolean retryable() {
        return status == Status.PROVIDER_TEMPORARY_FAILURE;
    }

    public boolean simulated() {
        return status == Status.SIMULATED;
    }

    public boolean policyBlocked() {
        return switch (status) {
            case NOOP, BLOCKED_BY_CONFIGURATION, BLOCKED_BY_KILL_SWITCH,
                    BLOCKED_BY_DRY_RUN, BLOCKED_BY_NETWORK_POLICY -> true;
            default -> false;
        };
    }

    public boolean terminalFailure() {
        return status == Status.INVALID_MESSAGE
                || status == Status.PROVIDER_REJECTED
                || status == Status.PROVIDER_PERMANENT_FAILURE;
    }

    private static String sanitize(String value) {
        if (value == null || value.isBlank()) return "";
        String sanitized = value.replace('\r', '_').replace('\n', '_').replace('\t', '_');
        return sanitized.length() <= 80 ? sanitized : sanitized.substring(0, 80);
    }

    public enum Status {
        NOOP,
        SIMULATED,
        BLOCKED_BY_CONFIGURATION,
        BLOCKED_BY_KILL_SWITCH,
        BLOCKED_BY_DRY_RUN,
        BLOCKED_BY_NETWORK_POLICY,
        PROVIDER_ACCEPTED,
        PROVIDER_REJECTED,
        PROVIDER_TEMPORARY_FAILURE,
        PROVIDER_PERMANENT_FAILURE,
        SENT_COPY_FAILED,
        INVALID_MESSAGE
    }
}
