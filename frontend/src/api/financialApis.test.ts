import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  get: vi.fn(),
  post: vi.fn(),
  put: vi.fn(),
  delete: vi.fn(),
}));

vi.mock("./axiosConfig", () => ({
  default: {
    get: mocks.get,
    post: mocks.post,
    put: mocks.put,
    delete: mocks.delete,
  },
}));

import bonificacionesApi from "./bonificacionesApi";
import cajaApi from "./cajaApi";
import cargosApi from "./cargosApi";
import condicionesEconomicasApi from "./condicionesEconomicasApi";
import egresosApi from "./egresosApi";
import metodosPagoApi from "./metodosPagoApi";
import pagosApi from "./pagosApi";
import recargosApi from "./recargosApi";
import tarifasApi from "./tarifasApi";

const apiError = new Error("backend unavailable");

beforeEach(() => {
  vi.clearAllMocks();
});

describe("cajaApi y cargosApi", () => {
  it("contrata resumen de caja con defaults y paginación explícita", async () => {
    const data = { ingresos: "100.00", egresos: "20.00" };
    mocks.get.mockResolvedValue({ data });

    await expect(cajaApi.obtenerResumen("2026-08-01", "2026-08-31")).resolves.toBe(data);
    await expect(cajaApi.obtenerResumen("2026-08-01", "2026-08-31", 2, 25)).resolves.toBe(data);

    expect(mocks.get).toHaveBeenNthCalledWith(1, "/caja/resumen", {
      params: { desde: "2026-08-01", hasta: "2026-08-31", page: 0, size: 50 },
    });
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/caja/resumen", {
      params: { desde: "2026-08-01", hasta: "2026-08-31", page: 2, size: 25 },
    });
  });

  it("contrata cargos pendientes y detalle", async () => {
    const page = { content: [{ id: 9 }] };
    const item = { id: 9 };
    mocks.get.mockResolvedValueOnce({ data: page }).mockResolvedValueOnce({ data: page }).mockResolvedValueOnce({ data: item });

    await expect(cargosApi.listarPendientes(1)).resolves.toBe(page);
    await expect(cargosApi.listarPendientes(1, 3, 10)).resolves.toBe(page);
    await expect(cargosApi.obtener(9)).resolves.toBe(item);

    expect(mocks.get).toHaveBeenNthCalledWith(1, "/cargos/alumno/1/pendientes", { params: { page: 0, size: 50 } });
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/cargos/alumno/1/pendientes", { params: { page: 3, size: 10 } });
    expect(mocks.get).toHaveBeenNthCalledWith(3, "/cargos/9");
  });

  it("propaga rechazos", async () => {
    mocks.get.mockRejectedValueOnce(apiError);

    await expect(cajaApi.obtenerResumen("2026-08-01", "2026-08-31")).rejects.toBe(apiError);
  });

  it.each([
    ["listar pendientes", () => cargosApi.listarPendientes(1)],
    ["obtener cargo", () => cargosApi.obtener(9)],
  ])("propaga el rechazo de cargos al %s", async (_case, invoke) => {
    mocks.get.mockRejectedValueOnce(apiError);

    await expect(invoke()).rejects.toBe(apiError);
  });
});

