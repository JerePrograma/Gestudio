package gestudio.servicios.pdfs;

import gestudio.entidades.EstadoReciboPendiente;
import gestudio.entidades.Recibo;
import gestudio.entidades.ReciboPendiente;
import gestudio.entidades.Pago;
import gestudio.infra.configuracion.AppProperties;
import gestudio.repositorios.AplicacionPagoRepositorio;
import gestudio.repositorios.ReciboPendienteRepositorio;
import gestudio.repositorios.ReciboRepositorio;
import gestudio.servicios.email.IEmailService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.StandardCopyOption;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

@Service
@ConditionalOnProperty(name = "app.scheduling-enabled", havingValue = "true")
public class ReciboStorageService {
    private static final Logger log = LoggerFactory.getLogger(ReciboStorageService.class);
    private static final int MAX_INTENTOS = 5;
    private static final Duration LEASE = Duration.ofMinutes(5);
    private final PdfService pdf;
    private final IEmailService email;
    private final AppProperties properties;
    private final ReciboPendienteRepositorio pendientes;
    private final ReciboRepositorio recibos;
    private final AplicacionPagoRepositorio aplicaciones;
    private final Clock clock;
    private final TransactionTemplate transactions;

    public ReciboStorageService(PdfService pdf,
                                IEmailService email,
                                AppProperties properties,
                                ReciboPendienteRepositorio pendientes,
                                ReciboRepositorio recibos,
                                AplicacionPagoRepositorio aplicaciones,
                                Clock clock,
                                PlatformTransactionManager transactionManager) {
        this.pdf = pdf;
        this.email = email;
        this.properties = properties;
        this.pendientes = pendientes;
        this.recibos = recibos;
        this.aplicaciones = aplicaciones;
        this.clock = clock;
        this.transactions = new TransactionTemplate(transactionManager);
    }

    @Scheduled(fixedDelayString = "${app.receipts.worker-delay-ms:30000}")
    public void procesarPendientes() {
        List<Claim> trabajos = transactions.execute(status -> reclamar());
        if (trabajos == null) {
            return;
        }
        trabajos.forEach(this::procesar);
    }

    private List<Claim> reclamar() {
        Instant ahora = clock.instant();
        return pendientes.findClaimableForUpdate(ahora, 10).stream()
                .map(trabajo -> {
                    UUID token = UUID.randomUUID();
                    trabajo.setEstado(EstadoReciboPendiente.PROCESANDO);
                    trabajo.setIntentos(trabajo.getIntentos() + 1);
                    trabajo.setClaimToken(token);
                    trabajo.setClaimedAt(ahora);
                    trabajo.setLeaseUntil(ahora.plus(LEASE));
                    return new Claim(trabajo.getId(), token);
                }).toList();
    }

    private void procesar(Claim claim) {
        try {
            Trabajo trabajo = transactions.execute(status -> cargar(claim));
            if (trabajo == null) {
                return;
            }
            String nombre = "recibo_" + trabajo.pago().getId() + ".pdf";
            Path raiz = properties.receiptsPath().toAbsolutePath().normalize();
            Path almacenado = ReciboPathResolver.resolveExistingFile(raiz, trabajo.storageKey());
            byte[] bytes;
            if (almacenado != null) {
                bytes = Files.readAllBytes(almacenado);
                nombre = trabajo.storageKey();
            } else {
                bytes = pdf.generarReciboPdf(trabajo.pago());
                if (!renovarLease(claim)) {
                    return;
                }
                guardar(raiz, nombre, bytes);
                String storageKey = nombre;
                transactions.executeWithoutResult(status -> confirmarGenerado(claim, storageKey));
            }

            String destinatario = trabajo.pago().getAlumno().getEmail();
            if (trabajo.enviadoAt() == null && destinatario != null && !destinatario.isBlank()) {
                if (!renovarLease(claim)) {
                    return;
                }
                email.sendEmailWithAttachmentAndInlineImage(
                        "administracion@gestudio.com.ar",
                        destinatario,
                        "Recibo de pago",
                        cuerpo(trabajo),
                        bytes,
                        nombre,
                        firma(),
                        "signature",
                        "image/png");
                transactions.executeWithoutResult(status -> confirmarEnviado(claim));
            }
            transactions.executeWithoutResult(status -> completar(claim));
            log.info("Recibo procesado pagoId={} enviado={}", trabajo.pago().getId(),
                    trabajo.enviadoAt() != null || destinatario != null && !destinatario.isBlank());
        } catch (Exception e) {
            transactions.executeWithoutResult(status -> fallar(claim, e));
        }
    }

