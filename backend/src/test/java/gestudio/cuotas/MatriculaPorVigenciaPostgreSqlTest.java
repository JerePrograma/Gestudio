package gestudio.cuotas;

import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.infra.persistencia.PostgreSqlIntegrationTest;
import gestudio.servicios.matricula.MatriculaServicio;
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
class MatriculaPorVigenciaPostgreSqlTest extends PostgreSqlIntegrationTest {

    @Autowired private MatriculaServicio matriculas;
    @Autowired private JdbcTemplate jdbc;

    @Test
    void noEmiteMatriculaCeroSinInscripcionesActivas() {
        Base base = base("sin-inscripciones");

        assertThatThrownBy(() -> matriculas.obtenerOMarcarPendienteMatricula(base.alumnoId(), 2026))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("sin inscripciones activas");
        assertThat(count("SELECT count(*) FROM matriculas WHERE alumno_id = ?", base.alumnoId())).isZero();
    }

    @Test
    void unaDisciplinaEmiteCargoYSnapshotConFechaPrimeroDeEnero() {
        Base base = base("una");
        Disciplina disciplina = disciplina(base, "Danza", "100.00", "60.00");
        Long inscripcion = inscripcion(base.alumnoId(), disciplina.id());

        var matricula = matriculas.obtenerOMarcarPendienteMatricula(base.alumnoId(), 2026);
        Long cargoId = cargoId(matricula.id());

        assertThat(cargoImporte(cargoId)).isEqualByComparingTo("60.00");
        assertThat(snapshotLong(cargoId, "tarifa_disciplina_id")).isEqualTo(disciplina.tarifaId());
        assertThat(snapshotDate(cargoId)).isEqualTo(LocalDate.of(2026, 1, 1));
        assertThat(snapshotText(cargoId, "observaciones")).contains("inscripciónGanadora=" + inscripcion);
    }

    @Test
    void multidisciplinaEligeMayorImporteFinalNoMayorTarifaBase() {
        Base base = base("max-final");
        Disciplina baseMayor = disciplina(base, "Base mayor", "100.00", "100.00");
        Disciplina finalMayor = disciplina(base, "Final mayor", "100.00", "80.00");
        Long inscripcionBaseMayor = inscripcion(base.alumnoId(), baseMayor.id());
        Long inscripcionFinalMayor = inscripcion(base.alumnoId(), finalMayor.id());
        condicion(base, inscripcionBaseMayor, LocalDate.of(2026, 1, 1), null, "50.0000", "0.00");

        var matricula = matriculas.obtenerOMarcarPendienteMatricula(base.alumnoId(), 2026);
        Long cargoId = cargoId(matricula.id());

        assertThat(cargoImporte(cargoId)).isEqualByComparingTo("80.00");
        assertThat(snapshotLong(cargoId, "tarifa_disciplina_id")).isEqualTo(finalMayor.tarifaId());
        assertThat(snapshotText(cargoId, "observaciones"))
                .contains("inscripciónGanadora=" + inscripcionFinalMayor)
                .doesNotContain("inscripciónGanadora=" + inscripcionBaseMayor + ";");
    }

    @Test
    void empateSeResuelvePorMenorIdDeInscripcion() {
        Base base = base("empate");
        Disciplina primera = disciplina(base, "Primera", "100.00", "80.00");
        Disciplina segunda = disciplina(base, "Segunda", "100.00", "80.00");
        Long inscripcionPrimera = inscripcion(base.alumnoId(), primera.id());
        Long inscripcionSegunda = inscripcion(base.alumnoId(), segunda.id());
        assertThat(inscripcionPrimera).isLessThan(inscripcionSegunda);

        var matricula = matriculas.obtenerOMarcarPendienteMatricula(base.alumnoId(), 2026);
        Long cargoId = cargoId(matricula.id());

        assertThat(snapshotLong(cargoId, "tarifa_disciplina_id")).isEqualTo(primera.tarifaId());
        assertThat(snapshotText(cargoId, "observaciones"))
                .contains("DESEMPATE_MENOR_ID_INSCRIPCION")
                .contains("inscripciónGanadora=" + inscripcionPrimera);
    }

    @Test
    void unaDisciplinaActivaSinTarifaAbortaTodaLaMatricula() {
        Base base = base("tarifa-faltante");
        Disciplina conTarifa = disciplina(base, "Con tarifa", "100.00", "80.00");
        Long sinTarifa = disciplinaSinTarifa(base, "Sin tarifa");
        inscripcion(base.alumnoId(), conTarifa.id());
        inscripcion(base.alumnoId(), sinTarifa);

        assertThatThrownBy(() -> matriculas.obtenerOMarcarPendienteMatricula(base.alumnoId(), 2026))
                .isInstanceOf(TarifaDisciplinaServicio.TarifaHistoricaNoDefinidaException.class);

        assertThat(count("SELECT count(*) FROM matriculas WHERE alumno_id = ?", base.alumnoId())).isZero();
        assertThat(count("SELECT count(*) FROM cargos WHERE alumno_id = ?", base.alumnoId())).isZero();
    }

