import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";

const api = vi.hoisted(() => ({
  obtener: vi.fn(),
  registrar: vi.fn(),
  actualizar: vi.fn(),
}));
const navigate = vi.hoisted(() => vi.fn());
const toastSuccess = vi.hoisted(() => vi.fn());
const toastError = vi.hoisted(() => vi.fn());

vi.mock("../../api/profesoresApi", () => ({
  default: {
    obtenerProfesorPorId: api.obtener,
    registrarProfesor: api.registrar,
    actualizarProfesor: api.actualizar,
  },
}));
vi.mock("react-toastify", () => ({ toast: { success: toastSuccess, error: toastError } }));
vi.mock("react-router", async (importOriginal) => ({
  ...(await importOriginal<typeof import("react-router")>()),
  useNavigate: () => navigate,
}));

import ProfesoresFormulario from "./ProfesoresFormulario";

describe("ProfesoresFormulario", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.obtener.mockResolvedValue(profesor(8));
    api.registrar.mockResolvedValue(profesor(8));
    api.actualizar.mockResolvedValue(profesor(8));
  });

  it("valida identidad mínima y registra la fecha en formato civil", async () => {
    renderForm();

    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));
    expect(await screen.findByText("El nombre es obligatorio")).toBeVisible();
    expect(await screen.findByText("El apellido es obligatorio")).toBeVisible();
    expect(api.registrar).not.toHaveBeenCalled();

    fireEvent.change(screen.getByLabelText("Nombre:"), { target: { value: "Ada" } });
    fireEvent.change(screen.getByLabelText("Apellido:"), { target: { value: "Lovelace" } });
    fireEvent.change(screen.getByLabelText("Fecha de Nacimiento:"), { target: { value: "1990-05-12" } });
    fireEvent.change(screen.getByLabelText("Telefono:"), { target: { value: "2235550101" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));

    await waitFor(() => expect(api.registrar).toHaveBeenCalledWith({
      nombre: "Ada",
      apellido: "Lovelace",
      fechaNacimiento: "1990-05-12",
      telefono: "2235550101",
      activo: true,
    }));
    expect(toastSuccess).toHaveBeenCalledWith("Profesor creado correctamente.");
  });

  it("busca, habilita el estado y actualiza el profesor cargado", async () => {
    renderForm();

    fireEvent.change(screen.getByLabelText("Numero de Profesor:"), { target: { value: "8" } });
    fireEvent.click(screen.getByRole("button", { name: "Buscar" }));

    await waitFor(() => expect(api.obtener).toHaveBeenCalledWith(8));
    expect(await screen.findByDisplayValue("Grace")).toBeVisible();
    fireEvent.click(screen.getByLabelText("Activo"));
    fireEvent.change(screen.getByLabelText("Telefono:"), { target: { value: "2230000000" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));

    await waitFor(() => expect(api.actualizar).toHaveBeenCalledWith(8, expect.objectContaining({
      nombre: "Grace",
      apellido: "Hopper",
      activo: false,
      telefono: "2230000000",
    })));
    expect(api.registrar).not.toHaveBeenCalled();
  });

  it("maneja búsqueda vacía y fallida sin dejar identidad anterior", async () => {
    api.obtener.mockRejectedValueOnce(new Error("not found"));
    renderForm();

    fireEvent.click(screen.getByRole("button", { name: "Buscar" }));
    expect(await screen.findByText("Por favor, ingrese un ID de profesor.")).toBeVisible();

    fireEvent.change(screen.getByLabelText("Numero de Profesor:"), { target: { value: "404" } });
    fireEvent.click(screen.getByRole("button", { name: "Buscar" }));

    await waitFor(() => expect(toastError).toHaveBeenCalledWith("Error al buscar el profesor:"));
    expect(screen.getByLabelText("Numero de Profesor:")).toHaveValue(null);
    expect(screen.queryByLabelText("Activo")).not.toBeInTheDocument();
  });

  it("expone rechazo de guardado, limpia el formulario y vuelve al listado", async () => {
    api.registrar.mockRejectedValueOnce(new Error("conflict"));
    renderForm();

    fireEvent.change(screen.getByLabelText("Nombre:"), { target: { value: "Alan" } });
    fireEvent.change(screen.getByLabelText("Apellido:"), { target: { value: "Turing" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));
    expect(await screen.findByText("Error al guardar el profesor.")).toBeVisible();

    fireEvent.click(screen.getByRole("button", { name: "Limpiar" }));
    expect(screen.getByLabelText("Nombre:")).toHaveValue("");
    fireEvent.click(screen.getByRole("button", { name: "Volver al Listado" }));
    expect(navigate).toHaveBeenCalledWith("/profesores");
  });
});

function renderForm() {
  return render(<MemoryRouter><ProfesoresFormulario /></MemoryRouter>);
}

function profesor(id: number) {
  return {
    id,
    nombre: "Grace",
    apellido: "Hopper",
    fechaNacimiento: "1906-12-09",
    edad: 85,
    telefono: "2235550909",
    activo: true,
    disciplinas: [],
  };
}
