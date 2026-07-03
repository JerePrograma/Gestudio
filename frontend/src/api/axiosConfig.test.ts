import axios, {
  AxiosError,
  AxiosHeaders,
  type AxiosResponse,
  type InternalAxiosRequestConfig,
} from "axios";
import { beforeEach, describe, expect, it, vi } from "vitest";
import api from "./axiosConfig";
import { getAccessToken, setAccessToken } from "./authSession";

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
    setAccessToken("old-access");
    localStorage.setItem("accessToken", "legacy-access");
    localStorage.setItem("refreshToken", "legacy-refresh");
    localStorage.setItem("usuario", "legacy-user");
    localStorage.setItem("unrelated", "keep-me");
    vi.restoreAllMocks();
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
        usuario: { id: 1, nombreUsuario: "admin", rol: "ADMINISTRADOR", activo: true },
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
