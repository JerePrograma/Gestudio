package ledance.entidades;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;

import java.time.Instant;
import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

@Entity
@Getter
@Setter
@NoArgsConstructor
@Table(name = "usuarios")
public class Usuario implements UserDetails {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(length = 100, nullable = false)
    private String nombreUsuario;

    @Column(length = 100, nullable = false)
    private String contrasena;

    /**
     * Rol principal legacy.
     * No borrar hasta migrar login, refresh, auditoría, bootstrap y tests.
     */
    @ManyToOne(optional = false)
    @JoinColumn(name = "rol_id", nullable = false)
    private Rol rol;

    @ManyToMany(fetch = FetchType.LAZY)
    @JoinTable(
            name = "usuario_roles",
            joinColumns = @JoinColumn(name = "usuario_id"),
            inverseJoinColumns = @JoinColumn(name = "rol_id")
    )
    private Set<Rol> roles = new LinkedHashSet<>();

    @Column(nullable = false)
    private Boolean activo = true;

    @Column(name = "auth_version", nullable = false)
    private Long authVersion = 0L;

    @Column(name = "password_changed_at")
    private Instant passwordChangedAt;

    @Version
    @Column(nullable = false)
    private Long version;

    @Override
    public Collection<? extends GrantedAuthority> getAuthorities() {
        Set<GrantedAuthority> authorities = new LinkedHashSet<>();

        for (Rol rolEfectivo : rolesEfectivos()) {
            if (rolEfectivo == null || !rolEfectivo.estaActivo()) {
                continue;
            }

            if (rolEfectivo.getCodigo() != null && !rolEfectivo.getCodigo().isBlank()) {
                authorities.add(new SimpleGrantedAuthority("ROLE_" + rolEfectivo.getCodigo()));
            }

            for (Permiso permiso : rolEfectivo.getPermisos()) {
                if (permiso != null && permiso.estaActivo()) {
                    authorities.add(new SimpleGrantedAuthority(permiso.getCodigo()));
                }
            }
        }

        return List.copyOf(authorities);
    }

    public Set<Rol> rolesEfectivos() {
        if (roles != null && !roles.isEmpty()) {
            return roles;
        }
        return rol == null ? Set.of() : Set.of(rol);
    }

    public boolean tienePermiso(String codigoPermiso) {
        if (codigoPermiso == null || codigoPermiso.isBlank()) {
            return false;
        }

        return getAuthorities().stream()
                .map(GrantedAuthority::getAuthority)
                .anyMatch(codigoPermiso::equals);
    }

    public Set<String> codigosPermisosActivos() {
        Set<String> permisos = new LinkedHashSet<>();

        for (Rol rolEfectivo : rolesEfectivos()) {
            if (rolEfectivo == null || !rolEfectivo.estaActivo()) {
                continue;
            }

            for (Permiso permiso : rolEfectivo.getPermisos()) {
                if (permiso != null && permiso.estaActivo()) {
                    permisos.add(permiso.getCodigo());
                }
            }
        }

        return permisos;
    }

    public Set<String> codigosRolesActivos() {
        Set<String> codigos = new LinkedHashSet<>();

        for (Rol rolEfectivo : rolesEfectivos()) {
            if (rolEfectivo != null && rolEfectivo.estaActivo()) {
                codigos.add(rolEfectivo.getCodigo());
            }
        }

        return codigos;
    }

    public boolean esSuperadminSistema() {
        return rolesEfectivos().stream().anyMatch(Rol::esSuperadminSistema);
    }

    @Override
    public String getPassword() {
        return contrasena;
    }

    @Override
    public String getUsername() {
        return nombreUsuario;
    }

    @Override
    public boolean isAccountNonExpired() {
        return true;
    }

    @Override
    public boolean isAccountNonLocked() {
        return true;
    }

    @Override
    public boolean isCredentialsNonExpired() {
        return true;
    }

    @Override
    public boolean isEnabled() {
        return Boolean.TRUE.equals(activo);
    }
}