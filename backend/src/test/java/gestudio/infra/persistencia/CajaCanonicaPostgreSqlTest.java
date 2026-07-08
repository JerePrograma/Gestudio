package gestudio.infra.persistencia;

import gestudio.repositorios.MovimientoCajaRepositorio;
import gestudio.servicios.caja.CajaServicio;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest
@Transactional
class CajaCanonicaPostgreSqlTest extends PostgreSqlIntegrationTest {

    @Autowired
    private JdbcTemplate jdbc;
    @Autowired
    private MovimientoCajaRepositorio movimientos;
    @Autowired
    private CajaServicio caja;

    private long metodoUno;
    private long metodoDos;
    private long usuario;
    private long alumno;
    private final LocalDate dia = LocalDate.of(2026, 6, 15);

    @BeforeEach
    void seedReferences() {
        String suffix = UUID.randomUUID().toString();
        metodoUno = id("INSERT INTO metodo_pagos(descripcion, activo, recargo) VALUES (?, true, 0) RETURNING id",
                "Caja uno " + suffix);
        metodoDos = id("INSERT INTO metodo_pagos(descripcion, activo, recargo) VALUES (?, true, 0) RETURNING id",
                "Caja dos " + suffix);
        usuario = id("""
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo)
                VALUES (?, 'no-login', (SELECT id FROM roles WHERE descripcion = 'ADMINISTRADOR'), true)
                RETURNING id
                """, "caja-" + suffix);
        alumno = id("""
                INSERT INTO alumnos(nombre, apellido, fecha_incorporacion, activo)
                VALUES (?, 'Caja', ?, true) RETURNING id
                """, "Alumno " + suffix, dia);
    }

    @Test
    void agregaSignosReversionesMetodosYRangoInclusivo() {
        long ingreso = movimiento("INGRESO_PAGO", dia, "100.00", metodoUno, null, "ingreso");
        long egreso = movimiento("EGRESO", dia, "40.00", metodoDos, null, "egreso");
        movimiento("AJUSTE_INGRESO", dia, "10.00", metodoUno, null, "ajuste ingreso");
        movimiento("AJUSTE_EGRESO", dia, "5.00", metodoDos, null, "ajuste egreso");
        movimiento("REVERSO", dia, "100.00", metodoUno, ingreso, "reverso ingreso");
        movimiento("REVERSO", dia, "40.00", metodoDos, egreso, "reverso egreso");
        movimiento("AJUSTE_INGRESO", dia.minusDays(1), "999.00", metodoUno, null, "fuera");

        var total = movimientos.totales(dia, dia);

        assertThat(total.getIngresos()).isEqualByComparingTo("100.00");
        assertThat(total.getEgresos()).isEqualByComparingTo("40.00");
        assertThat(total.getAjustesIngreso()).isEqualByComparingTo("10.00");
        assertThat(total.getAjustesEgreso()).isEqualByComparingTo("5.00");
        assertThat(total.getReversosIngreso()).isEqualByComparingTo("100.00");
        assertThat(total.getReversosEgreso()).isEqualByComparingTo("40.00");
        BigDecimal neto = total.getIngresos().add(total.getAjustesIngreso()).add(total.getReversosEgreso())
                .subtract(total.getEgresos()).subtract(total.getAjustesEgreso()).subtract(total.getReversosIngreso());
        assertThat(neto).isEqualByComparingTo("5.00");

        var resumen = caja.obtenerResumen(dia, dia,
                PageRequest.of(0, 20, Sort.by("fecha", "id")));
        assertThat(resumen.ingresos()).isEqualTo("100.00");
        assertThat(resumen.egresos()).isEqualTo("40.00");
        assertThat(resumen.ajustesIngreso()).isEqualTo("10.00");
        assertThat(resumen.ajustesEgreso()).isEqualTo("5.00");
        assertThat(resumen.reversosIngreso()).isEqualTo("100.00");
        assertThat(resumen.reversosEgreso()).isEqualTo("40.00");
        assertThat(resumen.totalIngresos()).isEqualTo("150.00");
        assertThat(resumen.totalEgresos()).isEqualTo("145.00");
        assertThat(resumen.saldo()).isEqualTo("5.00");
        assertThat(resumen.movimientos().totalElements()).isEqualTo(6);
    }

    @Test
    void diaSinMovimientosDevuelveCerosYLaIdempotenciaImpideDuplicados() {
        var total = movimientos.totales(dia.plusYears(1), dia.plusYears(1));
        assertThat(total.getIngresos()).isEqualByComparingTo(BigDecimal.ZERO);
        assertThat(total.getEgresos()).isEqualByComparingTo(BigDecimal.ZERO);
        assertThat(total.getAjustesIngreso()).isEqualByComparingTo(BigDecimal.ZERO);
        assertThat(total.getAjustesEgreso()).isEqualByComparingTo(BigDecimal.ZERO);
        assertThat(total.getReversosIngreso()).isEqualByComparingTo(BigDecimal.ZERO);
        assertThat(total.getReversosEgreso()).isEqualByComparingTo(BigDecimal.ZERO);

        String key = "caja-duplicada-" + UUID.randomUUID();
        insertar("AJUSTE_INGRESO", dia, "1.00", metodoUno, null, key, "primero");
        assertThatThrownBy(() -> insertar("AJUSTE_INGRESO", dia, "1.00", metodoUno, null, key, "duplicado"))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    private long movimiento(String tipo, LocalDate fecha, String importe, long metodo, Long revertido, String motivo) {
        String key = "caja-" + UUID.randomUUID();
        Long pago = null;
        Long egreso = null;
        if ("INGRESO_PAGO".equals(tipo)) {
            pago = id("""
                    INSERT INTO pagos(alumno_id, metodo_pago_id, usuario_id, fecha, monto_recibido, estado,
                                      idempotency_key, request_hash)
                    VALUES (?, ?, ?, ?, ?::numeric, 'REGISTRADO', ?, repeat('a', 64)) RETURNING id
                    """, alumno, metodo, usuario, fecha, importe, "pago-" + UUID.randomUUID());
        } else if ("EGRESO".equals(tipo)) {
            egreso = id("""
                    INSERT INTO egresos(fecha, monto, metodo_pago_id, estado, usuario_id, idempotency_key, request_hash)
                    VALUES (?, ?::numeric, ?, 'REGISTRADO', ?, ?, repeat('b', 64)) RETURNING id
                    """, fecha, importe, metodo, usuario, "egreso-" + UUID.randomUUID());
        }
        return insertar(tipo, fecha, importe, metodo, pago, egreso, revertido, key, motivo);
    }

    private long insertar(String tipo, LocalDate fecha, String importe, long metodo, Long revertido,
                          String key, String motivo) {
        return insertar(tipo, fecha, importe, metodo, null, null, revertido, key, motivo);
    }

    private long insertar(String tipo, LocalDate fecha, String importe, long metodo, Long pago, Long egreso,
                          Long revertido, String key, String motivo) {
        return id("""
                INSERT INTO movimientos_caja(tipo, fecha, importe, metodo_pago_id, pago_id, egreso_id,
                                             movimiento_revertido_id, usuario_id, idempotency_key, motivo)
                VALUES (?, ?, ?::numeric, ?, ?, ?, ?, ?, ?, ?) RETURNING id
                """, tipo, fecha, importe, metodo, pago, egreso, revertido, usuario, key, motivo);
    }

    private long id(String sql, Object... args) {
        Long value = jdbc.queryForObject(sql, Long.class, args);
        if (value == null) {
            throw new IllegalStateException("La insercion no devolvio id");
        }
        return value;
    }
}
