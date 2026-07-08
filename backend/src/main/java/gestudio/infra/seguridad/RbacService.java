package gestudio.infra.seguridad;

import gestudio.auditoria.application.AuditFailureService;
import gestudio.entidades.Usuario;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.repositorios.UsuarioRepositorio;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class RbacService {

    private final UsuarioRepositorio usuarios;
    private final AuditFailureService auditFailures;

    public RbacService(UsuarioRepositorio usuarios, AuditFailureService auditFailures) {
        this.usuarios = usuarios;
        this.auditFailures = auditFailures;
    }

    @Transactional(readOnly = true)
    public Usuario exigirPermiso(Usuario actor, String permiso, String operacion) {
        if (actor == null || actor.getId() == null) {
            auditFailures.registrarEscalamiento(actor, operacion);
            throw new OperacionNoPermitidaException("Actor requerido");
        }

        return usuarios.findByIdConRolesYPermisos(actor.getId())
                .filter(Usuario::isEnabled)
                .filter(usuario -> usuario.rolesEfectivos().stream()
                        .anyMatch(rol -> Boolean.TRUE.equals(rol.getActivo())))
                .filter(usuario -> usuario.tienePermiso(permiso))
                .orElseThrow(() -> {
                    auditFailures.registrarEscalamiento(actor, operacion);
                    return new OperacionNoPermitidaException("Permiso requerido: " + permiso);
                });
    }

    @Transactional(readOnly = true)
    public Usuario exigirSuperadminSistema(Usuario actor, String operacion) {
        if (actor == null || actor.getId() == null) {
            auditFailures.registrarEscalamiento(actor, operacion);
            throw new OperacionNoPermitidaException("SUPERADMIN autenticado requerido");
        }

        return usuarios.findByIdConRolesYPermisos(actor.getId())
                .filter(Usuario::isEnabled)
                .filter(Usuario::esSuperadminSistema)
                .orElseThrow(() -> {
                    auditFailures.registrarEscalamiento(actor, operacion);
                    return new OperacionNoPermitidaException("La operación requiere SUPERADMIN sistema");
                });
    }
}