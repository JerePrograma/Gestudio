import axios, {
  AxiosError,
  AxiosHeaders,
  type AxiosResponse,
  type InternalAxiosRequestConfig,
} from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import api from "./axiosConfig";
import { PERMISSIONS } from "../config/permissions";
import {
  getAccessToken,
  refreshSession,
  setAuthSession,
} from "./authSession";

function response(
  config: InternalAxiosRequestConfig,
  status: number,
  data: object = {}
): AxiosResponse {
  return { config, status, statusText: String(status), headers: {}, data };
}

function rejectWith(status: number, config: InternalAxiosRequestConfig): never {
  throw new AxiosError(
    `HTTP ${status}`,
    String(status),
    config,
    undefined,
    response(config, status)
  );
}

describe("interceptor de autenticación", () => {
  beforeEach(() => {
    window.history.replaceState({}, "", "/login");
    setAuthSession("old-access", {
      id: 1,
      nombreUsuario: "admin",
      roles: ["ADMINISTRADOR"],
      permisos: [PERMISSIONS.PAGOS_LEER],
      activo: true,
    });
    localStorage.setItem("accessToken", "legacy-access");
    localStorage.setItem("refreshToken", "legacy-refresh");
    localStorage.setItem("usuario", "legacy-user");
    localStorage.setItem("unrelated", "keep-me");
    vi.restoreAllMocks();
  });

  it("comparte el refresh de bootstrap con el retry de un 401", async () => {
    let completeRefresh!: () => void;
    let signalFirst401!: () => void;
    const first401 = new Promise<void>((resolve) => {
      signalFirst401 = resolve;
    });
    const pendingRefresh = new Promise<AxiosResponse>((resolve) => {
      completeRefresh = () => resolve(response(
        { headers: new AxiosHeaders() },
        200,
        {
          accessToken: "new-access",
          usuario: { id: 1, nombreUsuario: "admin", roles: ["ADMINISTRADOR"], permisos: [PERMISSIONS.PAGOS_LEER], activo: true },
        },
      ));
    });
    const refresh = vi.spyOn(axios, "post").mockImplementation(() => pendingRefresh);
    const adapter = async (config: InternalAxiosRequestConfig) => {
      const headers = AxiosHeaders.from(config.headers);
      if (headers.get("Authorization") === "Bearer new-access") {
        return response(config, 200, { ok: true });
      }
      signalFirst401();
      return rejectWith(401, config);
    };

    const bootstrap = refreshSession();
    const request = api.get("/private", { adapter });
    await first401;
    completeRefresh();

    await expect(Promise.all([bootstrap, request])).resolves.toHaveLength(2);
    expect(refresh).toHaveBeenCalledTimes(1);
    expect(getAccessToken()).toBe("new-access");
  });

  it("conserva la sesión y no refresca ante 403", async () => {
    const refresh = vi.spyOn(axios, "post");

    await expect(
      api.get("/admin", {
        adapter: async (config) => rejectWith(403, config),
      })
    ).rejects.toBeInstanceOf(AxiosError);

    expect(refresh).not.toHaveBeenCalled();
    expect(getAccessToken()).toBe("old-access");
    expect(localStorage.getItem("unrelated")).toBe("keep-me");
  });

  it("comparte un único refresh entre respuestas 401 concurrentes", async () => {
    const refresh = vi.spyOn(axios, "post").mockResolvedValue({
      data: {
        accessToken: "new-access",
        usuario: { id: 1, nombreUsuario: "admin", roles: ["ADMINISTRADOR"], permisos: [PERMISSIONS.PAGOS_LEER], activo: true },
      },
    });
    const adapter = async (config: InternalAxiosRequestConfig) => {
      const headers = AxiosHeaders.from(config.headers);
      if (headers.get("Authorization") === "Bearer new-access") {
        return response(config, 200, { ok: true });
      }
      return rejectWith(401, config);
    };

    const results = await Promise.all([
      api.get("/one", { adapter }),
      api.get("/two", { adapter }),
    ]);

    expect(results.map((result) => result.data)).toEqual([{ ok: true }, { ok: true }]);
    expect(refresh).toHaveBeenCalledTimes(1);
    expect(getAccessToken()).toBe("new-access");
    expect(refresh).toHaveBeenCalledWith(
      expect.stringContaining("/login/refresh"),
      {},
      expect.objectContaining({ withCredentials: true }),
    );
  });

  it("rechaza, limpia sólo claves propias y no entra en loop si falla refresh", async () => {
    vi.spyOn(axios, "post").mockRejectedValue(new Error("refresh failed"));

    await expect(
      api.get("/private", {
        adapter: async (config) => rejectWith(401, config),
      })
    ).rejects.toThrow("refresh failed");

    expect(localStorage.getItem("accessToken")).toBeNull();
    expect(localStorage.getItem("refreshToken")).toBeNull();
    expect(localStorage.getItem("usuario")).toBeNull();
    expect(getAccessToken()).toBeNull();
    expect(localStorage.getItem("unrelated")).toBe("keep-me");
  });

  it("no intenta refrescar la propia llamada de refresh", async () => {
    const refresh = vi.spyOn(axios, "post");

    await expect(
      api.post("/login/refresh", {}, {
        adapter: async (config) => rejectWith(401, config),
      })
    ).rejects.toBeInstanceOf(AxiosError);

    expect(refresh).not.toHaveBeenCalled();
  });
});
