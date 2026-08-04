package gestudio.tenancy;

import gestudio.entidades.Usuario;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;
import gestudio.auditoria.application.AuditFailureService;

@Service
public class PlatformAdminAccessService {
    private final PlatformAdminRepository admins;
    private final AuditFailureService auditFailures;

    public PlatformAdminAccessService(PlatformAdminRepository admins, AuditFailureService auditFailures) {
        this.admins = admins;
        this.auditFailures = auditFailures;
    }

    public void requireProvisioningCapability(Usuario actor, String operation) {
        if (actor == null || actor.getId() == null || !actor.isEnabled()
                || !admins.existsByUsuarioIdAndActiveTrue(actor.getId())) {
            auditFailures.registrarEscalamiento(actor, operation);
            throw new AccessDeniedException("Platform provisioning capability required");
        }
    }
}
