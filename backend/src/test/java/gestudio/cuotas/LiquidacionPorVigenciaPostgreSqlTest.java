package gestudio.cuotas;

import gestudio.cuotas.application.LiquidacionPorVigenciaServicio;
import gestudio.cuotas.application.OrigenPrecioLiquidacion;
import gestudio.cuotas.application.ResultadoLiquidacion;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.infra.persistencia.PostgreSqlIntegrationTest;
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
class LiquidacionPorVigenciaPostgreSqlTest extends PostgreSqlIntegrationTest {

    @Autowired private LiquidacionPorVigenciaServicio liquidaciones;
    @Autowired private JdbcTemplate jdbc;

    @Test
    void seleccionaTarifaAnteriorOExactaEIgnoraUnaFutura() {
        Fixture fixture = fixture("tarifas", null, null);
        Long enero = tarifa(fixture, LocalDate.of(2026, 1, 1), "100.00", "40.00");
        Long marzo = tarifa(fixture, LocalDate.of(2026, 3, 1), "130.00", "60.00");
        tarifa(fixture, LocalDate.of(2026, 8, 1), "180.00", "90.00");

        ResultadoLiquidacion febrero = mensualidad(fixture, LocalDate.of(2026, 2, 1));
        ResultadoLiquidacion exacta = mensualidad(fixture, LocalDate.of(2026, 3, 1));
        ResultadoLiquidacion julio = mensualidad(fixture, LocalDate.of(2026, 7, 1));

        assertThat(febrero.tarifa().getId()).isEqualTo(enero);
        assertThat(febrero.importeBase()).isEqualByComparingTo("100.00");
        assertThat(exacta.tarifa().getId()).isEqualTo(marzo);
        assertThat(exacta.importeBase()).isEqualByComparingTo("130.00");
        assertThat(julio.tarifa().getId()).isEqualTo(marzo);
        assertThat(julio.fechaEfectiva()).isEqualTo(LocalDate.of(2026, 7, 1));
    }

    @Test
    void condicionEsOpcionalYSeleccionaAnteriorOExactaSinTomarUnaFutura() {
        Fixture fixture = fixture("condiciones", null, null);
        tarifa(fixture, LocalDate.of(2025, 1, 1), "100.00", "50.00");

        ResultadoLiquidacion sinCondicion = mensualidad(fixture, LocalDate.of(2025, 12, 1));
        assertThat(sinCondicion.condicion()).isEmpty();
        assertThat(sinCondicion.origen()).isEqualTo(OrigenPrecioLiquidacion.TARIFA_HISTORICA);

        Long enero = condicion(fixture, LocalDate.of(2026, 1, 1), null, "10.0000", "5.00");
        Long marzo = condicion(fixture, LocalDate.of(2026, 3, 1), "200.00", "20.0000", "0.00");
        condicion(fixture, LocalDate.of(2026, 8, 1), "900.00", "0.0000", "0.00");

        ResultadoLiquidacion febrero = mensualidad(fixture, LocalDate.of(2026, 2, 1));
        ResultadoLiquidacion exacta = mensualidad(fixture, LocalDate.of(2026, 3, 1));
        ResultadoLiquidacion julio = mensualidad(fixture, LocalDate.of(2026, 7, 1));

        assertThat(febrero.condicion()).hasValueSatisfying(value ->
                assertThat(value.getId()).isEqualTo(enero));
        assertThat(febrero.importeBase()).isEqualByComparingTo("100.00");
        assertThat(febrero.descuentoPorcentaje()).isEqualByComparingTo("10.0000");
        assertThat(febrero.descuentoImporte()).isEqualByComparingTo("15.00");
        assertThat(febrero.importeFinal()).isEqualByComparingTo("85.00");

        assertThat(exacta.condicion()).hasValueSatisfying(value ->
                assertThat(value.getId()).isEqualTo(marzo));
        assertThat(exacta.origen()).isEqualTo(OrigenPrecioLiquidacion.COSTO_PARTICULAR);
        assertThat(exacta.importeBase()).isEqualByComparingTo("200.00");
        assertThat(exacta.descuentoImporte()).isEqualByComparingTo("40.00");
        assertThat(exacta.importeFinal()).isEqualByComparingTo("160.00");
        assertThat(julio.condicion()).hasValueSatisfying(value ->
                assertThat(value.getId()).isEqualTo(marzo));
    }

