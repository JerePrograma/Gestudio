import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { EstadoAsistencia } from "../../types/types";

const mocks = vi.hoisted(() => ({
  listarDisciplinas: vi.fn(),
  obtenerDetalle: vi.fn(),
  registrarDiaria: vi.fn(),
  actualizarMensual: vi.fn(),
  obtenerDisciplina: vi.fn(),
  hasPermission: vi.fn(),
  toastWarn: vi.fn(),
  toastError: vi.fn(),
}));

vi.mock("../../api/asistenciasApi", () => ({
  default: {
    listarDisciplinasSimplificadas: mocks.listarDisciplinas,
    obtenerAsistenciaMensualDetallePorParametros: mocks.obtenerDetalle,
    registrarAsistenciaDiaria: mocks.registrarDiaria,
    actualizarAsistenciaMensual: mocks.actualizarMensual,
  },
}));

vi.mock("../../api/axiosConfig", () => ({
  default: { get: mocks.obtenerDisciplina },
}));

vi.mock("../../hooks/context/useAuth", () => ({
  useAuth: () => ({ hasPermission: mocks.hasPermission }),
}));

vi.mock("react-toastify", () => ({
  toast: {
    warn: mocks.toastWarn,
    error: mocks.toastError,
  },
}));

vi.mock("react-datepicker", () => ({
  default: ({
    id,
    selected,
    onChange,
  }: {
    id: string;
    selected: Date;
    onChange: (date: Date | null) => void;
  }) => (
    <input
      id={id}
      aria-label="Fecha"
      type="date"
      value={localDate(selected)}
      onChange={(event) => onChange(new Date(`${event.target.value}T12:00:00`))}
    />
  ),
}));

import AsistenciaDiariaFormulario from "./AsistenciaDiariaFormulario";

