package gestudio.integraciones.jereplatform.application;

import gestudio.auditoria.application.AuditService;
import gestudio.entidades.Usuario;
import gestudio.infra.seguridad.RbacService;
import gestudio.integraciones.jereplatform.infrastructure.GestudioStudentReferenceReader;
import gestudio.integraciones.jereplatform.infrastructure.StudentSourceExportProperties;
import gestudio.integraciones.jereplatform.infrastructure.StudentSourceExportSerializer;
import gestudio.integraciones.jereplatform.infrastructure.StudentSourceExportSigner;
import gestudio.integraciones.jereplatform.infrastructure.StudentSourceExportStore;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static gestudio.infra.seguridad.PermissionCodes.PERM_CONFIG_ADMIN;
import static gestudio.infra.seguridad.PermissionCodes.PERM_REPORTES_EXPORTAR;
import static gestudio.integraciones.jereplatform.application.StudentSourceExportException.Code.CURSOR_INVALID;
import static gestudio.integraciones.jereplatform.application.StudentSourceExportException.Code.PAGE_TOO_LARGE;
import static gestudio.integraciones.jereplatform.application.StudentSourceExportException.Code.PAYLOAD_TOO_LARGE;
import static gestudio.integraciones.jereplatform.application.StudentSourceExportException.Code.SNAPSHOT_NOT_FOUND;

@Service
public class StudentSourceExportService {
    public static final String SOURCE_TYPE = "GESTUDIO_STUDENT";
    public static final int MAX_PAYLOAD_BYTES = 1_000_000;

    private static final Logger log = LoggerFactory.getLogger(StudentSourceExportService.class);

    private final SourceTenantMapping tenantMapping;
    private final StudentSourceExportProperties properties;
    private final GestudioStudentReferenceReader students;
    private final StudentSourceExportSerializer serializer;
    private final StudentSourceExportSigner signer;
    private final StudentSourceExportStore store;
    private final RbacService rbac;
    private final AuditService audit;
    private final Clock clock;

    public StudentSourceExportService(
            SourceTenantMapping tenantMapping,
            StudentSourceExportProperties properties,
            GestudioStudentReferenceReader students,
            StudentSourceExportSerializer serializer,
            StudentSourceExportSigner signer,
            StudentSourceExportStore store,
            RbacService rbac,
            AuditService audit,
            Clock clock
    ) {
        this.tenantMapping = tenantMapping;
        this.properties = properties;
        this.students = students;
        this.serializer = serializer;
        this.signer = signer;
        this.store = store;
        this.rbac = rbac;
        this.audit = audit;
        this.clock = clock;
    }

    @Transactional
    public SignedStudentSourceExportPage createSnapshot(Usuario actor) {
        Usuario authorized = authorize(actor, "CREAR_EXPORTACION_ESTUDIANTES_JERE_PLATFORM");
        SourceTenantMapping.Mapping mapping = tenantMapping.require();
        signer.requireConfigured();
        int pageSize = pageSize();
        List<StudentSourceExport.StudentReference> references = students.readAll();
        int pageCount = Math.max(1, (references.size() + pageSize - 1) / pageSize);
        if (pageCount > 1_000) {
            throw new StudentSourceExportException(PAGE_TOO_LARGE);
        }

        UUID checkpoint = UUID.randomUUID();
        UUID correlationId = UUID.randomUUID();
        List<UUID> cursors = cursors(pageCount);
        var createdAt = clock.instant();
        store.insertSnapshot(
                checkpoint,
                mapping,
                pageSize,
                pageCount,
                references.size(),
                authorized.getId(),
                createdAt
        );

        SignedStudentSourceExportPage firstPage = null;
        for (int pageNumber = 1; pageNumber <= pageCount; pageNumber++) {
            int from = Math.min((pageNumber - 1) * pageSize, references.size());
            int to = Math.min(from + pageSize, references.size());
            List<StudentSourceExport.StudentReference> pageRecords = references.subList(from, to);
            UUID currentCursor = cursors.get(pageNumber - 1);
            UUID nextCursor = pageNumber == pageCount ? null : cursors.get(pageNumber);
            boolean fullSnapshot = pageNumber == pageCount;
            byte[] payload = serializer.serialize(new StudentSourceExport(
                    1,
                    mapping.tenantId(),
                    SOURCE_TYPE,
                    checkpoint.toString(),
                    nextCursor == null ? null : nextCursor.toString(),
                    pageNumber,
                    pageCount,
                    fullSnapshot,
                    pageRecords
            ));
            if (pageRecords.size() > 1_000) {
                throw new StudentSourceExportException(PAGE_TOO_LARGE);
            }
            if (payload.length > MAX_PAYLOAD_BYTES) {
                throw new StudentSourceExportException(PAYLOAD_TOO_LARGE);
            }
            String signature = signer.sign(payload);
            store.insertPage(
                    checkpoint,
                    pageNumber,
                    currentCursor,
                    nextCursor,
                    fullSnapshot,
                    pageRecords.size(),
                    payload,
                    sha256(payload),
                    signature,
                    createdAt
            );
            if (pageNumber == 1) {
                firstPage = new SignedStudentSourceExportPage(
                        checkpoint,
                        pageNumber,
                        pageCount,
                        nextCursor == null ? null : nextCursor.toString(),
                        pageRecords.size(),
                        payload,
                        signature,
                        correlationId
                );
            }
        }

        audit.registrar(
                "SISTEMA",
                "EXPORTACION_ESTUDIANTES_CREADA",
                "JERE_PLATFORM_STUDENT_EXPORT",
                checkpoint.toString(),
                authorized,
                correlationId,
                "jere-student-export:" + checkpoint,
                null,
                null,
                auditMetadata(mapping, checkpoint, null, references.size(), pageCount, "CREATED")
        );
        log.info(
                "Jere student export created organization={} tenant={} checkpoint={} pages={} count={} correlationId={} result=CREATED",
                mapping.organizationId(), mapping.tenantId(), checkpoint, pageCount, references.size(), correlationId);
        return firstPage;
    }

