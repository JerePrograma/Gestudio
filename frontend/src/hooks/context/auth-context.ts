import { createContext } from "react";

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

  /**
   * Compatibilidad transicional.
   * La autorización funcional debe preferir permisos.
   */
  hasRole: (role: string) => boolean;
  hasAnyRole: (roles: string[]) => boolean;

  hasPermission: (permission: string) => boolean;
  hasAllPermissions: (permissions: string[]) => boolean;
  hasAnyPermission: (permissions: string[]) => boolean;
}

const normalizeAuthority = (value: string, prefix: string): string => {
  const normalized = value.trim().toUpperCase();
  return normalized.startsWith(prefix)
    ? normalized.substring(prefix.length)
    : normalized;
};

const hasAuthority = (
  values: string[] | undefined,
  expected: string,
  prefix: string,
): boolean => {
  const normalizedExpected = normalizeAuthority(expected, prefix);

  return (
    values?.some(
      (value) => normalizeAuthority(value, prefix) === normalizedExpected,
    ) ?? false
  );
};

export const profileHasRole = (
  user: UserProfile | null,
  role: string,
): boolean => hasAuthority(user?.roles, role, "ROLE_");

export const profileHasAnyRole = (
  user: UserProfile | null,
  roles: string[],
): boolean => roles.some((role) => profileHasRole(user, role));

export const profileHasPermission = (
  user: UserProfile | null,
  permission: string,
): boolean => hasAuthority(user?.permisos, permission, "PERM_");

export const profileHasAllPermissions = (
  user: UserProfile | null,
  permissions: string[],
): boolean =>
  permissions.every((permission) => profileHasPermission(user, permission));

export const profileHasAnyPermission = (
  user: UserProfile | null,
  permissions: string[],
): boolean =>
  permissions.some((permission) => profileHasPermission(user, permission));

export const sanitizeUserProfile = (value: unknown): UserProfile => {
  const raw = value as Partial<UserProfile>;

  if (
    !raw ||
    typeof raw.id !== "number" ||
    typeof raw.nombreUsuario !== "string" ||
    typeof raw.activo !== "boolean"
  ) {
    throw new Error("Perfil de usuario inválido");
  }

  return {
    id: raw.id,
    nombreUsuario: raw.nombreUsuario,
    email: raw.email,
    roles: Array.isArray(raw.roles) ? raw.roles : [],
    permisos: Array.isArray(raw.permisos) ? raw.permisos : [],
    activo: raw.activo,
  };
};

export const AuthContext = createContext<AuthContextProps | undefined>(
  undefined,
);