describe("AsistenciaDiariaFormulario", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.hasPermission.mockReturnValue(true);
    mocks.listarDisciplinas.mockResolvedValue([
      { id: 7, nombre: "Ballet", horarios: [] },
      { id: 8, nombre: "Danza jazz", horarios: [] },
    ]);
    mocks.obtenerDisciplina.mockResolvedValue({
      data: { horarios: [{ diaSemana: currentDayName() }] },
    });
    mocks.obtenerDetalle.mockResolvedValue(monthlyDetail());
    mocks.registrarDiaria.mockImplementation(async (request) => ({
      id: request.id ?? 500,
      ...request,
      alumno: student(request.asistenciaAlumnoMensualId),
      asistenciaMensualId: 40,
      disciplinaId: 7,
    }));
    mocks.actualizarMensual.mockResolvedValue(monthlyDetail());
  });

  it("muestra el estado inicial y el error seguro al no poder cargar disciplinas", async () => {
    mocks.listarDisciplinas.mockRejectedValueOnce(new Error("network"));

    renderPage();

    expect(screen.getByText("Prepará la asistencia")).toBeVisible();
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Error al cargar disciplinas",
    );
  });

  it("permite seleccionar y limpiar una disciplina usando el teclado", async () => {
    renderPage();

    const search = await screen.findByLabelText("Disciplina");
    fireEvent.focus(search);
    fireEvent.change(search, { target: { value: "danza" } });
    fireEvent.keyDown(search, { key: "ArrowDown" });
    fireEvent.keyDown(search, { key: "Enter" });

    expect(search).toHaveValue("Danza jazz");
    expect(screen.getByRole("button", { name: "Buscar asistencia" })).toBeEnabled();

    fireEvent.click(screen.getByRole("button", { name: "Limpiar" }));

    expect(search).toHaveValue("");
    expect(screen.getByRole("button", { name: "Buscar asistencia" })).toBeDisabled();
  });

  it("no consulta la planilla cuando la fecha no es un día de clase", async () => {
    mocks.obtenerDisciplina.mockResolvedValue({ data: { horarios: [] } });
    renderPage();
    await selectDiscipline("Ballet");

    fireEvent.click(screen.getByRole("button", { name: "Buscar asistencia" }));

    expect(await screen.findByText("No hay clase ese día")).toBeVisible();
    expect(mocks.obtenerDetalle).not.toHaveBeenCalled();
  });

  it("presenta loading y luego el estado vacío de una planilla sin alumnos", async () => {
    let resolveDetail!: (value: ReturnType<typeof monthlyDetail>) => void;
    mocks.obtenerDetalle.mockReturnValueOnce(
      new Promise<ReturnType<typeof monthlyDetail>>((resolve) => {
        resolveDetail = resolve;
      }),
    );
    renderPage();
    await selectDiscipline("Ballet");

    fireEvent.click(screen.getByRole("button", { name: "Buscar asistencia" }));

    expect(await screen.findByText("Cargando asistencia...")).toBeVisible();
    resolveDetail(monthlyDetail([]));
    expect(await screen.findByText("Sin alumnos para registrar")).toBeVisible();
    expect(mocks.obtenerDetalle).toHaveBeenCalledWith(
      7,
      new Date().getMonth() + 1,
      new Date().getFullYear(),
    );
  });

  it("informa un error de carga sin conservar el indicador de espera", async () => {
    mocks.obtenerDetalle.mockRejectedValueOnce(new Error("backend"));
    renderPage();
    await selectDiscipline("Ballet");

    fireEvent.click(screen.getByRole("button", { name: "Buscar asistencia" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Error al cargar las asistencias",
    );
    expect(screen.queryByText("Cargando asistencia...")).not.toBeInTheDocument();
  });

  it("deduplica alumnos y registra tanto una alternancia como una asistencia nueva", async () => {
    renderPage();
    await loadCurrentPlan();

    const table = await screen.findByRole("table");
    expect(within(table).getAllByText("Pérez, Ana")).toHaveLength(1);
    expect(within(table).getByText("López, Beto")).toBeVisible();

    fireEvent.click(
      within(table).getByRole("button", { name: "Marcar ausente a Ana Pérez" }),
    );
    await waitFor(() =>
      expect(mocks.registrarDiaria).toHaveBeenCalledWith({
        id: 301,
        fecha: localDate(new Date()),
        estado: EstadoAsistencia.AUSENTE,
        asistenciaAlumnoMensualId: 101,
      }),
    );

    fireEvent.click(
      within(table).getByRole("button", { name: "Marcar presente a Ana Pérez" }),
    );
    await waitFor(() =>
      expect(mocks.registrarDiaria).toHaveBeenCalledWith({
        id: 301,
        fecha: localDate(new Date()),
        estado: EstadoAsistencia.PRESENTE,
        asistenciaAlumnoMensualId: 101,
      }),
    );

    fireEvent.click(
      within(table).getByRole("button", { name: "Marcar presente a Beto López" }),
    );
    await waitFor(() =>
      expect(mocks.registrarDiaria).toHaveBeenCalledWith({
        fecha: localDate(new Date()),
        estado: EstadoAsistencia.PRESENTE,
        asistenciaAlumnoMensualId: 103,
      }),
    );
  });

  it("mantiene la planilla y muestra feedback si falla el registro diario", async () => {
    mocks.registrarDiaria.mockRejectedValueOnce(new Error("write"));
    renderPage();
    await loadCurrentPlan();

    fireEvent.click(
      screen.getByRole("button", { name: "Marcar ausente a Ana Pérez" }),
    );

    await waitFor(() =>
      expect(mocks.toastError).toHaveBeenCalledWith(
        "No se pudo actualizar la asistencia",
      ),
    );
    expect(screen.getByRole("button", { name: "Marcar ausente a Ana Pérez" })).toBeVisible();
  });

  it("persiste una observación con debounce y reporta el fallo de guardado", async () => {
    mocks.actualizarMensual.mockRejectedValueOnce(new Error("write"));
    renderPage();
    await loadCurrentPlan();

    fireEvent.change(screen.getAllByPlaceholderText("Agregar observación")[0], {
      target: { value: "Llegó tarde" },
    });

    await waitFor(
      () =>
        expect(mocks.actualizarMensual).toHaveBeenCalledWith(40, {
          asistenciasAlumnoMensual: [
            { id: 101, observacion: "Llegó tarde", asistenciasDiarias: [] },
          ],
        }),
      { timeout: 1_200 },
    );
    await waitFor(() =>
      expect(mocks.toastError).toHaveBeenCalledWith(
        "No se pudo guardar la observación",
      ),
    );
  });

  it("presenta la asistencia en modo lectura sin permiso de registro", async () => {
    mocks.hasPermission.mockReturnValue(false);
    renderPage();
    await loadCurrentPlan();

    expect(screen.getByLabelText("Presente")).toBeVisible();
    expect(screen.getAllByPlaceholderText("Agregar observación")[0]).toHaveAttribute(
      "readonly",
    );
    expect(
      screen.queryByRole("button", { name: /Marcar (presente|ausente)/ }),
    ).not.toBeInTheDocument();
    expect(mocks.registrarDiaria).not.toHaveBeenCalled();
  });

  it("vuelve al listado mensual conservando navegación por ruta", async () => {
    renderPage();

    fireEvent.click(screen.getByRole("button", { name: "Volver" }));

    expect(await screen.findByText("Destino mensual")).toBeVisible();
  });
});