    @Transactional
    public SignedStudentSourceExportPage page(String checkpointValue, String cursorValue, Usuario actor) {
        Usuario authorized = authorize(actor, "EMITIR_PAGINA_ESTUDIANTES_JERE_PLATFORM");
        SourceTenantMapping.Mapping mapping = tenantMapping.require();
        signer.requireConfigured();
        UUID checkpoint = parseCheckpoint(checkpointValue);
        UUID cursor = parseCursor(cursorValue);
        UUID correlationId = UUID.randomUUID();
        var stored = store.findPage(checkpoint, mapping, cursor)
                .orElseThrow(() -> new StudentSourceExportException(
                        cursor == null ? SNAPSHOT_NOT_FOUND : CURSOR_INVALID));
        SignedStudentSourceExportPage page = stored.signed(checkpoint, correlationId);
        audit.registrar(
                "SISTEMA",
                "EXPORTACION_ESTUDIANTES_EMITIDA",
                "JERE_PLATFORM_STUDENT_EXPORT",
                checkpoint.toString(),
                authorized,
                correlationId,
                null,
                null,
                null,
                auditMetadata(mapping, checkpoint, cursor, page.recordCount(), page.pageCount(), "EMITTED")
        );
        log.info(
                "Jere student export emitted organization={} tenant={} checkpoint={} page={} count={} correlationId={} result=EMITTED",
                mapping.organizationId(), mapping.tenantId(), checkpoint, page.pageNumber(),
                page.recordCount(), correlationId);
        return page;
    }

    private Usuario authorize(Usuario actor, String operation) {
        Usuario authorized = rbac.exigirPermiso(actor, PERM_CONFIG_ADMIN, operation);
        return rbac.exigirPermiso(authorized, PERM_REPORTES_EXPORTAR, operation);
    }

    private int pageSize() {
        int pageSize = properties.pageSize();
        if (pageSize < 1 || pageSize > 1_000) {
            throw new StudentSourceExportException(PAGE_TOO_LARGE);
        }
        return pageSize;
    }

    private static List<UUID> cursors(int pageCount) {
        List<UUID> cursors = new ArrayList<>(pageCount);
        cursors.add(null);
        for (int page = 2; page <= pageCount; page++) {
            cursors.add(UUID.randomUUID());
        }
        return cursors;
    }

    private static UUID parseCheckpoint(String value) {
        try {
            return UUID.fromString(value);
        } catch (RuntimeException invalid) {
            throw new StudentSourceExportException(SNAPSHOT_NOT_FOUND);
        }
    }

    private static UUID parseCursor(String value) {
        if (value == null) return null;
        if (value.isBlank() || !value.equals(value.trim())) {
            throw new StudentSourceExportException(CURSOR_INVALID);
        }
        try {
            return UUID.fromString(value);
        } catch (IllegalArgumentException invalid) {
            throw new StudentSourceExportException(CURSOR_INVALID);
        }
    }

    private static String sha256(byte[] payload) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(payload));
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 no disponible", impossible);
        }
    }

    private static Map<String, ?> auditMetadata(
            SourceTenantMapping.Mapping mapping,
            UUID checkpoint,
            UUID cursor,
            int count,
            int pageCount,
            String result
    ) {
        return Map.of(
                "organizationId", mapping.organizationId(),
                "tenantId", mapping.tenantId().toString(),
                "sourceType", SOURCE_TYPE,
                "checkpoint", checkpoint.toString(),
                "cursor", cursor == null ? "FIRST" : cursor.toString(),
                "recordCount", count,
                "pageCount", pageCount,
                "result", result
        );
    }
}
