import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";

const api = vi.hoisted(() => ({
  listarPermisos: vi.fn(),
  crearRol: vi.fn(),
  obtenerRol: vi.fn(),
  modificarRol: vi.fn(),
  asignarPermisos: vi.fn(),
}));

vi.mock("../../api/permisosApi", () => ({ default: { listar: api.listarPermisos } }));
vi.mock("../../api/rolesApi", () => ({
  default: {
    crear: api.crearRol,
    obtener: api.obtenerRol,
    modificar: api.modificarRol,
    asignarPermisos: api.asignarPermisos,
  },
}));

import RolesFormulario from "./RolesFormulario";

describe("RolesFormulario", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.listarPermisos.mockResolvedValue([
      { id: 1, codigo: "ALUMNOS_READ", descripcion: "Consultar alumnos", modulo: "ALUMNOS", activo: true, sistema: true },
      { id: 2, codigo: "PAGOS_WRITE", descripcion: "Registrar pagos", modulo: "FINANZAS", activo: true, sistema: true },
    ]);
    api.crearRol.mockResolvedValue({
      id: 7,
      codigo: "OPERADOR",
      nombre: "Operador",
      activo: true,
      sistema: false,
      editable: true,
      permisos: [],
    });
    api.asignarPermisos.mockResolvedValue({});
  });

  it("agrupa permisos y envía los seleccionados", async () => {
    render(<MemoryRouter><RolesFormulario /></MemoryRouter>);

    expect(await screen.findByText("ALUMNOS")).toBeVisible();
    expect(screen.getByText("FINANZAS")).toBeVisible();
    fireEvent.change(screen.getByLabelText("Código"), { target: { value: "OPERADOR" } });
    fireEvent.change(screen.getByLabelText("Nombre"), { target: { value: "Operador" } });
    fireEvent.click(screen.getByText("ALUMNOS_READ").closest("label")!.querySelector("input")!);
    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));

    await waitFor(() => expect(api.crearRol).toHaveBeenCalledWith({
      codigo: "OPERADOR",
      nombre: "Operador",
      descripcionFuncional: undefined,
    }));
    expect(api.asignarPermisos).toHaveBeenCalledWith(7, ["ALUMNOS_READ"]);
  });
});
