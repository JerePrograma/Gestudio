package gestudio.servicios.notificaciones;

import gestudio.infra.persistencia.PostgreSqlIntegrationTest;
import gestudio.repositorios.NotificacionRepositorio;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
class NotificacionIdempotenciaPostgreSqlTest extends PostgreSqlIntegrationTest {

    private static final int WORKERS = 8;

    @Autowired private NotificacionRepositorio notificaciones;
    @Autowired private PlatformTransactionManager transactionManager;
    @Autowired private JdbcTemplate jdbc;

    @Test
    @Timeout(30)
    void insercionesConcurrentesDeLaMismaNotificacionTienenUnSoloGanador() throws Exception {
        String dedupKey = "cumple-concurrente:" + UUID.randomUUID();
        CountDownLatch preparados = new CountDownLatch(WORKERS);
        CountDownLatch inicio = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(WORKERS);
        List<Future<Integer>> futures = new ArrayList<>();

        for (int worker = 0; worker < WORKERS; worker++) {
            futures.add(executor.submit(() -> insertarAlLiberar(preparados, inicio, dedupKey)));
        }

        boolean completado = false;
        try {
            assertThat(preparados.await(5, TimeUnit.SECONDS)).isTrue();
            inicio.countDown();

            List<Integer> resultados = new ArrayList<>();
            for (Future<Integer> future : futures) {
                resultados.add(future.get(10, TimeUnit.SECONDS));
            }
            completado = true;

            assertThat(resultados).containsOnly(0, 1);
            assertThat(resultados.stream().filter(resultado -> resultado == 1)).hasSize(1);
            assertThat(jdbc.queryForObject(
                    "SELECT count(*) FROM notificaciones WHERE dedup_key = ?",
                    Integer.class,
                    dedupKey
            )).isOne();
        } finally {
            inicio.countDown();
            if (completado) {
                executor.shutdown();
            } else {
                futures.forEach(future -> future.cancel(true));
                executor.shutdownNow();
            }
            assertThat(executor.awaitTermination(5, TimeUnit.SECONDS)).isTrue();
        }
    }

    private int insertarAlLiberar(CountDownLatch preparados,
                                  CountDownLatch inicio,
                                  String dedupKey) throws Exception {
        preparados.countDown();
        if (!inicio.await(5, TimeUnit.SECONDS)) {
            throw new IllegalStateException("Timeout esperando inicio concurrente");
        }

        Integer resultado = new TransactionTemplate(transactionManager).execute(status ->
                notificaciones.insertarSiAusente(
                        "CUMPLEANOS",
                        "Alumno: Concurrente Prueba",
                        Instant.parse("2026-07-21T15:00:00Z"),
                        LocalDate.of(2026, 7, 21),
                        dedupKey
                ));
        if (resultado == null) {
            throw new IllegalStateException("La inserción concurrente no devolvió resultado");
        }
        return resultado;
    }
}
