import axios, {
  AxiosHeaders,
  type AxiosError,
  type InternalAxiosRequestConfig,
} from "axios";
import { API_BASE_URL } from "../config/environment";
import {
  clearAuthSession,
  getAccessToken,
  getAuthSession,
  refreshSession,
} from "./authSession";
import type { SessionScope } from "../hooks/context/auth-context";
import {
  resetTenantClientState,
  tenantRequestSignal,
} from "../hooks/queryClient";

interface RetriableRequestConfig extends InternalAxiosRequestConfig {
  _retry?: boolean;
}

export const AUTH_STORAGE_KEYS = [
  "accessToken",
  "refreshToken",
  "usuario",
] as const;

export async function clearAuthStorage(): Promise<void> {
  AUTH_STORAGE_KEYS.forEach((key) => localStorage.removeItem(key));
  clearAuthSession();
  await resetTenantClientState();
}

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: { "Content-Type": "application/json" },
});

function normalizeHeaders(config: InternalAxiosRequestConfig): AxiosHeaders {
  const headers = AxiosHeaders.from(config.headers);
  config.headers = headers;
  return headers;
}

function requestPath(config: InternalAxiosRequestConfig): string {
  const url = config.url ?? "";

  if (/^https?:\/\//i.test(url)) {
    return new URL(url).pathname;
  }

  const baseUrl = config.baseURL ?? API_BASE_URL;
  return new URL(url, `${baseUrl.replace(/\/$/, "")}/`).pathname;
}

function isAuthEndpoint(config: InternalAxiosRequestConfig): boolean {
  const path = requestPath(config);

  return (
    path === "/api/login" ||
    path === "/api/login/refresh" ||
    path === "/api/login/logout" ||
    path === "/login" ||
    path === "/login/refresh" ||
    path === "/login/logout" ||
    path === "/api/platform/auth/login" ||
    path === "/api/platform/auth/refresh" ||
    path === "/api/platform/auth/logout" ||
    path === "/platform/auth/login" ||
    path === "/platform/auth/refresh" ||
    path === "/platform/auth/logout" ||
    path === "/api/platform/identity/activate" ||
    path === "/platform/identity/activate"
  );
}

function requestScope(config: InternalAxiosRequestConfig): SessionScope {
  const path = requestPath(config);
  return path === "/platform" ||
    path === "/api/platform" ||
    path.startsWith("/platform/") ||
    path.startsWith("/api/platform/")
    ? "PLATFORM"
    : "TENANT";
}

function removeAuthorizationHeader(config: InternalAxiosRequestConfig): void {
  const headers = normalizeHeaders(config);
  headers.delete("Authorization");
  headers.delete("authorization");
}

function setAuthorizationHeader(
  config: InternalAxiosRequestConfig,
  accessToken: string,
): void {
  const headers = normalizeHeaders(config);
  headers.set("Authorization", `Bearer ${accessToken}`);
}

function getAuthorizationHeader(config: InternalAxiosRequestConfig): string | null {
  const value = normalizeHeaders(config).get("Authorization");

  if (typeof value === "string") {
    return value;
  }

  return null;
}

function redirectToLogin(scope: SessionScope): void {
  const loginPath = scope === "PLATFORM" ? "/platform/login" : "/login";
  if (window.location.pathname !== loginPath) {
    window.location.assign(loginPath);
  }
}

api.interceptors.request.use((config) => {
  const tenantSignal = tenantRequestSignal();
  config.signal = config.signal instanceof AbortSignal
    ? AbortSignal.any([config.signal, tenantSignal])
    : config.signal ?? tenantSignal;

  if (isAuthEndpoint(config)) {
    removeAuthorizationHeader(config);
    return config;
  }

  const accessToken = getAccessToken(requestScope(config));

  if (accessToken !== null) {
    setAuthorizationHeader(config, accessToken);
  }

  return config;
});

api.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    const originalRequest = error.config as RetriableRequestConfig | undefined;
    const status = error.response?.status;

    if (
      status !== 401 ||
      !originalRequest ||
      originalRequest._retry ||
      isAuthEndpoint(originalRequest)
    ) {
      return Promise.reject(error);
    }

    originalRequest._retry = true;

    const expectedScope = requestScope(originalRequest);
    if (getAuthSession().scope !== expectedScope) {
      return Promise.reject(error);
    }

    const currentAccessToken = getAccessToken(expectedScope);
    const requestAuthorization = getAuthorizationHeader(originalRequest);

    if (
      currentAccessToken !== null &&
      requestAuthorization !== `Bearer ${currentAccessToken}`
    ) {
      setAuthorizationHeader(originalRequest, currentAccessToken);
      return api(originalRequest);
    }

    try {
      const refreshedSession = await refreshSession(expectedScope);

      setAuthorizationHeader(originalRequest, refreshedSession.accessToken);

      return api(originalRequest);
    } catch (refreshError) {
      if (axios.isCancel(refreshError)) {
        return Promise.reject(refreshError);
      }

      await clearAuthStorage();
      redirectToLogin(expectedScope);
      return Promise.reject(refreshError);
    }
  },
);

export default api;
