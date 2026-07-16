type ClientEnvironment = Pick<
  ImportMetaEnv,
  "PROD" | "VITE_API_BASE_URL" | "VITE_APP_TIME_ZONE"
>;

const DEVELOPMENT_API_BASE_URL = import.meta.env.DEV
  ? "http://localhost:8080/api"
  : "";

export function resolveEnvironment(environment: ClientEnvironment) {
  const configuredApiBaseUrl = environment.VITE_API_BASE_URL?.trim();

  if (!configuredApiBaseUrl && environment.PROD) {
    throw new Error("VITE_API_BASE_URL es obligatoria en producción");
  }

  const apiUrl = new URL(configuredApiBaseUrl || DEVELOPMENT_API_BASE_URL);
  const isLocal = ["localhost", "127.0.0.1"].includes(apiUrl.hostname);

  if (environment.PROD && apiUrl.protocol !== "https:" && !isLocal) {
    throw new Error("VITE_API_BASE_URL debe usar HTTPS en producción");
  }

  return {
    apiBaseUrl: apiUrl.toString().replace(/\/$/, ""),
    appTimeZone:
      environment.VITE_APP_TIME_ZONE?.trim() ||
      "America/Argentina/Buenos_Aires",
  };
}

const environment = resolveEnvironment(import.meta.env);

export const API_BASE_URL = environment.apiBaseUrl;
export const APP_TIME_ZONE = environment.appTimeZone;
