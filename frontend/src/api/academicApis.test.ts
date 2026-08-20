import { beforeEach, describe, expect, it, vi } from "vitest";
import axios from "axios";
import { EstadoAsistencia } from "../types/types";

const mocks = vi.hoisted(() => ({
  get: vi.fn(),
  post: vi.fn(),
  put: vi.fn(),
  delete: vi.fn(),
  toastSuccess: vi.fn(),
  toastWarn: vi.fn(),
  toastError: vi.fn(),
}));

vi.mock("./axiosConfig", () => ({
  default: {
    get: mocks.get,
    post: mocks.post,
    put: mocks.put,
    delete: mocks.delete,
  },
}));

vi.mock("react-toastify", () => ({
  toast: {
    success: mocks.toastSuccess,
    warn: mocks.toastWarn,
    error: mocks.toastError,
  },
}));

import alumnosApi from "./alumnosApi";
import asistenciasApi from "./asistenciasApi";
import disciplinasApi from "./disciplinasApi";
import inscripcionesApi from "./inscripcionesApi";
import mensualidadesApi from "./mensualidadesApi";
import profesoresApi from "./profesoresApi";

const apiError = new Error("backend unavailable");

beforeEach(() => {
  vi.clearAllMocks();
});

describe("alumnosApi", () => {
  it("usa paginación por defecto y devuelve data", async () => {
    const data = { content: [], totalElements: 0 };
    mocks.get.mockResolvedValueOnce({ data });

    await expect(alumnosApi.listar()).resolves.toBe(data);
    expect(mocks.get).toHaveBeenCalledWith("/alumnos", {
      params: { page: 0, size: 50 },
    });
  });

  it("respeta paginación explícita en listado y búsqueda", async () => {
    const list = { content: [{ id: 1 }], totalElements: 1 };
    const search = { content: [{ id: 2 }], totalElements: 1 };
    mocks.get.mockResolvedValueOnce({ data: list }).mockResolvedValueOnce({ data: search });

    await expect(alumnosApi.listar(3, 25)).resolves.toBe(list);
    await expect(alumnosApi.buscarPorNombre("Ana", 2, 10)).resolves.toBe(search);
    expect(mocks.get).toHaveBeenNthCalledWith(1, "/alumnos", {
      params: { page: 3, size: 25 },
    });
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/alumnos/buscar", {
      params: { nombre: "Ana", page: 2, size: 10 },
    });
  });

  it("contrata obtener, registrar, actualizar, baja y disciplinas", async () => {
    const alumno = { id: 9, nombre: "Ana" };
    const request = {
      nombre: "Ana",
      apellido: "Prueba",
      fechaNacimiento: "2010-01-01",
      fechaIncorporacion: "2026-01-01",
      activo: true,
    };
    const disciplinas = [{ id: 4, nombre: "Ballet" }];
    mocks.get.mockResolvedValueOnce({ data: alumno }).mockResolvedValueOnce({ data: disciplinas });
    mocks.post.mockResolvedValueOnce({ data: alumno });
    mocks.put.mockResolvedValueOnce({ data: alumno });
    mocks.delete.mockResolvedValueOnce({});

    await expect(alumnosApi.obtenerPorId(9)).resolves.toBe(alumno);
    await expect(alumnosApi.registrar(request)).resolves.toBe(alumno);
    await expect(alumnosApi.actualizar(9, request)).resolves.toBe(alumno);
    await expect(alumnosApi.darBaja(9)).resolves.toBeUndefined();
    await expect(alumnosApi.obtenerDisciplinas(9)).resolves.toBe(disciplinas);

    expect(mocks.get).toHaveBeenNthCalledWith(1, "/alumnos/9");
    expect(mocks.post).toHaveBeenCalledWith("/alumnos", request);
    expect(mocks.put).toHaveBeenCalledWith("/alumnos/9", request);
    expect(mocks.delete).toHaveBeenCalledWith("/alumnos/9");
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/alumnos/9/disciplinas");
  });

  it.each([
    ["listar", mocks.get, () => alumnosApi.listar()],
    ["obtener", mocks.get, () => alumnosApi.obtenerPorId(9)],
    ["registrar", mocks.post, () => alumnosApi.registrar({ nombre: "Ana", apellido: "Prueba", fechaNacimiento: "2010-01-01", fechaIncorporacion: "2026-01-01", activo: true })],
    ["actualizar", mocks.put, () => alumnosApi.actualizar(9, { nombre: "Ana", apellido: "Prueba", fechaNacimiento: "2010-01-01", fechaIncorporacion: "2026-01-01", activo: true })],
    ["dar de baja", mocks.delete, () => alumnosApi.darBaja(9)],
    ["buscar", mocks.get, () => alumnosApi.buscarPorNombre("Ana")],
    ["obtener disciplinas", mocks.get, () => alumnosApi.obtenerDisciplinas(9)],
  ])("propaga el rechazo original al %s", async (_case, client, invoke) => {
    client.mockRejectedValueOnce(apiError);

    await expect(invoke()).rejects.toBe(apiError);
  });
});

