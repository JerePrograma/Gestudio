import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type {
  AlumnoResponse,
  DisciplinaListadoResponse,
  InscripcionResponse,
  Page,
} from "../../types/types";

const alumnosApi = vi.hoisted(() => ({ buscar: vi.fn(), obtener: vi.fn() }));
const disciplinasApi = vi.hoisted(() => ({ listar: vi.fn() }));
const inscripcionesApi = vi.hoisted(() => ({ crear: vi.fn(), obtener: vi.fn(), actualizar: vi.fn() }));
const navigate = vi.hoisted(() => vi.fn());
const toastSuccess = vi.hoisted(() => vi.fn());
const toastError = vi.hoisted(() => vi.fn());
const getFieldErrors = vi.hoisted(() => vi.fn(() => ({})));
const getApiErrorMessage = vi.hoisted(() => vi.fn((_error: unknown, fallback: string) => fallback));

vi.mock("../../api/alumnosApi", () => ({
  default: { buscarPorNombre: alumnosApi.buscar, obtenerPorId: alumnosApi.obtener },
}));
vi.mock("../../api/disciplinasApi", () => ({ default: { listarDisciplinas: disciplinasApi.listar } }));
vi.mock("../../api/inscripcionesApi", () => ({
  default: {
    crear: inscripcionesApi.crear,
    obtenerPorId: inscripcionesApi.obtener,
    actualizar: inscripcionesApi.actualizar,
  },
}));
vi.mock("../../api/apiError", () => ({ getFieldErrors, getApiErrorMessage }));
vi.mock("react-toastify", () => ({ toast: { success: toastSuccess, error: toastError } }));
vi.mock("react-router", async (importOriginal) => ({
  ...(await importOriginal<typeof import("react-router")>()),
  useNavigate: () => navigate,
}));

import InscripcionesFormulario from "./InscripcionesFormulario";

