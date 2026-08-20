import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  get: vi.fn(),
  post: vi.fn(),
  put: vi.fn(),
  delete: vi.fn(),
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
  toast: { error: mocks.toastError },
}));

import conceptosApi from "./conceptosApi";
import permisosApi from "./permisosApi";
import rolesApi from "./rolesApi";
import salonesApi from "./salonesApi";
import stocksApi from "./stocksApi";
import subConceptosApi from "./subConceptosApi";
import usuariosApi from "./usuariosApi";

const apiError = new Error("backend unavailable");

beforeEach(() => {
  vi.clearAllMocks();
});

describe("conceptosApi", () => {
  it("contrata CRUD y relación con subconcepto", async () => {
    const subConcepto = { id: 2, descripcion: "Indumentaria" };
    const request = { descripcion: "Vestuario", precio: "100.00", subConcepto };
    const item = { id: 4, version: 0, ...request };
    mocks.post.mockResolvedValueOnce({ data: item });
    mocks.get
      .mockResolvedValueOnce({ data: item })
      .mockResolvedValueOnce({ data: [item] })
      .mockResolvedValueOnce({ data: [item] });
    mocks.put.mockResolvedValueOnce({ data: item });
    mocks.delete.mockResolvedValueOnce({});

    await expect(conceptosApi.registrarConcepto(request)).resolves.toBe(item);
    await expect(conceptosApi.obtenerConceptoPorId(4)).resolves.toBe(item);
    await expect(conceptosApi.listarConceptos()).resolves.toEqual([item]);
    await expect(conceptosApi.actualizarConcepto(4, request)).resolves.toBe(item);
    await expect(conceptosApi.eliminarConcepto(4)).resolves.toBeUndefined();
    await expect(conceptosApi.listarConceptosPorSubConcepto("ropa interna")).resolves.toEqual([item]);

    expect(mocks.post).toHaveBeenCalledWith("/conceptos", request);
    expect(mocks.get).toHaveBeenNthCalledWith(1, "/conceptos/4");
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/conceptos");
    expect(mocks.put).toHaveBeenCalledWith("/conceptos/4", request);
    expect(mocks.delete).toHaveBeenCalledWith("/conceptos/4");
    expect(mocks.get).toHaveBeenNthCalledWith(3, "/conceptos/sub-concepto/ropa interna");
  });

  it.each([
    ["registrar", mocks.post, () => conceptosApi.registrarConcepto({ descripcion: "Vestuario", precio: "100.00", subConcepto: { id: 2, descripcion: "Ropa" } })],
    ["obtener", mocks.get, () => conceptosApi.obtenerConceptoPorId(4)],
    ["listar", mocks.get, () => conceptosApi.listarConceptos()],
    ["actualizar", mocks.put, () => conceptosApi.actualizarConcepto(4, { descripcion: "Vestuario", precio: "100.00", subConcepto: { id: 2, descripcion: "Ropa" } })],
    ["eliminar", mocks.delete, () => conceptosApi.eliminarConcepto(4)],
    ["listar por subconcepto", mocks.get, () => conceptosApi.listarConceptosPorSubConcepto("2")],
  ])("propaga el rechazo original al %s", async (_case, client, invoke) => {
    client.mockRejectedValueOnce(apiError);

    await expect(invoke()).rejects.toBe(apiError);
  });
});

