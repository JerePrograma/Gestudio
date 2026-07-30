package gestudio.servicios.email;

import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.stereotype.Component;

@Component
public class EmailDeliveryMetrics {
    private final MeterRegistry registry;

    public EmailDeliveryMetrics(MeterRegistry registry) {
        this.registry = registry;
    }

    public void record(EmailDeliveryProperties.Provider provider,
                       EmailDeliveryResult result,
                       String messageType) {
        increment("gestudio.email.attempts", provider, result, messageType);
        if (result.policyBlocked()) increment("gestudio.email.blocked", provider, result, messageType);
        if (result.simulated()) increment("gestudio.email.simulated", provider, result, messageType);
        if (result.status() == EmailDeliveryResult.Status.SENT_COPY_FAILED) {
            increment("gestudio.email.sent.copy.failures", provider, result, messageType);
        }
        if (result.status() == EmailDeliveryResult.Status.PROVIDER_REJECTED
                || result.status() == EmailDeliveryResult.Status.PROVIDER_TEMPORARY_FAILURE
                || result.status() == EmailDeliveryResult.Status.PROVIDER_PERMANENT_FAILURE) {
            increment("gestudio.email.provider.failures", provider, result, messageType);
        }
    }

    private void increment(String name,
                           EmailDeliveryProperties.Provider provider,
                           EmailDeliveryResult result,
                           String messageType) {
        registry.counter(name,
                "provider", provider.name(),
                "result", result.status().name(),
                "message_type", messageType).increment();
    }
}
