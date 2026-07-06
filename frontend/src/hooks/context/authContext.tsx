import React, { useEffect, useState, type ReactNode } from "react";
import { useNavigate } from "react-router-dom";
import { toast } from "react-toastify";
import api, { clearAuthStorage } from "../../api/axiosConfig";
import {
  getAuthSession,
  refreshSession,
  setAuthSession,
  subscribeAuthSession,
} from "../../api/authSession";
import { AuthContext, type UserProfile } from "./auth-context";

export const AuthProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
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

  useEffect(() => {
    if (!loading && !isAuth && window.location.pathname !== "/login") navigate("/login");
  }, [loading, isAuth, navigate]);

  const login = async (nombreUsuario: string, contrasena: string): Promise<void> => {
    try {
      const { data } = await api.post(
        "/login",
        { nombreUsuario, contrasena },
        { withCredentials: true },
      );
      setAuthSession(data.accessToken, data.usuario);
    } catch (error) {
      toast.error("Error al iniciar sesión");
      throw error;
    }
  };

  const logout = async (): Promise<void> => {
    try {
      await api.post("/login/logout", {}, { withCredentials: true });
    } finally {
      clearAuthStorage();
      navigate("/login");
    }
  };

  const hasRole = (role: string): boolean =>
    user !== null && user.rol.trim().toUpperCase() === role.trim().toUpperCase();

  return (
    <AuthContext.Provider value={{
      isAuth, loading, login, logout, accessToken: session.accessToken, user, hasRole,
    }}>
      {children}
    </AuthContext.Provider>
  );
};
