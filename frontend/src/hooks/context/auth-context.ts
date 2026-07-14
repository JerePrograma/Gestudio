import { createContext } from "react";
import { PERMISSIONS, type PermissionCode } from "../../config/permissions";

const PERMISSION_CODES = new Set<string>(Object.values(PERMISSIONS));

export interface UserProfile {
  id: number;
  nombreUsuario: string;
  email?: string;
  roles: string[];
  permisos: string[];
  activo: boolean;
}

export interface AuthContextProps {
  isAuth: boolean;
  loading: boolean;
  login: (nombreUsuario: string, contrasena: string) => Promise<void>;
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
): boolean => accessToken !== null && user?.activo === true;

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
    !raw.permisos.every((permission) => typeof permission === "string")
  ) {
    throw new Error("Perfil de usuario inválido");
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
  };
};

export const AuthContext = createContext<AuthContextProps | undefined>(
  undefined,
);