describe("subConceptosApi", () => {
  it("contrata listado, detalle, alta, búsqueda, actualización y eliminación", async () => {
    const request = { descripcion: "Indumentaria" };
    const item = { id: 2, ...request };
    mocks.get
      .mockResolvedValueOnce({ data: [item] })
      .mockResolvedValueOnce({ data: item })
      .mockResolvedValueOnce({ data: [item] });
    mocks.post.mockResolvedValueOnce({ data: item });
    mocks.put.mockResolvedValueOnce({ data: item });
    mocks.delete.mockResolvedValueOnce({});

    await expect(subConceptosApi.listarSubConceptos()).resolves.toEqual([item]);
    await expect(subConceptosApi.obtenerSubConceptoPorId(2)).resolves.toBe(item);
    await expect(subConceptosApi.registrarSubConcepto(request)).resolves.toBe(item);
    await expect(subConceptosApi.buscarSubConceptos("ropa & más")).resolves.toEqual([item]);
    await expect(subConceptosApi.actualizarSubConcepto(2, request)).resolves.toBe(item);
    await expect(subConceptosApi.eliminarSubConcepto(2)).resolves.toBeUndefined();

    expect(mocks.get).toHaveBeenNthCalledWith(1, "/sub-conceptos");
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/sub-conceptos/2");
    expect(mocks.post).toHaveBeenCalledWith("/sub-conceptos", request);
    expect(mocks.get).toHaveBeenNthCalledWith(3, "/sub-conceptos/buscar?nombre=ropa%20%26%20m%C3%A1s");
    expect(mocks.put).toHaveBeenCalledWith("/sub-conceptos/2", request);
    expect(mocks.delete).toHaveBeenCalledWith("/sub-conceptos/2");
  });

  it("devuelve el primer resultado por descripción o null si está vacío", async () => {
    const item = { id: 2, descripcion: "Indumentaria" };
    mocks.get.mockResolvedValueOnce({ data: [item] }).mockResolvedValueOnce({ data: [] });

    await expect(subConceptosApi.obtenerSubConceptoPorDescripcion("ropa & más")).resolves.toBe(item);
    await expect(subConceptosApi.obtenerSubConceptoPorDescripcion("inexistente")).resolves.toBeNull();
    expect(mocks.get).toHaveBeenNthCalledWith(1, "/sub-conceptos?descripcion=ropa%20%26%20m%C3%A1s");
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/sub-conceptos?descripcion=inexistente");
  });

  it("transforma sólo el fallo por descripción en null", async () => {
    mocks.get.mockRejectedValueOnce(apiError);

    await expect(subConceptosApi.obtenerSubConceptoPorDescripcion("ropa")).resolves.toBeNull();
    expect(mocks.toastError).toHaveBeenCalledWith("Error al obtener subconcepto por descripcion:");
  });

  it.each([
    ["listar", mocks.get, () => subConceptosApi.listarSubConceptos(), "Error al listar subconceptos:"],
    ["obtener", mocks.get, () => subConceptosApi.obtenerSubConceptoPorId(2), "Error al obtener subconcepto con id 2:"],
    ["registrar", mocks.post, () => subConceptosApi.registrarSubConcepto({ descripcion: "Ropa" }), "Error al registrar subconcepto:"],
    ["buscar", mocks.get, () => subConceptosApi.buscarSubConceptos("ropa"), "Error al buscar subconceptos por nombre:"],
    ["actualizar", mocks.put, () => subConceptosApi.actualizarSubConcepto(2, { descripcion: "Ropa" }), "Error al actualizar subconcepto con id 2:"],
    ["eliminar", mocks.delete, () => subConceptosApi.eliminarSubConcepto(2), "Error al eliminar subconcepto con id 2:"],
  ])("propaga el rechazo de %s y emite su mensaje", async (_case, client, invoke, message) => {
    client.mockRejectedValueOnce(apiError);

    await expect(invoke()).rejects.toBe(apiError);
    expect(mocks.toastError).toHaveBeenCalledWith(message);
  });
});

describe("salonesApi", () => {
  it("contrata CRUD y ambos contratos de paginación", async () => {
    const create = { nombre: "Sala A", descripcion: "Principal" };
    const update = { nombre: "Sala A", descripcion: "Renovada" };
    const item = { id: 2, ...create };
    const page = { content: [item] };
    mocks.post.mockResolvedValueOnce({ data: item });
    mocks.get
      .mockResolvedValueOnce({ data: page })
      .mockResolvedValueOnce({ data: page })
      .mockResolvedValueOnce({ data: item });
    mocks.put.mockResolvedValueOnce({ data: item });
    mocks.delete.mockResolvedValueOnce({});

    await expect(salonesApi.registrarSalon(create)).resolves.toBe(item);
    await expect(salonesApi.listarSalones()).resolves.toBe(page);
    await expect(salonesApi.listarSalones(3, 25)).resolves.toBe(page);
    await expect(salonesApi.obtenerSalonPorId(2)).resolves.toBe(item);
    await expect(salonesApi.actualizarSalon(2, update)).resolves.toBe(item);
    await expect(salonesApi.eliminarSalon(2)).resolves.toBeUndefined();

    expect(mocks.post).toHaveBeenCalledWith("/salones", create);
    expect(mocks.get).toHaveBeenNthCalledWith(1, "/salones", { params: { page: 0, size: 10 } });
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/salones", { params: { page: 3, size: 25 } });
    expect(mocks.get).toHaveBeenNthCalledWith(3, "/salones/2");
    expect(mocks.put).toHaveBeenCalledWith("/salones/2", update);
    expect(mocks.delete).toHaveBeenCalledWith("/salones/2");
  });

  it.each([
    ["registrar", mocks.post, () => salonesApi.registrarSalon({ nombre: "Sala A", descripcion: "Principal" })],
    ["listar", mocks.get, () => salonesApi.listarSalones()],
    ["obtener", mocks.get, () => salonesApi.obtenerSalonPorId(2)],
    ["actualizar", mocks.put, () => salonesApi.actualizarSalon(2, { nombre: "Sala A", descripcion: "Renovada" })],
    ["eliminar", mocks.delete, () => salonesApi.eliminarSalon(2)],
  ])("propaga el rechazo original al %s", async (_case, client, invoke) => {
    client.mockRejectedValueOnce(apiError);

    await expect(invoke()).rejects.toBe(apiError);
  });
});

