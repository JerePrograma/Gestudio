package gestudio.servicios.email;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "app.email")
public record EmailDeliveryProperties(
        boolean enabled,
        Provider provider,
        boolean dryRun,
        boolean realNetworkAllowed,
        boolean killSwitch,
        String fromAddress,
        String fromName,
        SentCopyMode sentCopyMode,
        FakeOutcome fakeOutcome,
        SentCopy sentCopy
) {
    public EmailDeliveryProperties {
        provider = provider == null ? Provider.NOOP : provider;
        fromAddress = fromAddress == null ? "" : fromAddress.trim();
        fromName = fromName == null || fromName.isBlank() ? "Gestudio" : fromName.trim();
        sentCopyMode = sentCopyMode == null ? SentCopyMode.DISABLED : sentCopyMode;
        fakeOutcome = fakeOutcome == null ? FakeOutcome.SUCCESS : fakeOutcome;
        sentCopy = sentCopy == null ? new SentCopy("", 993, "", "", "", 5000, 5000) : sentCopy;
    }

    public enum Provider {
        NOOP,
        FAKE,
        GMAIL_SMTP
    }

    public enum SentCopyMode {
        DISABLED,
        BEST_EFFORT,
        REQUIRED
    }

    public enum FakeOutcome {
        SUCCESS,
        TEMPORARY_FAILURE,
        PERMANENT_FAILURE
    }

    public record SentCopy(
            String host,
            int port,
            String username,
            String appPassword,
            String folder,
            int connectionTimeoutMs,
            int readTimeoutMs
    ) {
        public SentCopy {
            host = host == null ? "" : host.trim();
            username = username == null ? "" : username.trim();
            appPassword = appPassword == null ? "" : appPassword;
            folder = folder == null ? "" : folder.trim();
        }
    }
}
