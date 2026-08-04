package gestudio.tenancy;

import java.util.Objects;
import java.util.Optional;
import java.util.UUID;

public final class TenantContext {
    private static final ThreadLocal<State> CURRENT = new ThreadLocal<>();

    private TenantContext() {
    }

    public static UUID requireTenantId() {
        return currentTenantId().orElseThrow(() -> new IllegalStateException("Tenant context required"));
    }

    public static Optional<UUID> currentTenantId() {
        State state = CURRENT.get();
        return state == null ? Optional.empty() : Optional.of(state.tenantId());
    }

    public static Optional<UUID> currentMembershipId() {
        State state = CURRENT.get();
        return state == null ? Optional.empty() : Optional.ofNullable(state.membershipId());
    }

    public static Scope open(UUID tenantId, UUID membershipId) {
        Objects.requireNonNull(tenantId, "tenantId");
        State previous = CURRENT.get();
        CURRENT.set(new State(tenantId, membershipId));
        return new Scope(previous, Thread.currentThread());
    }

    public static void clear() {
        CURRENT.remove();
    }

    private record State(UUID tenantId, UUID membershipId) {
    }

    public static final class Scope implements AutoCloseable {
        private final State previous;
        private final Thread owner;
        private boolean closed;

        private Scope(State previous, Thread owner) {
            this.previous = previous;
            this.owner = owner;
        }

        @Override
        public void close() {
            if (closed) {
                return;
            }
            if (Thread.currentThread() != owner) {
                throw new IllegalStateException("Tenant scope closed from a different thread");
            }
            closed = true;
            if (previous == null) {
                CURRENT.remove();
            } else {
                CURRENT.set(previous);
            }
        }
    }
}
