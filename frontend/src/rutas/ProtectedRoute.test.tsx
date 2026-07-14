import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { PERMISSIONS } from "../config/permissions";

const auth = vi.hoisted(() => ({
  isAuth: false,
  loading: false,
  user: null as null | { roles: string[]; permisos: string[] },
  hasPermission: vi.fn<(permission: string) => boolean>(),
  hasAllPermissions: vi.fn<(permissions: readonly string[]) => boolean>(),
  hasAnyPermission: vi.fn<(permissions: readonly string[]) => boolean>(),
}));

vi.mock("../hooks/context/useAuth", () => ({ useAuth: () => auth }));

import ProtectedRoute from "./ProtectedRoute";
import { permissionsForRoute, routePermissions } from "./routes";

const renderRoute = (requiredPermissions?: readonly (typeof PERMISSIONS)[keyof typeof PERMISSIONS][]) => render(
  <MemoryRouter initialEntries={["/private"]}>
    <Routes>
      <Route element={<ProtectedRoute requiredPermissions={requiredPermissions} />}>
        <Route path="/private" element={<p>Contenido privado</p>} />
      </Route>
      <Route path="/login" element={<p>Login</p>} />
      <Route path="/unauthorized" element={<p>Sin permiso</p>} />
    </Routes>
  </MemoryRouter>,
);

describe("ProtectedRoute", () => {
  beforeEach(() => {
    auth.isAuth = false;
    auth.loading = false;
    auth.user = null;
    vi.clearAllMocks();
  });

  it("mantiene /unauthorized autenticada sin exigir permiso funcional", () => {
    auth.isAuth = true;
    auth.user = { roles: [], permisos: [] };

    render(
      <MemoryRouter initialEntries={["/unauthorized"]}>
        <Routes>
          <Route element={<ProtectedRoute />}>
            <Route path="/unauthorized" element={<p>Sin permiso</p>} />
          </Route>
          <Route path="/login" element={<p>Login</p>} />
        </Routes>
      </MemoryRouter>,
    );

    expect(screen.getByText("Sin permiso")).toBeVisible();
    expect(permissionsForRoute("/unauthorized")).toBeUndefined();
    expect(auth.hasAllPermissions).not.toHaveBeenCalled();
  });

  it("redirige una sesión anónima sin montar el contenido", () => {
    renderRoute();
    expect(screen.getByText("Login")).toBeVisible();
    expect(screen.queryByText("Contenido privado")).not.toBeInTheDocument();
  });

  it("exige APP y permiso funcional en conjunto", () => {
    auth.isAuth = true;
    auth.user = { roles: [], permisos: [] };
    const required = [PERMISSIONS.APP_ACCESS, PERMISSIONS.ALUMNOS_LEER] as const;

    auth.hasAllPermissions.mockReturnValueOnce(false);
    const denied = renderRoute(required);
    expect(screen.getByText("Sin permiso")).toBeVisible();
    denied.unmount();

    auth.hasAllPermissions.mockReturnValueOnce(true);
    renderRoute(required);
    expect(screen.getByText("Contenido privado")).toBeVisible();
    expect(auth.hasAllPermissions).toHaveBeenLastCalledWith(required);
  });

  it.each([
    ["alumnos lectura", "/alumnos", PERMISSIONS.ALUMNOS_LEER],
    ["alumnos alta", "/alumnos/formulario", PERMISSIONS.ALUMNOS_ADMIN],
    ["inscripciones lectura", "/inscripciones", PERMISSIONS.INSCRIPCIONES_LEER],
    ["inscripciones alta", "/inscripciones/formulario", PERMISSIONS.INSCRIPCIONES_ADMIN],
    ["disciplinas lectura", "/disciplinas", PERMISSIONS.DISCIPLINAS_LEER],
    ["disciplinas alta", "/disciplinas/formulario", PERMISSIONS.DISCIPLINAS_ADMIN],
    ["profesores lectura", "/profesores", PERMISSIONS.PROFESORES_LEER],
    ["profesores alta", "/profesores/formulario", PERMISSIONS.PROFESORES_ADMIN],
    ["asistencias lectura", "/asistencias/alumnos", PERMISSIONS.ASISTENCIAS_LEER],
    ["pagos lectura", "/pagos", PERMISSIONS.PAGOS_LEER],
    ["pagos registro", "/pagos/formulario", PERMISSIONS.PAGOS_REGISTRAR],
    ["caja", "/caja", PERMISSIONS.CAJA_LEER],
    ["egresos", "/egresos", PERMISSIONS.EGRESOS_ADMIN],
    ["stock lectura", "/stocks", PERMISSIONS.STOCK_LEER],
    ["stock administración", "/stocks/formulario", PERMISSIONS.STOCK_ADMIN],
    ["tarifas", "/disciplinas/:id/tarifas", PERMISSIONS.TARIFAS_ADMIN],
    ["condiciones", "/inscripciones/:id/condiciones-economicas", PERMISSIONS.CONDICIONES_ECONOMICAS_ADMIN],
    ["reportes", "/reportes", PERMISSIONS.REPORTES_LEER],
    ["usuarios", "/usuarios", PERMISSIONS.USUARIOS_ADMIN],
    ["roles", "/roles", PERMISSIONS.ROLES_ADMIN],
    ["configuración lectura", "/metodos-pago", PERMISSIONS.CONFIG_LEER],
    ["configuración alta", "/metodos-pago/formulario", PERMISSIONS.CONFIG_ADMIN],
  ] as const)("prueba permitido y denegado para %s", (_name, path, functionalPermission) => {
    const policy = routePermissions[path];
    expect(policy).toEqual([PERMISSIONS.APP_ACCESS, functionalPermission]);

    auth.isAuth = true;
    auth.user = { roles: [], permisos: [] };
    auth.hasAllPermissions.mockReturnValueOnce(false);
    const denied = renderRoute(policy);
    expect(screen.getByText("Sin permiso")).toBeVisible();
    denied.unmount();

    auth.hasAllPermissions.mockReturnValueOnce(true);
    renderRoute(policy);
    expect(screen.getByText("Contenido privado")).toBeVisible();
  });
});
