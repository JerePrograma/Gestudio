import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  listarEgresos: vi.fn(),
  listarMetodos: vi.fn(),
  registrar: vi.fn(),
  toastError: vi.fn(),
  toastSuccess: vi.fn(),
}));
vi.mock("../../api/egresosApi", () => ({
  default: { listarEgresos: mocks.listarEgresos, registrarEgreso: mocks.registrar },
}));
vi.mock("../../api/metodosPagoApi", () => ({
  default: { listarMetodosPago: mocks.listarMetodos },
}));
vi.mock("react-toastify", () => ({
  toast: { error: mocks.toastError, success: mocks.toastSuccess },
}));

import EgresosPagina from "./EgresosPagina";

describe("EgresosPagina", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.stubGlobal("crypto", { randomUUID: () => "egreso-key" });
    mocks.listarEgresos.mockResolvedValue(pagina([egreso()]));
    mocks.listarMetodos.mockResolvedValue([
      { id: 2, descripcion: "Efectivo", activo: true, recargo: "0.00" },
      { id: 3, descripcion: "Archivado", activo: false, recargo: "0.00" },
    ]);
    mocks.registrar.mockResolvedValue(egreso());
  });

  it("lista egresos, filtra métodos inactivos y pagina", async () => {
    renderPage();

    expect(await screen.findByText("$ 500,00")).toBeVisible();
    expect(screen.getByRole("option", { name: "Efectivo" })).toBeVisible();
    expect(screen.queryByRole("option", { name: "Archivado" })).not.toBeInTheDocument();
    expect(screen.getByText("REGISTRADO")).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Siguiente" }));
    await waitFor(() => expect(mocks.listarEgresos).toHaveBeenCalledWith(1, 50));
  });

  it("registra un egreso monetario normalizado e invalida el historial", async () => {
    const client = renderPage();
    const invalidate = vi.spyOn(client, "invalidateQueries");
    await screen.findByRole("option", { name: "Efectivo" });

    fireEvent.change(screen.getByLabelText("Monto"), { target: { value: "123,45" } });
    fireEvent.change(screen.getByLabelText("Método de pago"), { target: { value: "2" } });
    fireEvent.click(screen.getByRole("button", { name: "Registrar" }));

    await waitFor(() => expect(mocks.registrar).toHaveBeenCalledWith({
      monto: "123.45",
      metodoPagoId: 2,
      idempotencyKey: "egreso-key",
    }));
    expect(invalidate).toHaveBeenCalledWith({ queryKey: ["egresos"] });
    expect(mocks.toastSuccess).toHaveBeenCalledWith("Egreso registrado.");
    expect(screen.getByLabelText("Monto")).toHaveValue("");
  });

  it("bloquea montos o métodos inválidos y comunica rechazo backend", async () => {
    mocks.registrar.mockRejectedValueOnce(new Error("save"));
    renderPage();
    await screen.findByRole("option", { name: "Efectivo" });

    expect(screen.getByRole("button", { name: "Registrar" })).toBeDisabled();
    fireEvent.change(screen.getByLabelText("Monto"), { target: { value: "-1" } });
    fireEvent.change(screen.getByLabelText("Método de pago"), { target: { value: "2" } });
    expect(screen.getByRole("button", { name: "Registrar" })).toBeDisabled();

    fireEvent.change(screen.getByLabelText("Monto"), { target: { value: "10" } });
    fireEvent.click(screen.getByRole("button", { name: "Registrar" }));
    await waitFor(() => expect(mocks.toastError).toHaveBeenCalledWith("No se pudo registrar el egreso."));
  });

  it("permite reintentar el listado y representa ausencia de registros", async () => {
    mocks.listarEgresos.mockRejectedValueOnce(new Error("load")).mockResolvedValueOnce(pagina([]));
    renderPage();

    fireEvent.click(await screen.findByRole("button", { name: "Reintentar" }));
    expect(await screen.findByText("No hay egresos registrados.")).toBeVisible();
  });
});

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(<QueryClientProvider client={client}><EgresosPagina /></QueryClientProvider>);
  return client;
}

function egreso() {
  return { id: 8, fecha: "2026-07-05", monto: "500.00", metodoPagoId: 2, usuarioId: 1, estado: "REGISTRADO", idempotencyKey: "existing" };
}

function pagina(content: ReturnType<typeof egreso>[]) {
  return { content, totalElements: 51, totalPages: 2, size: 50, number: 0, first: true, last: false };
}
