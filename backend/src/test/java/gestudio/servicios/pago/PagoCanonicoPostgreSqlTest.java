package gestudio.servicios.pago;

import gestudio.dto.credito.request.CreditoConsumoRequest;
import gestudio.dto.credito.request.CreditoReversionRequest;
import gestudio.dto.pago.request.AplicacionPagoRequest;
import gestudio.dto.pago.request.PagoAnulacionRequest;
import gestudio.dto.pago.request.PagoRegistroRequest;
import gestudio.entidades.Usuario;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.infra.persistencia.PostgreSqlIntegrationTest;
import gestudio.repositorios.UsuarioRepositorio;
import gestudio.servicios.caja.CajaServicio;
import gestudio.servicios.credito.CreditoServicio;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.jdbc.core.JdbcTemplate;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
class PagoCanonicoPostgreSqlTest extends PostgreSqlIntegrationTest {

    @Autowired
    private PagoServicio pagos;

    @Autowired
    private CreditoServicio creditos;

    @Autowired
    private CajaServicio caja;

    @Autowired
    private UsuarioRepositorio usuarios;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private Clock clock;

    @Test
    void pagoParcialYTotalDistribuidoMantienenUnaSolaDeudaOriginal() {
        Escenario escenario = escenario(new BigDecimal("100.00"), new BigDecimal("50.00"));

        var parcial = pagos.registrarPago(pago(escenario, "80.00", false,
                new AplicacionPagoRequest(escenario.cargo1(), "40.00"),
                new AplicacionPagoRequest(escenario.cargo2(), "40.00")), escenario.usuario());

        assertThat(parcial.montoRecibido()).isEqualTo("80.00");
        assertThat(parcial.aplicaciones()).extracting("saldoCargo").containsExactly("60.00", "10.00");
        assertThat(estadoCargo(escenario.cargo1())).isEqualTo("PARCIAL");
        assertThat(estadoCargo(escenario.cargo2())).isEqualTo("PARCIAL");
        assertThat(contar("aplicaciones_pago", "pago_id", parcial.id())).isEqualTo(2);

        assertThat(jdbc.queryForObject(
                "SELECT importe_original FROM cargos WHERE id = ?",
                BigDecimal.class,
                escenario.cargo1()
        )).isEqualByComparingTo("100.00");

        assertThat(jdbc.queryForObject(
                "SELECT importe FROM movimientos_caja WHERE pago_id = ?",
                BigDecimal.class,
                parcial.id()
        )).isEqualByComparingTo("80.00");

        pagos.registrarPago(pago(escenario, "70.00", false,
                new AplicacionPagoRequest(escenario.cargo1(), "60.00"),
                new AplicacionPagoRequest(escenario.cargo2(), "10.00")), escenario.usuario());

        assertThat(estadoCargo(escenario.cargo1())).isEqualTo("PAGADO");
        assertThat(estadoCargo(escenario.cargo2())).isEqualTo("PAGADO");
    }

    @Test
    void sobreaplicacionYSobrepagoImplicitoSeRechazanSinPersistenciaParcial() {
        Escenario escenario = escenario(new BigDecimal("100.00"), new BigDecimal("50.00"));

        int pagosAntes = total("pagos");
        int recibosAntes = total("recibos");
        int efectosAntes = total("recibos_pendientes");

        assertThatThrownBy(() -> pagos.registrarPago(pago(escenario, "120.00", false,
                new AplicacionPagoRequest(escenario.cargo1(), "120.00")), escenario.usuario()))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("supera el saldo");

        assertThatThrownBy(() -> pagos.registrarPago(pago(escenario, "120.00", false,
                new AplicacionPagoRequest(escenario.cargo1(), "100.00")), escenario.usuario()))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("generación explícita");

        assertThat(total("pagos")).isEqualTo(pagosAntes);
        assertThat(total("recibos")).isEqualTo(recibosAntes);
        assertThat(total("recibos_pendientes")).isEqualTo(efectosAntes);
        assertThat(estadoCargo(escenario.cargo1())).isEqualTo("PENDIENTE");
    }

