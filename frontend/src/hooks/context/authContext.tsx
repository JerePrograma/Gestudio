import axios from "axios";
import React, { useEffect, useState, type ReactNode } from "react";
import { useNavigate } from "react-router";
import api, { clearAuthStorage } from "../../api/axiosConfig";
import {
  getAuthSession,
  refreshSession,
  setAuthSession,
  subscribeAuthSession,
} from "../../api/authSession";
import {
  AuthContext,
  profileHasAllPermissions,
  profileHasAnyPermission,
  profileHasPermission,
  isAuthenticatedSession,
  sanitizeUserProfile,
  sanitizeTenantSummary,
  type TenantSelection,
  type UserProfile,
} from "./auth-context";
import type { PermissionCode } from "../../config/permissions";
import { resetTenantClientState } from "../queryClient";

interface LoginSuccessResponse {
  accessToken: string;
  usuario: unknown;
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

  const isAuth = isAuthenticatedSession(session.accessToken, session.user);
  const user: UserProfile | null = session.user;
  const sessionScopeKey = user
    ? `${user.id}:${user.tenantActivo.id}`
    : "anonymous";

  useEffect(() => subscribeAuthSession(setSession), []);

  useEffect(() => {
    refreshSession()
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

      setAuthSession(data.accessToken, profile);
      return null;
    } catch (error) {
      const selection = axios.isAxiosError(error) && error.response?.status === 409
        ? parseTenantSelection(error.response.data)
        : null;

      if (selection) return selection;
      throw error;
    }
  };

  const switchTenant = async (tenantId: string): Promise<void> => {
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

      setAuthSession(data.accessToken, profile);
    } finally {
      setLoading(false);
    }
  };

  const logout = async (): Promise<void> => {
    setLoading(true);
    try {
      await resetTenantClientState();
      await api.post("/login/logout", {}, { withCredentials: true });
    } finally {
      await clearAuthStorage();
      navigate("/login");
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
        login,
        switchTenant,
        logout,
        accessToken: session.accessToken,
        user,
        hasPermission,
        hasAllPermissions,
        hasAnyPermission,
      }}
    >
      <React.Fragment key={sessionScopeKey}>{children}</React.Fragment>
    </AuthContext.Provider>
  );
};
