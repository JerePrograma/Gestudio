package gestudio.cuotas;

import gestudio.dto.inscripcion.request.InscripcionRegistroRequest;
import gestudio.dto.mensualidad.request.MensualidadRegistroRequest;
import gestudio.infra.persistencia.PostgreSqlIntegrationTest;
import gestudio.servicios.inscripcion.InscripcionServicio;
import gestudio.servicios.mensualidad.MensualidadServicio;
import gestudio.tarifas.application.TarifaDisciplinaServicio;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
class LiquidacionCargoAtomicaPostgreSqlTest extends PostgreSqlIntegrationTest {

    @Autowired private MensualidadServicio mensualidades;
    @Autowired private InscripcionServicio inscripciones;
    @Autowired private JdbcTemplate jdbc;

    @Test
    void reintentoSecuencialDevuelveCargoYSnapshotOriginalSinRecalcularTarifaNueva() {
        Fixture fixture = fixture("retry", true);
        Long tarifaOriginal = tarifa(fixture, LocalDate.of(2026, 1, 1), "100.00", "40.00");

        var primera = mensualidades.crearMensualidad(
                new MensualidadRegistroRequest(fixture.inscripcionId(), 2026, 2, null, null));
        tarifa(fixture, LocalDate.of(2026, 2, 1), "150.00", "60.00");
        var segunda = mensualidades.crearMensualidad(
                new MensualidadRegistroRequest(fixture.inscripcionId(), 2026, 2, null, null));

        assertThat(segunda.id()).isEqualTo(primera.id());
        assertThat(segunda.cargoId()).isEqualTo(primera.cargoId());
        assertThat(segunda.importeOriginal()).isEqualTo("100.00");
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM cargo_liquidaciones WHERE cargo_id = ?",
                Integer.class, primera.cargoId())).isOne();
        assertThat(jdbc.queryForObject(
                "SELECT tarifa_disciplina_id FROM cargo_liquidaciones WHERE cargo_id = ?",
                Long.class, primera.cargoId())).isEqualTo(tarifaOriginal);
        assertThat(jdbc.queryForObject(
                "SELECT importe_final FROM cargo_liquidaciones WHERE cargo_id = ?",
                BigDecimal.class, primera.cargoId())).isEqualByComparingTo("100.00");
    }

    @Test
    void cargoExistenteSinSnapshotEsInconsistenciaYNoSeCompletaConConfiguracionActual() {
        Fixture fixture = fixture("missing-snapshot", true);
        tarifa(fixture, LocalDate.of(2026, 1, 1), "100.00", "40.00");
        var creada = mensualidades.crearMensualidad(
                new MensualidadRegistroRequest(fixture.inscripcionId(), 2026, 3, null, null));
        jdbc.update("DELETE FROM cargo_liquidaciones WHERE cargo_id = ?", creada.cargoId());
        tarifa(fixture, LocalDate.of(2026, 3, 1), "999.00", "999.00");

        assertThatThrownBy(() -> mensualidades.crearMensualidad(
                new MensualidadRegistroRequest(fixture.inscripcionId(), 2026, 3, null, null)))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("sin snapshot")
                .hasMessageContaining("no se recalcula");

        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM cargos WHERE id = ?", Integer.class, creada.cargoId())).isOne();
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM cargo_liquidaciones WHERE cargo_id = ?",
                Integer.class, creada.cargoId())).isZero();
    }

    @Test
    void falloDeSnapshotRevierteMensualidadYCargo() {
        Fixture fixture = fixture("snapshot-failure", true);
        tarifa(fixture, LocalDate.of(2026, 1, 1), "100.00", "40.00");
        instalarFalloSnapshot();
        try {
            assertThatThrownBy(() -> mensualidades.crearMensualidad(
                    new MensualidadRegistroRequest(fixture.inscripcionId(), 2026, 4, null, null)))
                    .isInstanceOf(RuntimeException.class)
                    .hasStackTraceContaining("fallo de snapshot inducido por test");
        } finally {
            retirarFalloSnapshot();
        }

        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM mensualidades
                WHERE inscripcion_id = ? AND anio = 2026 AND mes = 4
                """, Integer.class, fixture.inscripcionId())).isZero();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM cargos c
                JOIN mensualidades m ON m.id = c.mensualidad_id
                WHERE m.inscripcion_id = ? AND m.anio = 2026 AND m.mes = 4
                """, Integer.class, fixture.inscripcionId())).isZero();
    }

    @Test
    void altaDeInscripcionSinTarifaRevierteTodoElAgregado() {
        Fixture fixture = fixture("enrollment-rollback", false);

        assertThatThrownBy(() -> inscripciones.crearInscripcion(new InscripcionRegistroRequest(
                null,
                fixture.alumnoId(),
                fixture.disciplinaId(),
                null,
                LocalDate.of(2026, 7, 1),
                null
        ))).isInstanceOf(TarifaDisciplinaServicio.TarifaHistoricaNoDefinidaException.class);

        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM inscripciones
                WHERE alumno_id = ? AND disciplina_id = ?
                """, Integer.class, fixture.alumnoId(), fixture.disciplinaId())).isZero();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM mensualidades m
                JOIN inscripciones i ON i.id = m.inscripcion_id
                WHERE i.alumno_id = ? AND i.disciplina_id = ?
                """, Integer.class, fixture.alumnoId(), fixture.disciplinaId())).isZero();
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM matriculas WHERE alumno_id = ?",
                Integer.class, fixture.alumnoId())).isZero();
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM cargos WHERE alumno_id = ?",
                Integer.class, fixture.alumnoId())).isZero();
    }

    @Test
    void apiLegacyRechazaBonificacionYCostoParticularEnLugarDeIgnorarlos() {
        Fixture fixture = fixture("legacy-api", false);

        assertThatThrownBy(() -> inscripciones.crearInscripcion(new InscripcionRegistroRequest(
                null, fixture.alumnoId(), fixture.disciplinaId(), 99L,
                LocalDate.of(2026, 7, 1), null)))
                .hasMessageContaining("bonificacionId")
                .hasMessageContaining("condición económica");
        assertThatThrownBy(() -> inscripciones.crearInscripcion(new InscripcionRegistroRequest(
                null, fixture.alumnoId(), fixture.disciplinaId(), null,
                LocalDate.of(2026, 7, 1), new BigDecimal("80.00"))))
                .hasMessageContaining("costoParticular")
                .hasMessageContaining("condición económica");
    }

    private Fixture fixture(String prefix, boolean conInscripcion) {
        String suffix = prefix + "-" + UUID.randomUUID();
        Long role = jdbc.queryForObject("SELECT id FROM roles WHERE codigo = 'SUPERADMIN'", Long.class);
        Long user = id("""
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo)
                VALUES (?, 'test-only', ?, true) RETURNING id
                """, "atomicidad-" + suffix, role);
        jdbc.update("INSERT INTO usuario_roles(usuario_id, rol_id) VALUES (?, ?) ON CONFLICT DO NOTHING",
                user, role);
        Long profesor = id("""
                INSERT INTO profesores(nombre, apellido, activo)
                VALUES (?, 'Atomicidad', true) RETURNING id
                """, "Profesor " + suffix);
        Long disciplina = id("""
                INSERT INTO disciplinas(nombre, profesor_id, valor_cuota, matricula,
                                        clase_suelta, clase_prueba, activo)
                VALUES (?, ?, 999.00, 999.00, 0, 0, true) RETURNING id
                """, "Disciplina " + suffix, profesor);
        Long alumno = id("""
                INSERT INTO alumnos(nombre, apellido, fecha_incorporacion, activo)
                VALUES ('Alumno', ?, DATE '2025-01-01', true) RETURNING id
                """, suffix);
        Long inscripcion = conInscripcion ? id("""
                INSERT INTO inscripciones(alumno_id, disciplina_id, fecha_inscripcion, estado)
                VALUES (?, ?, DATE '2025-01-01', 'ACTIVA') RETURNING id
                """, alumno, disciplina) : null;
        return new Fixture(user, alumno, disciplina, inscripcion);
    }

    private Long tarifa(Fixture fixture, LocalDate desde, String cuota, String matricula) {
        return id("""
                INSERT INTO disciplina_tarifas(
                    disciplina_id, vigente_desde, valor_cuota, matricula,
                    clase_suelta, clase_prueba, motivo, creada_por_usuario_id)
                VALUES (?, ?, ?, ?, 0, 0, 'Fixture atomicidad', ?) RETURNING id
                """, fixture.disciplinaId(), desde, new BigDecimal(cuota),
                new BigDecimal(matricula), fixture.usuarioId());
    }

    private void instalarFalloSnapshot() {
        jdbc.execute("""
                CREATE OR REPLACE FUNCTION test_fallar_cargo_liquidacion()
                RETURNS trigger LANGUAGE plpgsql AS $$
                BEGIN
                    RAISE EXCEPTION 'fallo de snapshot inducido por test';
                END;
                $$
                """);
        jdbc.execute("""
                CREATE TRIGGER test_fallar_cargo_liquidacion_trigger
                BEFORE INSERT ON cargo_liquidaciones
                FOR EACH ROW EXECUTE FUNCTION test_fallar_cargo_liquidacion()
                """);
    }

    private void retirarFalloSnapshot() {
        jdbc.execute("DROP TRIGGER IF EXISTS test_fallar_cargo_liquidacion_trigger ON cargo_liquidaciones");
        jdbc.execute("DROP FUNCTION IF EXISTS test_fallar_cargo_liquidacion()");
    }

    private Long id(String sql, Object... args) {
        Long value = jdbc.queryForObject(sql, Long.class, args);
        if (value == null) throw new IllegalStateException("La inserción no devolvió id");
        return value;
    }

    private record Fixture(Long usuarioId, Long alumnoId, Long disciplinaId, Long inscripcionId) {
    }
}
