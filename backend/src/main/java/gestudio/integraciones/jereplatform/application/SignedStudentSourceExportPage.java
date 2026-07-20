package gestudio.integraciones.jereplatform.application;

import java.util.UUID;

public record SignedStudentSourceExportPage(
        UUID checkpoint,
        int pageNumber,
        int pageCount,
        String nextCursor,
        int recordCount,
        byte[] payload,
        String signature,
        UUID correlationId
) {
    public SignedStudentSourceExportPage {
        payload = payload.clone();
    }

    @Override
    public byte[] payload() {
        return payload.clone();
    }
}
