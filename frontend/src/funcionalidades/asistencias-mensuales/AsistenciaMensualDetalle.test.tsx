import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { EstadoAsistencia } from "../../types/types";

const mocks = vi.hoisted(() => ({
  listarDisciplinas: vi.fn(),
  obtenerDetalle: vi.fn(),
  registrarDiaria: vi.fn(),
  actualizarMensual: vi.fn(),
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

vi.mock("../../hooks/context/useAuth", () => ({
  useAuth: () => ({ hasPermission: mocks.hasPermission }),
}));

vi.mock("../../hooks/useDebounce", () => ({
  default: (value: unknown) => value,
}));

vi.mock("react-toastify", () => ({
  toast: {
    warn: mocks.toastWarn,
    error: mocks.toastError,
  },
}));

import AsistenciaMensualDetalle from "./AsistenciaMensualDetalle";

describe("AsistenciaMensualDetalle", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.hasPermission.mockReturnValue(true);
    mocks.listarDisciplinas.mockResolvedValue([
      { id: 7, nombre: "Ballet" },
      { id: 8, nombre: "Danza jazz" },
    ]);
    mocks.obtenerDetalle.mockResolvedValue(monthlyDetail());
    mocks.registrarDiaria.mockImplementation(async (request) => ({
      id: request.id,
      ...request,
      alumno: student(1, "Ana", "Pérez"),
      asistenciaMensualId: 40,
      disciplinaId: 7,
    }));
    mocks.actualizarMensual.mockResolvedValue(monthlyDetail());
  });

  it("valida filtros y notifica si falla la lista de disciplinas", async () => {
    mocks.listarDisciplinas.mockRejectedValueOnce(new Error("network"));
    renderPage();

    fireEvent.click(screen.getByRole("button", { name: "Consultar asistencia" }));

    expect(mocks.toastWarn).toHaveBeenCalledWith(
      "Complete todos los filtros antes de consultar.",
    );
    await waitFor(() =>
      expect(mocks.toastError).toHaveBeenCalledWith(
        "Error al cargar disciplinas",
      ),
    );
    expect(mocks.obtenerDetalle).not.toHaveBeenCalled();
  });

  it("selecciona por teclado, oculta sugerencias al hacer clic fuera y limpia", async () => {
    renderPage();

    const search = screen.getByLabelText("Buscar disciplina:");
    fireEvent.focus(search);
    expect(await screen.findByText("Ballet")).toBeVisible();
    fireEvent.mouseDown(document.body);
    expect(screen.queryByText("Ballet")).not.toBeInTheDocument();

    fireEvent.focus(search);
    fireEvent.change(search, { target: { value: "danza" } });
    fireEvent.keyDown(search, { key: "ArrowDown" });
    fireEvent.keyDown(search, { key: "Tab" });
    expect(search).toHaveValue("Danza jazz");

    fireEvent.click(screen.getByRole("button", { name: "Limpiar" }));
    expect(search).toHaveValue("");
  });

  it("muestra loading y el estado vacío usando los filtros elegidos", async () => {
    let resolveDetail!: (value: ReturnType<typeof monthlyDetail>) => void;
    mocks.obtenerDetalle.mockReturnValueOnce(
      new Promise<ReturnType<typeof monthlyDetail>>((resolve) => {
        resolveDetail = resolve;
      }),
    );
    renderPage();
    await selectDiscipline("Ballet");
    const nextYear = new Date().getFullYear() + 1;
    fireEvent.change(screen.getByLabelText("Mes:"), { target: { value: "2" } });
    fireEvent.change(screen.getByLabelText("Año:"), {
      target: { value: String(nextYear) },
    });

    fireEvent.click(screen.getByRole("button", { name: "Consultar asistencia" }));

    expect(await screen.findByText("Cargando asistencia mensual...")).toBeVisible();
    resolveDetail(monthlyDetail([]));
    expect(
      await screen.findByText(
        "No se encontraron registros diarios para este periodo.",
      ),
    ).toBeVisible();
    expect(mocks.obtenerDetalle).toHaveBeenCalledWith(7, 2, nextYear);
  });

  it("trata una respuesta nula como ausencia de planilla", async () => {
    mocks.obtenerDetalle.mockResolvedValueOnce(null);
    renderPage();
    await selectDiscipline("Ballet");

    fireEvent.click(screen.getByRole("button", { name: "Consultar asistencia" }));

    await waitFor(() => expect(mocks.obtenerDetalle).toHaveBeenCalledTimes(1));
    expect(screen.getByText("Consultar Asistencia Mensual")).toBeVisible();
    expect(screen.queryByRole("table")).not.toBeInTheDocument();
  });

  it("notifica un error de consulta y siempre retira el indicador de carga", async () => {
    mocks.obtenerDetalle.mockRejectedValueOnce(new Error("backend"));
    renderPage();
    await selectDiscipline("Ballet");

    fireEvent.click(screen.getByRole("button", { name: "Consultar asistencia" }));

    await waitFor(() =>
      expect(mocks.toastError).toHaveBeenCalledWith(
        "Error al cargar la asistencia mensual",
      ),
    );
    expect(screen.queryByText("Cargando asistencia mensual...")).not.toBeInTheDocument();
  });

  it("fusiona alumnos duplicados, alterna asistencia y conserva el resto del detalle", async () => {
    renderPage();
    await loadPlan();

    const table = await screen.findByRole("table");
    expect(within(table).getAllByText("Pérez, Ana")).toHaveLength(1);
    expect(within(table).getByText("Sin alumno")).toBeVisible();
    const anaRow = within(table).getByRole("row", { name: /Pérez, Ana/ });
    const attendanceButtons = within(anaRow).getAllByRole("button");

    fireEvent.click(attendanceButtons[0]);

    await waitFor(() =>
      expect(mocks.registrarDiaria).toHaveBeenCalledWith({
        id: 301,
        fecha: "2026-08-03",
        estado: EstadoAsistencia.AUSENTE,
        asistenciaAlumnoMensualId: 101,
      }),
    );

    fireEvent.click(within(anaRow).getAllByRole("button")[0]);
    await waitFor(() =>
      expect(mocks.registrarDiaria).toHaveBeenCalledWith({
        id: 301,
        fecha: "2026-08-03",
        estado: EstadoAsistencia.PRESENTE,
        asistenciaAlumnoMensualId: 101,
      }),
    );
    expect(screen.getByText("Detalle de Asistencia Mensual - Ballet")).toBeVisible();
  });

  it("envía todas las observaciones y muestra feedback ante un fallo diario", async () => {
    mocks.registrarDiaria.mockRejectedValueOnce(new Error("write"));
    renderPage();
    await loadPlan();

    const anaRow = screen.getByRole("row", { name: /Pérez, Ana/ });
    fireEvent.change(within(anaRow).getByPlaceholderText("Observaciones..."), {
      target: { value: "Trajo certificado" },
    });

    expect(mocks.actualizarMensual).toHaveBeenCalledWith(40, {
      asistenciasAlumnoMensual: [
        { id: 101, observacion: "Trajo certificado", asistenciasDiarias: [] },
        { id: 102, observacion: "Duplicado", asistenciasDiarias: [] },
        { id: 103, observacion: "Sin identidad", asistenciasDiarias: [] },
      ],
    });

    fireEvent.click(within(anaRow).getAllByRole("button")[0]);
    await waitFor(() =>
      expect(mocks.toastError).toHaveBeenCalledWith(
        "Error al guardar las observaciones",
      ),
    );
  });

  it("renderiza valores sin controles mutables cuando falta permiso", async () => {
    mocks.hasPermission.mockReturnValue(false);
    renderPage();
    await loadPlan();

    const anaRow = screen.getByRole("row", { name: /Pérez, Ana/ });
    expect(within(anaRow).getByLabelText("Presente")).toBeVisible();
    expect(within(anaRow).getByPlaceholderText("Observaciones...")).toHaveAttribute(
      "readonly",
    );
    expect(within(anaRow).queryByRole("button")).not.toBeInTheDocument();
    expect(mocks.registrarDiaria).not.toHaveBeenCalled();
    expect(mocks.actualizarMensual).not.toHaveBeenCalled();
  });

  it("vuelve al listado mensual", () => {
    renderPage();

    fireEvent.click(screen.getByRole("button", { name: "Volver" }));

    expect(screen.getByText("Listado mensual")).toBeVisible();
  });
});

