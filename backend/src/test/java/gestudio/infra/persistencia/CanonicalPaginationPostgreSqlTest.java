package gestudio.infra.persistencia;

import jakarta.persistence.EntityManagerFactory;
import gestudio.entidades.Alumno;
import gestudio.repositorios.AlumnoRepositorio;
import org.hibernate.SessionFactory;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(properties = {
        "spring.jpa.properties.hibernate.generate_statistics=true",
        "logging.level.org.hibernate.stat=OFF",
        "logging.level.org.hibernate.engine.internal.StatisticalLoggingSessionEventListener=OFF"
})
@AutoConfigureMockMvc
@Transactional
class CanonicalPaginationPostgreSqlTest extends PostgreSqlIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private AlumnoRepositorio alumnos;

    @Autowired
    private EntityManagerFactory entityManagerFactory;

    @Autowired
    private JdbcTemplate jdbc;

    @BeforeEach
    void seed() {
        jdbc.execute("TRUNCATE TABLE alumnos RESTART IDENTITY CASCADE");

        alumnos.saveAllAndFlush(IntStream.rangeClosed(1, 205)
                .mapToObj(index -> alumno("Nombre " + index, index % 2 == 0 ? "Igual" : "Otro"))
                .toList());
    }

    @Test
    @WithMockUser(authorities = {
            "PERM_APP_ACCESO",
            "PERM_ALUMNOS_LEER",
            "PERM_ALUMNOS_ADMIN"
    })
    void paginaPrimeraIntermediaUltimaFueraDeRangoYOrdenEstable() throws Exception {
        var first = mockMvc.perform(get("/api/alumnos?page=0&size=2"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.totalElements").value(205))
                .andExpect(jsonPath("$.totalPages").value(103))
                .andExpect(jsonPath("$.first").value(true))
                .andExpect(jsonPath("$.last").value(false))
                .andReturn();

        long firstId = ((Number) com.jayway.jsonpath.JsonPath.read(
                first.getResponse().getContentAsString(), "$.content[0].id")).longValue();
        long secondId = ((Number) com.jayway.jsonpath.JsonPath.read(
                first.getResponse().getContentAsString(), "$.content[1].id")).longValue();

        assertThat(secondId).isGreaterThan(firstId);

        mockMvc.perform(get("/api/alumnos?page=1&size=2"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.number").value(1))
                .andExpect(jsonPath("$.content.length()").value(2))
                .andExpect(jsonPath("$.first").value(false))
                .andExpect(jsonPath("$.last").value(false));

        mockMvc.perform(get("/api/alumnos?page=102&size=2"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content.length()").value(1))
                .andExpect(jsonPath("$.last").value(true));

        mockMvc.perform(get("/api/alumnos?page=103&size=2"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content.length()").value(0))
                .andExpect(jsonPath("$.last").value(true));
    }

    @Test
    @WithMockUser(authorities = {
            "PERM_APP_ACCESO",
            "PERM_ALUMNOS_LEER",
            "PERM_ALUMNOS_ADMIN"
    })
    void filtroSinResultadosYPaginaUsanDosConsultas() throws Exception {
        SessionFactory sessionFactory = entityManagerFactory.unwrap(SessionFactory.class);
        sessionFactory.getStatistics().clear();

        mockMvc.perform(get("/api/alumnos/buscar?nombre=inexistente&page=0&size=20"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content.length()").value(0))
                .andExpect(jsonPath("$.totalElements").value(0))
                .andExpect(jsonPath("$.totalPages").value(0))
                .andExpect(jsonPath("$.first").value(true))
                .andExpect(jsonPath("$.last").value(true));

        assertThat(sessionFactory.getStatistics().getPrepareStatementCount()).isLessThanOrEqualTo(2);
    }

    @Test
    @WithMockUser(authorities = {
            "PERM_APP_ACCESO",
            "PERM_ALUMNOS_LEER",
            "PERM_ALUMNOS_ADMIN"
    })
    void rechazaParametrosInvalidosYMasDeDoscientos() throws Exception {
        mockMvc.perform(get("/api/alumnos?page=-1&size=20"))
                .andExpect(status().isBadRequest());

        mockMvc.perform(get("/api/alumnos?page=0&size=0"))
                .andExpect(status().isBadRequest());

        mockMvc.perform(get("/api/alumnos?page=0&size=201"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void listadoNoEsPublico() throws Exception {
        mockMvc.perform(get("/api/alumnos?page=0&size=20"))
                .andExpect(status().isUnauthorized());
    }

    private static Alumno alumno(String nombre, String apellido) {
        Alumno alumno = new Alumno();
        alumno.setNombre(nombre);
        alumno.setApellido(apellido);
        alumno.setFechaIncorporacion(LocalDate.of(2026, 1, 1));
        alumno.setActivo(true);
        alumno.setAutorizadoParaSalirSolo(false);
        return alumno;
    }
}