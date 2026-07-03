package ledance.servicios.cargo;

import jakarta.persistence.EntityManagerFactory;
import ledance.dto.credito.request.CreditoAjusteRequest;
import ledance.dto.credito.request.CreditoConsumoRequest;
import ledance.dto.credito.request.CreditoReversionRequest;
import ledance.dto.mensualidad.request.MensualidadRegistroRequest;
import ledance.dto.pago.request.AplicacionPagoRequest;
import ledance.dto.pago.request.PagoAnulacionRequest;
import ledance.dto.pago.request.PagoRegistroRequest;
import ledance.entidades.EstadoCargo;
import ledance.entidades.Usuario;
import ledance.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import ledance.infra.persistencia.PostgreSqlIntegrationTest;
import ledance.repositorios.UsuarioRepositorio;
import ledance.servicios.credito.CreditoServicio;
import ledance.servicios.matricula.MatriculaServicio;
import ledance.servicios.mensualidad.MensualidadServicio;
import ledance.servicios.pago.PagoServicio;
import ledance.servicios.reporte.ReporteServicio;
import org.hibernate.SessionFactory;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
class CargoSaldoPostgreSqlTest extends PostgreSqlIntegrationTest {

    @Autowired private CargoServicio cargos;
    @Autowired private CargoSaldoServicio saldos;
    @Autowired private CreditoServicio creditos;
    @Autowired private PagoServicio pagos;
    @Autowired private MensualidadServicio mensualidades;
    @Autowired private MatriculaServicio matriculas;
    @Autowired private ReporteServicio reportes;
    @Autowired private UsuarioRepositorio usuarios;
    @Autowired private JdbcTemplate jdbc;
    @Autowired private Clock clock;
    @Autowired private EntityManagerFactory entityManagerFactory;

    @Test
    void mensualidadReporteYCargoDebenCoincidirCuandoHayCreditoAplicado() {
        Fixture fixture = fixture("100.00", "40.00");
        var mensualidad = mensualidades.crearMensualidad(
                new MensualidadRegistroRequest(fixture.inscripcion(), 2026, 3, null, null));
        aplicarCredito(fixture, mensualidad.cargoId(), "30.00");

        var cargo = cargos.obtener(mensualidad.cargoId());
        var respuestaMensualidad = mensualidades.obtenerMensualidad(mensualidad.id());
        LocalDate hoy = LocalDate.now(clock);
        var reporte = reportes.buscar(hoy, hoy, fixture.disciplina(), fixture.profesor()).getFirst();

        assertThat(cargo.saldo()).isEqualTo("70.00");
        assertThat(respuestaMensualidad.saldo()).isEqualTo(cargo.saldo());
        assertThat(reporte.importeCobrado()).isEqualTo("30.00");
        assertThat(reporte.saldo()).isEqualTo(cargo.saldo());
    }

    @Test
    void mensualidadConCreditoAplicadoNoSePuedeAnular() {
        Fixture fixture = fixture("100.00", "40.00");
        var mensualidad = mensualidades.crearMensualidad(
                new MensualidadRegistroRequest(fixture.inscripcion(), 2026, 4, null, null));
        aplicarCredito(fixture, mensualidad.cargoId(), "10.00");

        assertThatThrownBy(() -> mensualidades.eliminarMensualidad(mensualidad.id()))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("crédito");
    }

    @Test
    void matriculaConCreditoAplicadoNoSePuedeAnular() {
        Fixture fixture = fixture("100.00", "40.00");
        var matricula = matriculas.obtenerOMarcarPendienteMatricula(fixture.alumno(), 2026);
        Long cargoId = jdbc.queryForObject(
                "SELECT id FROM cargos WHERE matricula_id = ?", Long.class, matricula.id());
        aplicarCredito(fixture, cargoId, "10.00");

        assertThatThrownBy(() -> matriculas.anular(matricula.id()))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("crédito");
    }

    @Test
    void periodoPasadoCaracterizaQueHoyUsaElPrecioMutableActual() {
        Fixture fixture = fixture("100.00", "40.00");
        jdbc.update("UPDATE disciplinas SET valor_cuota = 150.00 WHERE id = ?", fixture.disciplina());

        var mensualidad = mensualidades.crearMensualidad(
                new MensualidadRegistroRequest(fixture.inscripcion(), 2025, 8, null, null));

        assertThat(cargos.obtener(mensualidad.cargoId()).importeOriginal()).isEqualTo("150.00");
    }