describe("stocksApi", () => {
  it("contrata CRUD y listados con defaults y valores explícitos", async () => {
    const create = {
      nombre: "Remera",
      precio: "100.00",
      stock: 5,
      requiereControlDeStock: true,
      idempotencyKey: "stock-key",
    };
    const update = { ...create, activo: true };
    const item = { id: 4, ...update };
    const page = { content: [item] };
    mocks.post.mockResolvedValueOnce({ data: item });
    mocks.get
      .mockResolvedValueOnce({ data: item })
      .mockResolvedValueOnce({ data: page })
      .mockResolvedValueOnce({ data: page })
      .mockResolvedValueOnce({ data: [item] });
    mocks.put.mockResolvedValueOnce({ data: item });
    mocks.delete.mockResolvedValueOnce({});

    await expect(stocksApi.registrarStock(create)).resolves.toBe(item);
    await expect(stocksApi.obtenerStockPorId(4)).resolves.toBe(item);
    await expect(stocksApi.listarStocks()).resolves.toBe(page);
    await expect(stocksApi.listarStocks(2, 15)).resolves.toBe(page);
    await expect(stocksApi.listarStocksActivos()).resolves.toEqual([item]);
    await expect(stocksApi.actualizarStock(4, update)).resolves.toBe(item);
    await expect(stocksApi.eliminarStock(4)).resolves.toBeUndefined();

    expect(mocks.post).toHaveBeenCalledWith("/stocks", create);
    expect(mocks.get).toHaveBeenNthCalledWith(1, "/stocks/4");
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/stocks", { params: { page: 0, size: 50 } });
    expect(mocks.get).toHaveBeenNthCalledWith(3, "/stocks", { params: { page: 2, size: 15 } });
    expect(mocks.get).toHaveBeenNthCalledWith(4, "/stocks/activos");
    expect(mocks.put).toHaveBeenCalledWith("/stocks/4", update);
    expect(mocks.delete).toHaveBeenCalledWith("/stocks/4");
  });

  it.each([
    ["registrar", mocks.post, () => stocksApi.registrarStock({ nombre: "Remera", precio: "100.00", stock: 5, requiereControlDeStock: true, idempotencyKey: "stock-key" })],
    ["obtener", mocks.get, () => stocksApi.obtenerStockPorId(4)],
    ["listar", mocks.get, () => stocksApi.listarStocks()],
    ["listar activos", mocks.get, () => stocksApi.listarStocksActivos()],
    ["actualizar", mocks.put, () => stocksApi.actualizarStock(4, { nombre: "Remera", precio: "100.00", stock: 5, requiereControlDeStock: true, idempotencyKey: "stock-key", activo: true })],
    ["eliminar", mocks.delete, () => stocksApi.eliminarStock(4)],
  ])("propaga el rechazo original al %s", async (_case, client, invoke) => {
    client.mockRejectedValueOnce(apiError);

    await expect(invoke()).rejects.toBe(apiError);
  });
});

