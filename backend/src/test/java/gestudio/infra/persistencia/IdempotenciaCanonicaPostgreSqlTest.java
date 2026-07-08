package gestudio.infra.persistencia;

import gestudio.dto.credito.request.CreditoAjusteRequest;
import gestudio.dto.egreso.request.EgresoAnulacionRequest;
import gestudio.dto.egreso.request.EgresoRegistroRequest;
import gestudio.dto.stock.request.ReversionStockRequest;
import gestudio.dto.stock.request.VentaStockRequest;
import gestudio.entidades.Usuario;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.repositorios.UsuarioRepositorio;
import gestudio.servicios.credito.CreditoServicio;
import gestudio.servicios.egreso.EgresoServicio;
import gestudio.servicios.stock.StockServicio;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
class IdempotenciaCanonicaPostgreSqlTest extends PostgreSqlIntegrationTest {

    @Autowired
    private EgresoServicio egresos;

    @Autowired
    private StockServicio stock;

    @Autowired
    private CreditoServicio creditos;

    @Autowired
    private UsuarioRepositorio usuarios;

    @Autowired
    private JdbcTemplate jdbc;

    @Test
    @Timeout(30)
    void mismaKeyConcurrenteNoDuplicaYUnPayloadDistintoEntraEnConflicto() throws Exception {
        Fixture fixture = fixture();

        String egresoKey = key("egreso");
        EgresoRegistroRequest egreso = new EgresoRegistroRequest(
                LocalDate.of(2026, 7, 1),
                "25.00",
                "insumo",
                fixture.metodo(),
                egresoKey
        );

        List<Long> egresoIds = concurrentes(() -> egresos.agregarEgreso(egreso, fixture.usuario()).id());

        assertThat(egresoIds).containsOnly(egresoIds.getFirst());
        assertThat(count("egresos", egresoKey)).isOne();

        assertThatThrownBy(() -> egresos.agregarEgreso(new EgresoRegistroRequest(
                egreso.fecha(),
                "26.00",
                egreso.observaciones(),
                egreso.metodoPagoId(),
                egresoKey
        ), fixture.usuario()))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("otro contenido");

        String ventaKey = key("venta");
        VentaStockRequest venta = new VentaStockRequest(
                fixture.alumno(),
                fixture.stock(),
                2,
                LocalDate.of(2026, 7, 31),
                ventaKey
        );

        List<Long> cargoIds = concurrentes(() -> stock.vender(venta, fixture.usuario()).id());

        assertThat(cargoIds).containsOnly(cargoIds.getFirst());
        assertThat(count("ventas_stock", ventaKey)).isOne();

        assertThatThrownBy(() -> stock.vender(new VentaStockRequest(
                fixture.alumno(),
                fixture.stock(),
                3,
                venta.fechaVencimiento(),
                ventaKey
        ), fixture.usuario()))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("otro contenido");

        String creditoKey = key("credito");
        CreditoAjusteRequest ajuste = new CreditoAjusteRequest(
                fixture.alumno(),
                "10.00",
                "CREDITO",
                "ajuste auditado",
                creditoKey
        );

        List<Long> movimientoIds = concurrentes(() -> creditos.ajustar(ajuste, fixture.usuario()).id());

        assertThat(movimientoIds).containsOnly(movimientoIds.getFirst());
        assertThat(count("movimientos_credito", creditoKey)).isOne();

        assertThatThrownBy(() -> creditos.ajustar(new CreditoAjusteRequest(
                fixture.alumno(),
                "11.00",
                "CREDITO",
                ajuste.motivo(),
                creditoKey
        ), fixture.usuario()))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("otro contenido");

        String egresoReversalKey = key("egreso-reversal");
        EgresoAnulacionRequest egresoReversal = new EgresoAnulacionRequest(
                egresoReversalKey,
                "carga duplicada"
        );

        assertThat(concurrentes(() -> egresos.anular(
                egresoIds.getFirst(),
                egresoReversal,
                fixture.usuario()
        ).id()))
                .containsOnly(egresoIds.getFirst());

        assertThatThrownBy(() -> egresos.anular(
                egresoIds.getFirst(),
                new EgresoAnulacionRequest(egresoReversalKey, "otro motivo"),
                fixture.usuario()
        ))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("otro contenido");

        Long ventaId = jdbc.queryForObject(
                "SELECT id FROM ventas_stock WHERE idempotency_key = ?",
                Long.class,
                ventaKey
        );

        String ventaReversalKey = key("venta-reversal");
        ReversionStockRequest ventaReversal = new ReversionStockRequest(
                ventaReversalKey,
                "venta incorrecta"
        );

        assertThat(concurrentes(() -> stock.revertirVenta(
                ventaId,
                ventaReversal,
                fixture.usuario()
        ).id()))
                .containsOnly(cargoIds.getFirst());

        assertThatThrownBy(() -> stock.revertirVenta(
                ventaId,
                new ReversionStockRequest(ventaReversalKey, "otro motivo"),
                fixture.usuario()
        ))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("otro contenido");
    }

