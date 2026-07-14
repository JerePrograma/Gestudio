package gestudio.tarifas;

import gestudio.entidades.Usuario;
import gestudio.infra.persistencia.PostgreSqlIntegrationTest;
import gestudio.repositorios.UsuarioRepositorio;
import gestudio.tarifas.api.TarifaDisciplinaRequest;
import gestudio.tarifas.application.TarifaDisciplinaServicio;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.AccessDeniedException;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static gestudio.infra.seguridad.PermissionCodes.PERM_TARIFAS_ADMIN;
import static gestudio.infra.seguridad.PermissionCodes.PERM_TARIFAS_HISTORICAS;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
class TarifaDisciplinaPostgreSqlTest extends PostgreSqlIntegrationTest {

    @Autowired private TarifaDisciplinaServicio tarifas;
    @Autowired private UsuarioRepositorio usuarios;
    @Autowired private JdbcTemplate jdbc;

    @Test
    void seleccionaLaFechaExactaOLaAnteriorMasRecienteSinAplicarUnaFutura() {
        Fixture fixture = fixture("seleccion");

        insertarTarifa(fixture.disciplinaId(), fixture.superadmin().getId(), LocalDate.of(2026, 1, 1), "100.00");
        insertarTarifa(fixture.disciplinaId(), fixture.superadmin().getId(), LocalDate.of(2026, 3, 1), "130.00");
        insertarTarifa(fixture.disciplinaId(), fixture.superadmin().getId(), LocalDate.of(2026, 8, 1), "180.00");

        assertThat(tarifas.vigente(fixture.disciplinaId(), LocalDate.of(2026, 3, 1)).getValorCuota())
                .isEqualByComparingTo("130.00");

        assertThat(tarifas.vigente(fixture.disciplinaId(), LocalDate.of(2026, 7, 1)).getValorCuota())
                .isEqualByComparingTo("130.00");
    }

    @Test
    void rechazaMismaFechaEImportesNegativosEnPostgreSql() {
        Fixture fixture = fixture("restricciones");
        LocalDate fecha = LocalDate.of(2026, 1, 1);

        insertarTarifa(fixture.disciplinaId(), fixture.superadmin().getId(), fecha, "100.00");

        assertThatThrownBy(() -> insertarTarifa(
                fixture.disciplinaId(),
                fixture.superadmin().getId(),
                fecha,
                "110.00"
        ))
                .isInstanceOf(DataIntegrityViolationException.class);

        assertThatThrownBy(() -> insertarTarifa(
                fixture.disciplinaId(),
                fixture.superadmin().getId(),
                LocalDate.of(2026, 2, 1),
                "-1.00"
        ))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void permisoDeEscrituraProgramaFuturoYLaCreacionQuedaAuditada() {
        Fixture fixture = fixture("permisos");

        LocalDate future = LocalDate.now().plusDays(10);

        var request = new TarifaDisciplinaRequest(
                future,
                new BigDecimal("150.00"),
                BigDecimal.ZERO,
                BigDecimal.ZERO,
                BigDecimal.ZERO,
                "Ajuste futuro verificado"
        );

        var created = tarifas.crear(fixture.disciplinaId(), request, fixture.gestor());

        assertThat(created.valorCuota()).isEqualTo("150.00");

        assertThat(jdbc.queryForObject("""
                SELECT count(*)
                FROM auditoria_eventos
                WHERE accion = 'TARIFA_CREADA'
                  AND entidad_id = ?
                """, Integer.class, created.id().toString()))
                .isOne();

        var historical = new TarifaDisciplinaRequest(
                LocalDate.of(2020, 1, 1),
                new BigDecimal("90.00"),
                BigDecimal.ZERO,
                BigDecimal.ZERO,
                BigDecimal.ZERO,
                "Historia documentada"
        );

        assertThatThrownBy(() -> tarifas.crear(fixture.disciplinaId(), historical, fixture.gestor()))
                .isInstanceOf(AccessDeniedException.class)
                .hasMessageContaining(PERM_TARIFAS_HISTORICAS);

        assertThat(tarifas.crear(fixture.disciplinaId(), historical, fixture.superadmin()).valorCuota())
                .isEqualTo("90.00");
    }

    private Fixture fixture(String prefix) {
        String suffix = prefix + "-" + UUID.randomUUID();

        Long superRole = jdbc.queryForObject(
                "SELECT id FROM roles WHERE descripcion = 'SUPERADMIN'",
                Long.class
        );

        garantizarPermiso(PERM_TARIFAS_ADMIN);
        garantizarPermiso(PERM_TARIFAS_HISTORICAS);

        asignarPermiso(superRole, PERM_TARIFAS_ADMIN);
        asignarPermiso(superRole, PERM_TARIFAS_HISTORICAS);

        Long superId = usuario("root-" + suffix, superRole);
        Long gestorId = usuarioConPermiso("gestor-" + suffix, PERM_TARIFAS_ADMIN);

        Long profesorId = jdbc.queryForObject("""
                INSERT INTO profesores(nombre, apellido, activo)
                VALUES (?, 'Test', true)
                RETURNING id
                """, Long.class, "Profesor-" + suffix);

        Long disciplinaId = jdbc.queryForObject("""
                INSERT INTO disciplinas(
                    nombre,
                    profesor_id,
                    valor_cuota,
                    matricula,
                    clase_suelta,
                    clase_prueba,
                    activo
                )
                VALUES (?, ?, 999, 0, 0, 0, true)
                RETURNING id
                """, Long.class, "Disciplina-" + suffix, profesorId);

        return new Fixture(
                disciplinaId,
                usuarios.findByIdConRolesYPermisos(superId).orElseThrow(),
                usuarios.findByIdConRolesYPermisos(gestorId).orElseThrow()
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

        String codigo = "GESTOR_TARIFAS_" + UUID.randomUUID()
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

    private void insertarTarifa(Long disciplinaId, Long usuarioId, LocalDate desde, String valor) {
        jdbc.update("""
                INSERT INTO disciplina_tarifas(
                    disciplina_id,
                    vigente_desde,
                    valor_cuota,
                    matricula,
                    clase_suelta,
                    clase_prueba,
                    motivo,
                    creada_por_usuario_id
                )
                VALUES (?, ?, ?, 0, 0, 0, 'Test', ?)
                """, disciplinaId, desde, new BigDecimal(valor), usuarioId);
    }

    private record Fixture(Long disciplinaId, Usuario superadmin, Usuario gestor) {
    }
}
