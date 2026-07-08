import { describe, expect, it } from "vitest";
import { filterNavigationItems, navigationItems } from "./navigation";

describe("navegación RBAC", () => {
  it("muestra sólo módulos con permiso efectivo", () => {
    const visibles = filterNavigationItems(navigationItems, (permiso) => permiso === "ALUMNOS_READ");
    expect(visibles.map((item) => item.id)).toContain("alumnos");
    expect(visibles.map((item) => item.id)).not.toContain("pagos");
    expect(visibles.map((item) => item.id)).not.toContain("seguridad");
  });
});
