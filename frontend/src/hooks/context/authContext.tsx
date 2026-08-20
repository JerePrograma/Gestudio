import axios from "axios";
import React, { useEffect, useRef, useState, type ReactNode } from "react";
import { useLocation, useNavigate } from "react-router";
import api, { clearAuthStorage } from "../../api/axiosConfig";
import {
  getAuthSession,
  refreshSession,
  setPlatformAuthSession,
  setTenantAuthSession,
  subscribeAuthSession,
} from "../../api/authSession";
import {
  AuthContext,
  profileHasAllPermissions,
  profileHasAnyPermission,
  profileHasPermission,
  isAuthenticatedSession,
  isPlatformAuthenticatedSession,
  sanitizePlatformProfile,
  sanitizeUserProfile,
  sanitizeTenantSummary,
  type PlatformMfaMethod,
  type PlatformProfile,
  type SessionScope,
  type TenantSelection,
  type UserProfile,
} from "./auth-context";
import type { PermissionCode } from "../../config/permissions";
import { resetTenantClientState } from "../queryClient";

interface LoginSuccessResponse {
  accessToken: string;
  usuario: unknown;
}

interface PlatformLoginSuccessResponse {
  accessToken: string;
  refreshExpiresAt: string;
  profile: unknown;
}

const parseTenantSelection = (value: unknown): TenantSelection | null => {
  if (!value || typeof value !== "object") return null;
  const raw = value as Record<string, unknown>;

  if (raw.selectionRequired !== true || !Array.isArray(raw.tenants)) return null;

  return {
    selectionRequired: true,
    tenants: raw.tenants.map(sanitizeTenantSummary),
  };
};

export const AuthProvider: React.FC<{ children: ReactNode }> = ({
  children,
}) => {
  const [loading, setLoading] = useState(true);
  const [session, setSession] = useState(getAuthSession);
  const navigate = useNavigate();
  const location = useLocation();
  const bootstrapScope = useRef<SessionScope>(
    location.pathname.startsWith("/platform") ? "PLATFORM" : "TENANT",
  );

  const user: UserProfile | null = session.scope === "TENANT" ? session.profile : null;
  const platformUser: PlatformProfile | null = session.scope === "PLATFORM" ? session.profile : null;
  const isAuth = session.scope === "TENANT"
    ? isAuthenticatedSession(session.accessToken, user)
    : session.scope === "PLATFORM"
      ? isPlatformAuthenticatedSession(session.accessToken, platformUser)
      : false;
  const sessionScopeKey = session.scope === "TENANT"
    ? `${user?.id}:${user?.tenantActivo.id}`
    : session.scope === "PLATFORM"
      ? `platform:${platformUser?.id}`
    : "anonymous";

  useEffect(() => subscribeAuthSession(setSession), []);

  useEffect(() => {
    refreshSession(bootstrapScope.current)
      .catch((error) => axios.isCancel(error) ? undefined : clearAuthStorage())
      .finally(() => setLoading(false));
  }, []);

  const login = async (
    nombreUsuario: string,
    contrasena: string,
    tenantId?: string,
  ): Promise<TenantSelection | null> => {
    await clearAuthStorage();

    try {
      const { data } = await api.post<LoginSuccessResponse>(
        "/login",
        { nombreUsuario, contrasena, ...(tenantId ? { tenantId } : {}) },
        { withCredentials: true },
      );
      const profile = sanitizeUserProfile(data.usuario);

      if (tenantId && profile.tenantActivo.id !== tenantId) {
        throw new Error("La sesión no corresponde a la organización seleccionada");
      }

      setTenantAuthSession(data.accessToken, profile);
      return null;
    } catch (error) {
      const selection = axios.isAxiosError(error) && error.response?.status === 409
        ? parseTenantSelection(error.response.data)
        : null;

      if (selection) return selection;
      throw error;
    }
  };

  const platformLogin = async (
    nombreUsuario: string,
    contrasena: string,
    metodo: PlatformMfaMethod,
    codigo: string,
  ): Promise<void> => {
    await clearAuthStorage();
    const { data } = await api.post<PlatformLoginSuccessResponse>(
      "/platform/auth/login",
      { nombreUsuario, contrasena, metodo, codigo },
      { withCredentials: true },
    );
    const profile = sanitizePlatformProfile(data.profile);
    setPlatformAuthSession(data.accessToken, profile);
  };

  const switchTenant = async (tenantId: string): Promise<void> => {
    if (session.scope !== "TENANT") {
      throw new Error("La sesión de plataforma no puede cambiar de organización");
    }

    const allowed = user?.tenantsDisponibles.some(
      (tenant) => tenant.id === tenantId && tenant.estado === "ACTIVE",
    );

    if (!allowed) throw new Error("Organización no disponible");
    if (tenantId === user?.tenantActivo.id) return;

    setLoading(true);
    try {
      await resetTenantClientState();
      const { data } = await api.post<LoginSuccessResponse>(
        "/login/tenant",
        { tenantId },
        { withCredentials: true },
      );
      const profile = sanitizeUserProfile(data.usuario);

      if (profile.tenantActivo.id !== tenantId) {
        throw new Error("La sesión no corresponde a la organización seleccionada");
      }

      setTenantAuthSession(data.accessToken, profile);
    } finally {
      setLoading(false);
    }
  };

  const logout = async (): Promise<void> => {
    const logoutScope = session.scope;
    setLoading(true);
    try {
      await resetTenantClientState();
      if (logoutScope) {
        const endpoint = logoutScope === "PLATFORM"
          ? "/platform/auth/logout"
          : "/login/logout";
        await api.post(endpoint, {}, { withCredentials: true });
      }
    } finally {
      await clearAuthStorage();
      navigate(logoutScope === "PLATFORM" ? "/platform/login" : "/login");
      setLoading(false);
    }
  };

  const hasPermission = (permission: PermissionCode): boolean =>
    profileHasPermission(user, permission);

  const hasAllPermissions = (permissions: readonly PermissionCode[]): boolean =>
    profileHasAllPermissions(user, permissions);

  const hasAnyPermission = (permissions: readonly PermissionCode[]): boolean =>
    profileHasAnyPermission(user, permissions);

  return (
    <AuthContext.Provider
      value={{
        isAuth,
        loading,
        scope: session.scope,
        profile: session.profile,
        login,
        platformLogin,
        switchTenant,
        logout,
        accessToken: session.accessToken,
        user,
        platformUser,
        hasPermission,
        hasAllPermissions,
        hasAnyPermission,
      }}
    >
      <React.Fragment key={sessionScopeKey}>{children}</React.Fragment>
    </AuthContext.Provider>
  );
};
