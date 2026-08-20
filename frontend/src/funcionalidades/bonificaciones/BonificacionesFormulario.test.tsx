import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";

const api = vi.hoisted(() => ({
  obtener: vi.fn(),
  crear: vi.fn(),
  actualizar: vi.fn(),
}));
const navigate = vi.hoisted(() => vi.fn());
const toastSuccess = vi.hoisted(() => vi.fn());
const toastError = vi.hoisted(() => vi.fn());

vi.mock("../../api/bonificacionesApi", () => ({
  default: {
    obtenerBonificacionPorId: api.obtener,
    crearBonificacion: api.crear,
    actualizarBonificacion: api.actualizar,
  },
}));
vi.mock("react-toastify", () => ({
  toast: { success: toastSuccess, error: toastError },
}));
vi.mock("react-router", async (importOriginal) => ({
  ...(await importOriginal<typeof import("react-router")>()),
  useNavigate: () => navigate,
}));

import BonificacionesFormulario from "./BonificacionesFormulario";

describe("BonificacionesFormulario", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.crear.mockResolvedValue(bonificacion(41));
    api.actualizar.mockResolvedValue(bonificacion(41));
    api.obtener.mockResolvedValue(bonificacion(41));
  });

  it("valida la descripción y crea sin confiar en un ID ingresado por el usuario", async () => {
    renderForm();

    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));

    expect(await screen.findByText("La descripcion es obligatoria")).toBeVisible();
    expect(api.crear).not.toHaveBeenCalled();

    fireEvent.change(screen.getByLabelText("Descripcion:"), { target: { value: "Beca familiar" } });
    fireEvent.change(screen.getByLabelText("Porcentaje de Descuento:"), { target: { value: "25" } });
    fireEvent.change(screen.getByLabelText("Valor Fijo:"), { target: { value: "1500" } });
    fireEvent.change(screen.getByLabelText("Observaciones:"), { target: { value: "Vigencia anual" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));

    await waitFor(() => expect(api.crear).toHaveBeenCalledWith({
      descripcion: "Beca familiar",
      porcentajeDescuento: "25.00",
      valorFijo: "1500.00",
      observaciones: "Vigencia anual",
      activo: true,
    }));
    expect(toastSuccess).toHaveBeenCalledWith("Bonificacion creada correctamente.");
    expect(await screen.findByText("Bonificacion guardada exitosamente.")).toBeVisible();
  });

  it("busca una bonificación, conserva sus importes y actualiza el registro encontrado", async () => {
    renderForm();

    fireEvent.change(screen.getByLabelText("Numero de Bonificacion:"), { target: { value: "41" } });
    fireEvent.click(screen.getByRole("button", { name: "Buscar" }));

    await waitFor(() => expect(api.obtener).toHaveBeenCalledWith(41));
    expect(await screen.findByDisplayValue("Beca hermanos")).toBeVisible();
    expect(screen.getByLabelText("Activo")).toBeChecked();

    fireEvent.change(screen.getByLabelText("Descripcion:"), { target: { value: "Beca hermanos actualizada" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));

    await waitFor(() => expect(api.actualizar).toHaveBeenCalledWith(41, expect.objectContaining({
      descripcion: "Beca hermanos actualizada",
      porcentajeDescuento: "20.00",
      valorFijo: "0.00",
      activo: true,
    })));
    expect(api.crear).not.toHaveBeenCalled();
  });

  it("informa búsqueda vacía, recupera un rechazo y permite limpiar y volver", async () => {
    api.obtener.mockRejectedValueOnce(new Error("not found"));
    renderForm();

    fireEvent.click(screen.getByRole("button", { name: "Buscar" }));
    expect(await screen.findByText("Por favor, ingrese un ID de bonificacion.")).toBeVisible();

    fireEvent.change(screen.getByLabelText("Numero de Bonificacion:"), { target: { value: "999" } });
    fireEvent.click(screen.getByRole("button", { name: "Buscar" }));
    await waitFor(() => expect(toastError).toHaveBeenCalledWith("Error al buscar la bonificacion:"));
    expect(screen.getByLabelText("Numero de Bonificacion:")).toHaveValue(null);

    fireEvent.change(screen.getByLabelText("Descripcion:"), { target: { value: "Temporal" } });
    fireEvent.click(screen.getByRole("button", { name: "Limpiar" }));
    expect(screen.getByLabelText("Descripcion:")).toHaveValue("");

    fireEvent.click(screen.getByRole("button", { name: "Volver al Listado" }));
    expect(navigate).toHaveBeenCalledWith("/bonificaciones");
  });

  it("mantiene el formulario utilizable cuando el backend rechaza el guardado", async () => {
    api.crear.mockRejectedValueOnce(new Error("conflict"));
    renderForm();

    fireEvent.change(screen.getByLabelText("Descripcion:"), { target: { value: "Beca especial" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));

    expect(await screen.findByText("Error al guardar la bonificacion.")).toBeVisible();
    expect(toastError).toHaveBeenCalledWith("Error al guardar la bonificacion.");
    expect(screen.getByRole("button", { name: "Guardar" })).toBeEnabled();
  });
});

function renderForm(initialEntry = "/bonificaciones/formulario") {
  return render(
    <MemoryRouter initialEntries={[initialEntry]}>
      <BonificacionesFormulario />
    </MemoryRouter>,
  );
}

function bonificacion(id: number) {
  return {
    id,
    descripcion: "Beca hermanos",
    porcentajeDescuento: "20",
    observaciones: "Grupo familiar",
    valorFijo: "0.00",
    activo: true,
  };
}
