package gestudio.integraciones.jereplatform.infrastructure;

import gestudio.integraciones.jereplatform.application.StudentSourceExport.StudentReference;
import gestudio.integraciones.jereplatform.application.StudentSourceExportException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.util.List;

import static gestudio.integraciones.jereplatform.application.StudentSourceExportException.Code.STUDENT_REFERENCE_INVALID;

@Repository
public class GestudioStudentReferenceReader {
    private final JdbcTemplate jdbc;

    public GestudioStudentReferenceReader(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<StudentReference> readAll() {
        return jdbc.query(
                """
                SELECT id, nombre, apellido, activo
                  FROM alumnos
                 ORDER BY id
                """,
                (resultSet, rowNumber) -> reference(
                        resultSet.getLong("id"),
                        resultSet.getString("nombre"),
                        resultSet.getString("apellido"),
                        resultSet.getBoolean("activo")
                )
        );
    }

    private static StudentReference reference(long id, String firstName, String lastName, boolean active) {
        String displayName = ((firstName == null ? "" : firstName) + " "
                + (lastName == null ? "" : lastName)).trim().replaceAll("\\s+", " ");
        if (id < 1 || displayName.isEmpty() || displayName.length() > 200) {
            throw new StudentSourceExportException(STUDENT_REFERENCE_INVALID);
        }
        return new StudentReference(Long.toString(id), displayName, active);
    }
}
