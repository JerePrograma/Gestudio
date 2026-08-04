import axios from "axios";
import { API_BASE_URL } from "../config/environment";
import {
  sanitizeUserProfile,
  type UserProfile,
} from "../hooks/context/auth-context";
import { tenantRequestSignal } from "../hooks/queryClient";

export interface AuthSession {
  accessToken: string | null;
  user: UserProfile | null;
}

interface ActiveAuthSession {
  accessToken: string;
  user: UserProfile;
}

interface RefreshResponse {
  accessToken: string;
  usuario: unknown;
}

let session: AuthSession = { accessToken: null, user: null };
let refreshPromise: Promise<ActiveAuthSession> | null = null;
const listeners = new Set<(session: AuthSession) => void>();

export const getAuthSession = (): AuthSession => session;

export const getAccessToken = (): string | null => session.accessToken;

export function setAuthSession(
  accessToken: string,
  user: UserProfile,
): void {
  if (!accessToken.trim()) throw new Error("Token de acceso inválido");
  session = { accessToken, user };
  listeners.forEach((listener) => listener(session));
}

export function clearAuthSession(): void {
  session = { accessToken: null, user: null };
  listeners.forEach((listener) => listener(session));
}

export function subscribeAuthSession(
  listener: (session: AuthSession) => void,
): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function refreshSession(): Promise<ActiveAuthSession> {
  refreshPromise ??= axios
    .post<RefreshResponse>(
      `${API_BASE_URL}/login/refresh`,
      {},
      {
        withCredentials: true,
        headers: { "Content-Type": "application/json" },
        signal: tenantRequestSignal(),
      },
    )
    .then(({ data }) => {
      const refreshedUser = sanitizeUserProfile(data.usuario);

      if (
        session.user &&
        refreshedUser.tenantActivo.id !== session.user.tenantActivo.id
      ) {
        throw new Error("El refresh intentó cambiar la organización activa");
      }

      const activeSession: ActiveAuthSession = {
        accessToken: data.accessToken,
        user: refreshedUser,
      };

      setAuthSession(activeSession.accessToken, activeSession.user);

      return activeSession;
    })
    .finally(() => {
      refreshPromise = null;
    });

  return refreshPromise;
}
