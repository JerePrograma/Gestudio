import { describe, expect, it } from "vitest";
import { PERMISSIONS } from "./permissions";
import { filterNavigationItems, navigationItems } from "./navigation";

describe("navegación RBAC", () => {
  it("muestra módulos generales sólo con permiso de acceso a la app", () => {
    const visibles = filterNavigationItems(
      navigationItems,
      (permiso) => permiso === PERMISSIONS.APP_ACCESS,
    );

    const ids = visibles.map((item) => item.id);

    expect(ids).toContain("alumnos");
    expect(ids).toContain("pagos");
    expect(ids).toContain("caja");
    expect(ids).toContain("administracion");
    expect(ids).toContain("academico");
    expect(ids).toContain("reportes");

    expect(ids).not.toContain("cobranza");
    expect(ids).not.toContain("seguridad");
  });

  it("muestra cobranza cuando existe permiso para registrar pagos", () => {
    const visibles = filterNavigationItems(
      navigationItems,
      (permiso) => permiso === PERMISSIONS.PAGOS_REGISTRAR,
    );

    const ids = visibles.map((item) => item.id);

    expect(ids).toContain("cobranza");
    expect(ids).not.toContain("pagos");
    expect(ids).not.toContain("alumnos");
    expect(ids).not.toContain("seguridad");
  });

  it("mantiene seguridad oculta sin permisos administrativos", () => {
    const visibles = filterNavigationItems(
      navigationItems,
      (permiso) => permiso === PERMISSIONS.APP_ACCESS,
    );

    expect(visibles.map((item) => item.id)).not.toContain("seguridad");
  });
});