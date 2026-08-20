import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ generar: vi.fn(), toastError: vi.fn(), toastSuccess: vi.fn() }));
vi.mock("../../api/mensualidadesApi", () => ({
  default: { generarMensualidadesParaMesVigente: mocks.generar },
}));
vi.mock("react-toastify", () => ({
  toast: { error: mocks.toastError, success: mocks.toastSuccess },
}));

import MensualidadesPagina from "./MensualidadPagina";

describe("MensualidadesPagina", () => {
  beforeEach(() => vi.clearAllMocks());

  it("informa cuántas cuotas fueron generadas o actualizadas", async () => {
    mocks.generar.mockResolvedValue([{ id: 1 }, { id: 2 }]);
    render(<MensualidadesPagina />);
    fireEvent.click(screen.getByRole("button", { name: "Generar cuotas del mes" }));

    await waitFor(() => expect(mocks.toastSuccess).toHaveBeenCalledWith("Se generaron/actualizaron 2 cuota(s) para el mes vigente."));
  });

  it("comunica el rechazo del proceso mensual", async () => {
    mocks.generar.mockRejectedValue(new Error("generate"));
    render(<MensualidadesPagina />);
    fireEvent.click(screen.getByRole("button", { name: "Generar cuotas del mes" }));

    await waitFor(() => expect(mocks.toastError).toHaveBeenCalledWith("Error al generar cuotas del mes."));
  });
});
