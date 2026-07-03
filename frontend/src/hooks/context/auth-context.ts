import { createContext } from "react";

export interface UserProfile {
  id: number;
  nombreUsuario: string;
  email?: string;
  rol: string;
}

export interface AuthContextProps {
  isAuth: boolean;
  loading: boolean;
  login: (nombreUsuario: string, contrasena: string) => Promise<void>;
  logout: () => Promise<void>;
  accessToken: string | null;
  user: UserProfile | null;
  hasRole: (role: string) => boolean;
}

export const AuthContext = createContext<AuthContextProps | undefined>(undefined);
