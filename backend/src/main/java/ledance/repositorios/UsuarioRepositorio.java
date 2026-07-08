package ledance.repositorios;

import jakarta.persistence.LockModeType;
import ledance.entidades.Rol;
import ledance.entidades.Usuario;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface UsuarioRepositorio extends JpaRepository<Usuario, Long> {

    Optional<Usuario> findByNombreUsuario(String nombreUsuario);

    Optional<Usuario> findByNombreUsuarioIgnoreCase(String nombreUsuario);

    List<Usuario> findByRolAndActivo(Rol rol, Boolean activo);

    List<Usuario> findByRol(Rol rol);

    List<Usuario> findByActivo(Boolean activo);

    List<Usuario> findByActivoTrue();

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select u from Usuario u where u.id = :id")
    Optional<Usuario> findByIdForUpdate(@Param("id") Long id);

    @Query("""
        select distinct u from Usuario u
        left join fetch u.rol rolPrincipal
        left join fetch u.roles roles
        left join fetch roles.permisos permisos
        where u.id = :id
        """)
    Optional<Usuario> findByIdConRolesYPermisos(@Param("id") Long id);

    @Query("""
        select distinct u from Usuario u
        left join fetch u.rol rolPrincipal
        left join fetch u.roles roles
        left join fetch roles.permisos permisos
        where lower(u.nombreUsuario) = lower(:username)
        """)
    Optional<Usuario> findByNombreUsuarioIgnoreCaseConRolesYPermisos(@Param("username") String username);

    @Query("""
        select distinct u from Usuario u
        left join fetch u.rol rolPrincipal
        left join fetch u.roles roles
        left join fetch roles.permisos permisos
        """)
    List<Usuario> findAllConRolesYPermisos();

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
        select distinct u from Usuario u
        join fetch u.roles roles
        where u.activo = true
          and upper(roles.codigo) = 'SUPERADMIN'
        order by u.id
        """)
    List<Usuario> findActiveSuperadminsForUpdate();

    @Modifying
    @Query(value = """
        UPDATE usuarios
        SET auth_version = auth_version + 1
        WHERE id IN (
            SELECT usuario_id
            FROM usuario_roles
            WHERE rol_id = :rolId
        )
        OR rol_id = :rolId
        """, nativeQuery = true)
    int incrementarAuthVersionPorRolId(@Param("rolId") Long rolId);
}