import React, { useEffect, useState, type ReactNode } from "react";
import { useNavigate } from "react-router-dom";
import { toast } from "react-toastify";
import api, { clearAuthStorage } from "../../api/axiosConfig";
import { setAccessToken as setSessionAccessToken } from "../../api/authSession";
import { AuthContext, type UserProfile } from "./auth-context";

export const AuthProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const [isAuth, setIsAuth] = useState(false);
  const [loading, setLoading] = useState(true);
  const [accessToken, setAccessToken] = useState<string | null>(null);
  const [user, setUser] = useState<UserProfile | null>(null);
  const navigate = useNavigate();

  useEffect(() => {
    api.post("/login/refresh", {}, { withCredentials: true })
      .then(({ data }) => {
        setSessionAccessToken(data.accessToken);
        setAccessToken(data.accessToken);
        setUser(data.usuario);
        setIsAuth(true);
      })
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
      setSessionAccessToken(data.accessToken);
      setAccessToken(data.accessToken);
      setIsAuth(true);
      setUser(data.usuario);
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
      setAccessToken(null);
      setIsAuth(false);
      setUser(null);
      navigate("/login");
    }
  };

  const hasRole = (role: string): boolean =>
    user !== null && user.rol.trim().toUpperCase() === role.trim().toUpperCase();

  return (
    <AuthContext.Provider value={{
      isAuth, loading, login, logout, accessToken, user, hasRole,
    }}>
      {children}
    </AuthContext.Provider>
  );
};
