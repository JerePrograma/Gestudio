import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type {
  AlumnoResponse,
  Page,
  PagoResponse,
  PagoResumenResponse,
} from "../../types/types";

const buscarPorNombre = vi.hoisted(() => vi.fn());
const obtenerPorId = vi.hoisted(() => vi.fn());
const listarPagosPorAlumno = vi.hoisted(() => vi.fn());
const anularPago = vi.hoisted(() => vi.fn());
const descargarRecibo = vi.hoisted(() => vi.fn());
const toastSuccess = vi.hoisted(() => vi.fn());
const toastError = vi.hoisted(() => vi.fn());
const hasPermission = vi.hoisted(() => vi.fn(() => true));

vi.mock("../../api/alumnosApi", () => ({
  default: { buscarPorNombre, obtenerPorId },
}));

vi.mock("../../api/pagosApi", () => ({
  default: { listarPagosPorAlumno, anularPago, descargarRecibo },
}));

vi.mock("react-toastify", () => ({
  toast: {
    success: toastSuccess,
    error: toastError,
  },
}));

vi.mock("../../hooks/context/useAuth", () => ({
  useAuth: () => ({ hasPermission }),
}));

import PagosPagina from "./PagosPagina";

describe("PagosPagina", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    vi.clearAllMocks();

    vi.stubGlobal("crypto", {
      randomUUID: () => "anulacion-key",
    });

    buscarPorNombre.mockResolvedValue(pagina([alumno(7)], 1, 1, 0, 8));
    obtenerPorId.mockResolvedValue(alumno(7));
    listarPagosPorAlumno.mockResolvedValue(pagina([pagoResumen(99)], 1, 1, 0));
    anularPago.mockResolvedValue(pagoRegistrado(99));
    descargarRecibo.mockResolvedValue(undefined);
  });

  it("permite buscar y seleccionar un alumno sin ingresar ID interno", async () => {
    renderPage();

    expect(screen.queryByText("Alumno ID")).not.toBeInTheDocument();

    fireEvent.change(screen.getByLabelText("Alumno"), {
      target: { value: "Ana" },
    });

    await waitFor(() => {
      expect(buscarPorNombre).toHaveBeenCalledWith("Ana", 0, 8);
    });

    fireEvent.click(await screen.findByRole("button", { name: "Seleccionar Ana Prueba" }));

    await waitFor(() => {
      expect(listarPagosPorAlumno).toHaveBeenCalledWith(7, 0, 50);
    });

    expect(screen.getAllByText("Ana Prueba").length).toBeGreaterThan(0);
    expect(await screen.findByRole("cell", { name: "$ 100,50" })).toBeVisible();
    expect(screen.getByText("REGISTRADO")).toBeVisible();
    expect(screen.queryByRole("columnheader", { name: "ID" })).not.toBeInTheDocument();
    expect(screen.queryByRole("cell", { name: "99" })).not.toBeInTheDocument();
    expect(screen.getByRole("button", {
      name: "Acciones del pago del 2026-07-09 por $ 100,50",
    })).toBeVisible();
  });

  it("resuelve el alumno del enlace interno y conserva la consulta por ID hacia backend", async () => {
    renderPage("/pagos?alumnoId=7");

    await waitFor(() => {
      expect(obtenerPorId).toHaveBeenCalledWith(7);
    });

    await waitFor(() => {
      expect(listarPagosPorAlumno).toHaveBeenCalledWith(7, 0, 50);
    });

    expect(await screen.findByText("Ana Prueba")).toBeVisible();
    expect(await screen.findByRole("cell", { name: "$ 100,50" })).toBeVisible();
  });

  it("rechaza consulta sin selección y representa búsqueda corta, vacía y fallida con retry", async () => {
    buscarPorNombre
      .mockResolvedValueOnce(pagina([], 0, 0, 0, 8))
      .mockRejectedValueOnce(new Error("network"))
      .mockResolvedValueOnce(pagina([alumno(8, false, false)], 1, 1, 0, 8));
    renderPage();

    expect(screen.getByText("Seleccioná un alumno")).toBeVisible();
    fireEvent.change(screen.getByLabelText("Alumno"), { target: { value: "A" } });
    expect(screen.getByText("Escribí al menos 2 caracteres para buscar.")).toBeVisible();

    fireEvent.change(screen.getByLabelText("Alumno"), { target: { value: "Nadie" } });
    expect(await screen.findByText("Sin resultados")).toBeVisible();
    fireEvent.change(screen.getByLabelText("Alumno"), { target: { value: "Error" } });
    expect(await screen.findByRole("alert")).toHaveTextContent("No se pudieron buscar alumnos.");
    fireEvent.click(screen.getByRole("button", { name: "Reintentar" }));
    expect(await screen.findByRole("button", { name: "Seleccionar Alumno 8" })).toBeDisabled();

    fireEvent.submit(screen.getByRole("button", { name: "Consultar pagos" }).closest("form")!);
    expect(toastError).toHaveBeenCalledWith("Seleccioná un alumno de la lista para consultar sus pagos.");
  });

  it("limpia la selección y pagina resultados del alumno", async () => {
    listarPagosPorAlumno.mockImplementation((_id: number, page: number) => Promise.resolve(
      pagina(page === 0 ? [pagoResumen(99)] : [pagoResumen(100, "ANULADO")], 2, 2, page),
    ));
    renderPage();
    fireEvent.change(screen.getByLabelText("Alumno"), { target: { value: "Ana" } });
    fireEvent.click(await screen.findByRole("button", { name: "Seleccionar Ana Prueba" }));
    expect(await screen.findByRole("cell", { name: "$ 100,50" })).toBeVisible();

    fireEvent.click(screen.getByRole("button", { name: "Siguiente" }));
    await waitFor(() => expect(listarPagosPorAlumno).toHaveBeenCalledWith(7, 1, 50));
    expect(await screen.findByText("ANULADO")).toBeVisible();

    fireEvent.click(screen.getByRole("button", { name: "Cambiar" }));
    expect(screen.getByLabelText("Alumno")).toHaveValue("");
    expect(screen.getByText("Seleccioná un alumno")).toBeVisible();
  });

  it("descarga recibo y reporta un fallo de descarga sin alterar el pago", async () => {
    renderPage();
    await selectDefaultAlumno();

    await openActions();
    fireEvent.click(await screen.findByRole("menuitem", { name: "Descargar recibo" }));
    await waitFor(() => expect(descargarRecibo).toHaveBeenCalledWith(99));

    descargarRecibo.mockRejectedValueOnce(new Error("download"));
    await openActions();
    fireEvent.click(await screen.findByRole("menuitem", { name: "Descargar recibo" }));
    await waitFor(() => expect(toastError).toHaveBeenCalledWith("No se pudo descargar el recibo."));
  });

  it("anula con motivo normalizado, invalida la consulta y respeta cancelación", async () => {
    vi.spyOn(window, "prompt").mockReturnValueOnce("  carga duplicada  ").mockReturnValueOnce(null);
    const queryClient = renderPage();
    const invalidate = vi.spyOn(queryClient, "invalidateQueries");
    await selectDefaultAlumno();

    await openActions();
    fireEvent.click(await screen.findByRole("menuitem", { name: "Anular pago" }));
    await waitFor(() => expect(anularPago).toHaveBeenCalledWith(99, {
      motivo: "carga duplicada",
      idempotencyKey: "anulacion-key",
    }));
    expect(invalidate).toHaveBeenCalledWith({ queryKey: ["pagos", 7] });
    expect(toastSuccess).toHaveBeenCalledWith("Pago anulado.");

    await openActions();
    fireEvent.click(await screen.findByRole("menuitem", { name: "Anular pago" }));
    expect(anularPago).toHaveBeenCalledTimes(1);
  });

  it("oculta anulación sin permiso y reporta rechazo de backend", async () => {
    hasPermission.mockReturnValue(false);
    const deniedClient = renderPage();
    await selectDefaultAlumno();
    await openActions();
    expect(screen.queryByRole("menuitem", { name: "Anular pago" })).not.toBeInTheDocument();
    expect(screen.getByRole("menuitem", { name: "Descargar recibo" })).toBeVisible();
    deniedClient.clear();
    cleanup();

    hasPermission.mockReturnValue(true);
    anularPago.mockRejectedValueOnce(new Error("conflict"));
    vi.spyOn(window, "prompt").mockReturnValue("reversión");
    renderPage();
    await selectDefaultAlumno();
    await openActions();
    fireEvent.click(await screen.findByRole("menuitem", { name: "Anular pago" }));
    await waitFor(() => expect(toastError).toHaveBeenCalledWith("No fue posible anular el pago."));
  });

  it("representa alumno del enlace fallido y estados loading/error/empty de pagos", async () => {
    obtenerPorId.mockRejectedValueOnce(new Error("missing"));
    listarPagosPorAlumno.mockResolvedValueOnce(pagina([], 0, 0, 0));
    const first = renderPage("/pagos?alumnoId=7");
    expect(await screen.findByText("No se pudo cargar el nombre del alumno del enlace.")).toBeVisible();
    expect(await screen.findByText("El alumno no tiene pagos registrados.")).toBeVisible();
    first.clear();
    cleanup();

    let reject!: (reason: unknown) => void;
    listarPagosPorAlumno.mockReturnValueOnce(new Promise((_resolve, fail) => { reject = fail; }));
    renderPage("/pagos?alumnoId=7");
    expect(screen.getByText("Cargando pagos...")).toBeVisible();
    reject(new Error("network"));
    expect(await screen.findByRole("alert")).toHaveTextContent("No se pudieron cargar los pagos.");
  });
});

