import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { describe, expect, it, vi } from "vitest";

const auth = vi.hoisted(() => ({
  isAuth: false,
  loading: false,
  user: null as null | { roles: string[]; permisos: string[] },
  hasRole: vi.fn<(role: string) => boolean>(),
  hasPermission: vi.fn<(permission: string) => boolean>(),
}));

vi.mock("../hooks/context/useAuth", () => ({ useAuth: () => auth }));

import ProtectedRoute from "./ProtectedRoute";

const renderRoute = (requiredRole?: string, requiredPermission?: string) => render(
  <MemoryRouter initialEntries={["/private"]}>
    <Routes>
      <Route element={<ProtectedRoute requiredRole={requiredRole} requiredPermission={requiredPermission} />}>
        <Route path="/private" element={<p>Contenido privado</p>} />
      </Route>
      <Route path="/login" element={<p>Login</p>} />
      <Route path="/unauthorized" element={<p>Sin permiso</p>} />
    </Routes>
  </MemoryRouter>,
);

describe("ProtectedRoute", () => {
  it("redirige una sesión anónima sin montar el contenido", () => {
    auth.isAuth = false;
    auth.loading = false;
    auth.user = null;
    renderRoute();
    expect(screen.getByText("Login")).toBeVisible();
    expect(screen.queryByText("Contenido privado")).not.toBeInTheDocument();
  });

  it("distingue carga, acceso y rol insuficiente", () => {
    auth.loading = true;
    const loading = renderRoute();
    expect(screen.getByRole("status")).toHaveTextContent("Cargando perfil");
    loading.unmount();

    auth.loading = false;
    auth.isAuth = true;
    auth.user = { roles: ["LECTURA"], permisos: [] };
    auth.hasRole.mockReturnValue(false);
    renderRoute("ADMINISTRADOR");
    expect(screen.getByText("Sin permiso")).toBeVisible();
  });

  it("autoriza y rechaza rutas según permiso", () => {
    auth.loading = false;
    auth.isAuth = true;
    auth.user = { roles: ["RECEPCION"], permisos: ["ALUMNOS_READ"] };
    auth.hasPermission.mockReturnValueOnce(true);
    const allowed = renderRoute(undefined, "ALUMNOS_READ");
    expect(screen.getByText("Contenido privado")).toBeVisible();
    allowed.unmount();

    auth.hasPermission.mockReturnValueOnce(false);
    renderRoute(undefined, "PAGOS_WRITE");
    expect(screen.getByText("Sin permiso")).toBeVisible();
  });
});
