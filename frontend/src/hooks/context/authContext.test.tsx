import axios from "axios";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { useState } from "react";
import { MemoryRouter, useLocation } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";
import api from "../../api/axiosConfig";
import {
  clearAuthSession,
  getAccessToken,
  setAuthSession,
  setPlatformAuthSession,
} from "../../api/authSession";
import { PERMISSIONS } from "../../config/permissions";
import {
  queryClient,
  tenantRequestSignal,
} from "../queryClient";
import { AuthProvider } from "./authContext";
import type { PlatformProfile, UserProfile } from "./auth-context";
import { useAuth } from "./useAuth";

const tenantA = {
  id: "00000000-0000-0000-0000-0000000000a1",
  codigo: "ACADEMIA_A",
  nombre: "Academia A",
  estado: "ACTIVE" as const,
};
const tenantB = {
  id: "00000000-0000-0000-0000-0000000000b2",
  codigo: "ACADEMIA_B",
  nombre: "Academia B",
  estado: "ACTIVE" as const,
};
const profile = (tenantActivo = tenantA): UserProfile => ({
  id: 1,
  nombreUsuario: "multi",
  roles: ["ADMINISTRADOR"],
  permisos: [PERMISSIONS.APP_ACCESS],
  activo: true,
  tenantActivo,
  tenantsDisponibles: [tenantA, tenantB],
});
const platformProfile: PlatformProfile = {
  id: 9,
  nombreUsuario: "platform-admin",
  authorities: ["PLATFORM_SUPERADMIN"],
  mfaEnabled: true,
  scope: "PLATFORM",
};

function SwitchProbe() {
  const { loading, switchTenant, user } = useAuth();
  const [residual, setResidual] = useState("Limpio");

  if (loading) return <p>Cargando</p>;

  return (
    <>
      <p>{user?.tenantActivo.nombre}</p>
      <p>{residual}</p>
      <button type="button" onClick={() => setResidual("Dato de A")}>Cargar dato</button>
      <button type="button" onClick={() => void switchTenant(tenantB.id)}>
        Cambiar
      </button>
    </>
  );
}

function LoginProbe() {
  const { loading, login, user } = useAuth();
  const [tenantCount, setTenantCount] = useState<number | null>(null);

  return (
    <>
      <p>{loading ? "Cargando" : "Listo"}</p>
      <p>{user?.tenantActivo.nombre ?? "Sin sesión"}</p>
      <p>{tenantCount === null ? "Sin selección" : `${tenantCount} organizaciones`}</p>
      <button
        type="button"
        onClick={() => void login("multi", "memory-only").then(
          (result) => setTenantCount(result?.tenants.length ?? 0),
        )}
      >
        Ingresar
      </button>
    </>
  );
}

function ActionsProbe({ onOutcome = () => undefined }: { onOutcome?: (outcome: string) => void }) {
  const {
    loading,
    scope,
    platformLogin,
    login,
    switchTenant,
    logout,
    hasPermission,
    hasAllPermissions,
    hasAnyPermission,
  } = useAuth();
  const location = useLocation();
  const [outcome, setOutcome] = useState("Sin resultado");
  const run = (action: Promise<unknown>, success: string) => {
    void action
      .then(() => {
        setOutcome(success);
        onOutcome(success);
      })
      .catch((error: unknown) => {
        const message = error instanceof Error ? error.message : "Error desconocido";
        setOutcome(message);
        onOutcome(message);
      });
  };

  return (
    <>
      <p>{loading ? "Cargando acciones" : "Acciones listas"}</p>
      <output data-testid="scope">{scope ?? "ANONYMOUS"}</output>
      <output data-testid="location">{location.pathname}</output>
      <output>{outcome}</output>
      <output data-testid="permission">
        {String(hasPermission(PERMISSIONS.APP_ACCESS))}/
        {String(hasAllPermissions([PERMISSIONS.APP_ACCESS]))}/
        {String(hasAnyPermission([PERMISSIONS.PAGOS_ANULAR, PERMISSIONS.APP_ACCESS]))}
      </output>
      <button
        type="button"
        onClick={() => run(
          platformLogin("platform-admin", "strong-password", "TOTP", "123456"),
          "Plataforma autenticada",
        )}
      >
        Ingresar a plataforma
      </button>
      <button
        type="button"
        onClick={() => run(login("multi", "strong-password", tenantB.id), "Tenant autenticado")}
      >
        Ingresar en tenant B
      </button>
      <button type="button" onClick={() => run(switchTenant(tenantA.id), "Tenant actual conservado")}>
        Conservar tenant actual
      </button>
      <button type="button" onClick={() => run(switchTenant(tenantB.id), "Tenant B activado")}>
        Cambiar a tenant B
      </button>
      <button
        type="button"
        onClick={() => run(
          switchTenant("00000000-0000-0000-0000-0000000000c3"),
          "Tenant desconocido activado",
        )}
      >
        Cambiar a tenant desconocido
      </button>
      <button type="button" onClick={() => run(logout(), "Sesión cerrada")}>Salir</button>
    </>
  );
}

