package gestudio.integraciones.jereplatform.application;

public final class StudentSourceExportException extends RuntimeException {

    public enum Code {
        TENANT_MAPPING_MISSING("tenant_mapping_missing"),
        TENANT_MAPPING_INVALID("tenant_mapping_invalid"),
        TENANT_MAPPING_DISABLED("tenant_mapping_disabled"),
        SOURCE_SECRET_MISSING("source_secret_missing"),
        SOURCE_SECRET_TOO_SHORT("source_secret_too_short"),
        SNAPSHOT_NOT_FOUND("snapshot_not_found"),
        CURSOR_INVALID("cursor_invalid"),
        PAGE_TOO_LARGE("page_too_large"),
        PAYLOAD_TOO_LARGE("payload_too_large"),
        STUDENT_REFERENCE_INVALID("student_reference_invalid"),
        SERIALIZATION_FAILED("serialization_failed"),
        SIGNATURE_FAILED("signature_failed");

        private final String value;

        Code(String value) {
            this.value = value;
        }

        public String value() {
            return value;
        }
    }

    private final Code code;

    public StudentSourceExportException(Code code) {
        super(code.value());
        this.code = code;
    }

    public Code code() {
        return code;
    }
}
