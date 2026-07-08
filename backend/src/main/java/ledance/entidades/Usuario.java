package ledance.entidades;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.JoinTable;
import jakarta.persistence.ManyToMany;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.FetchType;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;

import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.Set;
import java.time.Instant;
import java.util.stream.Stream;

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
    @ManyToOne(optional = false)
    @JoinColumn(name = "rol_id", nullable = false)
    private Rol rol;
    @ManyToMany(fetch = FetchType.EAGER)
    @JoinTable(name = "usuario_roles",
            joinColumns = @JoinColumn(name = "usuario_id"),
            inverseJoinColumns = @JoinColumn(name = "rol_id"))
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
        Stream<String> rolesAuthorities = roles.stream()
                .filter(value -> Boolean.TRUE.equals(value.getActivo()))
                .map(Rol::getCodigo)
                .map(code -> "ROLE_" + code);
        Stream<String> permisosAuthorities = roles.stream()
                .filter(value -> Boolean.TRUE.equals(value.getActivo()))
                .flatMap(value -> value.getPermisos().stream())
                .filter(value -> Boolean.TRUE.equals(value.getActivo()))
                .map(Permiso::getCodigo)
                .map(code -> "PERM_" + code);
        return Stream.concat(rolesAuthorities, permisosAuthorities)
                .distinct()
                .sorted()
                .map(SimpleGrantedAuthority::new)
                .toList();
    }

    @Override public String getPassword() { return contrasena; }
    @Override public String getUsername() { return nombreUsuario; }
    @Override public boolean isAccountNonExpired() { return true; }
    @Override public boolean isAccountNonLocked() { return true; }
    @Override public boolean isCredentialsNonExpired() { return true; }
    @Override public boolean isEnabled() { return Boolean.TRUE.equals(activo); }
}
