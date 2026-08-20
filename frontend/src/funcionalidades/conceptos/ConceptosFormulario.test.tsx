import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";

const api = vi.hoisted(() => ({
  listarSubConceptos: vi.fn(),
  obtener: vi.fn(),
  registrar: vi.fn(),
  actualizar: vi.fn(),
}));
const navigate = vi.hoisted(() => vi.fn());
const toastSuccess = vi.hoisted(() => vi.fn());
const toastError = vi.hoisted(() => vi.fn());

vi.mock("../../api/conceptosApi", () => ({
  default: {
    obtenerConceptoPorId: api.obtener,
    registrarConcepto: api.registrar,
    actualizarConcepto: api.actualizar,
  },
}));
vi.mock("../../api/subConceptosApi", () => ({
  default: { listarSubConceptos: api.listarSubConceptos },
}));
vi.mock("react-toastify", () => ({
  toast: { success: toastSuccess, error: toastError },
}));
vi.mock("react-router", async (importOriginal) => ({
  ...(await importOriginal<typeof import("react-router")>()),
  useNavigate: () => navigate,
}));

import ConceptosFormulario from "./ConceptosFormulario";

describe("ConceptosFormulario", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.listarSubConceptos.mockResolvedValue([subConcepto(4), subConcepto(5)]);
    api.obtener.mockResolvedValue(concepto(21));
    api.registrar.mockResolvedValue(concepto(22));
    api.actualizar.mockResolvedValue(concepto(21));
  });

  it("valida los campos obligatorios y crea con la referencia de subconcepto exacta", async () => {
    renderForm();

    expect(await screen.findByRole("option", { name: "Subconcepto 4" })).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Crear Concepto" }));
    expect(await screen.findByText("La descripción es obligatoria")).toBeVisible();
    expect(screen.getByText("Selecciona un subconcepto")).toBeVisible();
    expect(api.registrar).not.toHaveBeenCalled();

    fireEvent.change(descriptionField(), { target: { value: "Cuota mensual" } });
    fireEvent.change(priceField(), { target: { value: "12500.50" } });
    fireEvent.change(subConceptField(), { target: { value: "4" } });
    fireEvent.click(screen.getByRole("button", { name: "Crear Concepto" }));

    await waitFor(() => expect(api.registrar).toHaveBeenCalledWith({
      descripcion: "Cuota mensual",
      precio: "12500.50",
      subConcepto: { id: 4, descripcion: "" },
      activo: true,
    }));
    expect(toastSuccess).toHaveBeenCalledWith("Concepto creado correctamente.");
    expect(navigate).toHaveBeenCalledWith("/conceptos");
  });

  it("precarga el concepto solicitado y actualiza conservando su estado", async () => {
    renderForm("/conceptos/formulario-concepto?id=21");

    expect(await screen.findByText("Concepto encontrado.")).toBeVisible();
    expect(await screen.findByDisplayValue("Matrícula anual")).toBeVisible();
    expect(priceField()).toHaveValue(9000);
    expect(subConceptField()).toHaveValue("4");

    fireEvent.change(descriptionField(), { target: { value: "Matrícula 2027" } });
    fireEvent.click(screen.getByRole("button", { name: "Actualizar Concepto" }));

    await waitFor(() => expect(api.actualizar).toHaveBeenCalledWith(21, {
      descripcion: "Matrícula 2027",
      precio: "9000.00",
      subConcepto: { id: 4, descripcion: "" },
      activo: false,
    }));
    expect(api.registrar).not.toHaveBeenCalled();
    expect(toastSuccess).toHaveBeenCalledWith("Concepto actualizado correctamente.");
  });

  it("recupera errores de precarga y de catálogo sin presentar datos obsoletos", async () => {
    api.listarSubConceptos.mockRejectedValueOnce(new Error("catalog unavailable"));
    api.obtener.mockRejectedValueOnce(new Error("not found"));
    renderForm("/conceptos/formulario-concepto?id=999");

    await waitFor(() => {
      expect(toastError).toHaveBeenCalledWith("Error al cargar la lista de subconceptos");
      expect(toastError).toHaveBeenCalledWith("Error al buscar el concepto:");
    });
    expect(screen.getByText("Concepto no encontrado.")).toBeVisible();
    expect(descriptionField()).toHaveValue("");
    expect(screen.getByRole("button", { name: "Crear Concepto" })).toBeVisible();
  });

  it("mantiene el formulario editable ante un rechazo de guardado y permite limpiar o cancelar", async () => {
    api.registrar.mockRejectedValueOnce(new Error("conflict"));
    renderForm();
    await screen.findByRole("option", { name: "Subconcepto 4" });

    fireEvent.change(descriptionField(), { target: { value: "Concepto temporal" } });
    fireEvent.change(priceField(), { target: { value: "100" } });
    fireEvent.change(subConceptField(), { target: { value: "4" } });
    fireEvent.click(screen.getByRole("button", { name: "Crear Concepto" }));

    expect(await screen.findByText("Error al guardar el concepto.")).toBeVisible();
    expect(toastError).toHaveBeenCalledWith("Error al guardar el concepto.");
    expect(screen.getByRole("button", { name: "Crear Concepto" })).toBeEnabled();
    expect(descriptionField()).toHaveValue("Concepto temporal");

    fireEvent.click(screen.getByRole("button", { name: "Limpiar" }));
    expect(descriptionField()).toHaveValue("");
    fireEvent.click(screen.getByRole("button", { name: "Cancelar" }));
    expect(navigate).toHaveBeenCalledWith("/conceptos");
  });
});

function renderForm(initialEntry = "/conceptos/formulario-concepto") {
  return render(
    <MemoryRouter initialEntries={[initialEntry]}>
      <ConceptosFormulario />
    </MemoryRouter>,
  );
}

function descriptionField() {
  return screen.getByRole("textbox");
}

function priceField() {
  return screen.getByRole("spinbutton");
}

function subConceptField() {
  return screen.getByRole("combobox");
}

function subConcepto(id: number) {
  return { id, descripcion: `Subconcepto ${id}` };
}

function concepto(id: number) {
  return {
    version: 3,
    id,
    descripcion: "Matrícula anual",
    precio: "9000.00",
    subConcepto: subConcepto(4),
    activo: false,
  };
}
