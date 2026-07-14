import { describe, expect, it } from "vitest";
import { PERMISSIONS, type PermissionCode } from "./permissions";
import { filterNavigationItems, navigationItems, type NavigationItem } from "./navigation";

const visibleIds = (permissions: readonly PermissionCode[]): string[] => {
  const allowed = new Set<PermissionCode>(permissions);
  const flatten = (items: NavigationItem[]): string[] => items.flatMap((item) => [
    item.id,
    ...flatten(item.items ?? []),
  ]);

  return flatten(filterNavigationItems(navigationItems, (permission) => allowed.has(permission)));
};

describe("navegación RBAC", () => {
  it.each([
    ["alumnos", PERMISSIONS.ALUMNOS_LEER],
    ["cobranza", PERMISSIONS.PAGOS_REGISTRAR],
    ["pagos", PERMISSIONS.PAGOS_LEER],
    ["caja", PERMISSIONS.CAJA_LEER],
    ["egresos", PERMISSIONS.EGRESOS_ADMIN],
    ["stocks", PERMISSIONS.STOCK_LEER],
    ["inscripciones", PERMISSIONS.INSCRIPCIONES_LEER],
    ["asistencias", PERMISSIONS.ASISTENCIAS_LEER],
    ["profesores", PERMISSIONS.PROFESORES_LEER],
    ["disciplinas", PERMISSIONS.DISCIPLINAS_LEER],
    ["usuarios", PERMISSIONS.USUARIOS_ADMIN],
    ["roles", PERMISSIONS.ROLES_ADMIN],
  ] as const)("exige APP y el permiso funcional para %s", (itemId, functionalPermission) => {
    expect(visibleIds([PERMISSIONS.APP_ACCESS])).not.toContain(itemId);
    expect(visibleIds([functionalPermission])).not.toContain(itemId);
    expect(visibleIds([PERMISSIONS.APP_ACCESS, functionalPermission])).toContain(itemId);
  });

  it("exige lectura de reportes y disciplinas para el reporte académico", () => {
    expect(visibleIds([PERMISSIONS.APP_ACCESS, PERMISSIONS.REPORTES_LEER])).not.toContain("reportes");
    expect(visibleIds([PERMISSIONS.APP_ACCESS, PERMISSIONS.REPORTES_LEER, PERMISSIONS.DISCIPLINAS_LEER])).toContain("reportes");
  });

  it("no publica WebSocket, Observaciones ni el rol PROFESOR", () => {
    const ids = navigationItems.flatMap((item) => [item.id, ...(item.items ?? []).map((child) => child.id)]);

    expect(ids).not.toContain("observaciones");
    expect(ids).not.toContain("websocket");
    expect(ids).not.toContain("profesor-role");
  });
});
