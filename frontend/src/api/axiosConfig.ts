import axios, {
  type AxiosError,
  type InternalAxiosRequestConfig,
} from "axios";
import { toast } from "react-toastify";
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

api.interceptors.request.use((config) => {
  const accessToken = getAccessToken();
  if (accessToken) {
    config.headers.Authorization = `Bearer ${accessToken}`;
  }
  return config;
});

function isRefreshRequest(config: InternalAxiosRequestConfig): boolean {
  return config.url?.replace(API_BASE_URL, "").startsWith("/login/refresh") ?? false;
}

function redirectToLogin(): void {
  if (window.location.pathname !== "/login") {
    window.location.assign("/login");
  }
}

api.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    const originalRequest = error.config as RetriableRequestConfig | undefined;
    const status = error.response?.status;

    if (status === 403) {
      toast.warn("No tenés permisos para realizar esta acción.");
      return Promise.reject(error);
    }

    if (
      status !== 401 ||
      !originalRequest ||
      originalRequest._retry ||
      isRefreshRequest(originalRequest)
    ) {
      return Promise.reject(error);
    }

    originalRequest._retry = true;
    const currentAccessToken = getAccessToken();
    if (
      currentAccessToken &&
      originalRequest.headers.Authorization !== `Bearer ${currentAccessToken}`
    ) {
      originalRequest.headers.Authorization = `Bearer ${currentAccessToken}`;
      return api(originalRequest);
    }
    try {
      const session = await refreshSession();
      originalRequest.headers.Authorization = `Bearer ${session.accessToken}`;
      return api(originalRequest);
    } catch (refreshError) {
      clearAuthStorage();
      toast.error("La sesión expiró. Iniciá sesión nuevamente.");
      redirectToLogin();
      return Promise.reject(refreshError);
    }
  }
);

export default api;
