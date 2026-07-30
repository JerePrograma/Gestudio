package gestudio.servicios.email;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

@Service
@ConditionalOnProperty(prefix = "app.email", name = "provider", havingValue = "NOOP", matchIfMissing = true)
public class NoOpEmailService extends AbstractEmailService {

    public NoOpEmailService(EmailDeliveryProperties properties, EmailDeliveryMetrics metrics) {
        super(properties, metrics);
    }

    @Override
    protected EmailDeliveryResult deliverValidated(EmailMessage message) {
        return EmailDeliveryResult.of(EmailDeliveryResult.Status.NOOP);
    }
}