describe("pagosApi", () => {
  const request = {
    alumnoId: 1,
    metodoPagoId: 2,
    montoRecibido: "100.00",
    idempotencyKey: "payment-key",
    aplicaciones: [{ cargoId: 9, importe: "100.00" }],
    generarCredito: false,
  };

  it("contrata registrar, obtener, listar y anular", async () => {
    const payment = { id: 50 };
    const page = { content: [payment] };
    const cancellation = { idempotencyKey: "cancel-key", motivo: "error" };
    mocks.post.mockResolvedValueOnce({ data: payment }).mockResolvedValueOnce({ data: payment });
    mocks.get
      .mockResolvedValueOnce({ data: payment })
      .mockResolvedValueOnce({ data: page })
      .mockResolvedValueOnce({ data: page });

    await expect(pagosApi.registrarPago(request)).resolves.toBe(payment);
    await expect(pagosApi.obtenerPagoPorId(50)).resolves.toBe(payment);
    await expect(pagosApi.listarPagosPorAlumno(1)).resolves.toBe(page);
    await expect(pagosApi.listarPagosPorAlumno(1, 2, 15)).resolves.toBe(page);
    await expect(pagosApi.anularPago(50, cancellation)).resolves.toBe(payment);

    expect(mocks.post).toHaveBeenNthCalledWith(1, "/pagos", request);
    expect(mocks.get).toHaveBeenNthCalledWith(1, "/pagos/50");
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/pagos/alumno/1", { params: { page: 0, size: 50 } });
    expect(mocks.get).toHaveBeenNthCalledWith(3, "/pagos/alumno/1", { params: { page: 2, size: 15 } });
    expect(mocks.post).toHaveBeenNthCalledWith(2, "/pagos/50/anulacion", cancellation);
  });

  it("descarga y libera un recibo Blob", async () => {
    const blob = new Blob(["pdf"], { type: "application/pdf" });
    const createObjectURL = vi.fn(() => "blob:receipt");
    const revokeObjectURL = vi.fn();
    Object.defineProperty(URL, "createObjectURL", { configurable: true, value: createObjectURL });
    Object.defineProperty(URL, "revokeObjectURL", { configurable: true, value: revokeObjectURL });
    const linkClick = vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => undefined);
    mocks.get.mockResolvedValueOnce({ data: blob });

    await expect(pagosApi.descargarRecibo(50)).resolves.toBeUndefined();

    expect(mocks.get).toHaveBeenCalledWith("/pagos/recibo/50", { responseType: "blob" });
    expect(createObjectURL).toHaveBeenCalledWith(blob);
    expect(linkClick).toHaveBeenCalledTimes(1);
    expect(revokeObjectURL).toHaveBeenCalledWith("blob:receipt");
  });

  it.each([
    ["registrar", mocks.post, () => pagosApi.registrarPago(request)],
    ["obtener", mocks.get, () => pagosApi.obtenerPagoPorId(50)],
    ["listar", mocks.get, () => pagosApi.listarPagosPorAlumno(1)],
    ["anular", mocks.post, () => pagosApi.anularPago(50, { idempotencyKey: "cancel-key", motivo: "error" })],
    ["descargar recibo", mocks.get, () => pagosApi.descargarRecibo(50)],
  ])("propaga el rechazo original al %s", async (_case, client, invoke) => {
    client.mockRejectedValueOnce(apiError);

    await expect(invoke()).rejects.toBe(apiError);
  });
});

describe("egresosApi", () => {
  it("contrata alta, listado y anulación con UUID nuevo", async () => {
    vi.stubGlobal("crypto", { randomUUID: vi.fn(() => "expense-cancel-key") });
    const request = { monto: "20.00", metodoPagoId: 2, idempotencyKey: "expense-key" };
    const item = { id: 60 };
    const page = { content: [item] };
    mocks.post.mockResolvedValueOnce({ data: item }).mockResolvedValueOnce({ data: item });
    mocks.get.mockResolvedValueOnce({ data: page }).mockResolvedValueOnce({ data: page });

    await expect(egresosApi.registrarEgreso(request)).resolves.toBe(item);
    await expect(egresosApi.listarEgresos()).resolves.toBe(page);
    await expect(egresosApi.listarEgresos(2, 15)).resolves.toBe(page);
    await expect(egresosApi.anularEgreso(60, "duplicado")).resolves.toBe(item);

    expect(mocks.post).toHaveBeenNthCalledWith(1, "/egresos", request);
    expect(mocks.get).toHaveBeenNthCalledWith(1, "/egresos", { params: { page: 0, size: 50 } });
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/egresos", { params: { page: 2, size: 15 } });
    expect(mocks.post).toHaveBeenNthCalledWith(2, "/egresos/60/anulacion", {
      motivo: "duplicado",
      idempotencyKey: "expense-cancel-key",
    });
  });

  it.each([
    ["registrar", mocks.post, () => egresosApi.registrarEgreso({ monto: "20.00", metodoPagoId: 2, idempotencyKey: "expense-key" })],
    ["listar", mocks.get, () => egresosApi.listarEgresos()],
    ["anular", mocks.post, () => egresosApi.anularEgreso(60, "duplicado")],
  ])("propaga el rechazo original al %s", async (_case, client, invoke) => {
    client.mockRejectedValueOnce(apiError);

    await expect(invoke()).rejects.toBe(apiError);
  });
});

