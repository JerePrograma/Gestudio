package ledance.auditoria.application;

import ledance.entidades.Usuario;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.util.Map;

@Service
public class AuditFailureService {
    private final AuditService audit;

    public AuditFailureService(AuditService audit) {
        this.audit = audit;
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void registrarAnonimo(String accion, String usernameSnapshot, Map<String, ?> metadata) {
        audit.registrarAnonimo("SEGURIDAD", accion, usernameSnapshot, metadata);
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void registrarEscalamiento(Usuario actor, String operacion) {
        audit.registrar("SEGURIDAD", "ESCALAMIENTO_RECHAZADO", "USUARIO", null,
                actor, null, Map.of("operacion", operacion));
    }
}