describe("AuthProvider tenant-aware", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    queryClient.clear();
    clearAuthSession();
    setAuthSession("access-a", profile());
    vi.spyOn(axios, "post").mockResolvedValue({
      data: { accessToken: "access-a", usuario: profile() },
    });
  });

  it("cancela el scope y limpia cache antes de activar el nuevo tenant", async () => {
    queryClient.setQueryData(["alumnos"], [{ id: 11, nombre: "Tenant A" }]);
    const previousSignal = tenantRequestSignal();
    const switchRequest = vi.spyOn(api, "post").mockResolvedValue({
      data: { accessToken: "access-b", usuario: profile(tenantB) },
    });

    render(
      <MemoryRouter>
        <AuthProvider>
          <SwitchProbe />
        </AuthProvider>
      </MemoryRouter>,
    );

    expect(await screen.findByText("Academia A")).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Cargar dato" }));
    expect(screen.getByText("Dato de A")).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Cambiar" }));

    expect(await screen.findByText("Academia B")).toBeVisible();
    expect(screen.getByText("Limpio")).toBeVisible();
    expect(screen.queryByText("Dato de A")).not.toBeInTheDocument();
    expect(previousSignal.aborted).toBe(true);
    expect(queryClient.getQueryData(["alumnos"])).toBeUndefined();
    expect(switchRequest).toHaveBeenCalledWith(
      "/login/tenant",
      { tenantId: tenantB.id },
      { withCredentials: true },
    );
    await waitFor(() => expect(screen.queryByText("Cargando")).not.toBeInTheDocument());
  });

  it("interpreta el 409 de selección sin crear ni persistir una sesión", async () => {
    clearAuthSession();
    vi.spyOn(axios, "post").mockRejectedValue(new Error("no refresh cookie"));
    const loginRequest = vi.spyOn(api, "post").mockRejectedValue({
      isAxiosError: true,
      response: {
        status: 409,
        data: { selectionRequired: true, tenants: [tenantA, tenantB] },
      },
    });
    localStorage.setItem("unrelated", "keep-me");

    render(
      <MemoryRouter>
        <AuthProvider>
          <LoginProbe />
        </AuthProvider>
      </MemoryRouter>,
    );

    expect(await screen.findByText("Sin selección")).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Ingresar" }));

    expect(await screen.findByText("2 organizaciones")).toBeVisible();
    expect(loginRequest).toHaveBeenCalledWith(
      "/login",
      { nombreUsuario: "multi", contrasena: "memory-only" },
      { withCredentials: true },
    );
    expect(localStorage.getItem("accessToken")).toBeNull();
    expect(localStorage.getItem("refreshToken")).toBeNull();
    expect(localStorage.getItem("usuario")).toBeNull();
    expect(localStorage.getItem("tenantId")).toBeNull();
    expect(localStorage.getItem("unrelated")).toBe("keep-me");
  });

  it("no deja que un bootstrap cancelado borre un login nuevo", async () => {
    vi.spyOn(axios, "post").mockImplementation((_url, _body, config) =>
      new Promise((_resolve, reject) => {
        config?.signal?.addEventListener?.("abort", () => {
          reject(new axios.CanceledError("login started"));
        }, { once: true });
      }));
    vi.spyOn(api, "post").mockResolvedValue({
      data: { accessToken: "new-access", usuario: profile() },
    });

    render(
      <MemoryRouter>
        <AuthProvider>
          <LoginProbe />
        </AuthProvider>
      </MemoryRouter>,
    );

    fireEvent.click(screen.getByRole("button", { name: "Ingresar" }));

    expect(await screen.findByText("Academia A")).toBeVisible();
    expect(await screen.findByText("Listo")).toBeVisible();
    expect(getAccessToken()).toBe("new-access");
  });

  it("autentica la sesión PLATFORM con MFA y sanitiza el perfil recibido", async () => {
    const outcome = vi.fn();
    const platformLogin = vi.spyOn(api, "post").mockResolvedValue({
      data: {
        accessToken: "platform-access",
        refreshExpiresAt: "2030-01-01T00:00:00Z",
        profile: platformProfile,
      },
    });

    render(
      <MemoryRouter>
        <AuthProvider><ActionsProbe onOutcome={outcome} /></AuthProvider>
      </MemoryRouter>,
    );

    expect(await screen.findByText("Acciones listas")).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Ingresar a plataforma" }));

    await waitFor(() => expect(outcome).toHaveBeenCalledWith("Plataforma autenticada"));
    expect(screen.getByTestId("scope")).toHaveTextContent("PLATFORM");
    expect(platformLogin).toHaveBeenCalledWith(
      "/platform/auth/login",
      {
        nombreUsuario: "platform-admin",
        contrasena: "strong-password",
        metodo: "TOTP",
        codigo: "123456",
      },
      { withCredentials: true },
    );
    expect(getAccessToken()).toBe("platform-access");
  });

  it("rechaza login y cambio de tenant cuando el servidor devuelve otra organización", async () => {
    const outcome = vi.fn();
    const request = vi.spyOn(api, "post").mockResolvedValue({
      data: { accessToken: "wrong-access", usuario: profile(tenantA) },
    });

    const loginView = render(
      <MemoryRouter>
        <AuthProvider><ActionsProbe onOutcome={outcome} /></AuthProvider>
      </MemoryRouter>,
    );
    expect(await screen.findByText("Acciones listas")).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Ingresar en tenant B" }));
    await waitFor(() => expect(outcome).toHaveBeenCalledWith(
      "La sesión no corresponde a la organización seleccionada",
    ));
    expect(getAccessToken()).toBeNull();
    loginView.unmount();

    setAuthSession("access-a", profile());
    request.mockClear();
    outcome.mockClear();
    render(
      <MemoryRouter>
        <AuthProvider><ActionsProbe onOutcome={outcome} /></AuthProvider>
      </MemoryRouter>,
    );
    expect(await screen.findByText("Acciones listas")).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Cambiar a tenant B" }));
    await waitFor(() => expect(outcome).toHaveBeenCalledWith(
      "La sesión no corresponde a la organización seleccionada",
    ));
    await waitFor(() => expect(screen.getByText("Acciones listas")).toBeVisible());
  });

  it("propaga un login fallido que no representa una selección de tenant", async () => {
    const outcome = vi.fn();
    vi.spyOn(api, "post").mockRejectedValue(new Error("Credenciales rechazadas"));

    render(
      <MemoryRouter>
        <AuthProvider><ActionsProbe onOutcome={outcome} /></AuthProvider>
      </MemoryRouter>,
    );
    expect(await screen.findByText("Acciones listas")).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Ingresar en tenant B" }));

    await waitFor(() => expect(outcome).toHaveBeenCalledWith("Credenciales rechazadas"));
  });

  it("evita cambios redundantes, tenants ajenos y cambios desde scope PLATFORM", async () => {
    const request = vi.spyOn(api, "post");

    render(
      <MemoryRouter>
        <AuthProvider><ActionsProbe /></AuthProvider>
      </MemoryRouter>,
    );
    expect(await screen.findByText("Acciones listas")).toBeVisible();

    fireEvent.click(screen.getByRole("button", { name: "Conservar tenant actual" }));
    expect(await screen.findByText("Tenant actual conservado")).toBeVisible();
    expect(request).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole("button", { name: "Cambiar a tenant desconocido" }));
    expect(await screen.findByText("Organización no disponible")).toBeVisible();
    expect(request).not.toHaveBeenCalled();

    setPlatformAuthSession("platform-access", platformProfile);
    await waitFor(() => expect(screen.getByTestId("scope")).toHaveTextContent("PLATFORM"));
    fireEvent.click(screen.getByRole("button", { name: "Cambiar a tenant B" }));
    expect(await screen.findByText("La sesión de plataforma no puede cambiar de organización"))
      .toBeVisible();
    expect(request).not.toHaveBeenCalled();
  });

  it("cierra una sesión tenant contra su endpoint y navega al login tenant", async () => {
    const outcome = vi.fn();
    const logoutRequest = vi.spyOn(api, "post").mockResolvedValue({ data: {} });

    render(
      <MemoryRouter initialEntries={["/private"]}>
        <AuthProvider><ActionsProbe onOutcome={outcome} /></AuthProvider>
      </MemoryRouter>,
    );
    expect(await screen.findByText("Acciones listas")).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Salir" }));

    await waitFor(() => expect(outcome).toHaveBeenCalledWith("Sesión cerrada"));
    expect(logoutRequest).toHaveBeenCalledWith("/login/logout", {}, { withCredentials: true });
    await waitFor(() => expect(screen.getByTestId("location")).toHaveTextContent("/login"));
    expect(screen.getByTestId("scope")).toHaveTextContent("ANONYMOUS");
  });

  it("cierra una sesión PLATFORM contra su endpoint y conserva la frontera de navegación", async () => {
    const outcome = vi.fn();
    setPlatformAuthSession("platform-access", platformProfile);
    vi.spyOn(axios, "post").mockResolvedValue({
      data: {
        accessToken: "platform-access",
        refreshExpiresAt: "2030-01-01T00:00:00Z",
        profile: platformProfile,
      },
    });
    const logoutRequest = vi.spyOn(api, "post").mockResolvedValue({ data: {} });

    render(
      <MemoryRouter initialEntries={["/platform/tenants"]}>
        <AuthProvider><ActionsProbe onOutcome={outcome} /></AuthProvider>
      </MemoryRouter>,
    );
    expect(await screen.findByText("Acciones listas")).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Salir" }));

    await waitFor(() => expect(outcome).toHaveBeenCalledWith("Sesión cerrada"));
    expect(logoutRequest).toHaveBeenCalledWith(
      "/platform/auth/logout",
      {},
      { withCredentials: true },
    );
    await waitFor(() => expect(screen.getByTestId("location")).toHaveTextContent("/platform/login"));
  });

  it("limpia una sesión anónima sin inventar un logout remoto", async () => {
    clearAuthSession();
    vi.spyOn(axios, "post").mockRejectedValue(new Error("sin cookie"));
    const logoutRequest = vi.spyOn(api, "post");

    render(
      <MemoryRouter initialEntries={["/public"]}>
        <AuthProvider><ActionsProbe /></AuthProvider>
      </MemoryRouter>,
    );
    expect(await screen.findByText("Acciones listas")).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Salir" }));

    expect(await screen.findByText("Sesión cerrada")).toBeVisible();
    expect(logoutRequest).not.toHaveBeenCalled();
    await waitFor(() => expect(screen.getByTestId("location")).toHaveTextContent("/login"));
    expect(screen.getByTestId("permission")).toHaveTextContent("false/false/false");
  });
});