describe("disciplinasApi", () => {
  it("contrata altas, lecturas, actualización y bajas", async () => {
    const create = {
      nombre: "Ballet",
      salonId: 2,
      profesorId: 3,
      valorCuota: "100.00",
      matricula: "50.00",
      horarios: [],
    };
    const update = { ...create, activo: true };
    const detail = { id: 7, nombre: "Ballet" };
    mocks.post.mockResolvedValueOnce({ data: detail });
    mocks.get.mockResolvedValueOnce({ data: [detail] }).mockResolvedValueOnce({ data: detail });
    mocks.put.mockResolvedValueOnce({ data: detail });
    mocks.delete.mockResolvedValue({});

    await expect(disciplinasApi.registrarDisciplina(create)).resolves.toBe(detail);
    await expect(disciplinasApi.listarDisciplinas()).resolves.toEqual([detail]);
    await expect(disciplinasApi.obtenerDisciplinaPorId(7)).resolves.toBe(detail);
    await expect(disciplinasApi.actualizarDisciplina(7, update)).resolves.toBe(detail);
    await expect(disciplinasApi.eliminarDisciplina(7)).resolves.toBeUndefined();
    await expect(disciplinasApi.darBajaDisciplina(7)).resolves.toBeUndefined();

    expect(mocks.post).toHaveBeenCalledWith("/disciplinas", create);
    expect(mocks.get).toHaveBeenNthCalledWith(1, "/disciplinas");
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/disciplinas/7");
    expect(mocks.put).toHaveBeenCalledWith("/disciplinas/7", update);
    expect(mocks.delete).toHaveBeenNthCalledWith(1, "/disciplinas/7");
    expect(mocks.delete).toHaveBeenNthCalledWith(2, "/disciplinas/dar-baja/7");
  });

  it("contrata relaciones y listado simplificado", async () => {
    const disciplinas = [{ id: 7, nombre: "Ballet" }];
    const alumnos = [{ id: 1, nombre: "Ana" }];
    const profesor = { id: 3, nombre: "Profe" };
    mocks.get
      .mockResolvedValueOnce({ data: disciplinas })
      .mockResolvedValueOnce({ data: alumnos })
      .mockResolvedValueOnce({ data: profesor });

    await expect(disciplinasApi.listarDisciplinasSimplificadas()).resolves.toBe(disciplinas);
    await expect(disciplinasApi.obtenerAlumnosDeDisciplina(7)).resolves.toBe(alumnos);
    await expect(disciplinasApi.obtenerProfesorDeDisciplina(7)).resolves.toBe(profesor);

    expect(mocks.get).toHaveBeenNthCalledWith(1, "/disciplinas/listado");
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/disciplinas/7/alumnos");
    expect(mocks.get).toHaveBeenNthCalledWith(3, "/disciplinas/7/profesor");
  });

  it("codifica fecha, horario y nombre en las rutas de búsqueda", async () => {
    const data = [{ id: 7 }];
    mocks.get.mockResolvedValue({ data });

    await expect(disciplinasApi.obtenerDisciplinasPorFecha("2026/08/13 +1")).resolves.toBe(data);
    await expect(disciplinasApi.obtenerDisciplinasPorHorario("18:30 + salón A")).resolves.toBe(data);
    await expect(disciplinasApi.buscarPorNombre("Danza & Jazz")).resolves.toBe(data);

    expect(mocks.get).toHaveBeenNthCalledWith(1, "/disciplinas/por-fecha?fecha=2026%2F08%2F13%20%2B1");
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/disciplinas/por-horario?horario=18%3A30%20%2B%20sal%C3%B3n%20A");
    expect(mocks.get).toHaveBeenNthCalledWith(3, "/disciplinas/buscar?nombre=Danza%20%26%20Jazz");
  });

  it.each([
    ["registrar", mocks.post, () => disciplinasApi.registrarDisciplina({ nombre: "Ballet", salonId: 2, profesorId: 3, valorCuota: "100.00", matricula: "50.00", horarios: [] })],
    ["listar", mocks.get, () => disciplinasApi.listarDisciplinas()],
    ["obtener", mocks.get, () => disciplinasApi.obtenerDisciplinaPorId(7)],
    ["actualizar", mocks.put, () => disciplinasApi.actualizarDisciplina(7, { nombre: "Ballet", salonId: 2, profesorId: 3, valorCuota: "100.00", matricula: "50.00", activo: true, horarios: [] })],
    ["eliminar", mocks.delete, () => disciplinasApi.eliminarDisciplina(7)],
    ["dar de baja", mocks.delete, () => disciplinasApi.darBajaDisciplina(7)],
    ["listar simplificadas", mocks.get, () => disciplinasApi.listarDisciplinasSimplificadas()],
    ["buscar por fecha", mocks.get, () => disciplinasApi.obtenerDisciplinasPorFecha("2026-08-13")],
    ["obtener alumnos", mocks.get, () => disciplinasApi.obtenerAlumnosDeDisciplina(7)],
    ["obtener profesor", mocks.get, () => disciplinasApi.obtenerProfesorDeDisciplina(7)],
    ["buscar por horario", mocks.get, () => disciplinasApi.obtenerDisciplinasPorHorario("18:30")],
    ["buscar por nombre", mocks.get, () => disciplinasApi.buscarPorNombre("Ballet")],
  ])("propaga el rechazo original al %s", async (_case, client, invoke) => {
    client.mockRejectedValueOnce(apiError);

    await expect(invoke()).rejects.toBe(apiError);
  });
});

