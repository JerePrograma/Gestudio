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
  getAuthProfile,
  getAuthSession,
  refreshSession,
  clearAuthSession,
  setAuthSession,
  setPlatformAuthSession,
  subscribeAuthSession,
} from "./authSession";
import { resetTenantClientState } from "../hooks/queryClient";

const tenant = {
  id: "00000000-0000-0000-0000-0000000000a1",
  codigo: "ACADEMIA_A",
  nombre: "Academia A",
  estado: "ACTIVE" as const,
};
const otherTenant = {
  id: "00000000-0000-0000-0000-0000000000b2",
  codigo: "ACADEMIA_B",
  nombre: "Academia B",
  estado: "ACTIVE" as const,
};

const user = {
  id: 1,
  nombreUsuario: "admin",
  roles: ["ADMINISTRADOR"],
  permisos: [PERMISSIONS.PAGOS_LEER],
  activo: true,
  tenantActivo: tenant,
  tenantsDisponibles: [tenant],
};
const platformProfile = {
  id: 99,
  nombreUsuario: "platform-admin",
  authorities: ["PLATFORM_SUPERADMIN"],
  mfaEnabled: true,
  scope: "PLATFORM" as const,
};

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
    setAuthSession("old-access", user);
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
          usuario: user,
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
        usuario: user,
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

  it("serializa el refresh PLATFORM en su endpoint y conserva el scope", async () => {
    setPlatformAuthSession("old-platform-access", platformProfile);
    const refresh = vi.spyOn(axios, "post").mockResolvedValue({
      data: {
        accessToken: "new-platform-access",
        refreshExpiresAt: "2030-01-01T00:00:00Z",
        profile: platformProfile,
      },
    });
    const adapter = async (config: InternalAxiosRequestConfig) => {
      const authorization = AxiosHeaders.from(config.headers).get("Authorization");
      if (authorization === "Bearer new-platform-access") {
        return response(config, 200, { ok: true });
      }
      return rejectWith(401, config);
    };

    await expect(Promise.all([
      api.get("/platform/tenants", { adapter }),
      api.get("/platform/admins", { adapter }),
    ])).resolves.toHaveLength(2);

    expect(refresh).toHaveBeenCalledTimes(1);
    expect(refresh).toHaveBeenCalledWith(
      expect.stringContaining("/platform/auth/refresh"),
      {},
      expect.objectContaining({ withCredentials: true }),
    );
    expect(getAuthSession()).toMatchObject({ scope: "PLATFORM", accessToken: "new-platform-access" });
  });

  it("no envía ni refresca una sesión TENANT contra el control plane", async () => {
    const refresh = vi.spyOn(axios, "post");

    await expect(api.get("/platform/tenants", {
      adapter: async (config) => {
        expect(AxiosHeaders.from(config.headers).get("Authorization")).toBeUndefined();
        return rejectWith(401, config);
      },
    })).rejects.toBeInstanceOf(AxiosError);

    expect(refresh).not.toHaveBeenCalled();
    expect(getAuthSession().scope).toBe("TENANT");
  });

  it("mantiene separados los tokens y publica sólo cambios de sesión válidos", () => {
    const listener = vi.fn();
    const unsubscribe = subscribeAuthSession(listener);

    expect(() => setPlatformAuthSession("   ", platformProfile)).toThrow(
      "Token de acceso inválido",
    );
    expect(listener).not.toHaveBeenCalled();

    setPlatformAuthSession("platform-access", platformProfile);
    expect(getAccessToken()).toBe("platform-access");
    expect(getAccessToken("PLATFORM")).toBe("platform-access");
    expect(getAccessToken("TENANT")).toBeNull();
    expect(getAuthProfile()).toEqual(platformProfile);
    expect(listener).toHaveBeenLastCalledWith(expect.objectContaining({
      scope: "PLATFORM",
      accessToken: "platform-access",
    }));

    unsubscribe();
    setAuthSession("tenant-access", user);
    expect(listener).toHaveBeenCalledOnce();
  });

  it("infiere el refresh PLATFORM desde la ruta y rechaza cambiar su identidad", async () => {
    window.history.replaceState({}, "", "/platform/login");
    const differentProfile = { ...platformProfile, id: 100 };
    clearAuthSession();
    vi.spyOn(axios, "post").mockResolvedValue({
      data: {
        accessToken: "cross-identity-access",
        refreshExpiresAt: "2030-01-01T00:00:00Z",
        profile: platformProfile,
      },
    });

    await expect(refreshSession()).resolves.toMatchObject({
      scope: "PLATFORM",
      accessToken: "cross-identity-access",
    });
    expect(axios.post).toHaveBeenCalledWith(
      expect.stringContaining("/platform/auth/refresh"),
      {},
      expect.anything(),
    );

    setPlatformAuthSession("old-platform-access", platformProfile);
    vi.mocked(axios.post).mockResolvedValueOnce({
      data: {
        accessToken: "cross-identity-access",
        refreshExpiresAt: "2030-01-01T00:00:00Z",
        profile: differentProfile,
      },
    });
    await expect(refreshSession("PLATFORM")).rejects.toThrow(
      "El refresh intentó cambiar la identidad de plataforma",
    );
    expect(getAccessToken()).toBe("old-platform-access");
  });

  it("refresca un 401 cuyo Authorization coincide y reintenta con el token nuevo", async () => {
    vi.spyOn(axios, "post").mockResolvedValue({
      data: { accessToken: "new-access", usuario: user },
    });
    let attempts = 0;

    const result = await api.get("/private", {
      adapter: async (config) => {
        attempts += 1;
        const authorization = AxiosHeaders.from(config.headers).get("Authorization");
        if (attempts === 1) {
          expect(authorization).toBe("Bearer old-access");
          return rejectWith(401, config);
        }
        expect(authorization).toBe("Bearer new-access");
        return response(config, 200, { ok: true });
      },
    });

    expect(result.data).toEqual({ ok: true });
    expect(attempts).toBe(2);
  });

  it("propaga una cancelación del refresh sin limpiar la sesión", async () => {
    vi.spyOn(axios, "post").mockRejectedValue(new axios.CanceledError("scope rotated"));

    await expect(api.get("/private", {
      adapter: async (config) => rejectWith(401, config),
    })).rejects.toSatisfy(axios.isCancel);

    expect(getAccessToken()).toBe("old-access");
    expect(localStorage.getItem("accessToken")).toBe("legacy-access");
  });

  it("rechaza un refresh que intente cambiar el tenant de la sesión", async () => {
    vi.spyOn(axios, "post").mockResolvedValue({
      data: {
        accessToken: "cross-tenant-access",
        usuario: {
          ...user,
          tenantActivo: otherTenant,
          tenantsDisponibles: [tenant, otherTenant],
        },
      },
    });

    await expect(refreshSession()).rejects.toThrow(
      "El refresh intentó cambiar la organización activa",
    );
    expect(getAccessToken()).toBe("old-access");
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

  it("aborta las solicitudes en curso al rotar el scope de tenant", async () => {
    let configured = false;
    const request = api.get("/slow", {
      adapter: (config) => new Promise((_resolve, reject) => {
        configured = true;
        config.signal?.addEventListener?.("abort", () => {
          reject(new axios.CanceledError("tenant changed", config));
        }, { once: true });
      }),
    });

    await vi.waitFor(() => expect(configured).toBe(true));
    await resetTenantClientState();

    await expect(request).rejects.toSatisfy(axios.isCancel);
  });

  it("conserva la cancelación propia de cada solicitud", async () => {
    const controller = new AbortController();
    let configured = false;
    const request = api.get("/slow", {
      signal: controller.signal,
      adapter: (config) => new Promise((_resolve, reject) => {
        configured = true;
        config.signal?.addEventListener?.("abort", () => {
          reject(new axios.CanceledError("request canceled", config));
        }, { once: true });
      }),
    });

    await vi.waitFor(() => expect(configured).toBe(true));
    controller.abort();

    await expect(request).rejects.toSatisfy(axios.isCancel);
  });
});
