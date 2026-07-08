package gestudio.cuotas.application;

import com.fasterxml.jackson.databind.ObjectMapper;
import gestudio.auditoria.application.AuditService;
import gestudio.entidades.Cargo;
import gestudio.entidades.EstadoCargo;
import gestudio.entidades.Usuario;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.Map;
import java.util.UUID;

@Service
public class CargoEventoServicio {
    private final JdbcTemplate jdbc;
    private final AuditService audit;
    private final ObjectMapper objectMapper;

    public CargoEventoServicio(JdbcTemplate jdbc, AuditService audit, ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.audit = audit;
        this.objectMapper = objectMapper;
    }

    public void registrar(Cargo cargo, String tipo, EstadoCargo estadoAnterior, BigDecimal saldoAnterior,
                          BigDecimal saldoNuevo, String referenciaTipo, Long referenciaId,
                          String idempotencyKey, Usuario usuario, Map<String, ?> metadata) {
        jdbc.update("""
                INSERT INTO cargo_eventos(
                    cargo_id, tipo, estado_anterior, estado_nuevo, saldo_anterior, saldo_nuevo,
                    referencia_tipo, referencia_id, idempotency_key, usuario_id, correlation_id, metadata)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CAST(? AS jsonb))
                """, cargo.getId(), tipo, estadoAnterior == null ? null : estadoAnterior.name(),
                cargo.getEstado().name(), saldoAnterior, saldoNuevo, referenciaTipo, referenciaId,
                idempotencyKey, usuario == null ? null : usuario.getId(), UUID.randomUUID(), json(metadata));
        audit.registrar(categoria(tipo), tipo, "CARGO", cargo.getId().toString(), usuario,
                "audit:" + idempotencyKey, Map.of(
                        "referenciaTipo", referenciaTipo == null ? "SIN_REFERENCIA" : referenciaTipo,
                        "referenciaId", referenciaId == null ? 0L : referenciaId));
    }

    private String json(Map<String, ?> metadata) {
        try {
            return objectMapper.writeValueAsString(
                    metadata == null ? Map.of() : metadata);
        } catch (com.fasterxml.jackson.core.JsonProcessingException exception) {
            throw new IllegalArgumentException("Metadata de cargo inválida", exception);
        }
    }

    private String categoria(String tipo) {
        return tipo.startsWith("PAGO_") || tipo.startsWith("CREDITO_") ? "PAGOS" : "FACTURACION";
    }
}
