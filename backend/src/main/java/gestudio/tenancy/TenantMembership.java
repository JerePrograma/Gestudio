package gestudio.tenancy;

import gestudio.entidades.Permiso;
import gestudio.entidades.Rol;
import gestudio.entidades.Usuario;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;

import java.time.Instant;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

@Entity
@Getter
@Setter
@NoArgsConstructor
@Table(name = "tenant_memberships")
public class TenantMembership {
    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "tenant_id", nullable = false, updatable = false)
    private Tenant tenant;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "usuario_id", nullable = false, updatable = false)
    private Usuario usuario;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private TenantMembershipStatus status;

    @Column(name = "security_version", nullable = false)
    private Long securityVersion;

    @Column(name = "valid_from", nullable = false)
    private Instant validFrom;

    @Column(name = "valid_until")
    private Instant validUntil;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @OneToMany(mappedBy = "membership", fetch = FetchType.LAZY)
    private Set<TenantMembershipRole> roleAssignments = new LinkedHashSet<>();

    public Set<Rol> roles() {
        Set<Rol> result = new LinkedHashSet<>();
        roleAssignments.stream().map(TenantMembershipRole::getRole).forEach(result::add);
        return result;
    }

    public List<GrantedAuthority> authorities() {
        Set<GrantedAuthority> result = new LinkedHashSet<>();
        for (Rol role : roles()) {
            if (role == null || !role.estaActivo()) {
                continue;
            }
            if (role.getCodigo() != null && !role.getCodigo().isBlank()) {
                result.add(new SimpleGrantedAuthority("ROLE_" + role.getCodigo()));
            }
            for (Permiso permission : role.getPermisos()) {
                if (permission != null && permission.estaActivo()) {
                    result.add(new SimpleGrantedAuthority(permission.getCodigo()));
                }
            }
        }
        return List.copyOf(result);
    }

    public Set<String> roleCodes() {
        Set<String> result = new LinkedHashSet<>();
        roles().stream()
                .filter(Rol::estaActivo)
                .map(Rol::getCodigo)
                .filter(code -> code != null && !code.isBlank())
                .forEach(result::add);
        return Set.copyOf(result);
    }

    public Set<String> permissionCodes() {
        Set<String> result = new LinkedHashSet<>();
        authorities().stream()
                .map(GrantedAuthority::getAuthority)
                .filter(authority -> !authority.startsWith("ROLE_"))
                .forEach(result::add);
        return Set.copyOf(result);
    }

    public boolean hasPermission(String permission) {
        return permission != null && permissionCodes().contains(permission);
    }

    public boolean isSuperadmin() {
        return roleCodes().stream().anyMatch("SUPERADMIN"::equalsIgnoreCase);
    }
}