describe("profesoresApi", () => {
  it("contrata CRUD, búsqueda y ambos modos del listado", async () => {
    const create = { nombre: "Mora", apellido: "Díaz" };
    const update = { ...create, activo: true };
    const detail = { id: 3, ...create };
    mocks.post.mockResolvedValueOnce({ data: detail });
    mocks.get
      .mockResolvedValueOnce({ data: detail })
      .mockResolvedValueOnce({ data: [detail] })
      .mockResolvedValueOnce({ data: [detail] })
      .mockResolvedValueOnce({ data: [detail] });
    mocks.put.mockResolvedValueOnce({ data: detail });
    mocks.delete.mockResolvedValueOnce({});

    await expect(profesoresApi.registrarProfesor(create)).resolves.toBe(detail);
    await expect(profesoresApi.obtenerProfesorPorId(3)).resolves.toBe(detail);
    await expect(profesoresApi.listarProfesoresActivos()).resolves.toEqual([detail]);
    await expect(profesoresApi.listarProfesoresActivos(true)).resolves.toEqual([detail]);
    await expect(profesoresApi.buscarPorNombre("Mor")).resolves.toEqual([detail]);
    await expect(profesoresApi.actualizarProfesor(3, update)).resolves.toBe(detail);
    await expect(profesoresApi.eliminarProfesor(3)).resolves.toBeUndefined();

    expect(mocks.post).toHaveBeenCalledWith("/profesores", create);
    expect(mocks.get).toHaveBeenNthCalledWith(1, "/profesores/3");
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/profesores");
    expect(mocks.get).toHaveBeenNthCalledWith(3, "/profesores/activos");
    expect(mocks.get).toHaveBeenNthCalledWith(4, "/profesores/buscar", { params: { nombre: "Mor" } });
    expect(mocks.put).toHaveBeenCalledWith("/profesores/3", update);
    expect(mocks.delete).toHaveBeenCalledWith("/profesores/3");
  });

  it("contrata disciplinas y alumnos del profesor", async () => {
    const disciplinas = [{ id: 7 }];
    const alumnos = [{ id: 1 }];
    mocks.get.mockResolvedValueOnce({ data: disciplinas }).mockResolvedValueOnce({ data: alumnos });

    await expect(profesoresApi.obtenerDisciplinasDeProfesor(3)).resolves.toBe(disciplinas);
    await expect(profesoresApi.findAlumnosPorProfesor(3)).resolves.toBe(alumnos);
    expect(mocks.get).toHaveBeenNthCalledWith(1, "/profesores/3/disciplinas");
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/profesores/3/alumnos");
  });

  it.each([
    ["registrar", mocks.post, () => profesoresApi.registrarProfesor({ nombre: "Mora", apellido: "Díaz" })],
    ["obtener", mocks.get, () => profesoresApi.obtenerProfesorPorId(3)],
    ["listar", mocks.get, () => profesoresApi.listarProfesoresActivos()],
    ["buscar", mocks.get, () => profesoresApi.buscarPorNombre("Mora")],
    ["actualizar", mocks.put, () => profesoresApi.actualizarProfesor(3, { nombre: "Mora", apellido: "Díaz", activo: true })],
    ["eliminar", mocks.delete, () => profesoresApi.eliminarProfesor(3)],
    ["obtener disciplinas", mocks.get, () => profesoresApi.obtenerDisciplinasDeProfesor(3)],
    ["obtener alumnos", mocks.get, () => profesoresApi.findAlumnosPorProfesor(3)],
  ])("propaga el rechazo original al %s", async (_case, client, invoke) => {
    client.mockRejectedValueOnce(apiError);

    await expect(invoke()).rejects.toBe(apiError);
  });
});

