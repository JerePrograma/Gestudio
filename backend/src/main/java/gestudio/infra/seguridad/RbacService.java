package gestudio.infra.seguridad;

import gestudio.auditoria.application.AuditFailureService;
import gestudio.entidades.Usuario;
import gestudio.tenancy.TenantAccess;
import gestudio.tenancy.TenantAccessService;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class RbacService {

    private final TenantAccessService tenantAccess;
    private final AuditFailureService auditFailures;

    public RbacService(TenantAccessService tenantAccess, AuditFailureService auditFailures) {
        this.tenantAccess = tenantAccess;
        this.auditFailures = auditFailures;
    }

    @Transactional(readOnly = true)
    public Usuario exigirPermiso(Usuario actor, String permiso, String operacion) {
        if (actor == null || actor.getId() == null) {
            auditFailures.registrarEscalamiento(actor, operacion);
            throw new AccessDeniedException("Actor requerido");
        }

        TenantAccess access = tenantAccess.currentAccess(actor);
        if (!access.permissionCodes().contains(permiso)) {
            auditFailures.registrarEscalamiento(actor, operacion);
            throw new AccessDeniedException("Permiso requerido: " + permiso);
        }
        return access.usuario();
    }

    @Transactional(readOnly = true)
    public Usuario exigirSuperadminSistema(Usuario actor, String operacion) {
        if (actor == null || actor.getId() == null) {
            auditFailures.registrarEscalamiento(actor, operacion);
            throw new AccessDeniedException("SUPERADMIN autenticado requerido");
        }

        TenantAccess access = tenantAccess.currentAccess(actor);
        if (!access.membership().isSuperadmin()) {
            auditFailures.registrarEscalamiento(actor, operacion);
            throw new AccessDeniedException("La operación requiere SUPERADMIN del tenant");
        }
        return access.usuario();
    }

    public TenantAccess accesoActual(Usuario actor) {
        return tenantAccess.currentAccess(actor);
    }
}
