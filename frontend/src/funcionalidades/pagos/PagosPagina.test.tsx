import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
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

import PagosPagina from "./PagosPagina";

describe("PagosPagina", () => {
  beforeEach(() => {
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
    expect(await screen.findByText("$ 100.50")).toBeVisible();
    expect(screen.getByText("REGISTRADO")).toBeVisible();
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
    expect(await screen.findByText("$ 100.50")).toBeVisible();
  });
});

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

function alumno(id: number): AlumnoResponse {
  return {
    id,
    nombre: "Ana",
    apellido: "Prueba",
    fechaNacimiento: "2010-01-01",
    fechaIncorporacion: "2026-01-01",
    edad: 16,
    celular1: "2235550000",
    celular2: "",
    email: "",
    documento: "12345678",
    fechaDeBaja: null,
    nombrePadres: "",
    autorizadoParaSalirSolo: false,
    activo: true,
    otrasNotas: "",
    inscripciones: [],
  };
}

function pagoResumen(id: number): PagoResumenResponse {
  return {
    id,
    fecha: "2026-07-09",
    montoRecibido: "100.50",
    estado: "REGISTRADO",
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