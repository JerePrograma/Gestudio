package gestudio.infra.configuracion;

import gestudio.servicios.ScheduledTasks;
import gestudio.repositorios.AplicacionPagoRepositorio;
import gestudio.repositorios.ReciboPendienteRepositorio;
import gestudio.repositorios.ReciboRepositorio;
import gestudio.servicios.pdfs.PdfService;
import gestudio.servicios.pdfs.ReciboStorageService;
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
import gestudio.tenancy.TenantExecutionService;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.autoconfigure.mail.MailProperties;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.boot.test.context.runner.ContextConsumer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.core.io.ClassPathResource;
import org.springframework.transaction.PlatformTransactionManager;

import java.io.IOException;
import java.time.Clock;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;

class RuntimeProfilesTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withInitializer(context -> {
                try {
                    var sources = new YamlPropertySourceLoader().load(
                            "application", new ClassPathResource("application.yml"));
                    sources.forEach(source -> context.getEnvironment().getPropertySources().addLast(source));
                } catch (IOException exception) {
                    throw new IllegalStateException("No se pudo cargar la configuración real", exception);
                }
            })
            .withUserConfiguration(ProfileConfiguration.class)
            .withPropertyValues(
                    "app.receipts-path=./target/runtime-profile-receipts",
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
                assertThat(context).doesNotHaveBean(ReciboStorageService.class);
            });
        }
    }

    @Test
    void prodSeleccionaFakeSoloPorPropiedadExplicita() {
        run("prod", "true", context -> {
            assertThat(context).hasSingleBean(IEmailService.class);
            assertThat(context).hasSingleBean(FakeEmailService.class);
            assertThat(context).hasSingleBean(ScheduledTasks.class);
            assertThat(context).hasSingleBean(ReciboStorageService.class);
        }, "app.email.provider=FAKE");
    }

    @Test
    void recibosSeHabilitanSinActivarJobsDeNegocioNiEnvios() {
        for (String profile : List.of("dev", "test", "remote-demo", "prod")) {
            run(profile, "false", context -> {
                assertThat(context).hasNotFailed();
                assertThat(context).hasSingleBean(ReciboStorageService.class);
                assertThat(context).doesNotHaveBean(ScheduledTasks.class);
                assertThat(context).hasSingleBean(NoOpEmailService.class);
                verifyNoInteractions(context.getBean(JavaMailSender.class),
                        context.getBean(MensualidadServicio.class),
                        context.getBean(TenantExecutionService.class),
                        context.getBean(PdfService.class));
            }, "APP_RECEIPTS_WORKER_ENABLED=true");
        }
    }

    @Test
    void recibosPuedenDeshabilitarseConJobsGlobalesActivos() {
        run("prod", "true", context -> {
            assertThat(context).hasNotFailed();
            assertThat(context).hasSingleBean(ScheduledTasks.class);
            assertThat(context).doesNotHaveBean(ReciboStorageService.class);
        }, "APP_RECEIPTS_WORKER_ENABLED=false");
    }

    @Test
    void recibosHeredanSchedulingGlobalYPorDefectoPermanecenApagados() {
        runner.withInitializer(context -> context.getEnvironment().setActiveProfiles("dev"))
                .run(context -> {
                    assertThat(context).hasNotFailed();
                    assertThat(context).doesNotHaveBean(ReciboStorageService.class);
                    assertThat(context).doesNotHaveBean(ScheduledTasks.class);
                });
        run("prod", "true", context -> {
            assertThat(context).hasSingleBean(ReciboStorageService.class);
            assertThat(context).hasSingleBean(ScheduledTasks.class);
        });
    }

    @Test
    void recibosHeredanElDefaultDelPerfilProdReal() throws IOException {
        var source = new YamlPropertySourceLoader().load(
                "prod", new ClassPathResource("application-prod.yml")).getFirst();
        runner.withInitializer(context -> context.getEnvironment().setActiveProfiles("prod"))
                .withPropertyValues("app.scheduling-enabled=" + source.getProperty("app.scheduling-enabled"))
                .run(context -> {
                    assertThat(context).hasNotFailed();
                    assertThat(context).hasSingleBean(ReciboStorageService.class);
                    assertThat(context).hasSingleBean(ScheduledTasks.class);
                });
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

    @Test
    void flywayUsaLaUrlDelDatasourceConCredencialesSeparadas() throws IOException {
        for (String profile : List.of("dev", "prod", "remote-demo")) {
            var source = new YamlPropertySourceLoader().load(
                    profile, new ClassPathResource("application-" + profile + ".yml")).getFirst();

            assertThat(source.getProperty("spring.flyway.url"))
                    .as("URL Flyway del perfil %s", profile)
                    .isEqualTo(source.getProperty("spring.datasource.url"));
            assertThat(source.getProperty("spring.flyway.user"))
                    .as("usuario Flyway del perfil %s", profile)
                    .isNotEqualTo(source.getProperty("spring.datasource.username"));
        }
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
    @EnableConfigurationProperties({EmailDeliveryProperties.class, AppProperties.class})
    @Import({
            ActiveProfileGuard.class,
            EmailDeliveryMetrics.class,
            EmailDeliveryPolicy.class,
            EmailDeliveryConfigurationGuard.class,
            NoOpEmailService.class,
            FakeEmailService.class,
            GmailSmtpEmailService.class,
            ScheduledTasks.class,
            ReciboStorageService.class
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
        @Bean TenantExecutionService tenantExecutionService() { return mock(TenantExecutionService.class); }
        @Bean PdfService pdfService() { return mock(PdfService.class); }
        @Bean ReciboRepositorio reciboRepositorio() { return mock(ReciboRepositorio.class); }
        @Bean ReciboPendienteRepositorio reciboPendienteRepositorio() { return mock(ReciboPendienteRepositorio.class); }
        @Bean AplicacionPagoRepositorio aplicacionPagoRepositorio() { return mock(AplicacionPagoRepositorio.class); }
        @Bean Clock clock() { return Clock.systemUTC(); }
        @Bean PlatformTransactionManager transactionManager() { return mock(PlatformTransactionManager.class); }
    }
}
