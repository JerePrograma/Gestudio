import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type {
  AlumnoResponse,
  CargoResponse,
  MetodoPagoResponse,
  Page,
  PagoResponse,
} from "../../types/types";

const buscarPorNombre = vi.hoisted(() => vi.fn());
const listarPendientes = vi.hoisted(() => vi.fn());
const listarMetodosPago = vi.hoisted(() => vi.fn());
const registrarPago = vi.hoisted(() => vi.fn());
const toastSuccess = vi.hoisted(() => vi.fn());
const toastError = vi.hoisted(() => vi.fn());

vi.mock("../../api/alumnosApi", () => ({
  default: { buscarPorNombre },
}));

vi.mock("../../api/cargosApi", () => ({
  default: { listarPendientes },
}));

vi.mock("../../api/metodosPagoApi", () => ({
  default: { listarMetodosPago },
}));

vi.mock("../../api/pagosApi", () => ({
  default: { registrarPago },
}));

vi.mock("react-toastify", () => ({
  toast: {
    success: toastSuccess,
    error: toastError,
  },
}));

import PagosFormulario from "./PagosFormulario";

describe("PagosFormulario", () => {
  beforeEach(() => {
    vi.clearAllMocks();

    vi.stubGlobal("crypto", {
      randomUUID: () => "payment-key",
    });

    buscarPorNombre.mockResolvedValue(pagina([alumno(7)], 1, 1, 0, 8));
    listarPendientes.mockResolvedValue(pagina([cargo(10)], 1, 1, 0));
    listarMetodosPago.mockResolvedValue([metodoPago(2)]);
    registrarPago.mockResolvedValue(pagoRegistrado(99));
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
      expect(listarPendientes).toHaveBeenCalledWith(7, 0, 50);
    });

    expect(screen.getAllByText("Ana Prueba").length).toBeGreaterThan(0);
    expect(await screen.findByText("Cuota julio")).toBeVisible();
  });

  it("registra el pago manteniendo alumnoId interno y normalizando importes para el backend", async () => {
    renderPage();

    fireEvent.change(screen.getByLabelText("Alumno"), {
      target: { value: "Ana" },
    });

    fireEvent.click(await screen.findByRole("button", { name: "Seleccionar Ana Prueba" }));

    await screen.findByText("Cuota julio");

    fireEvent.change(screen.getByLabelText("Método de pago"), {
      target: { value: "2" },
    });

    fireEvent.change(screen.getByLabelText("Monto recibido"), {
      target: { value: "100,50" },
    });

    fireEvent.change(screen.getByLabelText("Aplicar a Cuota julio"), {
      target: { value: "100,50" },
    });

    fireEvent.click(screen.getByRole("button", { name: "Registrar pago" }));

    await waitFor(() => {
      expect(registrarPago).toHaveBeenCalledWith({
        alumnoId: 7,
        metodoPagoId: 2,
        montoRecibido: "100.50",
        idempotencyKey: "payment-key",
        aplicaciones: [{ cargoId: 10, importe: "100.50" }],
        generarCredito: false,
      });
    });

    expect(toastSuccess).toHaveBeenCalledWith("Pago 99 registrado");
  });
});

function renderPage() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });

  render(
    <QueryClientProvider client={queryClient}>
      <PagosFormulario />
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

function cargo(id: number): CargoResponse {
  return {
    id,
    alumnoId: 7,
    tipo: "MENSUALIDAD",
    descripcion: "Cuota julio",
    importeOriginal: "100.50",
    importeAplicado: "0.00",
    saldo: "100.50",
    fechaEmision: "2026-07-01",
    fechaVencimiento: "2026-07-10",
    estado: "PENDIENTE",
  };
}

function metodoPago(id: number): MetodoPagoResponse {
  return {
    id,
    descripcion: "Efectivo",
    activo: true,
    recargo: "0.00",
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