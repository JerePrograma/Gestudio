import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";

const api = vi.hoisted(() => ({ obtener: vi.fn(), registrar: vi.fn(), actualizar: vi.fn() }));
const navigate = vi.hoisted(() => vi.fn());
const toastSuccess = vi.hoisted(() => vi.fn());
const toastError = vi.hoisted(() => vi.fn());

vi.mock("../../api/salonesApi", () => ({
  default: {
    obtenerSalonPorId: api.obtener,
    registrarSalon: api.registrar,
    actualizarSalon: api.actualizar,
  },
}));
vi.mock("react-toastify", () => ({ toast: { success: toastSuccess, error: toastError } }));
vi.mock("react-router", async (importOriginal) => ({
  ...(await importOriginal<typeof import("react-router")>()),
  useNavigate: () => navigate,
}));

import SalonesFormulario from "./SalonesFormulario";

describe("SalonesFormulario", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.obtener.mockResolvedValue(salon(3));
    api.registrar.mockResolvedValue(salon(3));
    api.actualizar.mockResolvedValue(salon(3));
  });

  it("valida y registra un salón nuevo", async () => {
    renderForm();

    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));
    expect(await screen.findByText("El nombre es obligatorio")).toBeVisible();
    expect(api.registrar).not.toHaveBeenCalled();

    fireEvent.change(screen.getByLabelText("Nombre:"), { target: { value: "Sala Norte" } });
    fireEvent.change(screen.getByLabelText("Descripcion:"), { target: { value: "Piso de madera" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));

    await waitFor(() => expect(api.registrar).toHaveBeenCalledWith({
      nombre: "Sala Norte",
      descripcion: "Piso de madera",
    }));
    expect(toastSuccess).toHaveBeenCalledWith("Salon creado correctamente.");
  });

  it("busca por ID y actualiza el salón cargado", async () => {
    renderForm();

    fireEvent.change(screen.getByLabelText("Numero de Salon:"), { target: { value: "3" } });
    fireEvent.click(screen.getByRole("button", { name: "Buscar" }));
    await waitFor(() => expect(api.obtener).toHaveBeenCalledWith(3));
    expect(await screen.findByDisplayValue("Salón principal")).toBeVisible();

    fireEvent.change(screen.getByLabelText("Descripcion:"), { target: { value: "Capacidad 40" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));
    await waitFor(() => expect(api.actualizar).toHaveBeenCalledWith(3, {
      nombre: "Salón principal",
      descripcion: "Capacidad 40",
    }));
    expect(api.registrar).not.toHaveBeenCalled();
  });

  it("cubre búsqueda vacía/fallida y restablece el formulario", async () => {
    api.obtener.mockRejectedValueOnce(new Error("not found"));
    renderForm();

    fireEvent.click(screen.getByRole("button", { name: "Buscar" }));
    expect(await screen.findByText("Por favor, ingrese un ID de salon.")).toBeVisible();

    fireEvent.change(screen.getByLabelText("Numero de Salon:"), { target: { value: "99" } });
    fireEvent.click(screen.getByRole("button", { name: "Buscar" }));
    await waitFor(() => expect(toastError).toHaveBeenCalledWith("Error al buscar el salon:"));
    expect(screen.getByLabelText("Numero de Salon:")).toHaveValue(null);

    fireEvent.change(screen.getByLabelText("Nombre:"), { target: { value: "Temporal" } });
    fireEvent.click(screen.getByRole("button", { name: "Limpiar" }));
    expect(screen.getByLabelText("Nombre:")).toHaveValue("");
  });

  it("muestra el rechazo de guardado y permite volver al listado", async () => {
    api.registrar.mockRejectedValueOnce(new Error("conflict"));
    renderForm();
    fireEvent.change(screen.getByLabelText("Nombre:"), { target: { value: "Sala Sur" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));

    expect(await screen.findByText("Error al guardar el salon.")).toBeVisible();
    expect(toastError).toHaveBeenCalledWith("Error al guardar el salon.");

    fireEvent.click(screen.getByRole("button", { name: "Volver al Listado" }));
    expect(navigate).toHaveBeenCalledWith("/salones");
  });
});

function renderForm() {
  return render(<MemoryRouter><SalonesFormulario /></MemoryRouter>);
}

function salon(id: number) {
  return { id, nombre: "Salón principal", descripcion: "Planta baja" };
}