    @Test
    void idempotenciaReversionYCajaSonCompensatorias() {
        Escenario escenario = escenario(new BigDecimal("100.00"), new BigDecimal("50.00"));

        String key = key("pago");
        PagoRegistroRequest request = new PagoRegistroRequest(
                escenario.alumno(),
                escenario.metodo(),
                "40.00",
                key,
                null,
                List.of(new AplicacionPagoRequest(escenario.cargo1(), "40.00")),
                false
        );

        var creado = pagos.registrarPago(request, escenario.usuario());
        var repetido = pagos.registrarPago(request, escenario.usuario());

        assertThat(repetido.id()).isEqualTo(creado.id());
        assertThat(contar("pagos", "idempotency_key", key)).isOne();
        assertThat(contar("recibos", "pago_id", creado.id())).isOne();
        assertThat(contar("recibos_pendientes", "pago_id", creado.id())).isOne();

        assertThatThrownBy(() -> pagos.registrarPago(new PagoRegistroRequest(
                escenario.alumno(),
                escenario.metodo(),
                "41.00",
                key,
                null,
                List.of(new AplicacionPagoRequest(escenario.cargo1(), "41.00")),
                false
        ), escenario.usuario()))
                .isInstanceOf(OperacionNoPermitidaException.class);

        String reverseKey = key("reverse");

        var anulada = pagos.anularPago(
                creado.id(),
                new PagoAnulacionRequest(reverseKey, "error de carga"),
                escenario.usuario()
        );

        assertThat(anulada.estado()).isEqualTo("ANULADO");
        assertThat(estadoCargo(escenario.cargo1())).isEqualTo("PENDIENTE");

        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM movimientos_caja WHERE pago_id = ?",
                Integer.class,
                creado.id()
        )).isEqualTo(2);

        assertThat(jdbc.queryForObject("""
                SELECT sum(CASE WHEN tipo = 'REVERSO' THEN -importe ELSE importe END)
                FROM movimientos_caja
                WHERE pago_id = ?
                """, BigDecimal.class, creado.id()))
                .isEqualByComparingTo("0.00");

        var resumen = caja.obtenerResumen(
                LocalDate.now(clock),
                LocalDate.now(clock),
                PageRequest.of(0, 10, Sort.by("fecha", "id"))
        );

        assertThat(resumen.movimientos().totalElements()).isGreaterThanOrEqualTo(2);
        assertThat(new BigDecimal(resumen.totalIngresos())).isNotNegative();
        assertThat(new BigDecimal(resumen.totalEgresos())).isNotNegative();

        assertThat(pagos.anularPago(
                creado.id(),
                new PagoAnulacionRequest(reverseKey, "error de carga"),
                escenario.usuario()
        ).id()).isEqualTo(creado.id());

        assertThatThrownBy(() -> pagos.anularPago(
                creado.id(),
                new PagoAnulacionRequest(reverseKey, "payload distinto"),
                escenario.usuario()
        ))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("otro contenido");

        assertThatThrownBy(() -> pagos.anularPago(
                creado.id(),
                new PagoAnulacionRequest(key("other"), "segunda reversión"),
                escenario.usuario()
        ))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("ya fue anulado");
    }

    @Test
    void sobrepagoExplicitoGeneraCreditoConsumibleYReversible() {
        Escenario escenario = escenario(new BigDecimal("100.00"), new BigDecimal("50.00"));

        var pago = pagos.registrarPago(pago(escenario, "130.00", true,
                new AplicacionPagoRequest(escenario.cargo1(), "100.00")), escenario.usuario());

        assertThat(pago.creditoGenerado()).isEqualTo("30.00");
        assertThat(creditos.saldo(escenario.alumno())).isEqualTo("30.00");

        String consumoKey = key("consume");
        var consumoRequest = new CreditoConsumoRequest(
                escenario.alumno(),
                escenario.cargo2(),
                "20.00",
                consumoKey
        );

        var consumo = creditos.consumir(consumoRequest, escenario.usuario());

        assertThat(consumo.saldoCredito()).isEqualTo("10.00");
        assertThat(consumo.saldoCargo()).isEqualTo("30.00");
        assertThat(creditos.consumir(consumoRequest, escenario.usuario()).id()).isEqualTo(consumo.id());

        assertThatThrownBy(() -> creditos.consumir(new CreditoConsumoRequest(
                escenario.alumno(),
                escenario.cargo2(),
                "19.00",
                consumoKey
        ), escenario.usuario()))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("otro contenido");

        var reverso = creditos.revertirConsumo(
                consumo.id(),
                new CreditoReversionRequest(key("credit-reverse"), "aplicación equivocada"),
                escenario.usuario()
        );

        assertThat(reverso.saldoCredito()).isEqualTo("30.00");
        assertThat(reverso.saldoCargo()).isEqualTo("50.00");
    }

    @Test
    @Timeout(30)
    void dosPagosConcurrentesNoPuedenSobreaplicarElMismoCargo() throws Exception {
        Escenario escenario = escenario(new BigDecimal("100.00"), new BigDecimal("50.00"));

        CountDownLatch start = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);

        Future<Object> first = executor.submit(() -> registrarAlLiberar(start, escenario, key("concurrent-a")));
        Future<Object> second = executor.submit(() -> registrarAlLiberar(start, escenario, key("concurrent-b")));

        boolean completed = false;

        try {
            start.countDown();

            List<Object> results = List.of(
                    first.get(10, TimeUnit.SECONDS),
                    second.get(10, TimeUnit.SECONDS)
            );

            assertThat(results.stream().filter(r -> r instanceof Long).toList()).hasSize(1);
            assertThat(results.stream().filter(r -> r instanceof OperacionNoPermitidaException).toList()).hasSize(1);

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

        assertThat(jdbc.queryForObject("""
                SELECT coalesce(sum(importe_aplicado), 0)
                FROM aplicaciones_pago
                WHERE cargo_id = ?
                  AND estado = 'APLICADA'
                """, BigDecimal.class, escenario.cargo1()))
                .isEqualByComparingTo("80.00");

        assertThat(estadoCargo(escenario.cargo1())).isEqualTo("PARCIAL");
    }

    private Object registrarAlLiberar(CountDownLatch start, Escenario escenario, String key) {
        try {
            if (!start.await(5, TimeUnit.SECONDS)) {
                throw new IllegalStateException("Timeout esperando inicio concurrente");
            }

            return pagos.registrarPago(new PagoRegistroRequest(
                    escenario.alumno(),
                    escenario.metodo(),
                    "80.00",
                    key,
                    null,
                    List.of(new AplicacionPagoRequest(escenario.cargo1(), "80.00")),
                    false
            ), escenario.usuario()).id();
        } catch (OperacionNoPermitidaException e) {
            return e;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
    }

    private PagoRegistroRequest pago(
            Escenario escenario,
            String monto,
            boolean credito,
            AplicacionPagoRequest... aplicaciones
    ) {
        return new PagoRegistroRequest(
                escenario.alumno(),
                escenario.metodo(),
                monto,
                key("payment"),
                null,
                List.of(aplicaciones),
                credito
        );
    }

    private Escenario escenario(BigDecimal importe1, BigDecimal importe2) {
        String suffix = UUID.randomUUID().toString();

        Long role = jdbc.queryForObject(
                "SELECT id FROM roles WHERE descripcion = 'ADMINISTRADOR'",
                Long.class
        );

        Long usuario = jdbc.queryForObject("""
                INSERT INTO usuarios (nombre_usuario, contrasena, rol_id, activo)
                VALUES (?, 'test-hash', ?, true)
                RETURNING id
                """, Long.class, "test-" + suffix, role);

        otorgarPermisos(usuario, role,
                "PERM_PAGOS_REGISTRAR",
                "PERM_PAGOS_ANULAR",
                "PERM_CREDITOS_ADMIN",
                "PERM_CREDITOS_CONSUMIR"
        );

        Long alumno = jdbc.queryForObject("""
                INSERT INTO alumnos (nombre, fecha_incorporacion, activo)
                VALUES (?, ?, true)
                RETURNING id
                """, Long.class, "Alumno " + suffix, LocalDate.of(2026, 6, 30));

        Long metodo = jdbc.queryForObject("""
                INSERT INTO metodo_pagos (descripcion, activo, recargo)
                VALUES (?, true, 0)
                RETURNING id
                """, Long.class, "Método " + suffix);

        Long sub = jdbc.queryForObject("""
                INSERT INTO sub_conceptos (descripcion, activo)
                VALUES (?, true)
                RETURNING id
                """, Long.class, "Sub " + suffix);

        Long concepto = jdbc.queryForObject("""
                INSERT INTO conceptos (descripcion, precio, sub_concepto_id, activo)
                VALUES (?, 1, ?, true)
                RETURNING id
                """, Long.class, "Concepto " + suffix, sub);

        Long cargo1 = cargo(alumno, concepto, importe1, "Cargo A " + suffix);
        Long cargo2 = cargo(alumno, concepto, importe2, "Cargo B " + suffix);

        Usuario principal = usuarios.findById(usuario).orElseThrow();

        return new Escenario(alumno, metodo, cargo1, cargo2, principal);
    }

    private void otorgarPermisos(Long usuarioId, Long rolId, String... permisos) {
        jdbc.update("""
                INSERT INTO usuario_roles(usuario_id, rol_id)
                VALUES (?, ?)
                ON CONFLICT DO NOTHING
                """, usuarioId, rolId);

        for (String permiso : permisos) {
            jdbc.update("""
                    INSERT INTO permisos(codigo, descripcion, activo)
                    VALUES (?, ?, true)
                    ON CONFLICT (codigo) DO NOTHING
                    """, permiso, permiso);

            jdbc.update("""
                    INSERT INTO rol_permisos(rol_id, permiso_id)
                    SELECT ?, p.id
                    FROM permisos p
                    WHERE p.codigo = ?
                    ON CONFLICT DO NOTHING
                    """, rolId, permiso);
        }
    }

    private Long cargo(Long alumno, Long concepto, BigDecimal importe, String descripcion) {
        return jdbc.queryForObject("""
                INSERT INTO cargos (
                    alumno_id,
                    tipo,
                    descripcion,
                    importe_original,
                    fecha_emision,
                    fecha_vencimiento,
                    estado,
                    concepto_id
                )
                VALUES (?, 'CONCEPTO', ?, ?, DATE '2026-06-30', DATE '2026-07-10', 'PENDIENTE', ?)
                RETURNING id
                """, Long.class, alumno, descripcion, importe, concepto);
    }

    private int contar(String table, String column, Object value) {
        return jdbc.queryForObject(
                "SELECT count(*) FROM " + table + " WHERE " + column + " = ?",
                Integer.class,
                value
        );
    }

    private int total(String table) {
        return jdbc.queryForObject("SELECT count(*) FROM " + table, Integer.class);
    }

    private String estadoCargo(Long id) {
        return jdbc.queryForObject("SELECT estado FROM cargos WHERE id = ?", String.class, id);
    }

    private String key(String prefix) {
        return prefix + "-" + UUID.randomUUID();
    }

    private record Escenario(Long alumno, Long metodo, Long cargo1, Long cargo2, Usuario usuario) {
    }
}