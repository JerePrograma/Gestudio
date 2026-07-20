package gestudio.integraciones.jereplatform;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.Properties;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class StudentSourceExportContractTest {
    private static final Set<String> ROOT_FIELDS = Set.of(
            "contractVersion", "tenantId", "sourceType", "checkpoint", "nextCursor",
            "pageNumber", "pageCount", "fullSnapshot", "records");
    private static final Set<String> RECORD_FIELDS = Set.of("sourceId", "displayName", "active");

    @Test
    void copiaControladaPublicaSoloElContratoV1Aprobado() throws Exception {
        ObjectMapper objectMapper = new ObjectMapper();
        try (InputStream input = getClass().getResourceAsStream(
                "/contracts/party-source-export-v1.schema.json")) {
            assertThat(input).isNotNull();
            byte[] schemaBytes = input.readAllBytes();
            JsonNode schema = objectMapper.readTree(schemaBytes);
            assertThat(schema.path("properties").path("contractVersion").path("const").intValue())
                    .isOne();
            assertThat(fieldNames(schema.path("properties")))
                    .containsExactlyInAnyOrderElementsOf(ROOT_FIELDS);
            assertThat(schema.path("additionalProperties").booleanValue()).isFalse();
            JsonNode records = schema.path("properties").path("records");
            assertThat(records.path("maxItems").intValue()).isEqualTo(1_000);
            assertThat(fieldNames(records.path("items").path("properties")))
                    .containsExactlyInAnyOrderElementsOf(RECORD_FIELDS);
            assertThat(records.path("items").path("additionalProperties").booleanValue()).isFalse();

            Properties provenance = new Properties();
            try (InputStream metadata = getClass().getResourceAsStream(
                    "/contracts/party-source-export-v1.provenance.properties")) {
                assertThat(metadata).isNotNull();
                provenance.load(metadata);
            }
            assertThat(provenance.getProperty("version")).isEqualTo("1");
            assertThat(provenance.getProperty("sourceCommit"))
                    .isEqualTo("bebfe716780a1ea42cc65be6441af9cc5dfe5bae");
            String normalized = new String(schemaBytes, StandardCharsets.UTF_8)
                    .replace("\r\n", "\n");
            String checksum = HexFormat.of().formatHex(
                    MessageDigest.getInstance("SHA-256")
                            .digest(normalized.getBytes(StandardCharsets.UTF_8)));
            assertThat(checksum).isEqualTo(provenance.getProperty("normalizedSha256"));
        }
    }

    private static Set<String> fieldNames(JsonNode node) {
        Set<String> fields = new HashSet<>();
        node.fieldNames().forEachRemaining(fields::add);
        return fields;
    }
}
