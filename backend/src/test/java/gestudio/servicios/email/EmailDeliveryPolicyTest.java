package gestudio.servicios.email;

import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

import static org.assertj.core.api.Assertions.assertThat;

class EmailDeliveryPolicyTest {

    @Test
    void cadaGuardaBloqueaGmailDeFormaIndependiente() {
        assertBlocked(properties(false, false, false, false),
                EmailDeliveryResult.Status.BLOCKED_BY_CONFIGURATION);
        assertBlocked(properties(true, true, false, false),
                EmailDeliveryResult.Status.BLOCKED_BY_KILL_SWITCH);
        assertBlocked(properties(true, false, true, true),
                EmailDeliveryResult.Status.BLOCKED_BY_DRY_RUN);
        assertBlocked(properties(true, false, false, false),
                EmailDeliveryResult.Status.BLOCKED_BY_NETWORK_POLICY);
        assertThat(policy(properties(true, false, false, true), "prod").gmailBlock()).isEmpty();
        assertBlocked(properties(true, false, false, true), "dev",
                EmailDeliveryResult.Status.BLOCKED_BY_CONFIGURATION);
    }

    @Test
    void providerNoopNuncaSeInterpretaComoGmailHabilitado() {
        EmailDeliveryProperties properties = new EmailDeliveryProperties(true,
                EmailDeliveryProperties.Provider.NOOP, false, true, false,
                "sender@example.test", "Gestudio", EmailDeliveryProperties.SentCopyMode.DISABLED,
                EmailDeliveryProperties.FakeOutcome.SUCCESS,
                new EmailDeliveryProperties.SentCopy("", 993, "", "", "", 5000, 5000));

        assertBlocked(properties, "prod", EmailDeliveryResult.Status.BLOCKED_BY_CONFIGURATION);
    }

    private static void assertBlocked(EmailDeliveryProperties properties,
                                      EmailDeliveryResult.Status status) {
        assertBlocked(properties, "prod", status);
    }

    private static void assertBlocked(EmailDeliveryProperties properties,
                                      String profile,
                                      EmailDeliveryResult.Status status) {
        assertThat(policy(properties, profile).gmailBlock()).get()
                .extracting(EmailDeliveryResult::status).isEqualTo(status);
    }

    static EmailDeliveryPolicy policy(EmailDeliveryProperties properties, String profile) {
        MockEnvironment environment = new MockEnvironment();
        environment.setActiveProfiles(profile);
        return new EmailDeliveryPolicy(properties, environment);
    }

    static EmailDeliveryProperties properties(boolean enabled,
                                              boolean killSwitch,
                                              boolean dryRun,
                                              boolean networkAllowed) {
        return new EmailDeliveryProperties(enabled, EmailDeliveryProperties.Provider.GMAIL_SMTP,
                dryRun, networkAllowed, killSwitch,
                "sender@example.test", "Gestudio", EmailDeliveryProperties.SentCopyMode.DISABLED,
                EmailDeliveryProperties.FakeOutcome.SUCCESS,
                new EmailDeliveryProperties.SentCopy("", 993, "", "", "", 5000, 5000));
    }
}
