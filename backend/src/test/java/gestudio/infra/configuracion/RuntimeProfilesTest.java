package gestudio.infra.configuracion;

import gestudio.servicios.ScheduledTasks;
import gestudio.servicios.asistencia.AsistenciaMensualServicio;
import gestudio.servicios.email.EmailDeliveryMetrics;
import gestudio.servicios.email.EmailDeliveryConfigurationGuard;
import gestudio.servicios.email.EmailDeliveryPolicy;
import gestudio.servicios.email.EmailDeliveryProperties;
import gestudio.servicios.email.EmailDeliveryResult;
import gestudio.servicios.email.FakeEmailService;
import gestudio.servicios.email.GmailSmtpEmailService;
import gestudio.servicios.email.IEmailService;
import gestudio.servicios.email.NoOpEmailService;
import gestudio.servicios.email.SentCopyStrategy;
import gestudio.servicios.matricula.MatriculaServicio;
import gestudio.servicios.mensualidad.MensualidadServicio;
import gestudio.servicios.notificaciones.NotificacionService;
import gestudio.servicios.recargo.RecargoServicio;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.autoconfigure.mail.MailProperties;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.boot.test.context.runner.ContextConsumer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.mail.javamail.JavaMailSender;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;

class RuntimeProfilesTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(ProfileConfiguration.class)
            .withPropertyValues(
                    "app.email.enabled=false",
                    "app.email.dry-run=true",
                    "app.email.real-network-allowed=false",
                    "app.email.kill-switch=true",
                    "app.email.sent-copy-mode=DISABLED",
                    "app.email.fake-outcome=SUCCESS");

    @Test
    void devTestRemoteDemoYProdUsanNoOpPorDefecto() {
        for (String profile : new String[]{"dev", "test", "remote-demo", "prod"}) {
            run(profile, "false", context -> {
                assertThat(context).hasSingleBean(IEmailService.class);
                assertThat(context).hasSingleBean(NoOpEmailService.class);
                assertThat(context).doesNotHaveBean(ScheduledTasks.class);
            });
        }
    }

    @Test
    void prodSeleccionaFakeSoloPorPropiedadExplicita() {
        run("prod", "true", context -> {
            assertThat(context).hasSingleBean(IEmailService.class);
            assertThat(context).hasSingleBean(FakeEmailService.class);
            assertThat(context).hasSingleBean(ScheduledTasks.class);
        }, "app.email.provider=FAKE");
    }

    @Test
    void prodConGmailBloqueadoNoInvocaMailSender() {
        run("prod", "true", context -> {
            assertThat(context).hasSingleBean(IEmailService.class);
            assertThat(context).hasSingleBean(GmailSmtpEmailService.class);
            assertThat(context).hasSingleBean(ScheduledTasks.class);
            IEmailService service = context.getBean(IEmailService.class);
            assertThat(service.sendEmailWithInlineImage(
                    "recipient@example.test", "Subject", "<p>Body</p>",
                    new byte[]{1}, "signature", "image/png").status())
                    .isEqualTo(EmailDeliveryResult.Status.BLOCKED_BY_DRY_RUN);
            verifyNoInteractions(context.getBean(JavaMailSender.class));
        },
                "app.email.provider=GMAIL_SMTP",
                "app.email.enabled=true",
                "app.email.dry-run=true",
                "app.email.real-network-allowed=true",
                "app.email.kill-switch=false");
    }

    @Test
    void perfilAusenteFallaCerrado() {
        runner.withPropertyValues("spring.profiles.active=").run(context -> {
            assertThat(context).hasFailed();
            assertThat(context.getStartupFailure()).hasRootCauseMessage(
                    "Debe activar exactamente un perfil Spring explícito: dev, test, prod o remote-demo");
        });
    }

    private void run(String profile,
                     String schedulingEnabled,
                     ContextConsumer<org.springframework.boot.test.context.assertj.AssertableApplicationContext> assertions,
                     String... properties) {
        runner.withInitializer(context -> context.getEnvironment().setActiveProfiles(profile))
                .withPropertyValues("app.scheduling-enabled=" + schedulingEnabled)
                .withPropertyValues(properties)
                .run(assertions);
    }

    @Configuration(proxyBeanMethods = false)
    @EnableConfigurationProperties(EmailDeliveryProperties.class)
    @Import({
            ActiveProfileGuard.class,
            EmailDeliveryMetrics.class,
            EmailDeliveryPolicy.class,
            EmailDeliveryConfigurationGuard.class,
            NoOpEmailService.class,
            FakeEmailService.class,
            GmailSmtpEmailService.class,
            ScheduledTasks.class
    })
    static class ProfileConfiguration {
        @Bean MeterRegistry meterRegistry() { return new SimpleMeterRegistry(); }
        @Bean MailProperties mailProperties() { return new MailProperties(); }
        @Bean JavaMailSender javaMailSender() { return mock(JavaMailSender.class); }
        @Bean SentCopyStrategy sentCopyStrategy() { return mock(SentCopyStrategy.class); }
        @Bean MensualidadServicio mensualidadServicio() { return mock(MensualidadServicio.class); }
        @Bean MatriculaServicio matriculaServicio() { return mock(MatriculaServicio.class); }
        @Bean RecargoServicio recargoServicio() { return mock(RecargoServicio.class); }
        @Bean AsistenciaMensualServicio asistenciaMensualServicio() { return mock(AsistenciaMensualServicio.class); }
        @Bean NotificacionService notificacionService() { return mock(NotificacionService.class); }
    }
}
