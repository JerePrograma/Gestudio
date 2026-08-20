import { describe, expect, it } from "vitest";
import { PERMISSIONS } from "../../config/permissions";
import {
  isAuthenticatedSession,
  isPlatformAuthenticatedSession,
  profileHasAllPermissions,
  profileHasAnyPermission,
  profileHasPermission,
  sanitizePlatformProfile,
  sanitizeTenantSummary,
  sanitizeUserProfile,
  type UserProfile,
} from "./auth-context";

const tenant = {
  id: "00000000-0000-0000-0000-0000000000a1",
  codigo: "ACADEMIA_A",
  nombre: "Academia A",
  estado: "ACTIVE" as const,
};

const user: UserProfile = {
  id: 1,
  nombreUsuario: "operador",
  roles: ["RECEPCION", "COBRANZAS"],
  permisos: [PERMISSIONS.APP_ACCESS, PERMISSIONS.PAGOS_REGISTRAR],
  activo: true,
  tenantActivo: tenant,
  tenantsDisponibles: [tenant],
};

describe("autorización del perfil", () => {
  it("exige permisos canónicos exactos", () => {
    expect(profileHasPermission(user, PERMISSIONS.PAGOS_REGISTRAR)).toBe(true);
    expect(profileHasPermission(user, PERMISSIONS.PAGOS_ANULAR)).toBe(false);
    expect(profileHasPermission({ ...user, permisos: ["PAGOS_REGISTRAR"] }, PERMISSIONS.PAGOS_REGISTRAR)).toBe(false);
    expect(profileHasPermission(null, PERMISSIONS.PAGOS_REGISTRAR)).toBe(false);
    expect(profileHasAllPermissions(user, [PERMISSIONS.APP_ACCESS, PERMISSIONS.PAGOS_REGISTRAR])).toBe(true);
    expect(profileHasAllPermissions(user, [PERMISSIONS.APP_ACCESS, PERMISSIONS.PAGOS_ANULAR])).toBe(false);
    expect(profileHasAnyPermission(user, [PERMISSIONS.PAGOS_ANULAR, PERMISSIONS.PAGOS_REGISTRAR])).toBe(true);
    expect(profileHasAnyPermission(user, [PERMISSIONS.PAGOS_ANULAR])).toBe(false);
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

  it("exige una organización activa incluida en las memberships disponibles", () => {
    expect(() => sanitizeTenantSummary(null)).toThrow("Organización inválida");
    expect(() => sanitizeTenantSummary({ ...tenant, estado: "DESCONOCIDO" }))
      .toThrow("Organización inválida");
    expect(() => sanitizeUserProfile(null)).toThrow("Perfil de usuario inválido");
    expect(() => sanitizeUserProfile({
      ...user,
      tenantActivo: { ...tenant, estado: "SUSPENDED" },
    })).toThrow("Organización activa inválida");
    expect(() => sanitizeUserProfile({
      ...user,
      tenantsDisponibles: [],
    })).toThrow("Organización activa inválida");
    expect(() => sanitizeUserProfile({
      ...user,
      tenantActivo: undefined,
    })).toThrow("Organización inválida");
    expect(sanitizeUserProfile({ ...user, email: "operador@example.test" }).email)
      .toBe("operador@example.test");
  });

  it("acepta sólo perfiles PLATFORM con autoridad global y MFA activo", () => {
    expect(() => sanitizePlatformProfile(null)).toThrow("Perfil de plataforma inválido");
    const platform = sanitizePlatformProfile({
      id: 9,
      nombreUsuario: "global-admin",
      authorities: ["PLATFORM_SUPERADMIN", "PLATFORM_SUPERADMIN"],
      mfaEnabled: true,
      scope: "PLATFORM",
    });

    expect(platform.authorities).toEqual(["PLATFORM_SUPERADMIN"]);
    expect(isPlatformAuthenticatedSession("platform-access", platform)).toBe(true);
    expect(() => sanitizePlatformProfile({ ...platform, scope: "TENANT" })).toThrow("Perfil de plataforma inválido");
    expect(() => sanitizePlatformProfile({ ...platform, authorities: [] })).toThrow("Perfil de plataforma sin autoridad requerida");
    expect(() => sanitizePlatformProfile({ ...platform, mfaEnabled: false })).toThrow("Perfil de plataforma inválido");
    expect(isPlatformAuthenticatedSession(null, platform)).toBe(false);
    expect(isPlatformAuthenticatedSession("platform-access", null)).toBe(false);
  });
});
