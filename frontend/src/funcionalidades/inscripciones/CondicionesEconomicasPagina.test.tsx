import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { PERMISSIONS } from "../../config/permissions";

const mocks = vi.hoisted(() => ({
  crear: vi.fn(),
  listarCondiciones: vi.fn(),
  listarBonificaciones: vi.fn(),
  hasPermission: vi.fn(),
  toastError: vi.fn(),
}));

vi.mock("../../api/condicionesEconomicasApi", () => ({
  default: { crear: mocks.crear, listar: mocks.listarCondiciones },
}));

vi.mock("../../api/bonificacionesApi", () => ({
  default: { listarBonificaciones: mocks.listarBonificaciones },
}));

vi.mock("../../hooks/context/useAuth", () => ({
  useAuth: () => ({ hasPermission: mocks.hasPermission }),
}));

vi.mock("react-toastify", () => ({
  toast: { error: mocks.toastError, success: vi.fn() },
}));

import CondicionesEconomicasPagina from "./CondicionesEconomicasPagina";

const renderPage = () => render(
  <MemoryRouter initialEntries={["/inscripciones/1/condiciones-economicas"]}>
    <Routes>
      <Route path="/inscripciones/:id/condiciones-economicas" element={<CondicionesEconomicasPagina />} />
    </Routes>
  </MemoryRouter>,
);

describe("CondicionesEconomicasPagina", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.listarCondiciones.mockResolvedValue([]);
    mocks.listarBonificaciones.mockResolvedValue([]);
    mocks.crear.mockResolvedValue({});
  });

  it("impide vigencia histórica sin el permiso adicional", async () => {
    mocks.hasPermission.mockImplementation(
      (permission: string) => permission !== PERMISSIONS.TARIFAS_HISTORICAS,
    );
    renderPage();

    const date = await screen.findByLabelText("Vigente desde");
    expect(date).toHaveAttribute("min");
    fireEvent.change(date, { target: { value: "2000-01-01" } });
    fireEvent.submit(date.closest("form")!);

    expect(mocks.crear).not.toHaveBeenCalled();
    expect(mocks.toastError).toHaveBeenCalledWith(
      "Se requiere permiso para cargar una condición con vigencia histórica.",
    );
  });

  it("permite vigencia histórica con el permiso adicional", async () => {
    mocks.hasPermission.mockReturnValue(true);
    renderPage();

    const date = await screen.findByLabelText("Vigente desde");
    expect(date).not.toHaveAttribute("min");
    fireEvent.change(date, { target: { value: "2000-01-01" } });
    fireEvent.change(screen.getByLabelText("Motivo"), { target: { value: "Corrección autorizada" } });
    fireEvent.submit(date.closest("form")!);

    await waitFor(() => expect(mocks.crear).toHaveBeenCalledWith(1, expect.objectContaining({
      vigenteDesde: "2000-01-01",
      motivo: "Corrección autorizada",
    })));
  });
});
