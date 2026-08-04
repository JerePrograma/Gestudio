import { createContext } from "react";
import { PERMISSIONS, type PermissionCode } from "../../config/permissions";
import type { TenantStatus, TenantSummary } from "../../types/types";

const PERMISSION_CODES = new Set<string>(Object.values(PERMISSIONS));

export interface UserProfile {
  id: number;
  nombreUsuario: string;
  email?: string;
  roles: string[];
  permisos: string[];
  activo: boolean;
  tenantActivo: TenantSummary;
  tenantsDisponibles: TenantSummary[];
}

export interface TenantSelection {
  selectionRequired: true;
  tenants: TenantSummary[];
}

export interface AuthContextProps {
  isAuth: boolean;
  loading: boolean;
  login: (
    nombreUsuario: string,
    contrasena: string,
    tenantId?: string,
  ) => Promise<TenantSelection | null>;
  switchTenant: (tenantId: string) => Promise<void>;
  logout: () => Promise<void>;
  accessToken: string | null;
  user: UserProfile | null;

  hasPermission: (permission: PermissionCode) => boolean;
  hasAllPermissions: (permissions: readonly PermissionCode[]) => boolean;
  hasAnyPermission: (permissions: readonly PermissionCode[]) => boolean;
}

export const profileHasPermission = (
  user: UserProfile | null,
  permission: PermissionCode,
): boolean => user?.permisos.includes(permission) ?? false;

export const profileHasAllPermissions = (
  user: UserProfile | null,
  permissions: readonly PermissionCode[],
): boolean =>
  permissions.every((permission) => profileHasPermission(user, permission));

export const profileHasAnyPermission = (
  user: UserProfile | null,
  permissions: readonly PermissionCode[],
): boolean =>
  permissions.some((permission) => profileHasPermission(user, permission));

export const isAuthenticatedSession = (
  accessToken: string | null,
  user: UserProfile | null,
): boolean =>
  accessToken !== null &&
  user?.activo === true &&
  user.tenantActivo.estado === "ACTIVE";

const TENANT_STATUSES = new Set<TenantStatus>([
  "ACTIVE",
  "SUSPENDED",
  "ARCHIVED",
]);
const UUID_PATTERN = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;

export const sanitizeTenantSummary = (value: unknown): TenantSummary => {
  if (!value || typeof value !== "object") {
    throw new Error("Organización inválida");
  }

  const raw = value as Record<string, unknown>;

  if (
    typeof raw.id !== "string" ||
    !UUID_PATTERN.test(raw.id) ||
    typeof raw.codigo !== "string" ||
    raw.codigo.length === 0 ||
    typeof raw.nombre !== "string" ||
    raw.nombre.length === 0 ||
    typeof raw.estado !== "string" ||
    !TENANT_STATUSES.has(raw.estado as TenantStatus)
  ) {
    throw new Error("Organización inválida");
  }

  return {
    id: raw.id,
    codigo: raw.codigo,
    nombre: raw.nombre,
    estado: raw.estado as TenantStatus,
  };
};

export const sanitizeUserProfile = (value: unknown): UserProfile => {
  if (!value || typeof value !== "object") {
    throw new Error("Perfil de usuario inválido");
  }

  const raw = value as Record<string, unknown>;

  if (
    typeof raw.id !== "number" ||
    typeof raw.nombreUsuario !== "string" ||
    typeof raw.activo !== "boolean" ||
    !Array.isArray(raw.roles) ||
    !raw.roles.every((role) => typeof role === "string" && /^[A-Z][A-Z0-9_]{2,95}$/.test(role)) ||
    !Array.isArray(raw.permisos) ||
    !raw.permisos.every((permission) => typeof permission === "string") ||
    !Array.isArray(raw.tenantsDisponibles)
  ) {
    throw new Error("Perfil de usuario inválido");
  }

  const tenantActivo = sanitizeTenantSummary(raw.tenantActivo);
  const tenantsDisponibles = [
    ...new Map(
      raw.tenantsDisponibles
        .map(sanitizeTenantSummary)
        .map((tenant) => [tenant.id, tenant]),
    ).values(),
  ];

  if (
    tenantActivo.estado !== "ACTIVE" ||
    !tenantsDisponibles.some(
      (tenant) => tenant.id === tenantActivo.id && tenant.estado === "ACTIVE",
    )
  ) {
    throw new Error("Organización activa inválida");
  }

  return {
    id: raw.id,
    nombreUsuario: raw.nombreUsuario,
    email: typeof raw.email === "string" ? raw.email : undefined,
    roles: [...new Set(raw.roles.filter((role): role is string => typeof role === "string"))],
    permisos: [...new Set(raw.permisos.filter(
      (permission): permission is string => typeof permission === "string" && PERMISSION_CODES.has(permission),
    ))],
    activo: raw.activo,
    tenantActivo,
    tenantsDisponibles,
  };
};

export const AuthContext = createContext<AuthContextProps | undefined>(
  undefined,
);
