import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { PERMISSIONS } from "../../config/permissions";

const mocks = vi.hoisted(() => ({
  listar: vi.fn(),
  hasPermission: vi.fn(),
}));

vi.mock("../../api/usuariosApi", () => ({
  default: { listarUsuarios: mocks.listar, eliminarUsuario: vi.fn() },
}));
vi.mock("../../hooks/context/useAuth", () => ({
  useAuth: () => ({ hasPermission: mocks.hasPermission }),
}));

import UsuariosPagina from "./UsuariosPagina";

describe("UsuariosPagina", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.listar.mockResolvedValue([{
      id: 1,
      nombreUsuario: "lector",
      roles: ["LECTURA"],
      permisos: ["USUARIOS_READ"],
      activo: true,
    }]);
  });

  it("no ofrece mutaciones a quien sólo puede leer usuarios", async () => {
    mocks.hasPermission.mockReturnValue(false);

    render(<MemoryRouter><UsuariosPagina /></MemoryRouter>);

    expect(await screen.findAllByText("lector")).not.toHaveLength(0);
    expect(screen.queryByRole("button", { name: /registrar nuevo usuario/i })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /editar usuario/i })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /eliminar usuario/i })).not.toBeInTheDocument();
  });

  it("ofrece mutaciones con el permiso real de administración", async () => {
    mocks.hasPermission.mockImplementation(
      (permission) => permission === PERMISSIONS.USUARIOS_ADMIN,
    );

    render(<MemoryRouter><UsuariosPagina /></MemoryRouter>);

    expect(await screen.findByRole("button", { name: /registrar nuevo usuario/i })).toBeVisible();
    expect(mocks.hasPermission).toHaveBeenCalledWith(PERMISSIONS.USUARIOS_ADMIN);
  });
});
