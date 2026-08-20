import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";

const api = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn(), put: vi.fn() }));
const navigate = vi.hoisted(() => vi.fn());
const toastSuccess = vi.hoisted(() => vi.fn());
const toastError = vi.hoisted(() => vi.fn());

vi.mock("../../api/axiosConfig", () => ({ default: api }));
vi.mock("react-toastify", () => ({
  toast: { success: toastSuccess, error: toastError },
}));
vi.mock("react-router", async (importOriginal) => ({
  ...(await importOriginal<typeof import("react-router")>()),
  useNavigate: () => navigate,
}));

import MetodosPagoFormulario from "./MetodosPagoFormulario";

describe("MetodosPagoFormulario", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.get.mockResolvedValue({ data: metodo(6) });
    api.post.mockResolvedValue({ data: metodo(7) });
    api.put.mockResolvedValue({ data: metodo(6) });
  });

  it("valida la descripción y crea un método con payload exacto", async () => {
    renderForm();

    fireEvent.click(screen.getByRole("button", { name: "Guardar Método de Pago" }));
    expect(await screen.findByText("La descripcion es obligatoria")).toBeVisible();
    expect(api.post).not.toHaveBeenCalled();

    fireEvent.change(screen.getByLabelText("Descripción:"), { target: { value: "Transferencia" } });
    fireEvent.change(screen.getByLabelText("Recargo:"), { target: { value: "2.50" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar Método de Pago" }));

    await waitFor(() => expect(api.post).toHaveBeenCalledWith("/metodos-pago", {
      descripcion: "Transferencia",
      recargo: "2.50",
    }));
    expect(toastSuccess).toHaveBeenCalledWith("Método de pago creado correctamente.");
  });

  it("precarga el ID de la ruta y actualiza el método encontrado", async () => {
    renderForm("/metodos-pago/formulario?id=6");

    await waitFor(() => expect(api.get).toHaveBeenCalledWith("/metodos-pago/6"));
    expect(await screen.findByDisplayValue("Método 6")).toBeVisible();
    expect(toastSuccess).toHaveBeenCalledWith("Método de pago cargado correctamente.");
    fireEvent.change(screen.getByLabelText("Descripción:"), { target: { value: "Tarjeta" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar Método de Pago" }));

    await waitFor(() => expect(api.put).toHaveBeenCalledWith("/metodos-pago/6", {
      id: 6,
      descripcion: "Tarjeta",
      recargo: "3.00",
    }));
    expect(api.post).not.toHaveBeenCalled();
    expect(toastSuccess).toHaveBeenCalledWith("Método de pago actualizado correctamente.");
  });

  it("rechaza un ID no numérico sin consultar el backend", async () => {
    renderForm("/metodos-pago/formulario?id=no-numérico");

    await waitFor(() => expect(toastError).toHaveBeenCalledWith("ID inválido"));
    expect(api.get).not.toHaveBeenCalled();
    expect(screen.getByRole("heading", { name: "Editar Método de Pago" })).toBeVisible();
  });

  it("restablece el formulario si falla la búsqueda", async () => {
    api.get.mockRejectedValueOnce(new Error("not found"));
    renderForm("/metodos-pago/formulario?id=99");

    await waitFor(() => expect(toastError).toHaveBeenCalledWith(
      "Error al cargar los datos del método de pago.",
    ));
    expect(screen.getByLabelText("Descripción:")).toHaveValue("");
    expect(screen.getByLabelText("Recargo:")).toHaveValue(0);
  });

  it("mantiene los datos ante un rechazo de guardado y permite limpiar y volver", async () => {
    api.post.mockRejectedValueOnce(new Error("duplicate"));
    renderForm();

    fireEvent.change(screen.getByLabelText("Descripción:"), { target: { value: "Efectivo especial" } });
    fireEvent.change(screen.getByLabelText("Recargo:"), { target: { value: "1.00" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar Método de Pago" }));

    await waitFor(() => expect(toastError).toHaveBeenCalledWith(
      "Error al guardar los datos del método de pago.",
    ));
    expect(screen.getByRole("button", { name: "Guardar Método de Pago" })).toBeEnabled();
    expect(screen.getByLabelText("Descripción:")).toHaveValue("Efectivo especial");

    fireEvent.click(screen.getByRole("button", { name: "Limpiar" }));
    expect(screen.getByLabelText("Descripción:")).toHaveValue("");
    fireEvent.click(screen.getByRole("button", { name: "Volver al Listado" }));
    expect(navigate).toHaveBeenCalledWith("/metodos-pago");
  });
});

function renderForm(initialEntry = "/metodos-pago/formulario") {
  return render(
    <MemoryRouter initialEntries={[initialEntry]}>
      <MetodosPagoFormulario />
    </MemoryRouter>,
  );
}

function metodo(id: number) {
  return { id, descripcion: `Método ${id}`, recargo: "3.00", activo: true };
}
