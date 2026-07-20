package gestudio.integraciones.jereplatform.infrastructure;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.databind.ObjectWriter;
import gestudio.integraciones.jereplatform.application.StudentSourceExport;
import gestudio.integraciones.jereplatform.application.StudentSourceExportException;
import org.springframework.stereotype.Component;

import static gestudio.integraciones.jereplatform.application.StudentSourceExportException.Code.SERIALIZATION_FAILED;

@Component
public class StudentSourceExportSerializer {
    private final ObjectWriter writer;

    public StudentSourceExportSerializer(ObjectMapper objectMapper) {
        this.writer = objectMapper.copy()
                .setSerializationInclusion(JsonInclude.Include.ALWAYS)
                .disable(SerializationFeature.INDENT_OUTPUT)
                .writerFor(StudentSourceExport.class);
    }

    public byte[] serialize(StudentSourceExport export) {
        try {
            return writer.writeValueAsBytes(export);
        } catch (JsonProcessingException exception) {
            throw new StudentSourceExportException(SERIALIZATION_FAILED);
        }
    }
}
