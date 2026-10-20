import axios from "axios";
import { API_BASE_URL } from "../config/environment";
import {
  sanitizePlatformProfile,
  sanitizeUserProfile,
  type AuthProfile,
  type PlatformProfile,
  type SessionScope,
  type UserProfile,
} from "../hooks/context/auth-context";
import { tenantRequestSignal } from "../hooks/queryClient";

export type AuthSession =
  | { scope: null; accessToken: null; profile: null }
  | { scope: "TENANT"; accessToken: string; profile: UserProfile }
  | { scope: "PLATFORM"; accessToken: string; profile: PlatformProfile };

export type ActiveAuthSession = Exclude<AuthSession, { scope: null }>;

interface TenantRefreshResponse {
  accessToken: string;
  usuario: unknown;
}

interface PlatformRefreshResponse {
  accessToken: string;
  refreshExpiresAt: string;
  profile: unknown;
}

interface RefreshContext {
  session: AuthSession;
  signal: AbortSignal;
}

let session: AuthSession = { scope: null, accessToken: null, profile: null };
const refreshPromises = new Map<SessionScope, {
  context: RefreshContext;
  promise: Promise<ActiveAuthSession>;
}>();
const listeners = new Set<(nextSession: AuthSession) => void>();

const publishSession = (nextSession: AuthSession): void => {
  session = nextSession;
  listeners.forEach((listener) => listener(session));
};

export const getAuthSession = (): AuthSession => session;

export const getAccessToken = (scope?: SessionScope): string | null =>
  session.scope !== null && (!scope || session.scope === scope)
    ? session.accessToken
    : null;

export const getAuthProfile = (): AuthProfile | null => session.profile;

export function setTenantAuthSession(
  accessToken: string,
  user: UserProfile,
): void {
  if (!accessToken.trim()) throw new Error("Token de acceso inválido");
  publishSession({ scope: "TENANT", accessToken, profile: user });
}

export function setPlatformAuthSession(
  accessToken: string,
  profile: PlatformProfile,
): void {
  if (!accessToken.trim()) throw new Error("Token de acceso inválido");
  publishSession({ scope: "PLATFORM", accessToken, profile });
}

// Compatibilidad para los consumidores y tests tenant existentes.
export const setAuthSession = setTenantAuthSession;

export function clearAuthSession(): void {
  publishSession({ scope: null, accessToken: null, profile: null });
}

export function subscribeAuthSession(
  listener: (nextSession: AuthSession) => void,
): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

const inferredRefreshScope = (): SessionScope =>
  session.scope ?? (window.location.pathname.startsWith("/platform") ? "PLATFORM" : "TENANT");

const validateRefreshScope = (scope: SessionScope): void => {
  if (session.scope !== null && session.scope !== scope) {
    throw new Error("El refresh intentó cambiar el alcance de la sesión");
  }
};

const assertCurrentRefresh = (context: RefreshContext): void => {
  if (context.signal.aborted || session !== context.session) {
    throw new axios.CanceledError("La sesión cambió durante el refresh");
  }
};

const requestRefresh = async <T>(path: string, context: RefreshContext): Promise<T> => {
  try {
    const { data } = await axios.post<T>(`${API_BASE_URL}${path}`, {}, {
      withCredentials: true,
      headers: { "Content-Type": "application/json" },
      signal: context.signal,
    });
    assertCurrentRefresh(context);
    return data;
  } catch (error) {
    assertCurrentRefresh(context);
    throw error;
  }
};

const refreshTenantSession = async (context: RefreshContext): Promise<ActiveAuthSession> => {
  const data = await requestRefresh<TenantRefreshResponse>("/login/refresh", context);
  assertCurrentRefresh(context);
  const refreshedUser = sanitizeUserProfile(data.usuario);

  if (
    session.scope === "TENANT" &&
    refreshedUser.tenantActivo.id !== session.profile.tenantActivo.id
  ) {
    throw new Error("El refresh intentó cambiar la organización activa");
  }

  if (session.scope === "TENANT" && refreshedUser.id !== session.profile.id) {
    throw new Error("El refresh intentó cambiar la identidad del usuario");
  }

  setTenantAuthSession(data.accessToken, refreshedUser);
  return getAuthSession() as ActiveAuthSession;
};

const refreshPlatformSession = async (context: RefreshContext): Promise<ActiveAuthSession> => {
  const data = await requestRefresh<PlatformRefreshResponse>("/platform/auth/refresh", context);
  assertCurrentRefresh(context);
  const refreshedProfile = sanitizePlatformProfile(data.profile);

  if (
    session.scope === "PLATFORM" &&
    refreshedProfile.id !== session.profile.id
  ) {
    throw new Error("El refresh intentó cambiar la identidad de plataforma");
  }

  setPlatformAuthSession(data.accessToken, refreshedProfile);
  return getAuthSession() as ActiveAuthSession;
};

export function refreshSession(requestedScope?: SessionScope): Promise<ActiveAuthSession> {
  const scope = requestedScope ?? inferredRefreshScope();
  validateRefreshScope(scope);

  const pending = refreshPromises.get(scope);
  if (pending && pending.context.session === session && !pending.context.signal.aborted) {
    return pending.promise;
  }

  const context: RefreshContext = { session, signal: tenantRequestSignal() };
  const refresh = (scope === "PLATFORM"
    ? refreshPlatformSession(context)
    : refreshTenantSession(context)
  ).finally(() => {
    if (refreshPromises.get(scope)?.promise === refresh) refreshPromises.delete(scope);
  });

  refreshPromises.set(scope, { context, promise: refresh });
  return refresh;
}
