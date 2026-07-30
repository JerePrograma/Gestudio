package gestudio.servicios.email;

import java.util.Optional;

import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

import static gestudio.servicios.email.EmailDeliveryResult.Status.BLOCKED_BY_CONFIGURATION;
import static gestudio.servicios.email.EmailDeliveryResult.Status.BLOCKED_BY_DRY_RUN;
import static gestudio.servicios.email.EmailDeliveryResult.Status.BLOCKED_BY_KILL_SWITCH;
import static gestudio.servicios.email.EmailDeliveryResult.Status.BLOCKED_BY_NETWORK_POLICY;

@Component
public class EmailDeliveryPolicy {
    private final EmailDeliveryProperties properties;
    private final Environment environment;

    public EmailDeliveryPolicy(EmailDeliveryProperties properties, Environment environment) {
        this.properties = properties;
        this.environment = environment;
    }

    public Optional<EmailDeliveryResult> gmailBlock() {
        if (properties.provider() != EmailDeliveryProperties.Provider.GMAIL_SMTP
                || !environment.acceptsProfiles(Profiles.of("prod"))
                || !properties.enabled()) {
            return Optional.of(EmailDeliveryResult.of(BLOCKED_BY_CONFIGURATION));
        }
        if (properties.killSwitch()) {
            return Optional.of(EmailDeliveryResult.of(BLOCKED_BY_KILL_SWITCH));
        }
        if (properties.dryRun()) {
            return Optional.of(EmailDeliveryResult.of(BLOCKED_BY_DRY_RUN));
        }
        if (!properties.realNetworkAllowed()) {
            return Optional.of(EmailDeliveryResult.of(BLOCKED_BY_NETWORK_POLICY));
        }
        return Optional.empty();
    }
}
