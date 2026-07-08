import { createContext } from "react";

export interface UserProfile {
  id: number;
  nombreUsuario: string;
  email?: string;
  roles: string[];
  permisos: string[];
}

export interface AuthContextProps {
  isAuth: boolean;
  loading: boolean;
  login: (nombreUsuario: string, contrasena: string) => Promise<void>;
  logout: () => Promise<void>;
  accessToken: string | null;
  user: UserProfile | null;
  hasRole: (role: string) => boolean;
  hasAnyRole: (roles: string[]) => boolean;
  hasPermission: (permission: string) => boolean;
  hasAnyPermission: (permissions: string[]) => boolean;
}

const normalize = (value: string, prefix: string): string =>
  value.trim().toUpperCase().replace(new RegExp(`^${prefix}`), "");

export const profileHasRole = (user: UserProfile | null, role: string): boolean =>
  user?.roles.some((value) => normalize(value, "ROLE_") === normalize(role, "ROLE_")) ?? false;

export const profileHasPermission = (user: UserProfile | null, permission: string): boolean =>
  user?.permisos.some((value) => normalize(value, "PERM_") === normalize(permission, "PERM_")) ?? false;

export const AuthContext = createContext<AuthContextProps | undefined>(undefined);