describe("inscripcionesApi", () => {
  it("contrata CRUD, defaults, parámetros explícitos y activas", async () => {
    const request = { alumnoId: 1, disciplinaId: 7, fechaInscripcion: "2026-08-13" };
    const item = { id: 20, ...request };
    const page = { content: [item], totalElements: 1 };
    mocks.post.mockResolvedValueOnce({ data: item });
    mocks.get
      .mockResolvedValueOnce({ data: page })
      .mockResolvedValueOnce({ data: page })
      .mockResolvedValueOnce({ data: item })
      .mockResolvedValueOnce({ data: [item] });
    mocks.put.mockResolvedValueOnce({ data: item });
    mocks.delete.mockResolvedValueOnce({});

    await expect(inscripcionesApi.crear(request)).resolves.toBe(item);
    await expect(inscripcionesApi.listar()).resolves.toBe(page);
    await expect(inscripcionesApi.listar(2, 15, "ballet")).resolves.toBe(page);
    await expect(inscripcionesApi.obtenerPorId(20)).resolves.toBe(item);
    await expect(inscripcionesApi.actualizar(20, request)).resolves.toBe(item);
    await expect(inscripcionesApi.eliminar(20)).resolves.toBeUndefined();
    await expect(inscripcionesApi.obtenerInscripcionesActivas(1)).resolves.toEqual([item]);

    expect(mocks.post).toHaveBeenCalledWith("/inscripciones", request);
    expect(mocks.get).toHaveBeenNthCalledWith(1, "/inscripciones", { params: { page: 0, size: 50, filtro: "" } });
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/inscripciones", { params: { page: 2, size: 15, filtro: "ballet" } });
    expect(mocks.get).toHaveBeenNthCalledWith(3, "/inscripciones/20");
    expect(mocks.put).toHaveBeenCalledWith("/inscripciones/20", request);
    expect(mocks.delete).toHaveBeenCalledWith("/inscripciones/20");
    expect(mocks.get).toHaveBeenNthCalledWith(4, "/inscripciones/alumno/1/activas");
  });

  it.each([
    ["crear", mocks.post, () => inscripcionesApi.crear({ alumnoId: 1, disciplinaId: 7, fechaInscripcion: "2026-08-13" })],
    ["listar", mocks.get, () => inscripcionesApi.listar()],
    ["obtener", mocks.get, () => inscripcionesApi.obtenerPorId(20)],
    ["actualizar", mocks.put, () => inscripcionesApi.actualizar(20, { alumnoId: 1, disciplinaId: 7, fechaInscripcion: "2026-08-13" })],
    ["eliminar", mocks.delete, () => inscripcionesApi.eliminar(20)],
    ["obtener activas", mocks.get, () => inscripcionesApi.obtenerInscripcionesActivas(1)],
  ])("propaga el rechazo original al %s", async (_case, client, invoke) => {
    client.mockRejectedValueOnce(apiError);

    await expect(invoke()).rejects.toBe(apiError);
  });
});

