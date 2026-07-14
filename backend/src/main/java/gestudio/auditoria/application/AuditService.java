package gestudio.auditoria.application;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import gestudio.entidades.Usuario;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.LocalDate;
import java.util.Collection;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;

@Service
public class AuditService {
    private static final Set<String> SECRET_FRAGMENTS = Set.of(
            "password", "contrasena", "contraseña", "token", "secret", "jwt", "authorization", "bearer");
    private static final Set<String> NON_SECRET_CLASSIFICATIONS = Set.of("TOKEN_INVALIDO");
    private static final Pattern JWT = Pattern.compile(
            "^[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}$");
    private static final Pattern SENSITIVE_VALUE_MARKER = Pattern.compile(
            "(^|[\\s._-])(password|contrasena|contraseña|token|secret|jwt|authorization|bearer)"
                    + "(?=\\s*[:=]|[\\s._-]|$)",
            Pattern.CASE_INSENSITIVE | Pattern.UNICODE_CASE);
    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;
    private final Clock clock;

    public AuditService(JdbcTemplate jdbc, ObjectMapper objectMapper, Clock clock) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
        this.clock = clock;
    }

    public void registrar(String categoria, String accion, String entidadTipo, String entidadId,
                          Usuario actor, String idempotencyKey, Map<String, ?> metadata) {
        registrar(categoria, accion, entidadTipo, entidadId, actor, null, idempotencyKey,
                null, null, metadata);
    }

    public void registrar(String categoria, String accion, String entidadTipo, String entidadId,
                          Usuario actor, UUID correlationId, String idempotencyKey,
                          Map<String, ?> estadoAnterior, Map<String, ?> estadoNuevo,
                          Map<String, ?> metadata) {
        validarSinSecretos(estadoAnterior);
        validarSinSecretos(estadoNuevo);
        validarSinSecretos(metadata);
        jdbc.update("""
                INSERT INTO auditoria_eventos(
                    categoria, accion, entidad_tipo, entidad_id,
                    actor_usuario_id, actor_username_snapshot, actor_role_snapshot,
                    fecha_negocio, correlation_id, idempotency_key,
                    estado_anterior, estado_nuevo, metadata)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                        CAST(? AS jsonb), CAST(? AS jsonb), CAST(? AS jsonb))
                """,
                categoria, accion, entidadTipo, entidadId,
                actor == null ? null : actor.getId(),
                actor == null ? null : actor.getNombreUsuario(),
                actor == null || actor.getRol() == null ? null : actor.getRol().getDescripcion(),
                LocalDate.now(clock), correlationId, idempotencyKey,
                jsonNullable(estadoAnterior), jsonNullable(estadoNuevo), json(metadata));
    }

    public void registrarAnonimo(String categoria, String accion, String usernameSnapshot,
                                 Map<String, ?> metadata) {
        validarSinSecretos(metadata);
        jdbc.update("""
                INSERT INTO auditoria_eventos(
                    categoria, accion, actor_username_snapshot, fecha_negocio, metadata)
                VALUES (?, ?, ?, ?, CAST(? AS jsonb))
                """, categoria, accion, usernameSnapshot, LocalDate.now(clock), json(metadata));
    }

    private String json(Map<String, ?> metadata) {
        try {
            return objectMapper.writeValueAsString(metadata == null ? Map.of() : metadata);
        } catch (JsonProcessingException e) {
            throw new IllegalArgumentException("Metadata de auditoría inválida", e);
        }
    }

    private String jsonNullable(Map<String, ?> value) {
        return value == null ? null : json(value);
    }

    private void validarSinSecretos(Object value) {
        if (value instanceof Map<?, ?> map) {
            map.forEach((key, nested) -> {
                String normalized = String.valueOf(key).toLowerCase(Locale.ROOT);
                if (SECRET_FRAGMENTS.stream().anyMatch(normalized::contains)) {
                    throw new IllegalArgumentException("La auditoría no admite secretos");
                }
                validarSinSecretos(nested);
            });
        } else if (value instanceof Collection<?> values) {
            values.forEach(this::validarSinSecretos);
        } else if (value instanceof CharSequence text && esValorSensible(text.toString())) {
            throw new IllegalArgumentException("La auditoría no admite secretos");
        }
    }

    private boolean esValorSensible(String value) {
        String trimmed = value.trim();
        if (trimmed.isEmpty() || NON_SECRET_CLASSIFICATIONS.contains(trimmed)) {
            return false;
        }
        String normalized = trimmed.toLowerCase(Locale.ROOT);
        return JWT.matcher(trimmed).matches()
                || SENSITIVE_VALUE_MARKER.matcher(normalized).find();
    }
}
