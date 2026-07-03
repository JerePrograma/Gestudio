import axios, {
  type AxiosError,
  type InternalAxiosRequestConfig,
} from "axios";
import { toast } from "react-toastify";
import { API_BASE_URL } from "../config/environment";
import type { UsuarioResponse } from "../types/types";
import { getAccessToken, setAccessToken } from "./authSession";

interface RetriableRequestConfig extends InternalAxiosRequestConfig {
  _retry?: boolean;
}

interface RefreshResponse {
  accessToken: string;
  usuario?: UsuarioResponse;
}

export const AUTH_STORAGE_KEYS = [
  "accessToken",
  "refreshToken",
  "usuario",
] as const;

export function clearAuthStorage(): void {
  AUTH_STORAGE_KEYS.forEach((key) => localStorage.removeItem(key));
  setAccessToken(null);
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

let refreshPromise: Promise<RefreshResponse> | null = null;

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
    try {
      refreshPromise ??= axios
        .post<RefreshResponse>(
          `${API_BASE_URL}/login/refresh`,
          {},
          {
            withCredentials: true,
            headers: { "Content-Type": "application/json" },
          }
        )
        .then((response) => response.data);

      const data = await refreshPromise;
      setAccessToken(data.accessToken);
      originalRequest.headers.Authorization = `Bearer ${data.accessToken}`;
      return api(originalRequest);
    } catch (refreshError) {
      clearAuthStorage();
      toast.error("La sesión expiró. Iniciá sesión nuevamente.");
      redirectToLogin();
      return Promise.reject(refreshError);
    } finally {
      refreshPromise = null;
    }
  }
);

export default api;
