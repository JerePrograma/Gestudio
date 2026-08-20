import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ obtenerResumen: vi.fn() }));
vi.mock("../../api/cajaApi", () => ({ default: { obtenerResumen: mocks.obtenerResumen } }));

import CajaPagina from "./CajaPagina";

describe("CajaPagina", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.obtenerResumen.mockResolvedValue(resumenConMovimientos());
  });

  it("no consulta hasta confirmar un rango válido y presenta el resumen", async () => {
    renderPage();
    expect(mocks.obtenerResumen).not.toHaveBeenCalled();

    setRange("2026-07-01", "2026-07-31");
    fireEvent.click(screen.getByRole("button", { name: "Consultar" }));

    await waitFor(() => expect(mocks.obtenerResumen).toHaveBeenCalledWith("2026-07-01", "2026-07-31", 0, 50));
    expect(await screen.findByText("Pago 44")).toBeVisible();
    expect(screen.getByRole("region", { name: "Resumen de caja" })).toHaveTextContent("$ 2.000,00");
    expect(screen.getByRole("region", { name: "Resumen de caja" })).toHaveTextContent("$ 1.250,00");
    expect(screen.getByText("Egreso 55")).toBeVisible();
    expect(screen.getByText("Ajuste manual")).toBeVisible();
  });

  it("deshabilita una consulta con fechas invertidas", () => {
    renderPage();
    setRange("2026-08-01", "2026-07-01");

    expect(screen.getByRole("button", { name: "Consultar" })).toBeDisabled();
    expect(mocks.obtenerResumen).not.toHaveBeenCalled();
  });

  it("permite reintentar un error y muestra el estado vacío", async () => {
    mocks.obtenerResumen.mockRejectedValueOnce(new Error("load")).mockResolvedValueOnce(resumenVacio());
    renderPage();
    setRange("2026-07-01", "2026-07-31");
    fireEvent.click(screen.getByRole("button", { name: "Consultar" }));

    fireEvent.click(await screen.findByRole("button", { name: "Reintentar" }));
    expect(await screen.findByText("No hay movimientos en el período.")).toBeVisible();
    expect(mocks.obtenerResumen).toHaveBeenCalledTimes(2);
  });

  it("pagina el detalle manteniendo el rango consultado", async () => {
    renderPage();
    setRange("2026-07-01", "2026-07-31");
    fireEvent.click(screen.getByRole("button", { name: "Consultar" }));
    expect(await screen.findByText("Pago 44")).toBeVisible();

    fireEvent.click(screen.getByRole("button", { name: "Siguiente" }));
    await waitFor(() => expect(mocks.obtenerResumen).toHaveBeenCalledWith("2026-07-01", "2026-07-31", 1, 50));
  });
});

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(<QueryClientProvider client={client}><CajaPagina /></QueryClientProvider>);
}

function setRange(desde: string, hasta: string) {
  fireEvent.change(screen.getByLabelText("Desde"), { target: { value: desde } });
  fireEvent.change(screen.getByLabelText("Hasta"), { target: { value: hasta } });
}

function resumenConMovimientos() {
  return {
    desde: "2026-07-01",
    hasta: "2026-07-31",
    ingresos: "2000.00",
    egresos: "750.00",
    ajustesIngreso: "100.00",
    ajustesEgreso: "50.00",
    reversosIngreso: "20.00",
    reversosEgreso: "10.00",
    totalIngresos: "2000.00",
    totalEgresos: "750.00",
    saldo: "1250.00",
    movimientos: {
      content: [
        { id: 1, tipo: "INGRESO", fecha: "2026-07-03", importe: "1000.00", pagoId: 44, createdAt: "2026-07-03T10:00:00Z" },
        { id: 2, tipo: "EGRESO", fecha: "2026-07-04", importe: "500.00", egresoId: 55, createdAt: "2026-07-04T10:00:00Z" },
        { id: 3, tipo: "AJUSTE", fecha: "2026-07-05", importe: "100.00", motivo: "Ajuste manual", createdAt: "2026-07-05T10:00:00Z" },
      ],
      totalElements: 53,
      totalPages: 2,
      size: 50,
      number: 0,
      first: true,
      last: false,
    },
  };
}

function resumenVacio() {
  return { ...resumenConMovimientos(), movimientos: { ...resumenConMovimientos().movimientos, content: [], totalElements: 0, totalPages: 0, last: true } };
}
