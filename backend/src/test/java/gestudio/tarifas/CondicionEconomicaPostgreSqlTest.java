package gestudio.tarifas;

import gestudio.entidades.Usuario;
import gestudio.infra.persistencia.PostgreSqlIntegrationTest;
import gestudio.repositorios.UsuarioRepositorio;
import gestudio.tarifas.api.CondicionEconomicaRequest;
import gestudio.tarifas.application.CondicionEconomicaServicio;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.AccessDeniedException;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static gestudio.infra.seguridad.PermissionCodes.PERM_CONDICIONES_ECONOMICAS_ADMIN;
import static gestudio.infra.seguridad.PermissionCodes.PERM_TARIFAS_ADMIN;
import static gestudio.infra.seguridad.PermissionCodes.PERM_TARIFAS_HISTORICAS;

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
                VALUES ('Descuento histórico', 10.0000, 5.00, true)
                RETURNING id
                """, Long.class);

        var enero = condiciones.crear(
                fixture.inscripcionId(),
                new CondicionEconomicaRequest(
                        LocalDate.of(2026, 1, 1),
                        null,
                        bonificacionId,
                        "Condición enero"
                ),
                fixture.superadmin()
        );

        jdbc.update("""
                UPDATE bonificaciones
                SET descripcion = 'Actual',
                    porcentaje_descuento = 50,
                    valor_fijo = 20
                WHERE id = ?
                """, bonificacionId);

        condiciones.crear(
                fixture.inscripcionId(),
                new CondicionEconomicaRequest(
                        LocalDate.of(2026, 3, 1),
                        new BigDecimal("200.00"),
                        bonificacionId,
                        "Condición marzo"
                ),
                fixture.superadmin()
        );

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
    void ausenciaDeHistoriaYReglaDePermisosSonExplicitas() {
        Fixture fixture = fixture("ausencia");

        assertThatThrownBy(() -> condiciones.vigente(fixture.inscripcionId(), LocalDate.of(2020, 1, 1)))
                .isInstanceOf(CondicionEconomicaServicio.CondicionHistoricaNoDefinidaException.class);

        var historical = new CondicionEconomicaRequest(
                LocalDate.of(2020, 1, 1),
                null,
                null,
                "Planilla histórica verificada"
        );

        var future = new CondicionEconomicaRequest(
                LocalDate.now().plusDays(10),
                null,
                null,
                "Condición futura autorizada"
        );

        assertThat(condiciones.crear(fixture.inscripcionId(), future, fixture.gestor()).id())
                .isPositive();

        assertThatThrownBy(() -> condiciones.crear(
                fixture.inscripcionId(),
                future,
                fixture.gestorTarifas()
        )).isInstanceOf(AccessDeniedException.class);

        assertThatThrownBy(() -> condiciones.crear(fixture.inscripcionId(), historical, fixture.gestor()))
                .isInstanceOf(AccessDeniedException.class)
                .hasMessageContaining(PERM_TARIFAS_HISTORICAS);

        var created = condiciones.crear(fixture.inscripcionId(), historical, fixture.superadmin());

        assertThat(jdbc.queryForObject("""
                SELECT count(*)
                FROM auditoria_eventos
                WHERE accion = 'CONDICION_ECONOMICA_CREADA'
                  AND entidad_id = ?
                """, Integer.class, created.id().toString()))
                .isOne();
    }

    private Fixture fixture(String prefix) {
        String suffix = prefix + "-" + UUID.randomUUID();

        Long superRole = jdbc.queryForObject(
                "SELECT id FROM roles WHERE descripcion = 'SUPERADMIN'",
                Long.class
        );

        garantizarPermiso(PERM_TARIFAS_ADMIN);
        garantizarPermiso(PERM_TARIFAS_HISTORICAS);
        garantizarPermiso(PERM_CONDICIONES_ECONOMICAS_ADMIN);

        asignarPermiso(superRole, PERM_TARIFAS_ADMIN);
        asignarPermiso(superRole, PERM_TARIFAS_HISTORICAS);

        Long superId = usuario("root-condition-" + suffix, superRole);
        Long gestorId = usuarioConPermiso("gestor-condition-" + suffix, PERM_CONDICIONES_ECONOMICAS_ADMIN);
        Long gestorTarifasId = usuarioConPermiso("gestor-tarifas-" + suffix, PERM_TARIFAS_ADMIN);

        Long profesorId = jdbc.queryForObject("""
                INSERT INTO profesores(nombre, apellido)
                VALUES (?, 'Test')
                RETURNING id
                """, Long.class, "Profesor-" + suffix);

        Long disciplinaId = jdbc.queryForObject("""
                INSERT INTO disciplinas(
                    nombre,
                    profesor_id,
                    valor_cuota,
                    matricula,
                    clase_suelta,
                    clase_prueba
                )
                VALUES (?, ?, 100, 0, 0, 0)
                RETURNING id
                """, Long.class, "Disciplina-" + suffix, profesorId);

        Long alumnoId = jdbc.queryForObject("""
                INSERT INTO alumnos(nombre, apellido, fecha_incorporacion, activo)
                VALUES ('Alumno', ?, DATE '2020-01-01', true)
                RETURNING id
                """, Long.class, suffix);

        Long inscripcionId = jdbc.queryForObject("""
                INSERT INTO inscripciones(alumno_id, disciplina_id, fecha_inscripcion, estado)
                VALUES (?, ?, DATE '2020-01-01', 'ACTIVA')
                RETURNING id
                """, Long.class, alumnoId, disciplinaId);

        return new Fixture(
                inscripcionId,
                usuarios.findByIdConRolesYPermisos(superId).orElseThrow(),
                usuarios.findByIdConRolesYPermisos(gestorId).orElseThrow(),
                usuarios.findByIdConRolesYPermisos(gestorTarifasId).orElseThrow()
        );
    }

    private Long usuario(String username, Long roleId) {
        Long id = jdbc.queryForObject("""
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo)
                VALUES (?, 'test-only', ?, true)
                RETURNING id
                """, Long.class, username, roleId);

        jdbc.update("""
                INSERT INTO usuario_roles(usuario_id, rol_id)
                VALUES (?, ?)
                ON CONFLICT DO NOTHING
                """, id, roleId);

        return id;
    }

    private Long usuarioConPermiso(String username, String permiso) {
        garantizarPermiso(permiso);

        String codigo = "GESTOR_CONDICIONES_" + UUID.randomUUID()
                .toString()
                .substring(0, 8)
                .toUpperCase();

        Long roleId = jdbc.queryForObject("""
                INSERT INTO roles(descripcion, activo, codigo, nombre, sistema, editable)
                VALUES (?, true, ?, ?, false, true)
                RETURNING id
                """, Long.class, codigo, codigo, codigo);

        asignarPermiso(roleId, permiso);

        return usuario(username, roleId);
    }

    private void garantizarPermiso(String codigo) {
        jdbc.queryForObject("""
                INSERT INTO permisos(codigo, descripcion, modulo, activo, sistema)
                VALUES (?, ?, 'TARIFAS', true, true)
                ON CONFLICT (codigo)
                DO UPDATE SET activo = EXCLUDED.activo
                RETURNING id
                """, Long.class, codigo, codigo);
    }

    private void asignarPermiso(Long roleId, String permiso) {
        jdbc.update("""
                INSERT INTO rol_permisos(rol_id, permiso_id)
                SELECT ?, id
                FROM permisos
                WHERE codigo = ?
                ON CONFLICT DO NOTHING
                """, roleId, permiso);
    }

    private record Fixture(Long inscripcionId, Usuario superadmin, Usuario gestor, Usuario gestorTarifas) {
    }
}