    private Trabajo cargar(Claim claim) {
        ReciboPendiente pendiente = pendientes.findByIdAndClaimToken(claim.id(), claim.token()).orElse(null);
        if (pendiente == null) {
            return null;
        }
        Recibo recibo = recibos.findByPagoId(pendiente.getPago().getId())
                .orElseThrow(() -> new IllegalStateException("Outbox sin recibo"));
        return new Trabajo(pendiente.getPago(), recibo.getStorageKey(), recibo.getEnviadoAt());
    }

    private boolean renovarLease(Claim claim) {
        Boolean renovado = transactions.execute(status -> pendientes.findByIdAndClaimToken(claim.id(), claim.token())
                .map(trabajo -> {
                    trabajo.setLeaseUntil(clock.instant().plus(LEASE));
                    return true;
                }).orElse(false));
        return Boolean.TRUE.equals(renovado);
    }

    private void confirmarGenerado(Claim claim, String storageKey) {
        ReciboPendiente pendiente = pendientes.findByIdAndClaimToken(claim.id(), claim.token()).orElse(null);
        if (pendiente == null) {
            return;
        }
        Recibo recibo = recibos.findByPagoId(pendiente.getPago().getId()).orElseThrow();
        if (recibo.getStorageKey() == null) {
            recibo.setStorageKey(storageKey);
            recibo.setGeneradoAt(clock.instant());
        }
    }

    private void confirmarEnviado(Claim claim) {
        ReciboPendiente pendiente = pendientes.findByIdAndClaimToken(claim.id(), claim.token()).orElse(null);
        if (pendiente == null) {
            return;
        }
        Recibo recibo = recibos.findByPagoId(pendiente.getPago().getId()).orElseThrow();
        if (recibo.getEnviadoAt() == null) {
            recibo.setEnviadoAt(clock.instant());
        }
    }

    private void completar(Claim claim) {
        pendientes.findByIdAndClaimToken(claim.id(), claim.token()).ifPresent(trabajo -> {
            trabajo.setEstado(EstadoReciboPendiente.COMPLETADO);
            trabajo.setProcessedAt(clock.instant());
            trabajo.setUltimoError(null);
            liberar(trabajo);
        });
    }

    private void fallar(Claim claim, Exception e) {
        pendientes.findByIdAndClaimToken(claim.id(), claim.token()).ifPresent(trabajo -> {
            String error = e.getClass().getSimpleName();
            trabajo.setUltimoError(error);
            if (trabajo.getIntentos() >= MAX_INTENTOS) {
                trabajo.setEstado(EstadoReciboPendiente.ERROR);
                trabajo.setProcessedAt(clock.instant());
            } else {
                trabajo.setEstado(EstadoReciboPendiente.PENDIENTE);
                trabajo.setNextAttemptAt(clock.instant().plus(Duration.ofMinutes(5)));
            }
            liberar(trabajo);
            log.warn("Falló efecto de recibo pagoId={} intento={} error={}",
                    trabajo.getPago().getId(), trabajo.getIntentos(), error);
        });
    }

    private static void liberar(ReciboPendiente trabajo) {
        trabajo.setClaimToken(null);
        trabajo.setClaimedAt(null);
        trabajo.setLeaseUntil(null);
    }

    private static void guardar(Path raiz, String nombre, byte[] bytes) throws IOException {
        Path destino = raiz.resolve(nombre).normalize();
        if (!destino.startsWith(raiz)) {
            throw new IOException("Ruta de recibo inválida");
        }
        Files.createDirectories(raiz);
        Path temporal = Files.createTempFile(raiz, nombre, ".tmp");
        try {
            Files.write(temporal, bytes);
            try {
                Files.move(temporal, destino, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
            } catch (AtomicMoveNotSupportedException e) {
                Files.move(temporal, destino, StandardCopyOption.REPLACE_EXISTING);
            }
        } finally {
            Files.deleteIfExists(temporal);
        }
    }

    private String cuerpo(Trabajo trabajo) {
        String conceptos = aplicaciones.findByPagoIdOrderById(trabajo.pago().getId()).stream()
                .map(a -> escapar(a.getCargo().getDescripcion()))
                .reduce((a, b) -> a + "<br>" + b).orElse("Pago recibido");
        return "<p>Recibimos tu pago por:</p><p>" + conceptos + "</p><img src='cid:signature' alt='Firma'>";
    }

    private byte[] firma() throws IOException {
        try (InputStream entrada = getClass().getResourceAsStream("/firma_mesa-de-trabajo-1.png")) {
            if (entrada == null) {
                throw new IOException("Firma no disponible");
            }
            return entrada.readAllBytes();
        }
    }

    private static String escapar(String texto) {
        return texto.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
    }

    private record Claim(Long id, UUID token) {
    }

    private record Trabajo(Pago pago, String storageKey, Instant enviadoAt) {
    }
}
