package gestudio.infra.persistencia;

import gestudio.servicios.matricula.MatriculaServicio;
import gestudio.servicios.mensualidad.MensualidadServicio;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.Clock;
import java.time.LocalDate;
import java.time.Year;
import java.time.YearMonth;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
class SchedulerIdempotencyPostgreSqlTest extends PostgreSqlIntegrationTest {

    @Autowired private MensualidadServicio mensualidades;
    @Autowired private MatriculaServicio matriculas;
    @Autowired private JdbcTemplate jdbc;
    @Autowired private Clock clock;

    @Test
    @Timeout(30)
    void dosEjecucionesSimultaneasNoDuplicanMensualidadesMatriculasCargosNiSnapshots() throws Exception {
        String suffix = UUID.randomUUID().toString();
        // PostgreSqlIntegrationTest comparte un contenedor entre clases. El scheduler es global,
        // por lo que la fixture debe excluir inscripciones activas creadas por pruebas anteriores.
        jdbc.update("UPDATE inscripciones SET estado = 'INACTIVA' WHERE estado = 'ACTIVA'");
        Long usuario = usuario("scheduler-" + suffix);
        Long profesor = id("""
                INSERT INTO profesores(nombre, apellido, activo) VALUES (?, 'Scheduler', true) RETURNING id
                """, "Profesor " + suffix);
        Long disciplina = id("""
                INSERT INTO disciplinas(nombre, profesor_id, valor_cuota, matricula, clase_suelta, clase_prueba, activo)
                VALUES (?, ?, 999, 888, 0, 0, true) RETURNING id
                """, "Disciplina " + suffix, profesor);
        int anio = Year.now(clock).getValue();
        jdbc.update("""
                INSERT INTO disciplina_tarifas(
                    disciplina_id, vigente_desde, valor_cuota, matricula,
                    clase_suelta, clase_prueba, motivo, creada_por_usuario_id)
                VALUES (?, ?, 100.00, 40.00, 0, 0, 'Fixture scheduler por vigencia', ?)
                """, disciplina, LocalDate.of(anio, 1, 1), usuario);

        Long alumno1 = alumno("Alumno A " + suffix);
        Long alumno2 = alumno("Alumno B " + suffix);
        Long inscripcion1 = inscripcion(alumno1, disciplina);
        Long inscripcion2 = inscripcion(alumno2, disciplina);

        ejecutarDosVecesEnParalelo(mensualidades::generarMensualidadesParaMesVigente);
        ejecutarDosVecesEnParalelo(matriculas::generarMatriculasAnioVigente);
        mensualidades.generarMensualidadesParaMesVigente();
        matriculas.generarMatriculasAnioVigente();

        YearMonth periodo = YearMonth.now(clock);
        Integer mensualidadesCreadas = jdbc.queryForObject("""
                SELECT count(*) FROM mensualidades
                WHERE inscripcion_id IN (?, ?) AND anio = ? AND mes = ?
                """, Integer.class, inscripcion1, inscripcion2, periodo.getYear(), periodo.getMonthValue());
        Integer matriculasCreadas = jdbc.queryForObject("""
                SELECT count(*) FROM matriculas WHERE alumno_id IN (?, ?) AND anio = ?
                """, Integer.class, alumno1, alumno2, anio);
        Integer cargosMensualidad = jdbc.queryForObject("""
                SELECT count(*) FROM cargos c JOIN mensualidades m ON m.id = c.mensualidad_id
                WHERE m.inscripcion_id IN (?, ?) AND m.anio = ? AND m.mes = ?
                """, Integer.class, inscripcion1, inscripcion2, periodo.getYear(), periodo.getMonthValue());
        Integer cargosMatricula = jdbc.queryForObject("""
                SELECT count(*) FROM cargos c JOIN matriculas m ON m.id = c.matricula_id
                WHERE m.alumno_id IN (?, ?) AND m.anio = ?
                """, Integer.class, alumno1, alumno2, anio);
        Integer snapshots = jdbc.queryForObject("""
                SELECT count(*)
                FROM cargo_liquidaciones l
                JOIN cargos c ON c.id = l.cargo_id
                LEFT JOIN mensualidades me ON me.id = c.mensualidad_id
                LEFT JOIN matriculas ma ON ma.id = c.matricula_id
                WHERE (me.inscripcion_id IN (?, ?) AND me.anio = ? AND me.mes = ?)
                   OR (ma.alumno_id IN (?, ?) AND ma.anio = ?)
                """, Integer.class,
                inscripcion1, inscripcion2, periodo.getYear(), periodo.getMonthValue(),
                alumno1, alumno2, anio);
        Integer formulas = jdbc.queryForObject("""
                SELECT count(*)
                FROM cargo_liquidaciones l
                JOIN cargos c ON c.id = l.cargo_id
                LEFT JOIN mensualidades me ON me.id = c.mensualidad_id
                LEFT JOIN matriculas ma ON ma.id = c.matricula_id
                WHERE l.formula_version = 1
                  AND l.origen_precio = 'TARIFA_HISTORICA'
                  AND ((me.inscripcion_id IN (?, ?) AND me.anio = ? AND me.mes = ?)
                    OR (ma.alumno_id IN (?, ?) AND ma.anio = ?))
                """, Integer.class,
                inscripcion1, inscripcion2, periodo.getYear(), periodo.getMonthValue(),
                alumno1, alumno2, anio);

        assertThat(mensualidadesCreadas).isEqualTo(2);
        assertThat(matriculasCreadas).isEqualTo(2);
        assertThat(cargosMensualidad).isEqualTo(2);
        assertThat(cargosMatricula).isEqualTo(2);
        assertThat(snapshots).isEqualTo(4);
        assertThat(formulas).isEqualTo(4);
    }