function renderPage() {
  return render(
    <MemoryRouter initialEntries={["/asistencias-mensuales/detalle"]}>
      <Routes>
        <Route
          path="/asistencias-mensuales/detalle"
          element={<AsistenciaMensualDetalle />}
        />
        <Route path="/asistencias-mensuales" element={<p>Listado mensual</p>} />
      </Routes>
    </MemoryRouter>,
  );
}

async function selectDiscipline(name: string) {
  const search = screen.getByLabelText("Buscar disciplina:");
  fireEvent.focus(search);
  fireEvent.click(await screen.findByText(name));
  await waitFor(() => expect(search).toHaveValue(name));
}

async function loadPlan() {
  await selectDiscipline("Ballet");
  fireEvent.click(screen.getByRole("button", { name: "Consultar asistencia" }));
  await screen.findByRole("table");
}

function monthlyDetail(alumnos = attendanceRows()) {
  return {
    id: 40,
    mes: 8,
    anio: 2026,
    disciplina: { id: 7, nombre: "Ballet" },
    profesor: "Profe Uno",
    alumnos,
  };
}

function attendanceRows() {
  return [
    {
      id: 101,
      asistenciaMensualId: 40,
      inscripcionId: 501,
      alumno: student(1, "Ana", "Pérez"),
      observacion: "Inicial",
      asistenciasDiarias: [
        dailyRecord(301, 101, "2026-08-03", EstadoAsistencia.PRESENTE),
      ],
    },
    {
      id: 102,
      asistenciaMensualId: 40,
      inscripcionId: 502,
      alumno: student(1, "Ana", "Pérez"),
      observacion: "Duplicado",
      asistenciasDiarias: [
        dailyRecord(302, 102, "2026-08-10", EstadoAsistencia.AUSENTE),
      ],
    },
    {
      id: 103,
      asistenciaMensualId: 40,
      inscripcionId: 503,
      alumno: null,
      observacion: "Sin identidad",
      asistenciasDiarias: [
        dailyRecord(303, 103, "2026-08-03", EstadoAsistencia.AUSENTE),
      ],
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
