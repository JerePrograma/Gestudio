package gestudio.servicios.email;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

import java.util.concurrent.atomic.AtomicReference;

@Service
@ConditionalOnProperty(prefix = "app.email", name = "provider", havingValue = "FAKE")
public class FakeEmailService extends AbstractEmailService {
    private final AtomicReference<EmailDeliveryResult> lastResult = new AtomicReference<>();

    public FakeEmailService(EmailDeliveryProperties properties, EmailDeliveryMetrics metrics) {
        super(properties, metrics);
    }

    @Override
    protected EmailDeliveryResult deliverValidated(EmailMessage message) {
        EmailDeliveryResult result = switch (properties().fakeOutcome()) {
            case SUCCESS -> EmailDeliveryResult.of(EmailDeliveryResult.Status.SIMULATED);
            case TEMPORARY_FAILURE -> EmailDeliveryResult.of(
                    EmailDeliveryResult.Status.PROVIDER_TEMPORARY_FAILURE, "fake_temporary_failure");
            case PERMANENT_FAILURE -> EmailDeliveryResult.of(
                    EmailDeliveryResult.Status.PROVIDER_PERMANENT_FAILURE, "fake_permanent_failure");
        };
        lastResult.set(result);
        return result;
    }

    public EmailDeliveryResult lastSanitizedResult() {
        return lastResult.get();
    }
}
