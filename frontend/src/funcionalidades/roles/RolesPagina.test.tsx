import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { PERMISSIONS } from "../../config/permissions";

const mocks = vi.hoisted(() => ({
  listar: vi.fn(),
  hasPermission: vi.fn(),
}));

vi.mock("../../api/rolesApi", () => ({
  default: { listar: mocks.listar, desactivar: vi.fn() },
}));
vi.mock("../../hooks/context/useAuth", () => ({
  useAuth: () => ({ hasPermission: mocks.hasPermission }),
}));

import RolesPagina from "./RolesPagina";

describe("RolesPagina", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.listar.mockResolvedValue([{
      id: 1,
      codigo: "LECTURA",
      nombre: "Lectura",
      activo: true,
      sistema: true,
      editable: false,
      cantidadPermisos: 1,
    }]);
  });

  it("no ofrece mutaciones a quien sólo puede leer roles", async () => {
    mocks.hasPermission.mockReturnValue(false);

    render(<MemoryRouter><RolesPagina /></MemoryRouter>);

    expect(await screen.findAllByText("Lectura")).not.toHaveLength(0);
    expect(screen.queryByRole("button", { name: /nuevo rol/i })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /editar/i })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /desactivar/i })).not.toBeInTheDocument();
  });

  it("ofrece mutaciones con el permiso real de administración", async () => {
    mocks.hasPermission.mockImplementation(
      (permission) => permission === PERMISSIONS.ROLES_ADMIN,
    );

    render(<MemoryRouter><RolesPagina /></MemoryRouter>);

    expect(await screen.findByRole("button", { name: /nuevo rol/i })).toBeVisible();
    expect(mocks.hasPermission).toHaveBeenCalledWith(PERMISSIONS.ROLES_ADMIN);
  });
});
