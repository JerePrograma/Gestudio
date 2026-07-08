package ledance.repositorios;

import ledance.entidades.Rol;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;
import ledance.entidades.Usuario;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;

@Repository
public interface UsuarioRepositorio extends JpaRepository<Usuario, Long> {

    @EntityGraph(attributePaths = {"roles", "roles.permisos"})
    Optional<Usuario> findByNombreUsuario(String nombreUsuario);

    @EntityGraph(attributePaths = {"roles", "roles.permisos"})
    Optional<Usuario> findByNombreUsuarioIgnoreCase(String nombreUsuario);

    @EntityGraph(attributePaths = {"roles", "roles.permisos"})
    @Query("select distinct u from Usuario u join u.roles r where upper(r.codigo) = upper(:codigo) and u.activo = :activo")
    List<Usuario> findByRoleCodeAndActivo(@Param("codigo") String codigo, @Param("activo") Boolean activo);

    @EntityGraph(attributePaths = {"roles", "roles.permisos"})
    @Query("select distinct u from Usuario u join u.roles r where upper(r.codigo) = upper(:codigo)")
    List<Usuario> findByRoleCode(@Param("codigo") String codigo);

    List<Usuario> findByActivo(Boolean activo);

    List<Usuario> findByActivoTrue();

    @EntityGraph(attributePaths = {"roles", "roles.permisos"})
    @Query("select u from Usuario u where u.id = :id")
    Optional<Usuario> findWithAuthoritiesById(@Param("id") Long id);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select u from Usuario u where u.id = :id")
    Optional<Usuario> findByIdForUpdate(@Param("id") Long id);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
        select distinct u from Usuario u join fetch u.roles r
        where u.activo = true and r.activo = true and upper(r.codigo) = 'SUPERADMIN'
        order by u.id
        """)
    List<Usuario> findActiveSuperadminsForUpdate();

    long countByRolesIdAndActivoTrue(Long rolId);
}