describe("bonificacionesApi", () => {
  it("contrata CRUD completo", async () => {
    const create = { descripcion: "Beca", porcentajeDescuento: "10.00" };
    const update = { descripcion: "Beca", porcentajeDescuento: "15.00", activo: true };
    const item = { id: 4, descripcion: "Beca" };
    mocks.post.mockResolvedValueOnce({ data: item });
    mocks.get.mockResolvedValueOnce({ data: [item] }).mockResolvedValueOnce({ data: item });
    mocks.put.mockResolvedValueOnce({ data: item });
    mocks.delete.mockResolvedValueOnce({});

    await expect(bonificacionesApi.crearBonificacion(create)).resolves.toBe(item);
    await expect(bonificacionesApi.listarBonificaciones()).resolves.toEqual([item]);
    await expect(bonificacionesApi.obtenerBonificacionPorId(4)).resolves.toBe(item);
    await expect(bonificacionesApi.actualizarBonificacion(4, update)).resolves.toBe(item);
    await expect(bonificacionesApi.eliminarBonificacion(4)).resolves.toBeUndefined();

    expect(mocks.post).toHaveBeenCalledWith("/bonificaciones", create);
    expect(mocks.get).toHaveBeenNthCalledWith(1, "/bonificaciones");
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/bonificaciones/4");
    expect(mocks.put).toHaveBeenCalledWith("/bonificaciones/4", update);
    expect(mocks.delete).toHaveBeenCalledWith("/bonificaciones/4");
  });

  it.each([
    ["crear", mocks.post, () => bonificacionesApi.crearBonificacion({ descripcion: "Beca" })],
    ["listar", mocks.get, () => bonificacionesApi.listarBonificaciones()],
    ["obtener", mocks.get, () => bonificacionesApi.obtenerBonificacionPorId(4)],
    ["actualizar", mocks.put, () => bonificacionesApi.actualizarBonificacion(4, { descripcion: "Beca", activo: true })],
    ["eliminar", mocks.delete, () => bonificacionesApi.eliminarBonificacion(4)],
  ])("propaga el rechazo original al %s", async (_case, client, invoke) => {
    client.mockRejectedValueOnce(apiError);

    await expect(invoke()).rejects.toBe(apiError);
  });
});

describe("recargosApi", () => {
  it("contrata CRUD completo", async () => {
    const create = { descripcion: "Mora", porcentaje: "5.00", diaDelMesAplicacion: 10 };
    const update = { porcentaje: "7.00" };
    const item = { id: 4, descripcion: "Mora" };
    mocks.post.mockResolvedValueOnce({ data: item });
    mocks.get.mockResolvedValueOnce({ data: [item] }).mockResolvedValueOnce({ data: item });
    mocks.put.mockResolvedValueOnce({ data: item });
    mocks.delete.mockResolvedValueOnce({});

    await expect(recargosApi.crearRecargo(create)).resolves.toBe(item);
    await expect(recargosApi.listarRecargos()).resolves.toEqual([item]);
    await expect(recargosApi.obtenerRecargoPorId(4)).resolves.toBe(item);
    await expect(recargosApi.actualizarRecargo(4, update)).resolves.toBe(item);
    await expect(recargosApi.eliminarRecargo(4)).resolves.toBeUndefined();

    expect(mocks.post).toHaveBeenCalledWith("/recargos", create);
    expect(mocks.get).toHaveBeenNthCalledWith(1, "/recargos");
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/recargos/4");
    expect(mocks.put).toHaveBeenCalledWith("/recargos/4", update);
    expect(mocks.delete).toHaveBeenCalledWith("/recargos/4");
  });

  it.each([
    ["crear", mocks.post, () => recargosApi.crearRecargo({ descripcion: "Mora", porcentaje: "5.00", diaDelMesAplicacion: 10 })],
    ["listar", mocks.get, () => recargosApi.listarRecargos()],
    ["obtener", mocks.get, () => recargosApi.obtenerRecargoPorId(4)],
    ["actualizar", mocks.put, () => recargosApi.actualizarRecargo(4, { porcentaje: "7.00" })],
    ["eliminar", mocks.delete, () => recargosApi.eliminarRecargo(4)],
  ])("propaga el rechazo original al %s", async (_case, client, invoke) => {
    client.mockRejectedValueOnce(apiError);

    await expect(invoke()).rejects.toBe(apiError);
  });
});