    @Test
    void pagoYCreditoCompartenFormulaYLasReversionesRestauranElSaldo() {
        Fixture fixture = fixture("100.00", "40.00");
        var mensualidad = mensualidades.crearMensualidad(
                new MensualidadRegistroRequest(fixture.inscripcion(), 2026, 5, null, null));
        var pago = pagos.registrarPago(new PagoRegistroRequest(
                fixture.alumno(), fixture.metodo(), "30.00", key("pago"), null,
                List.of(new AplicacionPagoRequest(mensualidad.cargoId(), "30.00")), false), fixture.usuario());
        creditos.ajustar(new CreditoAjusteRequest(
                fixture.alumno(), "20.00", "CREDITO", "caracterización", key("ajuste")), fixture.usuario());
        var consumo = creditos.consumir(new CreditoConsumoRequest(
                fixture.alumno(), mensualidad.cargoId(), "20.00", key("consumo")), fixture.usuario());

        SaldoCargo combinado = saldos.calcular(mensualidad.cargoId());
        assertThat(combinado.importeOriginal()).isEqualByComparingTo("100.00");
        assertThat(combinado.aplicadoPagos()).isEqualByComparingTo("30.00");
        assertThat(combinado.aplicadoCredito()).isEqualByComparingTo("20.00");
        assertThat(combinado.aplicadoTotal()).isEqualByComparingTo("50.00");
        assertThat(combinado.saldo()).isEqualByComparingTo("50.00");
        assertThat(combinado.estadoEsperado()).isEqualTo(EstadoCargo.PARCIAL);

        pagos.anularPago(pago.id(), new PagoAnulacionRequest(key("reverso-pago"), "caracterización"),
                fixture.usuario());
        assertThat(saldos.calcular(mensualidad.cargoId()).saldo()).isEqualByComparingTo("80.00");

        creditos.revertirConsumo(consumo.id(),
                new CreditoReversionRequest(key("reverso-credito"), "caracterización"), fixture.usuario());
        SaldoCargo restaurado = saldos.calcular(mensualidad.cargoId());
        assertThat(restaurado.saldo()).isEqualByComparingTo("100.00");
        assertThat(restaurado.estadoEsperado()).isEqualTo(EstadoCargo.PENDIENTE);
        assertThat(jdbc.queryForObject("""
                SELECT string_agg(tipo || ':' || saldo_anterior || '>' || saldo_nuevo, ',' ORDER BY id)
                FROM cargo_eventos WHERE cargo_id = ?
                """, String.class, mensualidad.cargoId())).isEqualTo(
                "PAGO_APLICADO:100.00>70.00,CREDITO_APLICADO:70.00>50.00," +
                "PAGO_REVERTIDO:50.00>80.00,CREDITO_REVERTIDO:80.00>100.00");
    }

    @Test
    void creditoTotalYBatchSeCalculanEnTresConsultasSinNMasUno() {
        Fixture fixture = fixture("100.00", "40.00");
        var total = mensualidades.crearMensualidad(
                new MensualidadRegistroRequest(fixture.inscripcion(), 2026, 6, null, null));
        var pendiente = mensualidades.crearMensualidad(
                new MensualidadRegistroRequest(fixture.inscripcion(), 2026, 7, null, null));
        aplicarCredito(fixture, total.cargoId(), "100.00");

        SessionFactory sessionFactory = entityManagerFactory.unwrap(SessionFactory.class);
        var statistics = sessionFactory.getStatistics();
        statistics.setStatisticsEnabled(true);
        statistics.clear();

        var batch = saldos.calcularBatch(List.of(total.cargoId(), pendiente.cargoId()));

        assertThat(statistics.getQueryExecutionCount()).isEqualTo(3);
        assertThat(batch.get(total.cargoId()).saldo()).isEqualByComparingTo("0.00");
        assertThat(batch.get(total.cargoId()).estadoEsperado()).isEqualTo(EstadoCargo.PAGADO);
        assertThat(batch.get(pendiente.cargoId()).saldo()).isEqualByComparingTo("100.00");
        assertThat(batch.get(pendiente.cargoId()).estadoEsperado()).isEqualTo(EstadoCargo.PENDIENTE);
    }

    private void aplicarCredito(Fixture fixture, Long cargoId, String importe) {
        creditos.ajustar(new CreditoAjusteRequest(
                fixture.alumno(), importe, "CREDITO", "caracterización", key("ajuste")), fixture.usuario());
        creditos.consumir(new CreditoConsumoRequest(
                fixture.alumno(), cargoId, importe, key("consumo")), fixture.usuario());
    }

    private Fixture fixture(String cuota, String matricula) {
        String suffix = UUID.randomUUID().toString();
        Long role = jdbc.queryForObject(
                "SELECT id FROM roles WHERE descripcion = 'ADMINISTRADOR'", Long.class);
        Long user = id("""
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo)
                VALUES (?, 'test-only', ?, true) RETURNING id
                """, "saldo-" + suffix, role);
        Long profesor = id("""
                INSERT INTO profesores(nombre, apellido, activo)
                VALUES (?, 'Saldo', true) RETURNING id
                """, "Profesor " + suffix);
        Long disciplina = id("""
                INSERT INTO disciplinas(nombre, profesor_id, valor_cuota, matricula, clase_suelta, clase_prueba, activo)
                VALUES (?, ?, ?::numeric, ?::numeric, 0, 0, true) RETURNING id
                """, "Disciplina " + suffix, profesor, cuota, matricula);
        Long alumno = id("""
                INSERT INTO alumnos(nombre, fecha_incorporacion, activo)
                VALUES (?, DATE '2025-01-01', true) RETURNING id
                """, "Alumno " + suffix);
        Long inscripcion = id("""
                INSERT INTO inscripciones(alumno_id, disciplina_id, fecha_inscripcion, estado)
                VALUES (?, ?, DATE '2025-01-01', 'ACTIVA') RETURNING id
                """, alumno, disciplina);
        Long metodo = id("""
                INSERT INTO metodo_pagos(descripcion, activo, recargo)
                VALUES (?, true, 0) RETURNING id
                """, "Método " + suffix);
        return new Fixture(alumno, profesor, disciplina, inscripcion, metodo,
                usuarios.findById(user).orElseThrow());
    }

    private Long id(String sql, Object... args) {
        Long value = jdbc.queryForObject(sql, Long.class, args);
        if (value == null) throw new IllegalStateException("La inserción no devolvió id");
        return value;
    }

    private static String key(String prefix) {
        return prefix + "-" + UUID.randomUUID();
    }

    private record Fixture(Long alumno, Long profesor, Long disciplina, Long inscripcion,
                           Long metodo, Usuario usuario) {
    }
}
