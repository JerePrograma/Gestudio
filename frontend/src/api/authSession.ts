import axios from "axios";
import { API_BASE_URL } from "../config/environment";
import type { UsuarioResponse } from "../types/types";

export interface AuthSession {
  accessToken: string | null;
  user: UsuarioResponse | null;
}

interface RefreshResponse {
  accessToken: string;
  usuario: UsuarioResponse;
}

let session: AuthSession = { accessToken: null, user: null };
let refreshPromise: Promise<AuthSession> | null = null;
const listeners = new Set<(session: AuthSession) => void>();

export const getAuthSession = (): AuthSession => session;
export const getAccessToken = (): string | null => session.accessToken;

export function setAuthSession(accessToken: string, user: UsuarioResponse): void {
  session = { accessToken, user };
  listeners.forEach((listener) => listener(session));
}

export function clearAuthSession(): void {
  session = { accessToken: null, user: null };
  listeners.forEach((listener) => listener(session));
}

export function subscribeAuthSession(listener: (session: AuthSession) => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function refreshSession(): Promise<AuthSession> {
  refreshPromise ??= axios
    .post<RefreshResponse>(
      `${API_BASE_URL}/login/refresh`,
      {},
      {
        withCredentials: true,
        headers: { "Content-Type": "application/json" },
      },
    )
    .then(({ data }) => {
      setAuthSession(data.accessToken, data.usuario);
      return session;
    })
    .finally(() => {
      refreshPromise = null;
    });
  return refreshPromise;
}
