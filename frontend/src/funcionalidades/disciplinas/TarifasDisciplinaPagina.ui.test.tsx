import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { PERMISSIONS } from "../../config/permissions";
import type { AuthContextProps } from "../../hooks/context/auth-context";

const api = vi.hoisted(() => ({
  obtenerDisciplina: vi.fn(),
  listarTarifas: vi.fn(),
  crearTarifa: vi.fn(),
}));
const navigate = vi.hoisted(() => vi.fn());
const hasPermission = vi.hoisted(() =>
  vi.fn<AuthContextProps["hasPermission"]>(() => true),
);
const toastSuccess = vi.hoisted(() => vi.fn());
const toastError = vi.hoisted(() => vi.fn());

vi.mock("../../api/disciplinasApi", () => ({
  default: { obtenerDisciplinaPorId: api.obtenerDisciplina },
}));
vi.mock("../../api/tarifasApi", () => ({
  default: { listar: api.listarTarifas, crear: api.crearTarifa },
}));
vi.mock("../../hooks/context/useAuth", () => ({
  useAuth: () => ({ hasPermission }),
}));
vi.mock("react-toastify", () => ({
  toast: { success: toastSuccess, error: toastError },
}));
vi.mock("react-router", async (importOriginal) => ({
  ...(await importOriginal<typeof import("react-router")>()),
  useNavigate: () => navigate,
}));

import TarifasDisciplinaPagina from "./TarifasDisciplinaPagina";

describe("TarifasDisciplinaPagina", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    hasPermission.mockReturnValue(true);
    api.obtenerDisciplina.mockResolvedValue({ nombre: "Tango" });
    api.listarTarifas.mockResolvedValue([tarifa()]);
    api.crearTarifa.mockResolvedValue(tarifa());
  });

  it("carga el historial, expone sus metadatos y vuelve al listado", async () => {
    let resolveHistory!: (history: ReturnType<typeof tarifa>[]) => void;
    api.listarTarifas.mockReturnValueOnce(new Promise((resolve) => { resolveHistory = resolve; }));
    renderPage();

    expect(screen.getByText("Cargando...")).toBeVisible();
    resolveHistory([tarifa()]);

    expect(await screen.findByRole("heading", { name: "Tarifas de Tango" })).toBeVisible();
    expect(screen.getByText("Ajuste anual")).toBeVisible();
    expect(screen.getByText("admin.demo")).toBeVisible();
    expect(screen.getByText("Utilizada")).toBeVisible();
    expect(api.obtenerDisciplina).toHaveBeenCalledWith(9);
    expect(api.listarTarifas).toHaveBeenCalledWith(9);

    fireEvent.click(screen.getByRole("button", { name: "Volver" }));
    expect(navigate).toHaveBeenCalledWith("/disciplinas");
  });

  it("reserva fechas históricas al permiso adicional", async () => {
    hasPermission.mockImplementation(
      (permission) => permission !== PERMISSIONS.TARIFAS_HISTORICAS,
    );
    renderPage();

    const effectiveDate = await screen.findByLabelText("Vigente desde");
    expect(effectiveDate).toHaveAttribute("min");
    fireEvent.change(effectiveDate, { target: { value: "2020-01-01" } });
    fireEvent.submit(effectiveDate.closest("form")!);

    expect(api.crearTarifa).not.toHaveBeenCalled();
    expect(toastError).toHaveBeenCalledWith(
      "Se requiere permiso para cargar una tarifa con vigencia histórica.",
    );
  });

  it("crea una tarifa con payload exacto, limpia el formulario y recarga el historial", async () => {
    api.listarTarifas.mockResolvedValueOnce([]).mockResolvedValueOnce([tarifa()]);
    renderPage();

    await screen.findByText("No hay tarifas verificadas cargadas.");
    fill("Vigente desde", "2026-08-20");
    fill("Cuota", "18000.00");
    fill("Matrícula", "10000.00");
    fill("Clase suelta", "4000.00");
    fill("Clase de prueba", "2000.00");
    fill("Motivo", "Nueva temporada");
    fireEvent.click(screen.getByRole("button", { name: "Crear tarifa" }));

    await waitFor(() => expect(api.crearTarifa).toHaveBeenCalledWith(9, {
      vigenteDesde: "2026-08-20",
      valorCuota: "18000.00",
      matricula: "10000.00",
      claseSuelta: "4000.00",
      clasePrueba: "2000.00",
      motivo: "Nueva temporada",
    }));
    expect(toastSuccess).toHaveBeenCalledWith("Tarifa creada correctamente.");
    await waitFor(() => expect(api.listarTarifas).toHaveBeenCalledTimes(2));
    expect(screen.getByLabelText("Vigente desde")).toHaveValue("");
  });

  it("mantiene los valores y rehabilita el envío cuando la creación falla", async () => {
    api.crearTarifa.mockRejectedValueOnce(new Error("invalid amounts"));
    renderPage();

    await screen.findByRole("heading", { name: "Tarifas de Tango" });
    fill("Vigente desde", "2026-08-20");
    fill("Cuota", "18000.00");
    fireEvent.submit(screen.getByLabelText("Vigente desde").closest("form")!);

    await waitFor(() => expect(toastError).toHaveBeenCalledWith(
      "No se pudo crear la tarifa. Verifique fecha, importes y permisos.",
    ));
    expect(screen.getByRole("button", { name: "Crear tarifa" })).toBeEnabled();
    expect(screen.getByLabelText("Cuota")).toHaveValue("18000.00");
  });

  it("oculta el formulario sin permiso administrativo e informa fallos de carga", async () => {
    hasPermission.mockReturnValue(false);
    api.obtenerDisciplina.mockRejectedValueOnce(new Error("offline"));
    renderPage();

    await waitFor(() => expect(toastError).toHaveBeenCalledWith(
      "No se pudo cargar el historial de tarifas.",
    ));
    expect(screen.queryByRole("heading", { name: "Programar tarifa" })).not.toBeInTheDocument();
    expect(screen.getByText("No hay tarifas verificadas cargadas.")).toBeVisible();
  });

  it("no consulta APIs para un ID de disciplina inválido", () => {
    renderPage("/disciplinas/invalida/tarifas");

    expect(screen.getByText("Cargando...")).toBeVisible();
    expect(api.obtenerDisciplina).not.toHaveBeenCalled();
    expect(api.listarTarifas).not.toHaveBeenCalled();
  });
});

function renderPage(initialEntry = "/disciplinas/9/tarifas") {
  return render(
    <MemoryRouter initialEntries={[initialEntry]}>
      <Routes>
        <Route path="/disciplinas/:id/tarifas" element={<TarifasDisciplinaPagina />} />
      </Routes>
    </MemoryRouter>,
  );
}

function fill(label: string, value: string) {
  fireEvent.change(screen.getByLabelText(label), { target: { value } });
}

function tarifa() {
  return {
    id: 44,
    disciplinaId: 9,
    vigenteDesde: "2026-08-01",
    valorCuota: "17000.00",
    matricula: "9000.00",
    claseSuelta: "3500.00",
    clasePrueba: "1800.00",
    motivo: "Ajuste anual",
    creadaPorUsuarioId: 2,
    creadaPorUsername: "admin.demo",
    createdAt: "2026-07-20T12:00:00Z",
    utilizada: true,
  };
}
