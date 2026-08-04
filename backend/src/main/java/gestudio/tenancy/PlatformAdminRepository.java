package gestudio.tenancy;

import org.springframework.data.repository.Repository;

public interface PlatformAdminRepository extends Repository<PlatformAdmin, Long> {
    boolean existsByUsuarioIdAndActiveTrue(Long usuarioId);
}
