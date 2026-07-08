package gestudio.infra.persistencia;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.Statement;
import java.util.List;
import java.util.regex.Pattern;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
class DataAuditSqlPostgreSqlTest extends PostgreSqlIntegrationTest {
    private static final List<String> SQL_FILES = List.of(
            "01-counts.sql", "02-duplicates.sql", "03-orphans.sql",
            "04-financial-inconsistencies.sql", "05-state-inconsistencies.sql",
            "06-reconciliation-baseline.sql");
    private static final Pattern MUTATING_SQL = Pattern.compile(
            "(?i)\\b(INSERT|UPDATE|DELETE|MERGE|TRUNCATE|ALTER|DROP|CREATE)\\b");

    @Test
    void ejecutaLasAuditoriasCanonicasComoConsultasDeSoloLectura() throws Exception {
        Path directory = Path.of(System.getProperty("user.dir"), "..", "docs", "refactor", "sql")
                .toAbsolutePath().normalize();
        try (Connection connection = POSTGRESQL.createConnection("")) {
            connection.setReadOnly(true);
            connection.setAutoCommit(false);
            for (String fileName : SQL_FILES) {
                String sql = Files.readString(directory.resolve(fileName), StandardCharsets.UTF_8);
                String withoutComments = sql.replaceAll("(?m)--.*$", "");
                String structure = withoutComments.replaceAll("'(?:''|[^'])*'", "''");
                assertThat(MUTATING_SQL.matcher(structure).find()).as(fileName).isFalse();
                try (Statement statement = connection.createStatement(); ResultSet result = statement.executeQuery(sql)) {
                    ResultSetMetaData metadata = result.getMetaData();
                    assertThat(metadata.getColumnCount()).isGreaterThan(1);
                    int rows = 0;
                    while (result.next()) {
                        rows++;
                        if (fileName.compareTo("02-duplicates.sql") >= 0
                                && fileName.compareTo("05-state-inconsistencies.sql") <= 0) {
                            assertThat(result.getString("rule_id")).isNotBlank();
                            assertThat(result.getLong("affected_count")).as("%s %s", fileName,
                                    result.getString("rule_id")).isZero();
                        }
                    }
                    assertThat(rows).as(fileName).isPositive();
                }
            }
            connection.rollback();
        }
    }
}
