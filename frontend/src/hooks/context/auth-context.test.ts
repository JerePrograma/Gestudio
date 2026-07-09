import { describe, expect, it } from "vitest";
import { profileHasPermission, profileHasRole, type UserProfile } from "./auth-context";

const user: UserProfile = {
  id: 1,
  nombreUsuario: "operador",
  roles: ["RECEPCION", "COBRANZAS"],
  permisos: ["PERM_APP_ACCESO", "PERM_PAGOS_REGISTRAR"],
  activo: true,
};

describe("autorización del perfil", () => {
  it("reconoce múltiples roles sin jerarquías implícitas", () => {
    expect(profileHasRole(user, "ROLE_RECEPCION")).toBe(true);
    expect(profileHasRole(user, "RECEPCION")).toBe(true);
    expect(profileHasRole(user, "ADMINISTRADOR")).toBe(false);
  });

  it("normaliza y verifica permisos efectivos", () => {
    expect(profileHasPermission(user, "PERM_PAGOS_REGISTRAR")).toBe(true);
    expect(profileHasPermission(user, "PAGOS_REGISTRAR")).toBe(true);
    expect(profileHasPermission(user, "PERM_PAGOS_ANULAR")).toBe(false);
  });
});