import { describe, expect, it } from "vitest";
import { PERMISSIONS } from "../../config/permissions";
import { isAuthenticatedSession, profileHasPermission, sanitizeUserProfile, type UserProfile } from "./auth-context";

const user: UserProfile = {
  id: 1,
  nombreUsuario: "operador",
  roles: ["RECEPCION", "COBRANZAS"],
  permisos: [PERMISSIONS.APP_ACCESS, PERMISSIONS.PAGOS_REGISTRAR],
  activo: true,
};

describe("autorización del perfil", () => {
  it("exige permisos canónicos exactos", () => {
    expect(profileHasPermission(user, PERMISSIONS.PAGOS_REGISTRAR)).toBe(true);
    expect(profileHasPermission(user, PERMISSIONS.PAGOS_ANULAR)).toBe(false);
    expect(profileHasPermission({ ...user, permisos: ["PAGOS_REGISTRAR"] }, PERMISSIONS.PAGOS_REGISTRAR)).toBe(false);
  });

  it("ignora permisos personalizados para los gates tipados y rechaza arrays malformados", () => {
    expect(sanitizeUserProfile({
      ...user,
      permisos: [PERMISSIONS.APP_ACCESS, "PERM_CUSTOM_LEGACY"],
    }).permisos).toEqual([PERMISSIONS.APP_ACCESS]);
    expect(() => sanitizeUserProfile({ ...user, roles: ["CAJA", 1] }))
      .toThrow("Perfil de usuario inválido");
    expect(() => sanitizeUserProfile({ ...user, permisos: [PERMISSIONS.APP_ACCESS, 1] }))
      .toThrow("Perfil de usuario inválido");

    expect(sanitizeUserProfile({
      ...user,
      roles: ["CAJA", "CAJA"],
      permisos: [PERMISSIONS.APP_ACCESS, PERMISSIONS.APP_ACCESS],
    })).toMatchObject({
      roles: ["CAJA"],
      permisos: [PERMISSIONS.APP_ACCESS],
    });
  });

  it("no considera autenticado a un usuario inactivo", () => {
    expect(isAuthenticatedSession("token", user)).toBe(true);
    expect(isAuthenticatedSession("token", { ...user, activo: false })).toBe(false);
    expect(isAuthenticatedSession(null, user)).toBe(false);
  });
});
