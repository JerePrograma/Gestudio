package gestudio.integraciones.jereplatform.application;

import com.fasterxml.jackson.annotation.JsonPropertyOrder;

import java.util.List;
import java.util.UUID;

@JsonPropertyOrder({
        "contractVersion", "tenantId", "sourceType", "checkpoint", "nextCursor",
        "pageNumber", "pageCount", "fullSnapshot", "records"
})
public record StudentSourceExport(
        int contractVersion,
        UUID tenantId,
        String sourceType,
        String checkpoint,
        String nextCursor,
        int pageNumber,
        int pageCount,
        boolean fullSnapshot,
        List<StudentReference> records
) {
    public StudentSourceExport {
        records = List.copyOf(records);
    }

    @JsonPropertyOrder({"sourceId", "displayName", "active"})
    public record StudentReference(String sourceId, String displayName, boolean active) {
    }
}
