package ledance.dto.rol.request;

import jakarta.validation.constraints.NotNull;

import java.util.Set;

public record RolPermisosRequest(@NotNull Set<String> permisos) {
}