    private void ejecutarDosVecesEnParalelo(Runnable proceso) throws Exception {
        CountDownLatch start = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        Future<?> first = executor.submit(() -> ejecutar(start, proceso));
        Future<?> second = executor.submit(() -> ejecutar(start, proceso));
        boolean completed = false;
        try {
            start.countDown();
            first.get(10, TimeUnit.SECONDS);
            second.get(10, TimeUnit.SECONDS);
            completed = true;
        } finally {
            start.countDown();
            if (completed) {
                executor.shutdown();
            } else {
                first.cancel(true);
                second.cancel(true);
                executor.shutdownNow();
            }
            assertThat(executor.awaitTermination(5, TimeUnit.SECONDS)).isTrue();
        }
    }

    private static void ejecutar(CountDownLatch start, Runnable proceso) {
        try {
            if (!start.await(5, TimeUnit.SECONDS)) {
                throw new IllegalStateException("Timeout esperando inicio concurrente");
            }
            proceso.run();
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(exception);
        }
    }

    private Long usuario(String nombre) {
        Long rol = jdbc.queryForObject("SELECT id FROM roles WHERE codigo = 'SUPERADMIN'", Long.class);
        Long usuario = id("""
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo)
                VALUES (?, 'test-only', ?, true) RETURNING id
                """, nombre, rol);
        jdbc.update("INSERT INTO usuario_roles(usuario_id, rol_id) VALUES (?, ?) ON CONFLICT DO NOTHING",
                usuario, rol);
        return usuario;
    }

    private Long alumno(String nombre) {
        return id("""
                INSERT INTO alumnos(nombre, fecha_incorporacion, activo)
                VALUES (?, DATE '2026-01-01', true) RETURNING id
                """, nombre);
    }

    private Long inscripcion(Long alumno, Long disciplina) {
        return id("""
                INSERT INTO inscripciones(alumno_id, disciplina_id, fecha_inscripcion, estado)
                VALUES (?, ?, DATE '2026-01-01', 'ACTIVA') RETURNING id
                """, alumno, disciplina);
    }

    private Long id(String sql, Object... args) {
        Long value = jdbc.queryForObject(sql, Long.class, args);
        if (value == null) throw new IllegalStateException("La inserción no devolvió id");
        return value;
    }
}