function renderPage() {
  return render(
    <MemoryRouter initialEntries={["/asistencias-diarias"]}>
      <Routes>
        <Route path="/asistencias-diarias" element={<AsistenciaDiariaFormulario />} />
        <Route path="/asistencias-mensuales" element={<p>Destino mensual</p>} />
      </Routes>
    </MemoryRouter>,
  );
}

async function selectDiscipline(name: string) {
  const search = await screen.findByLabelText("Disciplina");
  fireEvent.focus(search);
  fireEvent.click(await screen.findByRole("option", { name }));
  await waitFor(() => expect(search).toHaveValue(name));
}

async function loadCurrentPlan() {
  await selectDiscipline("Ballet");
  fireEvent.click(screen.getByRole("button", { name: "Buscar asistencia" }));
  await screen.findByRole("table");
}

function monthlyDetail(alumnos = attendanceRows()) {
  return {
    id: 40,
    mes: new Date().getMonth() + 1,
    anio: new Date().getFullYear(),
    disciplina: { id: 7, nombre: "Ballet" },
    profesor: "Profe Uno",
    alumnos,
  };
}

function attendanceRows() {
  const date = localDate(new Date());
  return [
    {
      id: 101,
      asistenciaMensualId: 40,
      inscripcionId: 501,
      alumno: student(1, "Ana", "Pérez"),
      observacion: "Inicial",
      asistenciasDiarias: [dailyRecord(301, 101, date, EstadoAsistencia.PRESENTE)],
    },
    {
      id: 102,
      asistenciaMensualId: 40,
      inscripcionId: 502,
      alumno: student(1, "Ana", "Pérez"),
      observacion: "",
      asistenciasDiarias: [dailyRecord(302, 102, "2026-01-02", EstadoAsistencia.AUSENTE)],
    },
    {
      id: 103,
      asistenciaMensualId: 40,
      inscripcionId: 503,
      alumno: student(2, "Beto", "López"),
      observacion: "",
      asistenciasDiarias: [],
    },
  ];
}

function dailyRecord(
  id: number,
  monthlyStudentId: number,
  fecha: string,
  estado: EstadoAsistencia,
) {
  return {
    id,
    fecha,
    estado,
    asistenciaAlumnoMensualId: monthlyStudentId,
    alumno: student(monthlyStudentId),
    asistenciaMensualId: 40,
    disciplinaId: 7,
  };
}

function student(id: number, nombre = "Alumno", apellido = "Prueba") {
  return { id, nombre, apellido };
}

function currentDayName() {
  return [
    "DOMINGO",
    "LUNES",
    "MARTES",
    "MIERCOLES",
    "JUEVES",
    "VIERNES",
    "SABADO",
  ][new Date().getDay()];
}

function localDate(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}
