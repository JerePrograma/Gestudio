package gestudio.servicios.disciplina;

import gestudio.infra.persistencia.PostgreSqlIntegrationTest;
import jakarta.persistence.EntityManagerFactory;
import org.hibernate.SessionFactory;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.web.servlet.MockMvc;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(properties = {
        "spring.jpa.open-in-view=false",
        "spring.jpa.properties.hibernate.generate_statistics=true",
        "logging.level.org.hibernate.stat=OFF",
        "logging.level.org.hibernate.engine.internal.StatisticalLoggingSessionEventListener=OFF"
})
@AutoConfigureMockMvc
class DisciplinaListadoPostgreSqlTest extends PostgreSqlIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private EntityManagerFactory entityManagerFactory;

    @BeforeEach
    void seed() {
        jdbc.execute("TRUNCATE TABLE disciplinas, profesores, salones RESTART IDENTITY CASCADE");

        Long salonId = jdbc.queryForObject("""
                INSERT INTO salones(nombre, descripcion, activo)
                VALUES ('Sala OSIV', 'Regresión de listado', true)
                RETURNING id
                """, Long.class);
        Long profesorId = jdbc.queryForObject("""
                INSERT INTO profesores(nombre, apellido, activo)
                VALUES ('Ada', 'Lovelace', true)
                RETURNING id
                """, Long.class);
        Long disciplinaId = jdbc.queryForObject("""
                INSERT INTO disciplinas(
                    nombre, salon_id, profesor_id, valor_cuota,
                    matricula, clase_suelta, clase_prueba, activo)
                VALUES ('Ballet OSIV', ?, ?, 1000.00, 0.00, 0.00, 0.00, true)
                RETURNING id
                """, Long.class, salonId, profesorId);
        jdbc.update("""
                INSERT INTO disciplina_horarios(disciplina_id, dia_semana, horario_inicio, duracion)
                VALUES (?, 'LUNES', TIME '18:00', 1.50)
                """, disciplinaId);
    }

    @Test
    @WithMockUser(authorities = {"PERM_APP_ACCESO", "PERM_DISCIPLINAS_LEER"})
    void listadoMapeaHorariosConOsivDesactivadoSinNMasUno() throws Exception {
        SessionFactory sessionFactory = entityManagerFactory.unwrap(SessionFactory.class);
        sessionFactory.getStatistics().clear();

        mockMvc.perform(get("/api/disciplinas/listado"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].nombre").value("Ballet OSIV"))
                .andExpect(jsonPath("$[0].salon").value("Sala OSIV"))
                .andExpect(jsonPath("$[0].profesorNombre").value("Ada"))
                .andExpect(jsonPath("$[0].horarios[0].diaSemana").value("LUNES"))
                .andExpect(jsonPath("$[0].horarios[0].horarioInicio").value("18:00:00"));

        assertThat(sessionFactory.getStatistics().getPrepareStatementCount()).isEqualTo(1);
    }
}