    @Test
    void aplicaPorcentajeFijoYCombinacionConRedondeoHalfUp() {
        Fixture fixture = fixture("descuentos", null, null);
        tarifa(fixture, LocalDate.of(2026, 1, 1), "100.00", "50.00");
        condicion(fixture, LocalDate.of(2026, 1, 1), null, "12.3456", "0.00");
        condicion(fixture, LocalDate.of(2026, 2, 1), null, "0.0000", "5.00");
        condicion(fixture, LocalDate.of(2026, 3, 1), null, "10.0000", "5.00");

        ResultadoLiquidacion porcentaje = mensualidad(fixture, LocalDate.of(2026, 1, 1));
        ResultadoLiquidacion fijo = mensualidad(fixture, LocalDate.of(2026, 2, 1));
        ResultadoLiquidacion combinado = mensualidad(fixture, LocalDate.of(2026, 3, 1));

        assertThat(porcentaje.descuentoImporte()).isEqualByComparingTo("12.35");
        assertThat(porcentaje.importeFinal()).isEqualByComparingTo("87.65");
        assertThat(fijo.descuentoImporte()).isEqualByComparingTo("5.00");
        assertThat(fijo.importeFinal()).isEqualByComparingTo("95.00");
        assertThat(combinado.descuentoImporte()).isEqualByComparingTo("15.00");
        assertThat(combinado.importeFinal()).isEqualByComparingTo("85.00");
        assertThat(combinado.formulaVersion()).isEqualTo(1);
    }

    @Test
    void rechazaDescuentoSuperiorALaBase() {
        Fixture fixture = fixture("negativo", null, null);
        tarifa(fixture, LocalDate.of(2026, 1, 1), "100.00", "50.00");
        condicion(fixture, LocalDate.of(2026, 1, 1), null, "50.0000", "60.00");

        assertThatThrownBy(() -> mensualidad(fixture, LocalDate.of(2026, 1, 1)))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("supera");
    }

    @Test
    void matriculaUsaImporteDeMatriculaYLaMismaCondicionEfectiva() {
        Fixture fixture = fixture("matricula", null, null);
        Long tarifaId = tarifa(fixture, LocalDate.of(2026, 1, 1), "100.00", "70.00");
        Long condicionId = condicion(fixture, LocalDate.of(2026, 1, 1), null, "10.0000", "5.00");

        ResultadoLiquidacion resultado = liquidaciones.liquidarMatricula(
                fixture.inscripcionId(), LocalDate.of(2026, 1, 1));

        assertThat(resultado.tarifa().getId()).isEqualTo(tarifaId);
        assertThat(resultado.condicion()).hasValueSatisfying(value ->
                assertThat(value.getId()).isEqualTo(condicionId));
        assertThat(resultado.importeBase()).isEqualByComparingTo("70.00");
        assertThat(resultado.descuentoImporte()).isEqualByComparingTo("12.00");
        assertThat(resultado.importeFinal()).isEqualByComparingTo("58.00");
    }

