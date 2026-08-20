import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { PERMISSIONS } from "../config/permissions";

const mocks = vi.hoisted(() => ({ hasPermission: vi.fn() }));
vi.mock("../hooks/context/useAuth", () => ({ useAuth: () => ({ hasPermission: mocks.hasPermission }) }));

import Dashboard from "./Dashboard";

describe("Dashboard", () => {
  beforeEach(() => mocks.hasPermission.mockImplementation((permission) => [
    PERMISSIONS.APP_ACCESS,
    PERMISSIONS.ALUMNOS_LEER,
    PERMISSIONS.CONFIG_LEER,
  ].includes(permission)));

  it("presenta accesos simples y categorías filtradas", () => {
    renderPage();
    expect(screen.getByRole("link", { name: /Alumnos/ })).toHaveAttribute("href", "/alumnos");
    expect(screen.getByText("Administración")).toBeVisible();
    fireEvent.click(screen.getByText("Administración"));
    expect(screen.getByRole("link", { name: /Métodos de pago/ })).toHaveAttribute("href", "/metodos-pago");
    expect(screen.queryByText("Seguridad")).not.toBeInTheDocument();
  });

  it("no inventa accesos frecuentes cuando no hay permisos", () => {
    mocks.hasPermission.mockReturnValue(false);
    renderPage();
    expect(screen.queryByText("Accesos frecuentes")).not.toBeInTheDocument();
    expect(screen.getByText("Gestión del sistema")).toBeVisible();
  });
});

function renderPage() {
  render(<MemoryRouter><Dashboard /></MemoryRouter>);
}
