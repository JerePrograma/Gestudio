package gestudio.infra.persistencia;

import gestudio.entidades.EstadoReciboPendiente;
import gestudio.repositorios.ReciboPendienteRepositorio;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest
class ReciboOutboxPostgreSqlTest extends PostgreSqlIntegrationTest {

    @Autowired private JdbcTemplate jdbc;
    @Autowired private ReciboPendienteRepositorio pendientes;
    @Autowired private PlatformTransactionManager transactionManager;

    private long metodo;
    private long usuario;
    private long alumno;
    private long pago;
    private long recibo;
    private long pendiente;

    @BeforeEach
    void seed() {
        jdbc.execute("TRUNCATE TABLE recibos_pendientes RESTART IDENTITY");
        String suffix = UUID.randomUUID().toString();
        metodo = id("INSERT INTO metodo_pagos(descripcion, activo, recargo) VALUES (?, true, 0) RETURNING id",
                "Outbox " + suffix);
        usuario = id("""
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo)
                VALUES (?, 'no-login', (SELECT id FROM roles WHERE descripcion = 'ADMINISTRADOR'), true)
                RETURNING id
                """, "outbox-" + suffix);
        alumno = id("""
                INSERT INTO alumnos(nombre, fecha_incorporacion, email, activo)
                VALUES (?, DATE '2026-01-01', 'outbox@example.test', true) RETURNING id
                """, "Outbox " + suffix);
        pago = id("""
                INSERT INTO pagos(alumno_id, metodo_pago_id, usuario_id, fecha, monto_recibido, estado,
                                  idempotency_key, request_hash)
                VALUES (?, ?, ?, DATE '2026-01-01', 10, 'REGISTRADO', ?, repeat('c', 64)) RETURNING id
                """, alumno, metodo, usuario, "pago-" + suffix);
        recibo = id("INSERT INTO recibos(pago_id) VALUES (?) RETURNING id", pago);
        pendiente = id("""
                INSERT INTO recibos_pendientes(pago_id, tipo, estado, intentos, next_attempt_at, idempotency_key)
                VALUES (?, 'GENERAR_Y_ENVIAR', 'PENDIENTE', 0, CURRENT_TIMESTAMP, ?) RETURNING id
                """, pago, "recibo:" + pago + ":GENERAR_Y_ENVIAR");
    }

    @AfterEach
    void cleanup() {
        jdbc.update("DELETE FROM recibos_pendientes WHERE id = ?", pendiente);
        jdbc.update("DELETE FROM recibos WHERE id = ?", recibo);
        jdbc.update("DELETE FROM pagos WHERE id = ?", pago);
        jdbc.update("DELETE FROM alumnos WHERE id = ?", alumno);
        jdbc.update("DELETE FROM usuarios WHERE id = ?", usuario);
        jdbc.update("DELETE FROM metodo_pagos WHERE id = ?", metodo);
    }

    @Test
    @Timeout(15)
    void skipLockedEvitaDobleClaimYElLeaseVencidoEsRecuperable() throws Exception {
        TransactionTemplate tx = new TransactionTemplate(transactionManager);
        CountDownLatch locked = new CountDownLatch(1);
        CountDownLatch release = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        Future<List<Long>> first = null;
        Future<List<Long>> second = null;
        boolean completed = false;
        try {
            first = executor.submit(() -> tx.execute(status -> {
                var rows = pendientes.findClaimableForUpdate(Instant.now(), 1);
                var trabajo = rows.getFirst();
                trabajo.setEstado(EstadoReciboPendiente.PROCESANDO);
                trabajo.setClaimToken(UUID.randomUUID());
                trabajo.setClaimedAt(Instant.now());
                trabajo.setLeaseUntil(Instant.now().plusSeconds(300));
                pendientes.flush();
                locked.countDown();
                await(release);
                return rows.stream().map(r -> r.getId()).toList();
            }));

            assertThat(locked.await(5, TimeUnit.SECONDS)).isTrue();
            second = executor.submit(() -> tx.execute(status -> pendientes
                    .findClaimableForUpdate(Instant.now(), 1).stream().map(r -> r.getId()).toList()));
            assertThat(second.get(3, TimeUnit.SECONDS)).isEmpty();
            release.countDown();
            assertThat(first.get(5, TimeUnit.SECONDS)).containsExactly(pendiente);
            completed = true;
        } finally {
            release.countDown();
            if (completed) {
                executor.shutdown();
            } else {
                cancel(first);
                cancel(second);
                executor.shutdownNow();
            }
            assertThat(executor.awaitTermination(5, TimeUnit.SECONDS)).isTrue();
        }

        jdbc.update("""
                UPDATE recibos_pendientes
                SET estado = 'PROCESANDO', claim_token = ?::uuid, claimed_at = ?, lease_until = ?
                WHERE id = ?
                """, UUID.randomUUID().toString(), OffsetDateTime.now(ZoneOffset.UTC).minusSeconds(600),
                OffsetDateTime.now(ZoneOffset.UTC).minusSeconds(300), pendiente);
        List<Long> recovered = tx.execute(status -> pendientes.findClaimableForUpdate(Instant.now(), 1)
                .stream().map(r -> r.getId()).toList());
        assertThat(recovered).containsExactly(pendiente);
    }

    @Test
    void efectoDuplicadoEsRechazadoPorConstraint() {
        assertThatThrownBy(() -> jdbc.update("""
                INSERT INTO recibos_pendientes(pago_id, tipo, estado, intentos, next_attempt_at, idempotency_key)
                VALUES (?, 'GENERAR_Y_ENVIAR', 'PENDIENTE', 0, CURRENT_TIMESTAMP, ?)
                """, pago, "otra-key-" + UUID.randomUUID()))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    private long id(String sql, Object... args) {
        Long value = jdbc.queryForObject(sql, Long.class, args);
        if (value == null) throw new IllegalStateException("La insercion no devolvio id");
        return value;
    }

    private static void await(CountDownLatch latch) {
        try {
            if (!latch.await(5, TimeUnit.SECONDS)) {
                throw new IllegalStateException("Timeout esperando liberacion del claim");
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
    }

    private static void cancel(Future<?> future) {
        if (future != null) future.cancel(true);
    }
}
