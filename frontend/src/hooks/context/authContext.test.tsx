import axios from "axios";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { useState } from "react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";
import api from "../../api/axiosConfig";
import {
  clearAuthSession,
  getAccessToken,
  setAuthSession,
} from "../../api/authSession";
import { PERMISSIONS } from "../../config/permissions";
import {
  queryClient,
  tenantRequestSignal,
} from "../queryClient";
import { AuthProvider } from "./authContext";
import type { UserProfile } from "./auth-context";
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
});
