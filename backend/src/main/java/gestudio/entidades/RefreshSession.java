package gestudio.entidades;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.Instant;
import java.util.UUID;

@Entity
@Getter
@Setter
@NoArgsConstructor
@Table(name = "refresh_sessions")
public class RefreshSession {
    @Id private UUID id;
    @Column(name = "family_id", nullable = false) private UUID familyId;
    @ManyToOne(optional = false) @JoinColumn(name = "usuario_id", nullable = false) private Usuario usuario;
    @JdbcTypeCode(SqlTypes.CHAR) @Column(name = "token_hash", length = 64, nullable = false, updatable = false) private String tokenHash;
    @Column(name = "auth_version", nullable = false, updatable = false) private Long authVersion;
    @Column(name = "issued_at", nullable = false, updatable = false) private Instant issuedAt;
    @Column(name = "expires_at", nullable = false, updatable = false) private Instant expiresAt;
    @Column(name = "used_at") private Instant usedAt;
    @Column(name = "revoked_at") private Instant revokedAt;
    @Column(name = "revoke_reason", length = 100) private String revokeReason;
    @OneToOne @JoinColumn(name = "replaced_by_id") private RefreshSession replacedBy;
    @JdbcTypeCode(SqlTypes.CHAR) @Column(name = "user_agent_hash", length = 64, updatable = false) private String userAgentHash;
    @JdbcTypeCode(SqlTypes.CHAR) @Column(name = "ip_hash", length = 64, updatable = false) private String ipHash;
}