async function selectDefaultAlumno() {
  fireEvent.change(screen.getByLabelText("Alumno"), { target: { value: "Ana" } });
  fireEvent.click(await screen.findByRole("button", { name: "Seleccionar Ana Prueba" }));
  await screen.findByRole("cell", { name: "$ 100,50" });
}

async function openActions() {
  fireEvent.pointerDown((await screen.findAllByRole("button", {
    name: "Acciones del pago del 2026-07-09 por $ 100,50",
  }))[0]);
}

function renderPage(initialEntry = "/pagos") {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });

  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[initialEntry]}>
        <PagosPagina />
      </MemoryRouter>
    </QueryClientProvider>,
  );

  return queryClient;
}

function pagina<T>(
  content: T[],
  totalElements: number,
  totalPages: number,
  number: number,
  size = 50,
): Page<T> {
  return {
    content,
    totalElements,
    totalPages,
    size,
    number,
    first: number === 0,
    last: number + 1 >= totalPages,
  };
}

function alumno(id: number, activo = true, contacto = true): AlumnoResponse {
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

function pagoResumen(id: number, estado = "REGISTRADO"): PagoResumenResponse {
  return {
    id,
    fecha: "2026-07-09",
    montoRecibido: "100.50",
    estado,
  };
}

function pagoRegistrado(id: number): PagoResponse {
  return {
    id,
    alumnoId: 7,
    metodoPagoId: 2,
    usuarioId: 1,
    fecha: "2026-07-09",
    montoRecibido: "100.50",
    estado: "REGISTRADO",
    idempotencyKey: "payment-key",
    creditoGenerado: "0.00",
    aplicaciones: [],
  };
}