    private Base base(String prefix) {
        String suffix = prefix + "-" + UUID.randomUUID();
        Long role = jdbc.queryForObject("SELECT id FROM roles WHERE codigo = 'SUPERADMIN'", Long.class);
        Long user = id("""
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo)
                VALUES (?, 'test-only', ?, true) RETURNING id
                """, "matricula-" + suffix, role);
        jdbc.update("INSERT INTO usuario_roles(usuario_id, rol_id) VALUES (?, ?) ON CONFLICT DO NOTHING",
                user, role);
        Long profesor = id("""
                INSERT INTO profesores(nombre, apellido, activo)
                VALUES (?, 'Matrícula', true) RETURNING id
                """, "Profesor " + suffix);
        Long alumno = id("""
                INSERT INTO alumnos(nombre, apellido, fecha_incorporacion, activo)
                VALUES ('Alumno', ?, DATE '2025-01-01', true) RETURNING id
                """, suffix);
        return new Base(user, profesor, alumno, suffix);
    }

    private Disciplina disciplina(Base base, String nombre, String cuota, String matricula) {
        Long disciplina = disciplinaSinTarifa(base, nombre);
        Long tarifa = id("""
                INSERT INTO disciplina_tarifas(
                    disciplina_id, vigente_desde, valor_cuota, matricula,
                    clase_suelta, clase_prueba, motivo, creada_por_usuario_id)
                VALUES (?, DATE '2025-01-01', ?, ?, 0, 0, 'Fixture matrícula', ?) RETURNING id
                """, disciplina, new BigDecimal(cuota), new BigDecimal(matricula), base.usuarioId());
        return new Disciplina(disciplina, tarifa);
    }

    private Long disciplinaSinTarifa(Base base, String nombre) {
        return id("""
                INSERT INTO disciplinas(nombre, profesor_id, valor_cuota, matricula,
                                        clase_suelta, clase_prueba, activo)
                VALUES (?, ?, 999.00, 999.00, 0, 0, true) RETURNING id
                """, nombre + " " + base.suffix(), base.profesorId());
    }

    private Long inscripcion(Long alumno, Long disciplina) {
        return id("""
                INSERT INTO inscripciones(alumno_id, disciplina_id, fecha_inscripcion, estado)
                VALUES (?, ?, DATE '2025-01-01', 'ACTIVA') RETURNING id
                """, alumno, disciplina);
    }

    private void condicion(Base base, Long inscripcion, LocalDate desde, String costo,
                           String porcentaje, String fijo) {
        jdbc.update("""
                INSERT INTO inscripcion_condiciones_economicas(
                    inscripcion_id, vigente_desde, costo_particular,
                    bonificacion_descripcion_snapshot, bonificacion_porcentaje_snapshot,
                    bonificacion_valor_fijo_snapshot, motivo, creada_por_usuario_id)
                VALUES (?, ?, ?, 'Fixture matrícula', ?, ?, 'Fixture matrícula', ?)
                """, inscripcion, desde, costo == null ? null : new BigDecimal(costo),
                new BigDecimal(porcentaje), new BigDecimal(fijo), base.usuarioId());
    }

    private Long cargoId(Long matriculaId) {
        return jdbc.queryForObject("SELECT id FROM cargos WHERE matricula_id = ?", Long.class, matriculaId);
    }

    private BigDecimal cargoImporte(Long cargoId) {
        return jdbc.queryForObject("SELECT importe_original FROM cargos WHERE id = ?", BigDecimal.class, cargoId);
    }

    private Long snapshotLong(Long cargoId, String columna) {
        return jdbc.queryForObject("SELECT " + columna + " FROM cargo_liquidaciones WHERE cargo_id = ?",
                Long.class, cargoId);
    }

    private String snapshotText(Long cargoId, String columna) {
        return jdbc.queryForObject("SELECT " + columna + " FROM cargo_liquidaciones WHERE cargo_id = ?",
                String.class, cargoId);
    }

    private LocalDate snapshotDate(Long cargoId) {
        return jdbc.queryForObject("SELECT periodo_desde FROM cargo_liquidaciones WHERE cargo_id = ?",
                LocalDate.class, cargoId);
    }

    private int count(String sql, Object... args) {
        Integer value = jdbc.queryForObject(sql, Integer.class, args);
        return value == null ? 0 : value;
    }

    private Long id(String sql, Object... args) {
        Long value = jdbc.queryForObject(sql, Long.class, args);
        if (value == null) throw new IllegalStateException("La inserción no devolvió id");
        return value;
    }

    private record Base(Long usuarioId, Long profesorId, Long alumnoId, String suffix) {
    }

    private record Disciplina(Long id, Long tarifaId) {
    }
}
