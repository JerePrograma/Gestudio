package gestudio.servicios.cargo;

import jakarta.persistence.EntityManagerFactory;
import gestudio.dto.credito.request.CreditoAjusteRequest;
import gestudio.dto.credito.request.CreditoConsumoRequest;
import gestudio.dto.credito.request.CreditoReversionRequest;
import gestudio.dto.mensualidad.request.MensualidadRegistroRequest;
import gestudio.dto.pago.request.AplicacionPagoRequest;
import gestudio.dto.pago.request.PagoAnulacionRequest;
import gestudio.dto.pago.request.PagoRegistroRequest;
import gestudio.entidades.EstadoCargo;
import gestudio.entidades.Usuario;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.infra.persistencia.PostgreSqlIntegrationTest;
import gestudio.repositorios.CargoRepositorio;
import gestudio.repositorios.UsuarioRepositorio;
import gestudio.servicios.credito.CreditoServicio;
import gestudio.servicios.matricula.MatriculaServicio;
import gestudio.servicios.mensualidad.MensualidadServicio;
import gestudio.servicios.pago.PagoServicio;
import gestudio.servicios.reporte.ReporteServicio;
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
    @Autowired private CargoRepositorio cargoRepositorio;
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
        assertSnapshot(mensualidad.cargoId(), "100.00", "2026-03-01");
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
        assertSnapshot(cargoId, "40.00", "2026-01-01");
    }

    @Test
    void periodoPasadoUsaTarifaHistoricaYNoPrecioMutableActual() {
        Fixture fixture = fixture("100.00", "40.00");
        jdbc.update("UPDATE disciplinas SET valor_cuota = 150.00 WHERE id = ?", fixture.disciplina());

        var mensualidad = mensualidades.crearMensualidad(
                new MensualidadRegistroRequest(fixture.inscripcion(), 2025, 8, null, null));

        assertThat(cargos.obtener(mensualidad.cargoId()).importeOriginal()).isEqualTo("100.00");
        assertSnapshot(mensualidad.cargoId(), "100.00", "2025-08-01");
    }

    @Test
    void pagoYCreditoCompartenFormulaYLasReversionesRestauranElSaldo() {
        Fixture fixture = fixture("100.00", "40.00");
        var mensualidad = mensualidades.crearMensualidad(
                new MensualidadRegistroRequest(fixture.inscripcion(), 2026, 5, null, null));

        var pago = pagos.registrarPago(new PagoRegistroRequest(
                fixture.alumno(), fixture.metodo(), "30.00", key("pago"), null,
                List.of(new AplicacionPagoRequest(mensualidad.cargoId(), "30.00")), false
        ), fixture.usuario());

        creditos.ajustar(new CreditoAjusteRequest(
                fixture.alumno(), "20.00", "CREDITO", "caracterización", key("ajuste")
        ), fixture.usuario());
        var consumo = creditos.consumir(new CreditoConsumoRequest(
                fixture.alumno(), mensualidad.cargoId(), "20.00", key("consumo")
        ), fixture.usuario());

        SaldoCargo combinado = saldos.calcular(mensualidad.cargoId());
        assertThat(combinado.importeOriginal()).isEqualByComparingTo("100.00");
        assertThat(combinado.aplicadoPagos()).isEqualByComparingTo("30.00");
        assertThat(combinado.aplicadoCredito()).isEqualByComparingTo("20.00");
        assertThat(combinado.aplicadoTotal()).isEqualByComparingTo("50.00");
        assertThat(combinado.saldo()).isEqualByComparingTo("50.00");
        assertThat(combinado.estadoEsperado()).isEqualTo(EstadoCargo.PARCIAL);

        pagos.anularPago(pago.id(),
                new PagoAnulacionRequest(key("reverso-pago"), "caracterización"), fixture.usuario());
        assertThat(saldos.calcular(mensualidad.cargoId()).saldo()).isEqualByComparingTo("80.00");

        creditos.revertirConsumo(consumo.id(),
                new CreditoReversionRequest(key("reverso-credito"), "caracterización"), fixture.usuario());
        SaldoCargo restaurado = saldos.calcular(mensualidad.cargoId());
        assertThat(restaurado.saldo()).isEqualByComparingTo("100.00");
        assertThat(restaurado.estadoEsperado()).isEqualTo(EstadoCargo.PENDIENTE);

        assertThat(jdbc.queryForObject("""
                SELECT string_agg(tipo || ':' || saldo_anterior || '>' || saldo_nuevo, ',' ORDER BY id)
                FROM cargo_eventos WHERE cargo_id = ?
                """, String.class, mensualidad.cargoId()))
                .isEqualTo("PAGO_APLICADO:100.00>70.00,CREDITO_APLICADO:70.00>50.00,"
                        + "PAGO_REVERTIDO:50.00>80.00,CREDITO_REVERTIDO:80.00>100.00");
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

    @Test
    void runtimeYVistaSqlCoincidenConPagosCreditoReversoYRecargo() {
        Fixture fixture = fixture("100.00", "40.00");
        var pendiente = mensualidades.crearMensualidad(
                new MensualidadRegistroRequest(fixture.inscripcion(), 2026, 8, null, null));
        var parcial = mensualidades.crearMensualidad(
                new MensualidadRegistroRequest(fixture.inscripcion(), 2026, 9, null, null));
        var pagada = mensualidades.crearMensualidad(
                new MensualidadRegistroRequest(fixture.inscripcion(), 2026, 10, null, null));

        pagos.registrarPago(new PagoRegistroRequest(
                fixture.alumno(), fixture.metodo(), "30.00", key("pago-parcial"), null,
                List.of(new AplicacionPagoRequest(parcial.cargoId(), "30.00")), false
        ), fixture.usuario());
        creditos.ajustar(new CreditoAjusteRequest(
                fixture.alumno(), "20.00", "CREDITO", "alineación vista", key("ajuste")
        ), fixture.usuario());
        var consumo = creditos.consumir(new CreditoConsumoRequest(
                fixture.alumno(), parcial.cargoId(), "20.00", key("consumo")
        ), fixture.usuario());

        VistaCuota conCredito = assertVistaCoincide(parcial.cargoId());
        assertThat(conCredito.aplicadoPagos()).isEqualByComparingTo("30.00");
        assertThat(conCredito.aplicadoCredito()).isEqualByComparingTo("20.00");
        assertThat(conCredito.estado()).isEqualTo("PARCIAL");

        creditos.revertirConsumo(consumo.id(),
                new CreditoReversionRequest(key("reverso-credito"), "alineación vista"), fixture.usuario());
        VistaCuota conCreditoRevertido = assertVistaCoincide(parcial.cargoId());
        assertThat(conCreditoRevertido.aplicadoCredito()).isEqualByComparingTo("0.00");
        assertThat(conCreditoRevertido.saldo()).isEqualByComparingTo("70.00");

        pagos.registrarPago(new PagoRegistroRequest(
                fixture.alumno(), fixture.metodo(), "100.00", key("pago-total"), null,
                List.of(new AplicacionPagoRequest(pagada.cargoId(), "100.00")), false
        ), fixture.usuario());

        var cargoPendiente = cargoRepositorio.findById(pendiente.cargoId()).orElseThrow();
        var recargo = cargos.crearRecargo(cargoPendiente, new BigDecimal("15.00"),
                "Recargo de alineación", key("recargo"));

        VistaCuota vistaPendiente = assertVistaCoincide(pendiente.cargoId());
        assertThat(vistaPendiente.estado()).isEqualTo("PENDIENTE");
        assertThat(vistaPendiente.recargos()).isEqualByComparingTo("15.00");
        assertThat(vistaPendiente.saldoTotal()).isEqualByComparingTo(
                saldos.calcular(pendiente.cargoId()).saldo().add(saldos.calcular(recargo).saldo()));
        assertThat(assertVistaCoincide(pagada.cargoId()).estado()).isEqualTo("PAGADO");
    }

    private VistaCuota assertVistaCoincide(Long cargoId) {
        SaldoCargo runtime = saldos.calcular(cargoId);
        VistaCuota vista = jdbc.queryForObject("""
                SELECT aplicado_pagos, aplicado_credito, saldo_cuota,
                       recargos_vinculados, saldo_total_periodo, estado_esperado
                FROM v_cuotas_seguimiento WHERE cargo_id = ?
                """, (rs, row) -> new VistaCuota(
                rs.getBigDecimal("aplicado_pagos"),
                rs.getBigDecimal("aplicado_credito"),
                rs.getBigDecimal("saldo_cuota"),
                rs.getBigDecimal("recargos_vinculados"),
                rs.getBigDecimal("saldo_total_periodo"),
                rs.getString("estado_esperado")
        ), cargoId);

        assertThat(vista).isNotNull();
        assertThat(vista.aplicadoPagos()).isEqualByComparingTo(runtime.aplicadoPagos());
        assertThat(vista.aplicadoCredito()).isEqualByComparingTo(runtime.aplicadoCredito());
        assertThat(vista.saldo()).isEqualByComparingTo(runtime.saldo());
        assertThat(vista.estado()).isEqualTo(runtime.estadoEsperado().name());
        return vista;
    }

    private void assertSnapshot(Long cargoId, String importe, String periodo) {
        MapSnapshot snapshot = jdbc.queryForObject("""
                SELECT periodo_desde, origen_precio, importe_base, descuento_importe,
                       importe_final, formula_version, recargo_porcentaje, recargo_importe
                FROM cargo_liquidaciones WHERE cargo_id = ?
                """, (rs, row) -> new MapSnapshot(
                rs.getObject("periodo_desde", LocalDate.class),
                rs.getString("origen_precio"),
                rs.getBigDecimal("importe_base"),
                rs.getBigDecimal("descuento_importe"),
                rs.getBigDecimal("importe_final"),
                rs.getInt("formula_version"),
                rs.getBigDecimal("recargo_porcentaje"),
                rs.getBigDecimal("recargo_importe")
        ), cargoId);

        assertThat(snapshot).isNotNull();
        assertThat(snapshot.periodoDesde()).isEqualTo(LocalDate.parse(periodo));
        assertThat(snapshot.origen()).isEqualTo("TARIFA_HISTORICA");
        assertThat(snapshot.base()).isEqualByComparingTo(importe);
        assertThat(snapshot.descuento()).isEqualByComparingTo("0.00");
        assertThat(snapshot.finalImporte()).isEqualByComparingTo(importe);
        assertThat(snapshot.formula()).isEqualTo(1);
        assertThat(snapshot.recargoPorcentaje()).isEqualByComparingTo("0.0000");
        assertThat(snapshot.recargoImporte()).isEqualByComparingTo("0.00");
    }

    private void aplicarCredito(Fixture fixture, Long cargoId, String importe) {
        creditos.ajustar(new CreditoAjusteRequest(
                fixture.alumno(), importe, "CREDITO", "caracterización", key("ajuste")
        ), fixture.usuario());
        creditos.consumir(new CreditoConsumoRequest(
                fixture.alumno(), cargoId, importe, key("consumo")
        ), fixture.usuario());
    }

    private Fixture fixture(String cuota, String matricula) {
        String suffix = UUID.randomUUID().toString();
        Long role = jdbc.queryForObject(
                "SELECT id FROM roles WHERE descripcion = 'ADMINISTRADOR'", Long.class);
        Long user = id("""
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo)
                VALUES (?, 'test-only', ?, true) RETURNING id
                """, "saldo-" + suffix, role);

        otorgarPermisos(user, role,
                "PERM_PAGOS_REGISTRAR", "PERM_PAGOS_ANULAR",
                "PERM_CREDITOS_ADMIN", "PERM_CREDITOS_CONSUMIR");

        Long profesor = id("""
                INSERT INTO profesores(nombre, apellido, activo)
                VALUES (?, 'Saldo', true) RETURNING id
                """, "Profesor " + suffix);
        Long disciplina = id("""
                INSERT INTO disciplinas(nombre, profesor_id, valor_cuota, matricula, clase_suelta, clase_prueba, activo)
                VALUES (?, ?, 999.00, 888.00, 0, 0, true) RETURNING id
                """, "Disciplina " + suffix, profesor);
        jdbc.update("""
                INSERT INTO disciplina_tarifas(
                    disciplina_id, vigente_desde, valor_cuota, matricula,
                    clase_suelta, clase_prueba, motivo, creada_por_usuario_id)
                VALUES (?, DATE '2025-01-01', ?::numeric, ?::numeric, 0, 0,
                        'Fixture de saldo por vigencia', ?)
                """, disciplina, cuota, matricula, user);

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
                usuarios.findByIdConRolesYPermisos(user).orElseThrow());
    }

    private void otorgarPermisos(Long usuarioId, Long rolId, String... permisos) {
        jdbc.update("""
                INSERT INTO usuario_roles(usuario_id, rol_id)
                VALUES (?, ?) ON CONFLICT DO NOTHING
                """, usuarioId, rolId);
        for (String permiso : permisos) {
            jdbc.update("""
                    INSERT INTO permisos(codigo, descripcion, modulo, activo, sistema)
                    VALUES (?, ?, ?, true, true)
                    ON CONFLICT (codigo) DO UPDATE
                    SET descripcion = EXCLUDED.descripcion,
                        modulo = EXCLUDED.modulo,
                        activo = true,
                        sistema = true
                    """, permiso, permiso, moduloDe(permiso));
            jdbc.update("""
                    INSERT INTO rol_permisos(rol_id, permiso_id)
                    SELECT ?, p.id FROM permisos p WHERE p.codigo = ?
                    ON CONFLICT DO NOTHING
                    """, rolId, permiso);
        }
    }

    private static String moduloDe(String permiso) {
        String normalizado = permiso == null ? "" : permiso.trim().toUpperCase();
        if (!normalizado.startsWith("PERM_")) return "GENERAL";
        String sinPrefijo = normalizado.substring("PERM_".length());
        int separador = sinPrefijo.indexOf('_');
        String modulo = separador <= 0 ? sinPrefijo : sinPrefijo.substring(0, separador);
        return modulo.length() < 2 ? "GENERAL" : modulo;
    }

    private Long id(String sql, Object... args) {
        Long value = jdbc.queryForObject(sql, Long.class, args);
        if (value == null) throw new IllegalStateException("La inserción no devolvió id");
        return value;
    }

    private static String key(String prefix) {
        return prefix + "-" + UUID.randomUUID();
    }

    private record Fixture(Long alumno, Long profesor, Long disciplina,
                           Long inscripcion, Long metodo, Usuario usuario) {
    }

    private record VistaCuota(BigDecimal aplicadoPagos, BigDecimal aplicadoCredito,
                              BigDecimal saldo, BigDecimal recargos,
                              BigDecimal saldoTotal, String estado) {
    }

    private record MapSnapshot(LocalDate periodoDesde, String origen, BigDecimal base,
                               BigDecimal descuento, BigDecimal finalImporte, int formula,
                               BigDecimal recargoPorcentaje, BigDecimal recargoImporte) {
    }
}