    private List<Long> concurrentes(Callable<Long> operation) throws Exception {
        CountDownLatch start = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);

        Future<Long> first = executor.submit(() -> ejecutarAlLiberar(start, operation));
        Future<Long> second = executor.submit(() -> ejecutarAlLiberar(start, operation));

        boolean completed = false;

        try {
            start.countDown();
            List<Long> results = List.of(
                    first.get(10, TimeUnit.SECONDS),
                    second.get(10, TimeUnit.SECONDS)
            );
            completed = true;
            return results;
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

    private static Long ejecutarAlLiberar(CountDownLatch start, Callable<Long> operation) throws Exception {
        if (!start.await(5, TimeUnit.SECONDS)) {
            throw new IllegalStateException("Timeout esperando inicio concurrente");
        }

        return operation.call();
    }

    private Fixture fixture() {
        String suffix = UUID.randomUUID().toString();

        Long role = jdbc.queryForObject(
                "SELECT id FROM roles WHERE descripcion = 'ADMINISTRADOR'",
                Long.class
        );

        Long user = id("""
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo)
                VALUES (?, 'test-only', ?, true)
                RETURNING id
                """, "idem-" + suffix, role);

        otorgarPermisos(user, role,
                "PERM_EGRESOS_ADMIN",
                "PERM_STOCK_VENDER",
                "PERM_STOCK_ADMIN",
                "PERM_CREDITOS_ADMIN",
                "PERM_CREDITOS_CONSUMIR"
        );

        Long alumno = id("""
                INSERT INTO alumnos(nombre, fecha_incorporacion, activo)
                VALUES (?, DATE '2026-01-01', true)
                RETURNING id
                """, "Alumno " + suffix);

        Long metodo = id("""
                INSERT INTO metodo_pagos(descripcion, activo, recargo)
                VALUES (?, true, 0)
                RETURNING id
                """, "Método " + suffix);

        Long stockId = id("""
                INSERT INTO stocks(nombre, precio, cantidad_actual, requiere_control_de_stock, activo)
                VALUES (?, 5, 20, true, true)
                RETURNING id
                """, "Stock " + suffix);

        return new Fixture(alumno, metodo, stockId, usuarios.findByIdConRolesYPermisos(user).orElseThrow());
    }

    private void otorgarPermisos(Long usuarioId, Long rolId, String... permisos) {
        jdbc.update("""
                INSERT INTO usuario_roles(usuario_id, rol_id)
                VALUES (?, ?)
                ON CONFLICT DO NOTHING
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
                    SELECT ?, p.id
                    FROM permisos p
                    WHERE p.codigo = ?
                    ON CONFLICT DO NOTHING
                    """, rolId, permiso);
        }
    }

    private static String moduloDe(String permiso) {
        String normalizado = permiso == null ? "" : permiso.trim().toUpperCase();

        if (!normalizado.startsWith("PERM_")) {
            return "GENERAL";
        }

        String sinPrefijo = normalizado.substring("PERM_".length());
        int separador = sinPrefijo.indexOf('_');
        String modulo = separador <= 0 ? sinPrefijo : sinPrefijo.substring(0, separador);

        return modulo.length() < 2 ? "GENERAL" : modulo;
    }

    private int count(String table, String key) {
        return jdbc.queryForObject(
                "SELECT count(*) FROM " + table + " WHERE idempotency_key = ?",
                Integer.class,
                key
        );
    }

    private Long id(String sql, Object... args) {
        Long value = jdbc.queryForObject(sql, Long.class, args);

        if (value == null) {
            throw new IllegalStateException("La inserción no devolvió id");
        }

        return value;
    }

    private String key(String prefix) {
        return prefix + "-" + UUID.randomUUID();
    }

    private record Fixture(Long alumno, Long metodo, Long stock, Usuario usuario) {
    }
}