    @Test
    void costoParticularDeCondicionTienePrioridadEnMensualidadYMatricula() {
        Fixture fixture = fixture("particular", null, null);
        tarifa(fixture, LocalDate.of(2026, 1, 1), "100.00", "50.00");
        condicion(fixture, LocalDate.of(2026, 1, 1), "80.00", "25.0000", "0.00");

        ResultadoLiquidacion mensualidad = mensualidad(fixture, LocalDate.of(2026, 1, 1));
        ResultadoLiquidacion matricula = liquidaciones.liquidarMatricula(
                fixture.inscripcionId(), LocalDate.of(2026, 1, 1));

        assertThat(mensualidad.origen()).isEqualTo(OrigenPrecioLiquidacion.COSTO_PARTICULAR);
        assertThat(mensualidad.importeBase()).isEqualByComparingTo("80.00");
        assertThat(mensualidad.importeFinal()).isEqualByComparingTo("60.00");
        assertThat(matricula.origen()).isEqualTo(OrigenPrecioLiquidacion.COSTO_PARTICULAR);
        assertThat(matricula.importeFinal()).isEqualByComparingTo("60.00");
    }

    @Test
    void ignoraCostoYBonificacionLegacyDeLaInscripcion() {
        Fixture fixture = fixture("legacy", "777.00", bonificacion("Legacy", "90.0000", "500.00"));
        tarifa(fixture, LocalDate.of(2026, 1, 1), "100.00", "50.00");

        ResultadoLiquidacion resultado = mensualidad(fixture, LocalDate.of(2026, 1, 1));

        assertThat(resultado.condicion()).isEmpty();
        assertThat(resultado.origen()).isEqualTo(OrigenPrecioLiquidacion.TARIFA_HISTORICA);
        assertThat(resultado.importeBase()).isEqualByComparingTo("100.00");
        assertThat(resultado.descuentoImporte()).isEqualByComparingTo("0.00");
        assertThat(resultado.importeFinal()).isEqualByComparingTo("100.00");
    }

    @Test
    void ausenciaDeTarifaAbortaAunqueExistanPreciosLegacy() {
        Fixture fixture = fixture("sin-tarifa", "10.00", null);

        assertThatThrownBy(() -> mensualidad(fixture, LocalDate.of(2026, 1, 1)))
                .isInstanceOf(TarifaDisciplinaServicio.TarifaHistoricaNoDefinidaException.class);
        assertThatThrownBy(() -> liquidaciones.liquidarMatricula(
                fixture.inscripcionId(), LocalDate.of(2026, 1, 1)))
                .isInstanceOf(TarifaDisciplinaServicio.TarifaHistoricaNoDefinidaException.class);
    }

    @Test
    void conservaFechasEfectivasDeMensualidadPasadaActualYFutura() {
        Fixture fixture = fixture("periodos", null, null);
        tarifa(fixture, LocalDate.of(2025, 1, 1), "80.00", "40.00");
        tarifa(fixture, LocalDate.of(2026, 1, 1), "100.00", "50.00");
        tarifa(fixture, LocalDate.of(2027, 1, 1), "120.00", "60.00");

        ResultadoLiquidacion pasada = mensualidad(fixture, LocalDate.of(2025, 6, 1));
        ResultadoLiquidacion actual = mensualidad(fixture, LocalDate.of(2026, 7, 1));
        ResultadoLiquidacion futura = mensualidad(fixture, LocalDate.of(2027, 3, 1));

        assertThat(pasada.fechaEfectiva()).isEqualTo(LocalDate.of(2025, 6, 1));
        assertThat(pasada.importeFinal()).isEqualByComparingTo("80.00");
        assertThat(actual.fechaEfectiva()).isEqualTo(LocalDate.of(2026, 7, 1));
        assertThat(actual.importeFinal()).isEqualByComparingTo("100.00");
        assertThat(futura.fechaEfectiva()).isEqualTo(LocalDate.of(2027, 3, 1));
        assertThat(futura.importeFinal()).isEqualByComparingTo("120.00");
    }

    private ResultadoLiquidacion mensualidad(Fixture fixture, LocalDate fecha) {
        return liquidaciones.liquidarMensualidad(fixture.inscripcionId(), fecha);
    }

