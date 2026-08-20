import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
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

  it("rechaza localmente datos incompletos sin inventar una operación financiera", async () => {
    renderPage();

    const submit = screen.getByRole("button", { name: "Registrar pago" });
    await waitFor(() => expect(submit).toBeEnabled());
    fireEvent.submit(submit.closest("form")!);

    await waitFor(() => expect(toastError).toHaveBeenCalledWith("Completá alumno, método e importe con hasta dos decimales"));
    expect(registrarPago).not.toHaveBeenCalled();
  });

  it("representa búsqueda corta, vacía, fallida con retry e inhabilita alumnos dados de baja", async () => {
    buscarPorNombre
      .mockResolvedValueOnce(pagina([], 0, 0, 0, 8))
      .mockRejectedValueOnce(new Error("network"))
      .mockResolvedValueOnce(pagina([alumno(8, false, false)], 1, 1, 0, 8));
    renderPage();

    fireEvent.change(screen.getByLabelText("Alumno"), { target: { value: "A" } });
    expect(screen.getByText("Escribí al menos 2 caracteres para buscar.")).toBeVisible();
    expect(buscarPorNombre).not.toHaveBeenCalled();

    fireEvent.change(screen.getByLabelText("Alumno"), { target: { value: "Nadie" } });
    expect(await screen.findByText("Sin resultados")).toBeVisible();

    fireEvent.change(screen.getByLabelText("Alumno"), { target: { value: "Error" } });
    expect(await screen.findByRole("alert")).toHaveTextContent("No se pudieron buscar alumnos.");
    fireEvent.click(screen.getByRole("button", { name: "Reintentar" }));
    expect(await screen.findByRole("button", { name: "Seleccionar Alumno 8" })).toBeDisabled();
  });

  it("calcula centavos sin punto flotante, advierte excedente y envía crédito explícito", async () => {
    renderPage();
    fireEvent.change(screen.getByLabelText("Alumno"), { target: { value: "Ana" } });
    fireEvent.click(await screen.findByRole("button", { name: "Seleccionar Ana Prueba" }));
    await screen.findByText("Cuota julio");

    fireEvent.change(screen.getByLabelText("Método de pago"), { target: { value: "2" } });
    fireEvent.change(screen.getByLabelText("Monto recibido"), { target: { value: "150,00" } });
    fireEvent.blur(screen.getByLabelText("Monto recibido"));
    fireEvent.change(screen.getByLabelText("Aplicar a Cuota julio"), { target: { value: "100,00" } });
    fireEvent.blur(screen.getByLabelText("Aplicar a Cuota julio"));

    expect(screen.getByText("$ 50,00")).toBeVisible();
    expect(screen.getByText(/Hay un excedente sin marcar como crédito/)).toBeVisible();
    fireEvent.click(screen.getByRole("checkbox", { name: /Generar crédito con el excedente/ }));
    expect(screen.queryByText(/Hay un excedente sin marcar como crédito/)).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Registrar pago" }));
    await waitFor(() => expect(registrarPago).toHaveBeenCalledWith(expect.objectContaining({
      montoRecibido: "150.00",
      aplicaciones: [{ cargoId: 10, importe: "100.00" }],
      generarCredito: true,
    })));
  });

  it("expone sobreaplicación y descarta aplicaciones vacías o inválidas del payload", async () => {
    listarPendientes.mockResolvedValue(pagina([cargo(10), { ...cargo(11), descripcion: "Matrícula" }], 2, 1, 0));
    renderPage();
    fireEvent.change(screen.getByLabelText("Alumno"), { target: { value: "Ana" } });
    fireEvent.click(await screen.findByRole("button", { name: "Seleccionar Ana Prueba" }));
    await screen.findByText("Matrícula");

    fireEvent.change(screen.getByLabelText("Método de pago"), { target: { value: "2" } });
    fireEvent.change(screen.getByLabelText("Monto recibido"), { target: { value: "100" } });
    fireEvent.change(screen.getByLabelText("Aplicar a Cuota julio"), { target: { value: "150" } });
    fireEvent.blur(screen.getByLabelText("Aplicar a Cuota julio"));
    fireEvent.change(screen.getByLabelText("Aplicar a Matrícula"), { target: { value: "invalido" } });

    expect(screen.getByText("Aplicado de más $ 50,00")).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Registrar pago" }));
    await waitFor(() => expect(registrarPago).toHaveBeenCalledWith(expect.objectContaining({
      aplicaciones: [{ cargoId: 10, importe: "150.00" }],
    })));
  });

  it("cubre errores de métodos/cargos, paginación, limpieza y rechazo backend", async () => {
    listarMetodosPago.mockRejectedValueOnce(new Error("methods"));
    listarPendientes.mockImplementation((_id: number, page: number) => Promise.resolve(
      pagina(page === 0 ? [cargo(10)] : [], 1, 2, page),
    ));
    registrarPago.mockRejectedValueOnce(new Error("conflict"));
    const firstClient = renderPage();

    expect(await screen.findByText("No se pudieron cargar los métodos de pago.")).toBeVisible();
    fireEvent.change(screen.getByLabelText("Alumno"), { target: { value: "Ana" } });
    fireEvent.click(await screen.findByRole("button", { name: "Seleccionar Ana Prueba" }));
    await screen.findByText("Cuota julio");
    fireEvent.click(screen.getByRole("button", { name: "Siguiente" }));
    await waitFor(() => expect(listarPendientes).toHaveBeenCalledWith(7, 1, 50));
    expect(await screen.findByText("Sin cargos pendientes")).toBeVisible();

    fireEvent.click(screen.getByRole("button", { name: "Cambiar" }));
    expect(screen.getByLabelText("Alumno")).toHaveValue("");
    expect(screen.getByText("Seleccioná un alumno")).toBeVisible();

    firstClient.clear();
    cleanup();
    renderPage();
    fireEvent.change(screen.getByLabelText("Alumno"), { target: { value: "Ana" } });
    fireEvent.click(await screen.findByRole("button", { name: "Seleccionar Ana Prueba" }));
    fireEvent.change(screen.getByLabelText("Método de pago"), { target: { value: "2" } });
    fireEvent.change(screen.getByLabelText("Monto recibido"), { target: { value: "100" } });
    fireEvent.click(screen.getByRole("button", { name: "Registrar pago" }));

    await waitFor(() => expect(toastError).toHaveBeenCalledWith("El backend rechazó el pago; revisá saldos y aplicaciones"));
    expect(screen.getByRole("button", { name: "Registrar pago" })).toBeEnabled();
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
