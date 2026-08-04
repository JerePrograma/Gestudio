package gestudio.integraciones.jereplatform.api;

import gestudio.auditoria.application.AuditService;
import gestudio.entidades.Usuario;
import gestudio.infra.seguridad.RbacService;
import gestudio.integraciones.jereplatform.application.SourceTenantMapping;
import gestudio.integraciones.jereplatform.application.SourceTenantMapping.Mapping;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;
import java.util.UUID;

import static gestudio.infra.seguridad.PermissionCodes.PERM_CONFIG_ADMIN;

@RestController
@RequestMapping("/api/integraciones/jere-platform/mapping")
public class TenantMappingController {
    private final SourceTenantMapping mappings;
    private final RbacService rbac;
    private final AuditService audit;

    public TenantMappingController(SourceTenantMapping mappings, RbacService rbac, AuditService audit) {
        this.mappings = mappings;
        this.rbac = rbac;
        this.audit = audit;
    }

    @GetMapping
    public MappingResponse current(@AuthenticationPrincipal Usuario actor) {
        rbac.exigirPermiso(actor, PERM_CONFIG_ADMIN, "LEER_MAPPING_JERE_PLATFORM");
        return mappings.current().map(MappingResponse::from).orElse(null);
    }

    @PutMapping
    public MappingResponse configure(@Valid @RequestBody MappingRequest request,
                                     @AuthenticationPrincipal Usuario actor) {
        Usuario authorized = rbac.exigirPermiso(actor, PERM_CONFIG_ADMIN,
                "CONFIGURAR_MAPPING_JERE_PLATFORM");
        Mapping mapping = mappings.configure(
                request.externalOrganizationId(), request.externalTenantId(), authorized.getId());
        audit.registrar("INTEGRACION", "MAPPING_JERE_PLATFORM_CONFIGURADO", "TENANT", null,
                authorized, "jere-mapping:" + mapping.internalTenantId() + ":" + mapping.configVersion(),
                Map.of("sourceType", mapping.sourceType(), "configVersion", mapping.configVersion(),
                        "externalOrganizationId", mapping.organizationId(),
                        "externalTenantId", mapping.externalTenantId().toString()));
        return MappingResponse.from(mapping);
    }

    public record MappingRequest(
            @NotBlank String externalOrganizationId,
            @NotNull UUID externalTenantId
    ) {
    }

    public record MappingResponse(
            UUID internalTenantId,
            String externalOrganizationId,
            UUID externalTenantId,
            String sourceType,
            long configVersion
    ) {
        static MappingResponse from(Mapping mapping) {
            return new MappingResponse(mapping.internalTenantId(), mapping.organizationId(),
                    mapping.externalTenantId(), mapping.sourceType(), mapping.configVersion());
        }
    }
}