    private Fixture fixture(String prefix, String costoLegacy, Long bonificacionLegacyId) {
        String suffix = prefix + "-" + UUID.randomUUID();
        Long roleId = jdbc.queryForObject("SELECT id FROM roles WHERE codigo = 'SUPERADMIN'", Long.class);
        Long usuarioId = id("""
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo)
                VALUES (?, 'test-only', ?, true) RETURNING id
                """, "liquidador-" + suffix, roleId);
        jdbc.update("INSERT INTO usuario_roles(usuario_id, rol_id) VALUES (?, ?) ON CONFLICT DO NOTHING",
                usuarioId, roleId);
        Long profesorId = id("""
                INSERT INTO profesores(nombre, apellido, activo)
                VALUES (?, 'Vigencia', true) RETURNING id
                """, "Profesor-" + suffix);
        Long disciplinaId = id("""
                INSERT INTO disciplinas(nombre, profesor_id, valor_cuota, matricula, clase_suelta, clase_prueba, activo)
                VALUES (?, ?, 999.00, 888.00, 0, 0, true) RETURNING id
                """, "Disciplina-" + suffix, profesorId);
        Long alumnoId = id("""
                INSERT INTO alumnos(nombre, apellido, fecha_incorporacion, activo)
                VALUES ('Alumno', ?, DATE '2025-01-01', true) RETURNING id
                """, suffix);
        Long inscripcionId = id("""
                INSERT INTO inscripciones(
                    alumno_id, disciplina_id, bonificacion_id, costo_particular, fecha_inscripcion, estado)
                VALUES (?, ?, ?, ?, DATE '2025-01-01', 'ACTIVA') RETURNING id
                """, alumnoId, disciplinaId, bonificacionLegacyId,
                costoLegacy == null ? null : new BigDecimal(costoLegacy));
        return new Fixture(usuarioId, disciplinaId, inscripcionId);
    }

    private Long tarifa(Fixture fixture, LocalDate desde, String cuota, String matricula) {
        return id("""
                INSERT INTO disciplina_tarifas(
                    disciplina_id, vigente_desde, valor_cuota, matricula,
                    clase_suelta, clase_prueba, motivo, creada_por_usuario_id)
                VALUES (?, ?, ?, ?, 0, 0, 'Caracterización GATE-1B', ?) RETURNING id
                """, fixture.disciplinaId(), desde, new BigDecimal(cuota),
                new BigDecimal(matricula), fixture.usuarioId());
    }

    private Long condicion(Fixture fixture, LocalDate desde, String costoParticular,
                           String porcentaje, String fijo) {
        return id("""
                INSERT INTO inscripcion_condiciones_economicas(
                    inscripcion_id, vigente_desde, costo_particular,
                    bonificacion_descripcion_snapshot, bonificacion_porcentaje_snapshot,
                    bonificacion_valor_fijo_snapshot, motivo, creada_por_usuario_id)
                VALUES (?, ?, ?, 'Snapshot test', ?, ?, 'Caracterización GATE-1B', ?) RETURNING id
                """, fixture.inscripcionId(), desde,
                costoParticular == null ? null : new BigDecimal(costoParticular),
                new BigDecimal(porcentaje), new BigDecimal(fijo), fixture.usuarioId());
    }

    private Long bonificacion(String descripcion, String porcentaje, String fijo) {
        return id("""
                INSERT INTO bonificaciones(descripcion, porcentaje_descuento, valor_fijo, activo)
                VALUES (?, ?, ?, true) RETURNING id
                """, descripcion, new BigDecimal(porcentaje), new BigDecimal(fijo));
    }

    private Long id(String sql, Object... args) {
        Long value = jdbc.queryForObject(sql, Long.class, args);
        if (value == null) throw new IllegalStateException("La inserción no devolvió id");
        return value;
    }

    private record Fixture(Long usuarioId, Long disciplinaId, Long inscripcionId) {
    }
}
