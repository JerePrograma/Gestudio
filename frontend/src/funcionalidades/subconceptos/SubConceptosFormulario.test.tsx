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

vi.mock("../../api/subConceptosApi", () => ({
  default: {
    obtenerSubConceptoPorId: api.obtener,
    registrarSubConcepto: api.registrar,
    actualizarSubConcepto: api.actualizar,
  },
}));
vi.mock("react-toastify", () => ({
  toast: { success: toastSuccess, error: toastError },
}));
vi.mock("react-router", async (importOriginal) => ({
  ...(await importOriginal<typeof import("react-router")>()),
  useNavigate: () => navigate,
}));

import SubConceptosFormulario from "./SubConceptosFormulario";

describe("SubConceptosFormulario", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.obtener.mockResolvedValue(subConcepto(14));
    api.registrar.mockResolvedValue(subConcepto(15));
    api.actualizar.mockResolvedValue(subConcepto(14));
  });

  it("valida la descripción y registra un subconcepto nuevo", async () => {
    renderForm();

    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));
    expect(await screen.findByText("La descripcion es obligatoria")).toBeVisible();
    expect(api.registrar).not.toHaveBeenCalled();

    fireEvent.change(descriptionField(), { target: { value: "Aranceles" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));

    await waitFor(() => expect(api.registrar).toHaveBeenCalledWith({ descripcion: "Aranceles" }));
    expect(toastSuccess).toHaveBeenCalledWith("Subconcepto creado correctamente.");
    expect(await screen.findByText("Subconcepto guardado exitosamente.")).toBeVisible();
  });

  it("exige ID para buscar y actualiza el registro encontrado", async () => {
    renderForm();

    fireEvent.click(screen.getByRole("button", { name: "Buscar" }));
    expect(screen.getByText("Por favor, ingrese un ID de subconcepto.")).toBeVisible();
    expect(api.obtener).not.toHaveBeenCalled();

    fireEvent.change(screen.getByLabelText("ID de Subconcepto:"), { target: { value: "14" } });
    fireEvent.click(screen.getByRole("button", { name: "Buscar" }));

    await waitFor(() => expect(api.obtener).toHaveBeenCalledWith(14));
    expect(await screen.findByDisplayValue("Subconcepto 14")).toBeVisible();
    fireEvent.change(descriptionField(), { target: { value: "Aranceles mensuales" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));

    await waitFor(() => expect(api.actualizar).toHaveBeenCalledWith(14, {
      descripcion: "Aranceles mensuales",
    }));
    expect(api.registrar).not.toHaveBeenCalled();
    expect(toastSuccess).toHaveBeenCalledWith("Subconcepto actualizado correctamente.");
  });

  it("precarga el ID de la ruta para edición", async () => {
    renderForm("/subconceptos/formulario?id=14");

    await waitFor(() => expect(api.obtener).toHaveBeenCalledWith(14));
    expect(screen.getByLabelText("ID de Subconcepto:")).toHaveValue(14);
    expect(await screen.findByText("Subconcepto encontrado.")).toBeVisible();
  });

  it("limpia datos tras una búsqueda fallida y permite volver al listado", async () => {
    api.obtener.mockRejectedValueOnce(new Error("not found"));
    renderForm();

    fireEvent.change(screen.getByLabelText("ID de Subconcepto:"), { target: { value: "999" } });
    fireEvent.click(screen.getByRole("button", { name: "Buscar" }));

    await waitFor(() => expect(toastError).toHaveBeenCalledWith("Error al buscar el subconcepto:"));
    expect(screen.getByLabelText("ID de Subconcepto:")).toHaveValue(null);
    expect(descriptionField()).toHaveValue("");

    fireEvent.click(screen.getByRole("button", { name: "Volver al Listado" }));
    expect(navigate).toHaveBeenCalledWith("/subconceptos");
  });

  it("informa un rechazo de guardado y restablece el formulario a pedido", async () => {
    api.registrar.mockRejectedValueOnce(new Error("duplicate"));
    renderForm();

    fireEvent.change(descriptionField(), { target: { value: "Duplicado" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));

    expect(await screen.findByText("Error al guardar el subconcepto.")).toBeVisible();
    expect(toastError).toHaveBeenCalledWith("Error al guardar el subconcepto.");
    expect(screen.getByRole("button", { name: "Guardar" })).toBeEnabled();
    fireEvent.click(screen.getByRole("button", { name: "Limpiar" }));
    expect(descriptionField()).toHaveValue("");
    expect(screen.queryByText("Error al guardar el subconcepto.")).not.toBeInTheDocument();
  });
});

function renderForm(initialEntry = "/subconceptos/formulario") {
  return render(
    <MemoryRouter initialEntries={[initialEntry]}>
      <SubConceptosFormulario />
    </MemoryRouter>,
  );
}

function descriptionField() {
  return screen.getByRole("textbox");
}

function subConcepto(id: number) {
  return { id, descripcion: `Subconcepto ${id}` };
}
