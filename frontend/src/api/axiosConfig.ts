import axios, {
  AxiosHeaders,
  type AxiosError,
  type InternalAxiosRequestConfig,
} from "axios";
import { API_BASE_URL } from "../config/environment";
import { clearAuthSession, getAccessToken, refreshSession } from "./authSession";

interface RetriableRequestConfig extends InternalAxiosRequestConfig {
  _retry?: boolean;
}

export const AUTH_STORAGE_KEYS = [
  "accessToken",
  "refreshToken",
  "usuario",
] as const;

export function clearAuthStorage(): void {
  AUTH_STORAGE_KEYS.forEach((key) => localStorage.removeItem(key));
  clearAuthSession();
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
    path === "/login/logout"
  );
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

function redirectToLogin(): void {
  if (window.location.pathname !== "/login") {
    window.location.assign("/login");
  }
}

api.interceptors.request.use((config) => {
  if (isAuthEndpoint(config)) {
    removeAuthorizationHeader(config);
    return config;
  }

  const accessToken = getAccessToken();

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

    const currentAccessToken = getAccessToken();
    const requestAuthorization = getAuthorizationHeader(originalRequest);

    if (
      currentAccessToken !== null &&
      requestAuthorization !== `Bearer ${currentAccessToken}`
    ) {
      setAuthorizationHeader(originalRequest, currentAccessToken);
      return api(originalRequest);
    }

    try {
      const refreshedSession = await refreshSession();

      setAuthorizationHeader(originalRequest, refreshedSession.accessToken);

      return api(originalRequest);
    } catch (refreshError) {
      clearAuthStorage();
      redirectToLogin();
      return Promise.reject(refreshError);
    }
  },
);

export default api;