describe("asistenciasApi", () => {
  const monthlyRequest = { mes: 8, anio: 2026, disciplinaId: 7 };
  const dailyRequest = {
    id: 5,
    fecha: "2026-08-13",
    estado: EstadoAsistencia.PRESENTE,
    asistenciaAlumnoMensualId: 20,
  };

  it("consulta detalle y transforma su error contractual en null", async () => {
    const detail = { id: 40 };
    mocks.get.mockResolvedValueOnce({ data: detail }).mockRejectedValueOnce(apiError);

    await expect(asistenciasApi.obtenerAsistenciaMensualDetallePorParametros(7, 8, 2026)).resolves.toBe(detail);
    await expect(asistenciasApi.obtenerAsistenciaMensualDetallePorParametros(7, 8, 2026)).resolves.toBeNull();
    expect(mocks.get).toHaveBeenNthCalledWith(1, "/asistencias-mensuales/por-disciplina/detalle", {
      params: { disciplinaId: 7, mes: 8, anio: 2026 },
    });
    expect(mocks.toastError).toHaveBeenCalledWith("Error al obtener la asistencia mensual. Intente nuevamente.");
  });

  it("crea, actualiza y lista planillas con parámetros opcionales", async () => {
    const detail = { id: 40 };
    const list = [{ id: 40 }];
    const modification = { asistenciasAlumnoMensual: [{ id: 20, observacion: "ok" }] };
    mocks.post.mockResolvedValueOnce({ data: detail });
    mocks.get.mockResolvedValueOnce({ data: list }).mockResolvedValueOnce({ data: list });
    mocks.put.mockResolvedValueOnce({ data: detail });

    await expect(asistenciasApi.crearAsistenciaMensualPorDisciplina(monthlyRequest)).resolves.toBe(detail);
    await expect(asistenciasApi.listarAsistenciasMensuales()).resolves.toBe(list);
    await expect(asistenciasApi.listarAsistenciasMensuales(3, 7, 8, 2026)).resolves.toBe(list);
    await expect(asistenciasApi.actualizarAsistenciaMensual(40, modification)).resolves.toBe(detail);

    expect(mocks.post).toHaveBeenCalledWith("/asistencias-mensuales", monthlyRequest);
    expect(mocks.get).toHaveBeenNthCalledWith(1, "/asistencias-mensuales", {
      params: { profesorId: undefined, disciplinaId: undefined, mes: undefined, anio: undefined },
    });
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/asistencias-mensuales", {
      params: { profesorId: 3, disciplinaId: 7, mes: 8, anio: 2026 },
    });
    expect(mocks.put).toHaveBeenCalledWith("/asistencias-mensuales/40", modification);
  });

  it("convierte sólo un error Axios 404 de listado en colección vacía", async () => {
    const notFound = new axios.AxiosError("not found", "404", undefined, undefined, {
      data: null,
      status: 404,
      statusText: "Not Found",
      headers: new axios.AxiosHeaders(),
      config: { headers: new axios.AxiosHeaders() },
    });
    mocks.get.mockRejectedValueOnce(notFound).mockRejectedValueOnce(apiError);

    await expect(asistenciasApi.listarAsistenciasMensuales()).resolves.toEqual([]);
    await expect(asistenciasApi.listarAsistenciasMensuales()).rejects.toBe(apiError);
    expect(mocks.toastWarn).toHaveBeenCalledWith("No se encontraron asistencias para los criterios seleccionados.");
    expect(mocks.toastError).toHaveBeenCalledWith("Error al obtener listado de asistencias. Intente nuevamente.");
  });

  it("contrata consultas diarias con defaults y valores explícitos", async () => {
    const page = { content: [] };
    const list = [{ id: 5 }];
    mocks.get.mockResolvedValueOnce({ data: page }).mockResolvedValueOnce({ data: page }).mockResolvedValueOnce({ data: list });

    await expect(asistenciasApi.obtenerAsistenciasPorDisciplinaYFecha(7, "2026-08-13")).resolves.toBe(page);
    await expect(asistenciasApi.obtenerAsistenciasPorDisciplinaYFecha(7, "2026-08-13", 2, 25)).resolves.toBe(page);
    await expect(asistenciasApi.obtenerAsistenciasDiarias(40)).resolves.toBe(list);

    expect(mocks.get).toHaveBeenNthCalledWith(1, "/asistencias-diarias/por-disciplina-y-fecha", {
      params: { disciplinaId: 7, fecha: "2026-08-13", page: 0, size: 10 },
    });
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/asistencias-diarias/por-disciplina-y-fecha", {
      params: { disciplinaId: 7, fecha: "2026-08-13", page: 2, size: 25 },
    });
    expect(mocks.get).toHaveBeenNthCalledWith(3, "/asistencias-diarias/por-asistencia-mensual/40");
  });

  it("registra, modifica y elimina asistencia diaria con feedback contractual", async () => {
    const record = { id: 5 };
    mocks.put.mockResolvedValueOnce({ data: record }).mockResolvedValueOnce({ data: record });
    mocks.delete.mockResolvedValueOnce({});

    await expect(asistenciasApi.registrarAsistenciaDiaria(dailyRequest)).resolves.toBe(record);
    await expect(asistenciasApi.modificarAsistenciaDiaria(5, dailyRequest)).resolves.toBe(record);
    await expect(asistenciasApi.eliminarAsistenciaDiaria(5)).resolves.toBeUndefined();

    expect(mocks.put).toHaveBeenNthCalledWith(1, "/asistencias-diarias/registrar", dailyRequest);
    expect(mocks.put).toHaveBeenNthCalledWith(2, "/asistencias-diarias/5", dailyRequest);
    expect(mocks.delete).toHaveBeenCalledWith("/asistencias-diarias/5");
    expect(mocks.toastSuccess).toHaveBeenCalledWith("Asistencia eliminada correctamente.");
  });

  it("contrata generación masiva y listado simplificado", async () => {
    const generated = { totalPlanillasCreadas: 2 };
    const disciplines = [{ id: 7 }];
    mocks.post.mockResolvedValueOnce({ data: generated });
    mocks.get.mockResolvedValueOnce({ data: disciplines });

    await expect(asistenciasApi.crearAsistenciasParaInscripcionesActivas()).resolves.toBe(generated);
    await expect(asistenciasApi.listarDisciplinasSimplificadas()).resolves.toBe(disciplines);
    expect(mocks.post).toHaveBeenCalledWith("/asistencias-mensuales/crear-asistencias-activos-detallado");
    expect(mocks.get).toHaveBeenCalledWith("/disciplinas/listado");
  });

  it.each([
    ["crear planilla", mocks.post, () => asistenciasApi.crearAsistenciaMensualPorDisciplina(monthlyRequest), "Error al crear la asistencia mensual. Intente nuevamente."],
    ["actualizar planilla", mocks.put, () => asistenciasApi.actualizarAsistenciaMensual(40, { asistenciasAlumnoMensual: [] }), "Error al actualizar asistencia. Intente nuevamente."],
    ["consultar por disciplina y fecha", mocks.get, () => asistenciasApi.obtenerAsistenciasPorDisciplinaYFecha(7, "2026-08-13"), "Error al obtener asistencias. Intente nuevamente."],
    ["consultar diarias", mocks.get, () => asistenciasApi.obtenerAsistenciasDiarias(40), "Error al obtener asistencias. Intente nuevamente."],
    ["registrar diaria", mocks.put, () => asistenciasApi.registrarAsistenciaDiaria(dailyRequest), "No se pudo registrar la asistencia. Verifica los datos."],
    ["modificar diaria", mocks.put, () => asistenciasApi.modificarAsistenciaDiaria(5, dailyRequest), "No se pudo modificar la asistencia. Intente nuevamente."],
    ["eliminar diaria", mocks.delete, () => asistenciasApi.eliminarAsistenciaDiaria(5), "Error al eliminar asistencia. Intente nuevamente."],
    ["generar masivo", mocks.post, () => asistenciasApi.crearAsistenciasParaInscripcionesActivas(), "Error al crear las asistencias. Intente nuevamente."],
    ["listar disciplinas", mocks.get, () => asistenciasApi.listarDisciplinasSimplificadas(), "Error al obtener disciplinas. Intente nuevamente."],
  ])("propaga el rechazo de %s y emite su mensaje", async (_case, client, invoke, message) => {
    client.mockRejectedValueOnce(apiError);

    await expect(invoke()).rejects.toBe(apiError);
    expect(mocks.toastError).toHaveBeenCalledWith(message);
  });
});

