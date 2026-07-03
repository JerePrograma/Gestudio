package ledance.tarifas;

import ledance.entidades.Usuario;
import ledance.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import ledance.infra.persistencia.PostgreSqlIntegrationTest;
import ledance.repositorios.UsuarioRepositorio;
import ledance.tarifas.api.CondicionEconomicaRequest;
import ledance.tarifas.application.CondicionEconomicaServicio;
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
class CondicionEconomicaPostgreSqlTest extends PostgreSqlIntegrationTest {
    @Autowired private CondicionEconomicaServicio condiciones;
    @Autowired private UsuarioRepositorio usuarios;
    @Autowired private JdbcTemplate jdbc;

    @Test
    void conservaSnapshotDeBonificacionYSeleccionaLaCondicionDelPeriodo() {
        Fixture fixture = fixture("snapshot");
        Long bonificacionId = jdbc.queryForObject("""
                INSERT INTO bonificaciones(descripcion, porcentaje_descuento, valor_fijo, activo)
                VALUES ('Descuento histórico', 10.0000, 5.00, true) RETURNING id
                """, Long.class);
        var enero = condiciones.crear(fixture.inscripcionId(), new CondicionEconomicaRequest(
                LocalDate.of(2026, 1, 1), null, bonificacionId, "Condición enero"), fixture.superadmin());
        jdbc.update("UPDATE bonificaciones SET descripcion = 'Actual', porcentaje_descuento = 50, valor_fijo = 20 WHERE id = ?",
                bonificacionId);
        condiciones.crear(fixture.inscripcionId(), new CondicionEconomicaRequest(
                LocalDate.of(2026, 3, 1), new BigDecimal("200.00"), bonificacionId, "Condición marzo"), fixture.superadmin());

        var febrero = condiciones.vigente(fixture.inscripcionId(), LocalDate.of(2026, 2, 1));
        var marzo = condiciones.vigente(fixture.inscripcionId(), LocalDate.of(2026, 3, 1));
        assertThat(febrero.getId()).isEqualTo(enero.id());
        assertThat(febrero.getBonificacionDescripcionSnapshot()).isEqualTo("Descuento histórico");
        assertThat(febrero.getBonificacionPorcentajeSnapshot()).isEqualByComparingTo("10.0000");
        assertThat(febrero.getBonificacionValorFijoSnapshot()).isEqualByComparingTo("5.00");
        assertThat(marzo.getCostoParticular()).isEqualByComparingTo("200.00");
        assertThat(marzo.getBonificacionPorcentajeSnapshot()).isEqualByComparingTo("50.0000");
    }

    @Test
    void ausenciaDeHistoriaYReglaDeRolSonExplicitas() {
        Fixture fixture = fixture("ausencia");
        assertThatThrownBy(() -> condiciones.vigente(fixture.inscripcionId(), LocalDate.of(2020, 1, 1)))
                .isInstanceOf(CondicionEconomicaServicio.CondicionHistoricaNoDefinidaException.class);

        var historical = new CondicionEconomicaRequest(LocalDate.of(2020, 1, 1), null, null,
                "Planilla histórica verificada");
        assertThatThrownBy(() -> condiciones.crear(fixture.inscripcionId(), historical, fixture.admin()))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("SUPERADMIN");
        var created = condiciones.crear(fixture.inscripcionId(), historical, fixture.superadmin());
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM auditoria_eventos
                WHERE accion = 'CONDICION_ECONOMICA_CREADA' AND entidad_id = ?
                """, Integer.class, created.id().toString())).isOne();
    }

    private Fixture fixture(String prefix) {
        String suffix = prefix + "-" + UUID.randomUUID();
        Long superRole = jdbc.queryForObject("SELECT id FROM roles WHERE descripcion = 'SUPERADMIN'", Long.class);
        Long adminRole = jdbc.queryForObject("SELECT id FROM roles WHERE descripcion = 'ADMINISTRADOR'", Long.class);
        Long superId = usuario("root-condition-" + suffix, superRole);
        Long adminId = usuario("admin-condition-" + suffix, adminRole);
        Long profesorId = jdbc.queryForObject("INSERT INTO profesores(nombre, apellido) VALUES (?, 'Test') RETURNING id",
                Long.class, "Profesor-" + suffix);
        Long disciplinaId = jdbc.queryForObject("""
                INSERT INTO disciplinas(nombre, profesor_id, valor_cuota, matricula, clase_suelta, clase_prueba)
                VALUES (?, ?, 100, 0, 0, 0) RETURNING id
                """, Long.class, "Disciplina-" + suffix, profesorId);
        Long alumnoId = jdbc.queryForObject("""
                INSERT INTO alumnos(nombre, apellido, fecha_incorporacion, activo)
                VALUES ('Alumno', ?, DATE '2020-01-01', true) RETURNING id
                """, Long.class, suffix);
        Long inscripcionId = jdbc.queryForObject("""
                INSERT INTO inscripciones(alumno_id, disciplina_id, fecha_inscripcion, estado)
                VALUES (?, ?, DATE '2020-01-01', 'ACTIVA') RETURNING id
                """, Long.class, alumnoId, disciplinaId);
        return new Fixture(inscripcionId, usuarios.findById(superId).orElseThrow(),
                usuarios.findById(adminId).orElseThrow());
    }

    private Long usuario(String username, Long roleId) {
        return jdbc.queryForObject("""
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo)
                VALUES (?, 'test-only', ?, true) RETURNING id
                """, Long.class, username, roleId);
    }

    private record Fixture(Long inscripcionId, Usuario superadmin, Usuario admin) { }
}
