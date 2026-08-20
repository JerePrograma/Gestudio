import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  apiGet: vi.fn(),
  apiPost: vi.fn(),
  disciplinas: vi.fn(),
  hasPermission: vi.fn(),
  profesores: vi.fn(),
  toastError: vi.fn(),
}));

vi.mock("../api/axiosConfig", () => ({
  default: { get: mocks.apiGet, post: mocks.apiPost },
}));
vi.mock("../api/disciplinasApi", () => ({
  default: { listarDisciplinasSimplificadas: mocks.disciplinas },
}));
vi.mock("../api/profesoresApi", () => ({
  default: { listarProfesoresActivos: mocks.profesores },
}));
vi.mock("../hooks/context/useAuth", () => ({
  useAuth: () => ({ hasPermission: mocks.hasPermission }),
}));
vi.mock("react-toastify", () => ({ toast: { error: mocks.toastError } }));

import Reportes from "./Reportes";

describe("Reportes", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.disciplinas.mockResolvedValue([disciplina()]);
    mocks.hasPermission.mockReturnValue(true);
    mocks.profesores.mockResolvedValue([{ id: 4, nombre: "Ada", apellido: "Lovelace", activo: true }]);
    mocks.apiGet.mockResolvedValue({ data: [filaReporte()] });
    mocks.apiPost.mockResolvedValue({ data: new Blob(["pdf"], { type: "application/pdf" }) });
    Object.defineProperty(URL, "createObjectURL", { configurable: true, value: vi.fn(() => "blob:liquidacion") });
    Object.defineProperty(URL, "revokeObjectURL", { configurable: true, value: vi.fn() });
    vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => undefined);
  });

  it("carga filtros y consulta con parámetros opcionales seleccionados", async () => {
    render(<Reportes />);

    expect(await screen.findByRole("option", { name: "Danza" })).toBeVisible();
    expect(screen.getByRole("option", { name: "Ada Lovelace" })).toBeVisible();
    expect(mocks.profesores).toHaveBeenCalledWith(true);

    completeRange();
    fireEvent.change(screen.getByLabelText("Disciplina"), { target: { value: "3" } });
    fireEvent.change(screen.getByLabelText("Profesor"), { target: { value: "4" } });
    fireEvent.click(screen.getByRole("button", { name: "Consultar" }));

    await waitFor(() => expect(mocks.apiGet).toHaveBeenCalledWith("/reportes/mensualidades", {
      params: { desde: "2026-07-01", hasta: "2026-07-31", disciplinaId: "3", profesorId: "4" },
    }));
    expect((await screen.findAllByText("Ana Pérez"))[0]).toBeVisible();
    expect(screen.getAllByText("$ 1.000,00")[0]).toBeVisible();
    expect(screen.getAllByText("$ 750,00")[0]).toBeVisible();
    expect(screen.getAllByText("$ 250,00")[0]).toBeVisible();
    expect(screen.getByText("1 registro")).toBeVisible();
  });

  it("rechaza rangos inválidos y conserva vacío cuando la consulta falla", async () => {
    mocks.apiGet.mockRejectedValueOnce(new Error("report"));
    render(<Reportes />);
    await screen.findByRole("option", { name: "Danza" });

    fireEvent.click(screen.getByRole("button", { name: "Consultar" }));
    expect(mocks.toastError).toHaveBeenCalledWith("Ingresá un rango de fechas válido");
    expect(mocks.apiGet).not.toHaveBeenCalled();

    fireEvent.change(screen.getByLabelText("Desde"), { target: { value: "2026-08-01" } });
    fireEvent.change(screen.getByLabelText("Hasta"), { target: { value: "2026-07-01" } });
    fireEvent.click(screen.getByRole("button", { name: "Consultar" }));
    expect(mocks.apiGet).not.toHaveBeenCalled();

    completeRange();
    fireEvent.click(screen.getByRole("button", { name: "Consultar" }));
    await waitFor(() => expect(mocks.toastError).toHaveBeenCalledWith("No se pudo generar el reporte"));
    expect(screen.getByText("No hay resultados para el rango consultado.")).toBeVisible();
  });

  it("exporta la liquidación con importes normalizados y filtros numéricos", async () => {
    render(<Reportes />);
    await screen.findByRole("option", { name: "Danza" });
    completeRange();
    fireEvent.change(screen.getByLabelText("Disciplina"), { target: { value: "3" } });
    fireEvent.change(screen.getByLabelText("Profesor"), { target: { value: "4" } });
    fireEvent.change(screen.getByLabelText("Porcentaje escuela"), { target: { value: "25,50" } });
    fireEvent.click(screen.getByRole("button", { name: "Exportar PDF" }));

    await waitFor(() => expect(mocks.apiPost).toHaveBeenCalledWith(
      "/reportes/mensualidades/exportar",
      {
        fechaInicio: "2026-07-01",
        fechaFin: "2026-07-31",
        disciplinaId: 3,
        profesorId: 4,
        porcentajeEscuela: "25.50",
      },
      { responseType: "blob" },
    ));
    expect(URL.createObjectURL).toHaveBeenCalledOnce();
    expect(HTMLAnchorElement.prototype.click).toHaveBeenCalledOnce();
    expect(URL.revokeObjectURL).toHaveBeenCalledWith("blob:liquidacion");
  });

  it("valida el porcentaje y comunica fallos de exportación", async () => {
    mocks.apiPost.mockRejectedValueOnce(new Error("export"));
    render(<Reportes />);
    await screen.findByRole("option", { name: "Danza" });
    completeRange();

    fireEvent.change(screen.getByLabelText("Porcentaje escuela"), { target: { value: "100.01" } });
    fireEvent.click(screen.getByRole("button", { name: "Exportar PDF" }));
    expect(mocks.toastError).toHaveBeenCalledWith("El porcentaje de la escuela debe tener hasta dos decimales");
    expect(mocks.apiPost).not.toHaveBeenCalled();

    fireEvent.change(screen.getByLabelText("Porcentaje escuela"), { target: { value: "20" } });
    fireEvent.click(screen.getByRole("button", { name: "Exportar PDF" }));
    await waitFor(() => expect(mocks.toastError).toHaveBeenCalledWith("No se pudo exportar la liquidación"));
  });

  it("oculta exportación sin permiso e informa filtros que no pudieron cargarse", async () => {
    mocks.disciplinas.mockRejectedValueOnce(new Error("filters"));
    mocks.hasPermission.mockReturnValue(false);
    render(<Reportes />);

    await waitFor(() => expect(mocks.toastError).toHaveBeenCalledWith("No se pudieron cargar los filtros del reporte"));
    expect(screen.queryByRole("button", { name: "Exportar PDF" })).not.toBeInTheDocument();
  });
});

function completeRange() {
  fireEvent.change(screen.getByLabelText("Desde"), { target: { value: "2026-07-01" } });
  fireEvent.change(screen.getByLabelText("Hasta"), { target: { value: "2026-07-31" } });
}

function disciplina() {
  return {
    id: 3,
    nombre: "Danza",
    salon: "Sala",
    salonId: 2,
    valorCuota: "1000.00",
    matricula: "100.00",
    profesorNombre: "Ada",
    profesorApellido: "Lovelace",
    profesorId: 4,
    inscritos: 8,
    activo: true,
    horarios: [],
  };
}

function filaReporte() {
  return {
    cargoId: 11,
    fechaEmision: "2026-07-01",
    alumno: "Ana Pérez",
    disciplina: "Danza",
    profesor: "Ada Lovelace",
    importeOriginal: "1000.00",
    importeCobrado: "750.00",
    saldo: "250.00",
    estado: "PARCIAL",
  };
}
