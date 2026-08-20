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

vi.mock("../../api/recargosApi", () => ({
  default: {
    obtenerRecargoPorId: api.obtener,
    crearRecargo: api.crear,
    actualizarRecargo: api.actualizar,
  },
}));
vi.mock("react-toastify", () => ({
  toast: { success: toastSuccess, error: toastError },
}));
vi.mock("react-router", async (importOriginal) => ({
  ...(await importOriginal<typeof import("react-router")>()),
  useNavigate: () => navigate,
}));

import RecargosFormulario from "./RecargosFormulario";

describe("RecargosFormulario", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.obtener.mockResolvedValue(recargo(10));
    api.crear.mockResolvedValue(recargo(11));
    api.actualizar.mockResolvedValue(recargo(10));
  });

  it("valida la descripción y crea con los importes y día configurados", async () => {
    renderForm();

    fireEvent.change(screen.getByLabelText("Descripcion:"), { target: { value: "ab" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));
    expect(await screen.findByText("Debe tener al menos 3 caracteres")).toBeVisible();
    expect(api.crear).not.toHaveBeenCalled();

    fireEvent.change(screen.getByLabelText("Descripcion:"), { target: { value: "Mora mensual" } });
    fireEvent.change(screen.getByLabelText("Porcentaje:"), { target: { value: "12.5" } });
    fireEvent.change(screen.getByLabelText("Valor Fijo:"), { target: { value: "1500.00" } });
    fireEvent.change(screen.getByLabelText("Dia del Mes:"), { target: { value: "10" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));

    await waitFor(() => expect(api.crear).toHaveBeenCalledWith({
      descripcion: "Mora mensual",
      porcentaje: "12.50",
      valorFijo: "1500.00",
      diaDelMesAplicacion: 10,
    }));
    expect(toastSuccess).toHaveBeenCalledWith("Recargo creado correctamente.");
    expect(await screen.findByRole("heading", { name: "Editar Recargo" })).toBeVisible();
  });

  it("muestra carga, precarga el ID de la ruta y actualiza el recargo", async () => {
    let resolveRecargo!: (value: ReturnType<typeof recargo>) => void;
    api.obtener.mockReturnValueOnce(new Promise((resolve) => { resolveRecargo = resolve; }));
    renderForm("/recargos/formulario?id=10");

    expect(screen.getByText("Cargando datos...")).toBeVisible();
    resolveRecargo(recargo(10));

    expect(await screen.findByDisplayValue("Recargo 10")).toBeVisible();
    expect(toastSuccess).toHaveBeenCalledWith("Recargo cargado correctamente.");
    fireEvent.change(screen.getByLabelText("Descripcion:"), { target: { value: "Recargo actualizado" } });
    fireEvent.click(screen.getByRole("button", { name: "Actualizar" }));

    await waitFor(() => expect(api.actualizar).toHaveBeenCalledWith(10, {
      descripcion: "Recargo actualizado",
      porcentaje: "5.00",
      valorFijo: "1000.00",
      diaDelMesAplicacion: 15,
    }));
    expect(api.crear).not.toHaveBeenCalled();
    expect(toastSuccess).toHaveBeenCalledWith("Recargo actualizado correctamente.");
  });

  it("aplica el valor fijo por defecto al cargar una respuesta sin ese importe", async () => {
    api.obtener.mockResolvedValueOnce({ ...recargo(12), valorFijo: undefined });
    renderForm("/recargos/formulario?id=12");

    expect(await screen.findByDisplayValue("Recargo 12")).toBeVisible();
    expect(screen.getByLabelText("Valor Fijo:")).toHaveValue(0);
  });

  it("restablece los valores ante una precarga fallida", async () => {
    api.obtener.mockRejectedValueOnce(new Error("not found"));
    renderForm("/recargos/formulario?id=999");

    await waitFor(() => expect(toastError).toHaveBeenCalledWith("Recargo no encontrado."));
    expect(screen.getByLabelText("Descripcion:")).toHaveValue("");
    expect(screen.getByLabelText("Porcentaje:")).toHaveValue(0);
    expect(screen.getByRole("button", { name: "Guardar" })).toBeVisible();
  });

  it("rehabilita el envío ante error y permite volver al listado", async () => {
    api.crear.mockRejectedValueOnce(new Error("conflict"));
    renderForm();

    fireEvent.change(screen.getByLabelText("Descripcion:"), { target: { value: "Recargo válido" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));

    await waitFor(() => expect(toastError).toHaveBeenCalledWith("Error al guardar el recargo."));
    expect(screen.getByRole("button", { name: "Guardar" })).toBeEnabled();
    expect(screen.getByLabelText("Descripcion:")).toHaveValue("Recargo válido");
    fireEvent.click(screen.getByRole("button", { name: "Volver al Listado" }));
    expect(navigate).toHaveBeenCalledWith("/recargos");
  });
});

function renderForm(initialEntry = "/recargos/formulario") {
  return render(
    <MemoryRouter initialEntries={[initialEntry]}>
      <RecargosFormulario />
    </MemoryRouter>,
  );
}

function recargo(id: number) {
  return {
    id,
    descripcion: `Recargo ${id}`,
    porcentaje: "5.00",
    valorFijo: "1000.00",
    diaDelMesAplicacion: 15,
  };
}
