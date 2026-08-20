import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { PERMISSIONS } from "../config/permissions";

const mocks = vi.hoisted(() => ({ hasPermission: vi.fn(), loading: false, user: { nombreUsuario: "lector" } }));
vi.mock("../hooks/context/useAuth", () => ({ useAuth: () => mocks }));

import Navigation from "./Navigation";

describe("Navigation", () => {
  beforeEach(() => {
    mocks.loading = false;
    mocks.user = { nombreUsuario: "lector" };
    mocks.hasPermission.mockImplementation((permission) => [
      PERMISSIONS.APP_ACCESS,
      PERMISSIONS.ALUMNOS_LEER,
      PERMISSIONS.CONFIG_LEER,
    ].includes(permission));
  });

  it("muestra fallback mientras falta el perfil", () => {
    mocks.loading = true;
    renderPage();
    expect(screen.getByText("Cargando navegación...")).toBeVisible();
  });

  it("filtra enlaces y conserva categorías con hijos permitidos", () => {
    renderPage();
    expect(screen.getByRole("link", { name: "Alumnos" })).toHaveAttribute("href", "/alumnos");
    expect(screen.getByText("Administración")).toBeVisible();
    expect(screen.getByRole("link", { name: "Métodos de pago" })).toBeVisible();
    expect(screen.queryByRole("link", { name: "Usuarios" })).not.toBeInTheDocument();
  });
});

function renderPage() {
  render(<MemoryRouter><Navigation /></MemoryRouter>);
}
