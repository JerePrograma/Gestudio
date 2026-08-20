import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  actualizar: vi.fn(),
  navigate: vi.fn(),
  obtener: vi.fn(),
  registrar: vi.fn(),
  toastError: vi.fn(),
  toastSuccess: vi.fn(),
}));

vi.mock("../../api/stocksApi", () => ({
  default: {
    actualizarStock: mocks.actualizar,
    obtenerStockPorId: mocks.obtener,
    registrarStock: mocks.registrar,
  },
}));
vi.mock("react-router", async (importOriginal) => ({
  ...(await importOriginal<typeof import("react-router")>()),
  useNavigate: () => mocks.navigate,
}));
vi.mock("react-toastify", () => ({
  toast: { error: mocks.toastError, success: mocks.toastSuccess },
}));

import StocksFormulario from "./StocksFormulario";

describe("StocksFormulario", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.stubGlobal("crypto", { randomUUID: () => "stock-idempotency-key" });
    mocks.actualizar.mockResolvedValue(stock(9));
    mocks.obtener.mockResolvedValue(stock(9));
    mocks.registrar.mockResolvedValue(stock(10));
  });

  it("crea un producto normalizando el importe e invalidando el listado", async () => {
    const queryClient = renderForm();
    const invalidate = vi.spyOn(queryClient, "invalidateQueries");

    fireEvent.change(screen.getByLabelText("Nombre"), { target: { value: "Remera" } });
    fireEvent.change(screen.getByLabelText("Precio"), { target: { value: "1234,50" } });
    fireEvent.change(screen.getByLabelText("Cantidad"), { target: { value: "12" } });
    fireEvent.change(screen.getByLabelText("Código de barras"), { target: { value: "7790001" } });
    fireEvent.click(screen.getByRole("checkbox", { name: /Requiere control de stock/ }));
    fireEvent.click(screen.getByRole("button", { name: "Guardar producto" }));

    await waitFor(() => expect(mocks.registrar).toHaveBeenCalledWith({
      nombre: "Remera",
      precio: "1234.50",
      stock: 12,
      requiereControlDeStock: true,
      codigoBarras: "7790001",
      activo: true,
      idempotencyKey: "stock-idempotency-key",
    }));
    expect(invalidate).toHaveBeenCalledWith({ queryKey: ["stocks"] });
    expect(mocks.toastSuccess).toHaveBeenCalledWith("Producto creado");
    expect(mocks.navigate).toHaveBeenCalledWith("/stocks");
  });

  it("carga y actualiza el producto incluyendo su estado", async () => {
    renderForm("/stocks/formulario?id=9");

    expect(await screen.findByDisplayValue("Botella")).toBeVisible();
    expect(screen.getByLabelText("Precio")).toHaveValue("1500.00");
    expect(screen.getByRole("checkbox", { name: /Producto activo/ })).toBeChecked();

    fireEvent.click(screen.getByRole("checkbox", { name: /Producto activo/ }));
    fireEvent.click(screen.getByRole("button", { name: "Guardar producto" }));

    await waitFor(() => expect(mocks.actualizar).toHaveBeenCalledWith(9, {
      nombre: "Botella",
      precio: "1500.00",
      stock: 4,
      requiereControlDeStock: true,
      codigoBarras: "7799999",
      activo: false,
      idempotencyKey: "stock-idempotency-key",
    }));
    expect(mocks.toastSuccess).toHaveBeenCalledWith("Producto actualizado");
  });

  it("impide valores inválidos antes de invocar el backend", async () => {
    renderForm();

    fireEvent.change(screen.getByLabelText("Precio"), { target: { value: "-1" } });
    fireEvent.change(screen.getByLabelText("Cantidad"), { target: { value: "-2" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar producto" }));

    expect(await screen.findByText("El nombre es requerido")).toBeVisible();
    expect(screen.getByText("El precio debe ser mayor que 0 y tener hasta dos decimales")).toBeVisible();
    expect(screen.getByText("El stock no puede ser negativo")).toBeVisible();
    expect(mocks.registrar).not.toHaveBeenCalled();
  });

  it("muestra errores de campo y mensaje backend sin navegar", async () => {
    mocks.registrar.mockRejectedValueOnce(new Error("save"));
    renderForm();

    fireEvent.change(screen.getByLabelText("Nombre"), { target: { value: "Remera" } });
    fireEvent.change(screen.getByLabelText("Precio"), { target: { value: "100" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar producto" }));

    await waitFor(() => expect(mocks.toastError).toHaveBeenCalledWith("No se pudo guardar el producto."));
    expect(screen.getByRole("button", { name: "Guardar producto" })).toBeEnabled();
    expect(mocks.navigate).not.toHaveBeenCalled();
  });

  it("permite reintentar una carga fallida y cancelar", async () => {
    mocks.obtener.mockRejectedValueOnce(new Error("load")).mockResolvedValueOnce(stock(9));
    renderForm("/stocks/formulario?id=9");

    fireEvent.click(await screen.findByRole("button", { name: "Reintentar" }));
    expect(await screen.findByDisplayValue("Botella")).toBeVisible();
    expect(mocks.obtener).toHaveBeenCalledTimes(2);

    fireEvent.click(screen.getByRole("button", { name: "Cancelar" }));
    expect(mocks.navigate).toHaveBeenCalledWith("/stocks");
  });
});

function renderForm(entry = "/stocks/formulario") {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[entry]}>
        <StocksFormulario />
      </MemoryRouter>
    </QueryClientProvider>,
  );
  return queryClient;
}

function stock(id: number) {
  return {
    id,
    nombre: "Botella",
    precio: "1500.00",
    stock: 4,
    requiereControlDeStock: true,
    codigoBarras: "7799999",
    activo: true,
  };
}
