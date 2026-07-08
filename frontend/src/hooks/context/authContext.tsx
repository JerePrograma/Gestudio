import React, { useEffect, useState, type ReactNode } from "react";
import { useNavigate } from "react-router-dom";
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
  profileHasAnyRole,
  profileHasPermission,
  profileHasRole,
  sanitizeUserProfile,
  type UserProfile,
} from "./auth-context";

export const AuthProvider: React.FC<{ children: ReactNode }> = ({
  children,
}) => {
  const [loading, setLoading] = useState(true);
  const [session, setSession] = useState(getAuthSession);
  const navigate = useNavigate();

  const isAuth = session.accessToken !== null && session.user !== null;
  const user: UserProfile | null = session.user;

  useEffect(() => subscribeAuthSession(setSession), []);

  useEffect(() => {
    refreshSession()
      .catch(() => clearAuthStorage())
      .finally(() => setLoading(false));
  }, []);

  const login = async (
    nombreUsuario: string,
    contrasena: string,
  ): Promise<void> => {
    clearAuthStorage();

    const { data } = await api.post(
      "/login",
      { nombreUsuario, contrasena },
      { withCredentials: true },
    );

    setAuthSession(data.accessToken, sanitizeUserProfile(data.usuario));
  };

  const logout = async (): Promise<void> => {
    try {
      await api.post("/login/logout", {}, { withCredentials: true });
    } finally {
      clearAuthStorage();
      navigate("/login");
    }
  };

  const hasRole = (role: string): boolean => profileHasRole(user, role);

  const hasAnyRole = (roles: string[]): boolean =>
    profileHasAnyRole(user, roles);

  const hasPermission = (permission: string): boolean =>
    profileHasPermission(user, permission);

  const hasAllPermissions = (permissions: string[]): boolean =>
    profileHasAllPermissions(user, permissions);

  const hasAnyPermission = (permissions: string[]): boolean =>
    profileHasAnyPermission(user, permissions);

  return (
    <AuthContext.Provider
      value={{
        isAuth,
        loading,
        login,
        logout,
        accessToken: session.accessToken,
        user,
        hasRole,
        hasAnyRole,
        hasPermission,
        hasAllPermissions,
        hasAnyPermission,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};