describe("InscripcionesFormulario", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    disciplinasApi.listar.mockResolvedValue([disciplina(3, "Danza", true), disciplina(4, "Archivada", false)]);
    alumnosApi.buscar.mockResolvedValue(pagina([alumno(7, true), alumno(8, false, false)], 0, 8));
    alumnosApi.obtener.mockResolvedValue(alumno(7, true));
    inscripcionesApi.obtener.mockResolvedValue(inscripcion(21));
    inscripcionesApi.crear.mockResolvedValue(inscripcion(21));
    inscripcionesApi.actualizar.mockResolvedValue(inscripcion(21));
  });

  it("representa carga y error de las dependencias del formulario", async () => {
    let reject!: (reason: unknown) => void;
    disciplinasApi.listar.mockReturnValueOnce(new Promise((_resolve, fail) => { reject = fail; }));
    renderForm();
    expect(screen.getByText("Cargando formulario...")).toBeVisible();
    reject(new Error("network"));
    expect(await screen.findByRole("alert")).toHaveTextContent("No se pudieron cargar los datos del formulario.");
    cleanup();

    inscripcionesApi.obtener.mockRejectedValueOnce(new Error("missing"));
    renderForm("/inscripciones/formulario?id=21");
    expect(await screen.findByRole("alert")).toHaveTextContent("No se pudieron cargar los datos del formulario.");
  });

  it("busca un alumno humano, excluye disciplina inactiva y crea con IDs explícitos", async () => {
    const queryClient = renderForm();
    const invalidate = vi.spyOn(queryClient, "invalidateQueries");

    expect(await screen.findByRole("heading", { name: "Nueva inscripción" })).toBeVisible();
    fireEvent.change(screen.getByLabelText("Alumno"), { target: { value: "A" } });
    expect(screen.getByText("Escribí al menos 2 caracteres para buscar.")).toBeVisible();
    expect(alumnosApi.buscar).not.toHaveBeenCalled();

    fireEvent.change(screen.getByLabelText("Alumno"), { target: { value: "Ana" } });
    await waitFor(() => expect(alumnosApi.buscar).toHaveBeenCalledWith("Ana", 0, 8));
    expect(await screen.findByRole("button", { name: "Seleccionar Alumno 8" })).toBeDisabled();
    fireEvent.click(screen.getByRole("button", { name: "Seleccionar Ana Prueba" }));
    expect(screen.getAllByText("Ana Prueba").length).toBeGreaterThan(0);

    expect(screen.queryByRole("option", { name: "Archivada" })).not.toBeInTheDocument();
    fireEvent.change(screen.getByLabelText(/Disciplina/), { target: { value: "3" } });
    fireEvent.change(control("fechaInscripcion"), { target: { value: "2026-08-13" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar inscripción" }));

    await waitFor(() => expect(inscripcionesApi.crear).toHaveBeenCalledWith({
      alumnoId: 7,
      disciplinaId: 3,
      fechaInscripcion: "2026-08-13",
    }));
    expect(invalidate).toHaveBeenCalledWith({ queryKey: ["inscripciones"] });
    expect(toastSuccess).toHaveBeenCalledWith("Inscripción guardada correctamente.");
    expect(navigate).toHaveBeenCalledWith("/inscripciones");
  });

  it("impide submit incompleto y muestra los errores de selección", async () => {
    renderForm();
    await screen.findByRole("heading", { name: "Nueva inscripción" });

    fireEvent.click(screen.getByRole("button", { name: "Guardar inscripción" }));
    expect(await screen.findByText("Debe seleccionar un alumno")).toBeVisible();
    expect(screen.getByText("Debe seleccionar una disciplina")).toBeVisible();
    expect(screen.getByText("La fecha de inscripción es obligatoria")).toBeVisible();
    expect(inscripcionesApi.crear).not.toHaveBeenCalled();
  });

  it("carga edición con alumno inicial, permite cambiarlo y actualiza", async () => {
    renderForm("/inscripciones/formulario?id=21");

    expect(await screen.findByRole("heading", { name: "Editar inscripción" })).toBeVisible();
    await waitFor(() => expect(alumnosApi.obtener).toHaveBeenCalledWith(7));
    expect(await screen.findByText("DNI 12345678 · 2235550000")).toBeVisible();
    expect(screen.getByLabelText(/Disciplina/)).toHaveValue("3");
    expect(control("fechaInscripcion")).toHaveValue("2026-08-01");

    fireEvent.click(screen.getByRole("button", { name: "Cambiar" }));
    expect(screen.getByLabelText("Alumno")).toHaveValue("");
    fireEvent.change(screen.getByLabelText("Alumno"), { target: { value: "Ana" } });
    fireEvent.click(await screen.findByRole("button", { name: "Seleccionar Ana Prueba" }));
    fireEvent.change(control("fechaInscripcion"), { target: { value: "2026-08-02" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar inscripción" }));

    await waitFor(() => expect(inscripcionesApi.actualizar).toHaveBeenCalledWith(21, {
      id: 21,
      alumnoId: 7,
      disciplinaId: 3,
      fechaInscripcion: "2026-08-02",
    }));
  });

  it("representa búsqueda vacía, error con retry y resultado sin contacto", async () => {
    alumnosApi.buscar
      .mockResolvedValueOnce(pagina([], 0, 8))
      .mockRejectedValueOnce(new Error("network"))
      .mockResolvedValueOnce(pagina([alumno(9, true, false)], 0, 8));
    renderForm();
    await screen.findByRole("heading", { name: "Nueva inscripción" });

    fireEvent.change(screen.getByLabelText("Alumno"), { target: { value: "Nadie" } });
    expect(await screen.findByText("Sin resultados")).toBeVisible();

    fireEvent.change(screen.getByLabelText("Alumno"), { target: { value: "Error" } });
    expect(await screen.findByRole("alert")).toHaveTextContent("No se pudieron buscar alumnos.");
    fireEvent.click(screen.getByRole("button", { name: "Reintentar" }));
    expect(await screen.findByRole("button", { name: "Seleccionar Alumno 9" })).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Seleccionar Alumno 9" }));
    expect(screen.getByText("Sin datos de contacto cargados")).toBeVisible();
  });

  it("conserva el formulario y aplica errores de campo ante rechazo backend", async () => {
    const rejection = new Error("conflict");
    inscripcionesApi.crear.mockRejectedValueOnce(rejection);
    getFieldErrors.mockReturnValueOnce({ disciplinaId: "La inscripción ya existe" });
    getApiErrorMessage.mockReturnValueOnce("Inscripción duplicada");
    renderForm("/inscripciones/formulario?alumnoId=7");

    await screen.findByRole("heading", { name: "Nueva inscripción" });
    await waitFor(() => expect(alumnosApi.obtener).toHaveBeenCalledWith(7));
    fireEvent.change(screen.getByLabelText(/Disciplina/), { target: { value: "3" } });
    fireEvent.change(control("fechaInscripcion"), { target: { value: "2026-08-13" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar inscripción" }));

    expect(await screen.findByText("La inscripción ya existe")).toBeVisible();
    expect(getFieldErrors).toHaveBeenCalledWith(rejection);
    expect(toastError).toHaveBeenCalledWith("Inscripción duplicada");
    expect(screen.getByRole("button", { name: "Guardar inscripción" })).toBeEnabled();

    fireEvent.click(screen.getByRole("button", { name: "Cancelar" }));
    expect(navigate).toHaveBeenCalledWith("/inscripciones");
  });
});

function renderForm(initialEntry = "/inscripciones/formulario") {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } });
  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[initialEntry]}>
        <InscripcionesFormulario />
      </MemoryRouter>
    </QueryClientProvider>,
  );
  return queryClient;
}

function control(id: string): HTMLInputElement | HTMLSelectElement {
  const element = document.getElementById(id) as HTMLInputElement | HTMLSelectElement | null;
  expect(element).not.toBeNull();
  return element!;
}

function pagina(content: AlumnoResponse[], number: number, size: number): Page<AlumnoResponse> {
  return { content, totalElements: content.length, totalPages: content.length ? 1 : 0, size, number, first: true, last: true };
}

function alumno(id: number, activo: boolean, contacto = true): AlumnoResponse {
  return {
    id,
    nombre: id === 7 ? "Ana" : "Alumno",
    apellido: id === 7 ? "Prueba" : String(id),
    fechaNacimiento: "2010-01-01",
    fechaIncorporacion: "2026-01-01",
    edad: 16,
    celular1: contacto ? "2235550000" : "",
    celular2: "",
    email: "",
    documento: contacto ? "12345678" : "",
    fechaDeBaja: null,
    nombrePadres: "",
    autorizadoParaSalirSolo: false,
    activo,
    otrasNotas: "",
    inscripciones: [],
  };
}

function disciplina(id: number, nombre: string, activo: boolean): DisciplinaListadoResponse {
  return {
    id,
    nombre,
    salon: "Sala",
    salonId: 1,
    valorCuota: "100.00",
    matricula: "50.00",
    profesorNombre: "Ada",
    profesorApellido: "Docente",
    profesorId: 2,
    inscritos: 4,
    activo,
    horarios: [],
  };
}

function inscripcion(id: number): InscripcionResponse {
  return {
    id,
    alumnoId: 7,
    alumno: "Ana Prueba",
    disciplinaId: 3,
    disciplina: "Danza",
    fechaInscripcion: "2026-08-01",
    estado: "ACTIVA",
  };
}
