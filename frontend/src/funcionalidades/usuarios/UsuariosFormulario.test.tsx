import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

const api = vi.hoisted(() => ({
  listarRolesAsignables: vi.fn(),
  obtenerUsuario: vi.fn(),
  registrarUsuario: vi.fn(),
  actualizarUsuario: vi.fn(),
}));

vi.mock("../../api/usuariosApi", () => ({
  default: {
    listarRolesAsignables: api.listarRolesAsignables,
    obtenerUsuarioPorId: api.obtenerUsuario,
    registrarUsuario: api.registrarUsuario,
    actualizarUsuario: api.actualizarUsuario,
  },
}));

import UsuariosFormulario from "./UsuariosFormulario";

describe("UsuariosFormulario RBAC", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.listarRolesAsignables.mockResolvedValue([
      { codigo: "CAJA", nombre: "Caja" },
    ]);
    api.obtenerUsuario.mockResolvedValue(null);
    api.actualizarUsuario.mockResolvedValue(undefined);
  });

  it("consume sólo la proyección backend de roles asignables", async () => {
    render(<MemoryRouter><UsuariosFormulario /></MemoryRouter>);

    expect(await screen.findByRole("checkbox", { name: /Caja.*CAJA/ })).toBeVisible();
    expect(api.listarRolesAsignables).toHaveBeenCalledOnce();
  });

  it("conserva PROFESOR como rol deshabilitado al editar otros datos", async () => {
    api.obtenerUsuario.mockResolvedValue({
      id: 7,
      nombreUsuario: "docente",
      roles: ["CAJA", "PROFESOR"],
      permisos: [],
      activo: true,
    });

    render(
      <MemoryRouter initialEntries={["/usuarios/formulario?id=7"]}>
        <UsuariosFormulario />
      </MemoryRouter>,
    );

    expect(await screen.findByRole("checkbox", { name: /PROFESOR.*conservado/ })).toBeDisabled();
    fireEvent.change(screen.getByLabelText("Nombre de usuario"), { target: { value: "docente-editado" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));

    await waitFor(() => expect(api.actualizarUsuario).toHaveBeenCalledWith(7, expect.objectContaining({
      nombreUsuario: "docente-editado",
      roles: ["CAJA", "PROFESOR"],
    })));
  });

  it("no presenta un formulario que reenviaría un rol fuera de delegación", async () => {
    api.obtenerUsuario.mockResolvedValue({
      id: 8,
      nombreUsuario: "root",
      roles: ["SUPERADMIN"],
      permisos: [],
      activo: true,
    });

    render(
      <MemoryRouter initialEntries={["/usuarios/formulario?id=8"]}>
        <UsuariosFormulario />
      </MemoryRouter>,
    );

    expect(await screen.findByRole("alert")).toHaveTextContent("No tenés autorización");
    expect(screen.queryByRole("button", { name: "Guardar" })).not.toBeInTheDocument();
  });
});