describe("mensualidadesApi", () => {
  it("contrata CRUD, ambas lecturas por inscripción y generación", async () => {
    const request = { inscripcionId: 20, anio: 2026, mes: 8 };
    const item = { id: 30, ...request };
    mocks.post.mockResolvedValueOnce({ data: item }).mockResolvedValueOnce({ data: [item] });
    mocks.put.mockResolvedValueOnce({ data: item });
    mocks.get
      .mockResolvedValueOnce({ data: item })
      .mockResolvedValueOnce({ data: [item] })
      .mockResolvedValueOnce({ data: [item] })
      .mockResolvedValueOnce({ data: [item] });
    mocks.delete.mockResolvedValueOnce({});

    await expect(mensualidadesApi.crearMensualidad(request)).resolves.toBe(item);
    await expect(mensualidadesApi.actualizarMensualidad(30, request)).resolves.toBe(item);
    await expect(mensualidadesApi.obtenerMensualidad(30)).resolves.toBe(item);
    await expect(mensualidadesApi.listarMensualidades()).resolves.toEqual([item]);
    await expect(mensualidadesApi.listarMensualidadesPorInscripcion(20)).resolves.toEqual([item]);
    await expect(mensualidadesApi.listarPorInscripcion(20)).resolves.toEqual([item]);
    await expect(mensualidadesApi.eliminarMensualidad(30)).resolves.toBeUndefined();
    await expect(mensualidadesApi.generarMensualidadesParaMesVigente()).resolves.toEqual([item]);

    expect(mocks.post).toHaveBeenNthCalledWith(1, "/mensualidades", request);
    expect(mocks.put).toHaveBeenCalledWith("/mensualidades/30", request);
    expect(mocks.get).toHaveBeenNthCalledWith(1, "/mensualidades/30");
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/mensualidades");
    expect(mocks.get).toHaveBeenNthCalledWith(3, "/mensualidades/inscripcion/20");
    expect(mocks.get).toHaveBeenNthCalledWith(4, "/mensualidades/inscripcion/20");
    expect(mocks.delete).toHaveBeenCalledWith("/mensualidades/30");
    expect(mocks.post).toHaveBeenNthCalledWith(2, "/mensualidades/generar-mensualidades");
  });

  it.each([
    ["crear", mocks.post, () => mensualidadesApi.crearMensualidad({ inscripcionId: 20, anio: 2026, mes: 8 })],
    ["actualizar", mocks.put, () => mensualidadesApi.actualizarMensualidad(30, { inscripcionId: 20, anio: 2026, mes: 8 })],
    ["obtener", mocks.get, () => mensualidadesApi.obtenerMensualidad(30)],
    ["listar", mocks.get, () => mensualidadesApi.listarMensualidades()],
    ["listar por inscripción", mocks.get, () => mensualidadesApi.listarMensualidadesPorInscripcion(20)],
    ["eliminar", mocks.delete, () => mensualidadesApi.eliminarMensualidad(30)],
    ["listar alias por inscripción", mocks.get, () => mensualidadesApi.listarPorInscripcion(20)],
    ["generar", mocks.post, () => mensualidadesApi.generarMensualidadesParaMesVigente()],
  ])("propaga el rechazo original al %s", async (_case, client, invoke) => {
    client.mockRejectedValueOnce(apiError);

    await expect(invoke()).rejects.toBe(apiError);
  });
});
