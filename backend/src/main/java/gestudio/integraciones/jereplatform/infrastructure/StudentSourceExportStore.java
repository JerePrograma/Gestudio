package gestudio.integraciones.jereplatform.infrastructure;

import gestudio.integraciones.jereplatform.application.SourceTenantMapping.Mapping;
import gestudio.integraciones.jereplatform.application.SignedStudentSourceExportPage;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

@Repository
public class StudentSourceExportStore {
    private final JdbcTemplate jdbc;

    public StudentSourceExportStore(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public void insertSnapshot(
            UUID checkpoint,
            Mapping mapping,
            int pageSize,
            int pageCount,
            int totalRecords,
            long actorId,
            Instant createdAt
    ) {
        jdbc.update(
                """
                INSERT INTO jere_platform_student_export_snapshots(
                    checkpoint, organization_id, tenant_id, status, page_size,
                    page_count, total_records, created_by, created_at, version)
                VALUES (?, ?, ?, 'READY', ?, ?, ?, ?, ?, 0)
                """,
                checkpoint,
                mapping.organizationId(),
                mapping.tenantId(),
                pageSize,
                pageCount,
                totalRecords,
                actorId,
                Timestamp.from(createdAt)
        );
    }

    public void insertPage(
            UUID checkpoint,
            int pageNumber,
            UUID cursor,
            UUID nextCursor,
            boolean fullSnapshot,
            int recordCount,
            byte[] payload,
            String payloadSha256,
            String signature,
            Instant createdAt
    ) {
        jdbc.update(
                """
                INSERT INTO jere_platform_student_export_pages(
                    snapshot_checkpoint, page_number, cursor_token, next_cursor_token,
                    full_snapshot, record_count, payload, payload_sha256, signature, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                checkpoint,
                pageNumber,
                cursor,
                nextCursor,
                fullSnapshot,
                recordCount,
                payload,
                payloadSha256,
                signature,
                Timestamp.from(createdAt)
        );
    }

    public Optional<StoredPage> findPage(UUID checkpoint, Mapping mapping, UUID cursor) {
        return jdbc.query(
                """
                SELECT s.page_count, p.page_number, p.next_cursor_token, p.record_count,
                       p.payload, p.signature
                  FROM jere_platform_student_export_snapshots s
                  JOIN jere_platform_student_export_pages p
                    ON p.snapshot_checkpoint = s.checkpoint
                 WHERE s.checkpoint = ?
                   AND s.organization_id = ?
                   AND s.tenant_id = ?
                   AND ((CAST(? AS UUID) IS NULL AND p.cursor_token IS NULL)
                        OR p.cursor_token = CAST(? AS UUID))
                """,
                (resultSet, rowNumber) -> new StoredPage(
                        resultSet.getInt("page_number"),
                        resultSet.getInt("page_count"),
                        resultSet.getObject("next_cursor_token", UUID.class),
                        resultSet.getInt("record_count"),
                        resultSet.getBytes("payload"),
                        resultSet.getString("signature")
                ),
                checkpoint,
                mapping.organizationId(),
                mapping.tenantId(),
                cursor,
                cursor
        ).stream().findFirst();
    }

    public record StoredPage(
            int pageNumber,
            int pageCount,
            UUID nextCursor,
            int recordCount,
            byte[] payload,
            String signature
    ) {
        public SignedStudentSourceExportPage signed(UUID checkpoint, UUID correlationId) {
            return new SignedStudentSourceExportPage(
                    checkpoint,
                    pageNumber,
                    pageCount,
                    nextCursor == null ? null : nextCursor.toString(),
                    recordCount,
                    payload,
                    signature,
                    correlationId
            );
        }
    }
}