describe("condicionesEconomicasApi y tarifasApi", () => {
  it("contrata listado y creación de condición económica", async () => {
    const request = {
      vigenteDesde: "2026-08-13",
      costoParticular: "100.00",
      bonificacionId: null,
      motivo: "Alta",
    };
    const item = { id: 1 };
    mocks.get.mockResolvedValueOnce({ data: [item] });
    mocks.post.mockResolvedValueOnce({ data: item });

    await expect(condicionesEconomicasApi.listar(20)).resolves.toEqual([item]);
    await expect(condicionesEconomicasApi.crear(20, request)).resolves.toBe(item);
    expect(mocks.get).toHaveBeenCalledWith("/inscripciones/20/condiciones-economicas");
    expect(mocks.post).toHaveBeenCalledWith("/inscripciones/20/condiciones-economicas", request);
  });

  it("contrata listado y creación de tarifa", async () => {
    const request = {
      vigenteDesde: "2026-08-13",
      valorCuota: "100.00",
      matricula: "50.00",
      claseSuelta: "20.00",
      clasePrueba: "0.00",
      motivo: "Actualización",
    };
    const item = { id: 2 };
    mocks.get.mockResolvedValueOnce({ data: [item] });
    mocks.post.mockResolvedValueOnce({ data: item });

    await expect(tarifasApi.listar(7)).resolves.toEqual([item]);
    await expect(tarifasApi.crear(7, request)).resolves.toBe(item);
    expect(mocks.get).toHaveBeenCalledWith("/disciplinas/7/tarifas");
    expect(mocks.post).toHaveBeenCalledWith("/disciplinas/7/tarifas", request);
  });

  it.each([
    ["listar condiciones", mocks.get, () => condicionesEconomicasApi.listar(20)],
    ["crear condición", mocks.post, () => condicionesEconomicasApi.crear(20, { vigenteDesde: "2026-08-13", costoParticular: null, bonificacionId: null, motivo: "Alta" })],
    ["listar tarifas", mocks.get, () => tarifasApi.listar(7)],
    ["crear tarifa", mocks.post, () => tarifasApi.crear(7, { vigenteDesde: "2026-08-13", valorCuota: "100.00", matricula: "50.00", claseSuelta: "20.00", clasePrueba: "0.00", motivo: "Alta" })],
  ])("propaga el rechazo original al %s", async (_case, client, invoke) => {
    client.mockRejectedValueOnce(apiError);

    await expect(invoke()).rejects.toBe(apiError);
  });
});

describe("metodosPagoApi", () => {
  it("contrata CRUD completo", async () => {
    const create = { descripcion: "Efectivo", recargo: "0.00" };
    const update = { ...create, activo: true };
    const item = { id: 2, ...update };
    mocks.post.mockResolvedValueOnce({ data: item });
    mocks.get.mockResolvedValueOnce({ data: item }).mockResolvedValueOnce({ data: [item] });
    mocks.put.mockResolvedValueOnce({ data: item });
    mocks.delete.mockResolvedValueOnce({});

    await expect(metodosPagoApi.registrarMetodoPago(create)).resolves.toBe(item);
    await expect(metodosPagoApi.obtenerMetodoPagoPorId(2)).resolves.toBe(item);
    await expect(metodosPagoApi.listarMetodosPago()).resolves.toEqual([item]);
    await expect(metodosPagoApi.actualizarMetodoPago(2, update)).resolves.toBe(item);
    await expect(metodosPagoApi.eliminarMetodoPago(2)).resolves.toBeUndefined();

    expect(mocks.post).toHaveBeenCalledWith("/metodos-pago", create);
    expect(mocks.get).toHaveBeenNthCalledWith(1, "/metodos-pago/2");
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/metodos-pago");
    expect(mocks.put).toHaveBeenCalledWith("/metodos-pago/2", update);
    expect(mocks.delete).toHaveBeenCalledWith("/metodos-pago/2");
  });

  it.each([
    ["registrar", mocks.post, () => metodosPagoApi.registrarMetodoPago({ descripcion: "Efectivo", recargo: "0.00" })],
    ["obtener", mocks.get, () => metodosPagoApi.obtenerMetodoPagoPorId(2)],
    ["listar", mocks.get, () => metodosPagoApi.listarMetodosPago()],
    ["actualizar", mocks.put, () => metodosPagoApi.actualizarMetodoPago(2, { descripcion: "Efectivo", recargo: "0.00", activo: true })],
    ["eliminar", mocks.delete, () => metodosPagoApi.eliminarMetodoPago(2)],
  ])("propaga el rechazo original al %s", async (_case, client, invoke) => {
    client.mockRejectedValueOnce(apiError);

    await expect(invoke()).rejects.toBe(apiError);
  });
});