describe("usuariosApi", () => {
  it("contrata roles asignables y CRUD de usuarios", async () => {
    const create = { nombreUsuario: "admin", contrasena: "Secret123!", roles: ["ADMIN"] };
    const update = { nombreUsuario: "admin", roles: ["ADMIN"], activo: true };
    const item = { id: 7, nombreUsuario: "admin" };
    const roles = [{ codigo: "ADMIN", nombre: "Administrador" }];
    mocks.get
      .mockResolvedValueOnce({ data: roles })
      .mockResolvedValueOnce({ data: item })
      .mockResolvedValueOnce({ data: [item] });
    mocks.post.mockResolvedValueOnce({ data: item });
    mocks.put.mockResolvedValueOnce({ data: item });
    mocks.delete.mockResolvedValueOnce({});

    await expect(usuariosApi.listarRolesAsignables()).resolves.toBe(roles);
    await expect(usuariosApi.registrarUsuario(create)).resolves.toBe(item);
    await expect(usuariosApi.obtenerUsuarioPorId(7)).resolves.toBe(item);
    await expect(usuariosApi.listarUsuarios()).resolves.toEqual([item]);
    await expect(usuariosApi.actualizarUsuario(7, update)).resolves.toBe(item);
    await expect(usuariosApi.eliminarUsuario(7)).resolves.toBeUndefined();

    expect(mocks.get).toHaveBeenNthCalledWith(1, "/usuarios/roles-asignables");
    expect(mocks.post).toHaveBeenCalledWith("/usuarios/registro", create);
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/usuarios/7");
    expect(mocks.get).toHaveBeenNthCalledWith(3, "/usuarios");
    expect(mocks.put).toHaveBeenCalledWith("/usuarios/7", update);
    expect(mocks.delete).toHaveBeenCalledWith("/usuarios/7");
  });

  it.each([
    ["listar roles", mocks.get, () => usuariosApi.listarRolesAsignables()],
    ["registrar", mocks.post, () => usuariosApi.registrarUsuario({ nombreUsuario: "admin", contrasena: "Secret123!", roles: ["ADMIN"] })],
    ["obtener", mocks.get, () => usuariosApi.obtenerUsuarioPorId(7)],
    ["listar", mocks.get, () => usuariosApi.listarUsuarios()],
    ["actualizar", mocks.put, () => usuariosApi.actualizarUsuario(7, { nombreUsuario: "admin", roles: ["ADMIN"], activo: true })],
    ["eliminar", mocks.delete, () => usuariosApi.eliminarUsuario(7)],
  ])("propaga el rechazo original al %s", async (_case, client, invoke) => {
    client.mockRejectedValueOnce(apiError);

    await expect(invoke()).rejects.toBe(apiError);
  });
});

describe("rolesApi y permisosApi", () => {
  it("contrata CRUD y asignación de permisos de rol", async () => {
    const create = { codigo: "COBRADOR", nombre: "Cobrador", permisos: ["PAGOS_LEER"] };
    const update = { nombre: "Cobrador", activo: true, permisos: ["PAGOS_LEER"] };
    const item = { id: 3, codigo: "COBRADOR" };
    mocks.get.mockResolvedValueOnce({ data: [item] }).mockResolvedValueOnce({ data: item });
    mocks.post.mockResolvedValueOnce({ data: item });
    mocks.put.mockResolvedValueOnce({ data: item }).mockResolvedValueOnce({ data: item });
    mocks.delete.mockResolvedValueOnce({});

    await expect(rolesApi.listar()).resolves.toEqual([item]);
    await expect(rolesApi.obtener(3)).resolves.toBe(item);
    await expect(rolesApi.crear(create)).resolves.toBe(item);
    await expect(rolesApi.modificar(3, update)).resolves.toBe(item);
    await expect(rolesApi.desactivar(3)).resolves.toBeUndefined();
    await expect(rolesApi.asignarPermisos(3, ["PAGOS_LEER", "PAGOS_REGISTRAR"])).resolves.toBe(item);

    expect(mocks.get).toHaveBeenNthCalledWith(1, "/roles");
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/roles/3");
    expect(mocks.post).toHaveBeenCalledWith("/roles", create);
    expect(mocks.put).toHaveBeenNthCalledWith(1, "/roles/3", update);
    expect(mocks.delete).toHaveBeenCalledWith("/roles/3");
    expect(mocks.put).toHaveBeenNthCalledWith(2, "/roles/3/permisos", {
      permisos: ["PAGOS_LEER", "PAGOS_REGISTRAR"],
    });
  });

  it("lista permisos con y sin filtro opcional", async () => {
    const data = [{ id: 1, codigo: "PAGOS_LEER" }];
    mocks.get.mockResolvedValue({ data });

    await expect(permisosApi.listar()).resolves.toBe(data);
    await expect(permisosApi.listar("PAGOS")).resolves.toBe(data);
    expect(mocks.get).toHaveBeenNthCalledWith(1, "/permisos", { params: undefined });
    expect(mocks.get).toHaveBeenNthCalledWith(2, "/permisos", { params: { modulo: "PAGOS" } });
  });

  it.each([
    ["listar roles", mocks.get, () => rolesApi.listar()],
    ["obtener rol", mocks.get, () => rolesApi.obtener(3)],
    ["crear rol", mocks.post, () => rolesApi.crear({ codigo: "COBRADOR", nombre: "Cobrador", permisos: [] })],
    ["modificar rol", mocks.put, () => rolesApi.modificar(3, { nombre: "Cobrador", activo: true, permisos: [] })],
    ["desactivar rol", mocks.delete, () => rolesApi.desactivar(3)],
    ["asignar permisos", mocks.put, () => rolesApi.asignarPermisos(3, ["PAGOS_LEER"])],
    ["listar permisos", mocks.get, () => permisosApi.listar()],
  ])("propaga el rechazo original al %s", async (_case, client, invoke) => {
    client.mockRejectedValueOnce(apiError);

    await expect(invoke()).rejects.toBe(apiError);
  });
});
