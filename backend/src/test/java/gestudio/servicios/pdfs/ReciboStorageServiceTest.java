package gestudio.servicios.pdfs;

import gestudio.entidades.Alumno;
import gestudio.entidades.EstadoReciboPendiente;
import gestudio.entidades.Pago;
import gestudio.entidades.Recibo;
import gestudio.entidades.ReciboPendiente;
import gestudio.infra.configuracion.AppProperties;
import gestudio.repositorios.AplicacionPagoRepositorio;
import gestudio.repositorios.ReciboPendienteRepositorio;
import gestudio.repositorios.ReciboRepositorio;
import gestudio.servicios.email.IEmailService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.TransactionStatus;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class ReciboStorageServiceTest {

    private static final Instant NOW = Instant.parse("2026-06-30T15:00:00Z");

    @Mock private PdfService pdf;
    @Mock private IEmailService email;
    @Mock private ReciboPendienteRepositorio pendientes;
    @Mock private ReciboRepositorio recibos;
    @Mock private AplicacionPagoRepositorio aplicaciones;
    @Mock private PlatformTransactionManager transactionManager;
    @Mock private TransactionStatus transactionStatus;
    @TempDir Path receiptsPath;

    @BeforeEach
    void transactions() {
        when(transactionManager.getTransaction(any(TransactionDefinition.class))).thenReturn(transactionStatus);
    }

    @Test
    void procesaUnaVezArchivoYEmailYCompletaElTrabajo() throws Exception {
        Pago pago = pago("alumno@example.test");
        Recibo recibo = recibo(pago);
        ReciboPendiente trabajo = trabajo(pago, 0);
        byte[] bytes = "pdf-test".getBytes();
        when(pendientes.findClaimableForUpdate(any(Instant.class), eq(10)))
                .thenReturn(List.of(trabajo))
                .thenReturn(List.of());
        when(pendientes.findByIdAndClaimToken(eq(1L), any(UUID.class)))
                .thenAnswer(invocation -> Optional.of(trabajo));
        when(recibos.findByPagoId(7L)).thenReturn(Optional.of(recibo));
        when(aplicaciones.findByPagoIdOrderById(7L)).thenReturn(List.of());
        when(pdf.generarReciboPdf(pago)).thenReturn(bytes);

        service().procesarPendientes();
        service().procesarPendientes();

        assertThat(trabajo.getEstado()).isEqualTo(EstadoReciboPendiente.COMPLETADO);
        assertThat(trabajo.getIntentos()).isOne();
        assertThat(trabajo.getProcessedAt()).isEqualTo(NOW);
        assertThat(recibo.getStorageKey()).isEqualTo("recibo_7.pdf");
        assertThat(recibo.getGeneradoAt()).isEqualTo(NOW);
        assertThat(recibo.getEnviadoAt()).isEqualTo(NOW);
        assertThat(Files.readAllBytes(receiptsPath.resolve("recibo_7.pdf"))).isEqualTo(bytes);
        verify(pdf, times(1)).generarReciboPdf(pago);
        verify(email, times(1)).sendEmailWithAttachmentAndInlineImage(
                any(), any(), any(), any(), any(), any(), any(), any(), any());
    }

    @Test
    void reintentaConLimiteYMarcaFalloPermanente() throws Exception {
        Pago pago = pago(null);
        Recibo recibo = recibo(pago);
        ReciboPendiente reintentable = trabajo(pago, 0);
        ReciboPendiente finalizado = trabajo(pago, 4);
        when(pendientes.findClaimableForUpdate(any(Instant.class), eq(10)))
                .thenReturn(List.of(reintentable))
                .thenReturn(List.of(finalizado));
        when(pendientes.findByIdAndClaimToken(eq(1L), any(UUID.class)))
                .thenAnswer(invocation -> {
                    UUID token = invocation.getArgument(1);
                    if (token.equals(reintentable.getClaimToken())) return Optional.of(reintentable);
                    if (token.equals(finalizado.getClaimToken())) return Optional.of(finalizado);
                    return Optional.empty();
                });
        when(recibos.findByPagoId(7L)).thenReturn(Optional.of(recibo));
        when(pdf.generarReciboPdf(pago)).thenThrow(new IllegalStateException("detalle que no se persiste"));

        ReciboStorageService service = service();
        service.procesarPendientes();
        assertThat(reintentable.getEstado()).isEqualTo(EstadoReciboPendiente.PENDIENTE);
        assertThat(reintentable.getNextAttemptAt()).isEqualTo(NOW.plusSeconds(300));
        assertThat(reintentable.getUltimoError()).isEqualTo("IllegalStateException");

        service.procesarPendientes();
        assertThat(finalizado.getEstado()).isEqualTo(EstadoReciboPendiente.ERROR);
        assertThat(finalizado.getIntentos()).isEqualTo(5);
        assertThat(finalizado.getProcessedAt()).isEqualTo(NOW);
        verify(email, never()).sendEmailWithAttachmentAndInlineImage(
                any(), any(), any(), any(), any(), any(), any(), any(), any());
    }

    @Test
    void recuperaLeaseYNoRepiteDocumentoNiEmailYaConfirmados() throws Exception {
        Pago pago = pago("alumno@example.test");
        Recibo recibo = recibo(pago);
        recibo.setStorageKey("recibo_7.pdf");
        recibo.setGeneradoAt(NOW.minusSeconds(60));
        recibo.setEnviadoAt(NOW.minusSeconds(30));
        Files.write(receiptsPath.resolve("recibo_7.pdf"), "existente".getBytes());
        ReciboPendiente trabajo = trabajo(pago, 1);
        trabajo.setEstado(EstadoReciboPendiente.PROCESANDO);
        trabajo.setClaimToken(UUID.randomUUID());
        trabajo.setClaimedAt(NOW.minusSeconds(600));
        trabajo.setLeaseUntil(NOW.minusSeconds(300));
        when(pendientes.findClaimableForUpdate(any(Instant.class), eq(10))).thenReturn(List.of(trabajo));
        when(pendientes.findByIdAndClaimToken(eq(1L), any(UUID.class)))
                .thenAnswer(invocation -> Optional.of(trabajo));
        when(recibos.findByPagoId(7L)).thenReturn(Optional.of(recibo));

        service().procesarPendientes();

        assertThat(trabajo.getEstado()).isEqualTo(EstadoReciboPendiente.COMPLETADO);
        assertThat(trabajo.getIntentos()).isEqualTo(2);
        assertThat(trabajo.getClaimToken()).isNull();
        assertThat(trabajo.getLeaseUntil()).isNull();
        verify(pdf, never()).generarReciboPdf(any());
        verify(email, never()).sendEmailWithAttachmentAndInlineImage(
                any(), any(), any(), any(), any(), any(), any(), any(), any());
    }

    private ReciboStorageService service() {
        return new ReciboStorageService(pdf, email,
                new AppProperties(ZoneOffset.UTC, receiptsPath, List.of("https://example.test")),
                pendientes, recibos, aplicaciones, Clock.fixed(NOW, ZoneOffset.UTC), transactionManager);
    }

    private Pago pago(String email) {
        Alumno alumno = new Alumno();
        alumno.setEmail(email);
        Pago pago = new Pago();
        pago.setId(7L);
        pago.setAlumno(alumno);
        return pago;
    }

    private Recibo recibo(Pago pago) {
        Recibo recibo = new Recibo();
        recibo.setPago(pago);
        return recibo;
    }

    private ReciboPendiente trabajo(Pago pago, int intentos) {
        ReciboPendiente trabajo = new ReciboPendiente();
        trabajo.setId(1L);
        trabajo.setPago(pago);
        trabajo.setIntentos(intentos);
        trabajo.setNextAttemptAt(NOW);
        trabajo.setIdempotencyKey("recibo:7:GENERAR_Y_ENVIAR");
        return trabajo;
    }
}
