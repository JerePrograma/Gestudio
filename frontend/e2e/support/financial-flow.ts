import { expect, test, type APIRequestContext, type APIResponse, type Page, type Response } from "@playwright/test";
import { e2eState } from "./e2e-state";
import { currentDateInTimeZone } from "../../src/utils/civilDate";

const object = (value: unknown): Record<string, unknown> => {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Flujo financiero: respuesta JSON sin objeto");
  }
  return value as Record<string, unknown>;
};
const records = (value: unknown): Record<string, unknown>[] => {
  if (!Array.isArray(value)) throw new Error("Flujo financiero: lista JSON ausente");
  return value.map(object);
};
const id = (value: unknown): number => {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 1) {
    throw new Error("Flujo financiero: ID persistido invalido");
  }
  return value;
};
const json = async (response: APIResponse | Response, status: number): Promise<Record<string, unknown>> => {
  if (response.status() !== status) {
    throw new Error(`Flujo financiero: HTTP ${response.status()}, esperado ${status}`);
  }
  return object(await response.json());
};
const endpoint = (response: Response, method: string, path: string): boolean =>
  response.request().method() === method && new URL(response.url()).pathname === `/api${path}`;

interface FinancialSession {
  page: Page;
  accessToken: string;
}

export async function verifyFinancialFlow(
  request: APIRequestContext,
  alpha: FinancialSession,
  betaAccessToken: string,
  alumnoId: number,
): Promise<void> {
  if (!/^gestudio-e2e-[a-f0-9]{12}$/.test(e2eState.composeProject)) {
    throw new Error("El recorrido financiero requiere un proyecto efimero aislado");
  }
  const headers = { Authorization: `Bearer ${alpha.accessToken}` };
  const betaHeaders = { Authorization: `Bearer ${betaAccessToken}` };
  const api = (path: string) => `${e2eState.apiUrl}${path}`;
  const post = async (path: string, data: object, status: number) =>
    json(await request.post(api(path), { headers, data }), status);
  const get = async (path: string) => json(await request.get(api(path), { headers }), 200);
  const today = currentDateInTimeZone("America/Argentina/Buenos_Aires");
  const page = alpha.page;
  const studentName = `Marcador Alpha E2E ${e2eState.runId}`;
  let cargos: Record<string, unknown>[] = [];
  let pago: Record<string, unknown> = {};

  await test.step("Preparar salon/profesor/tarifa/metodo sinteticos mediante APIs", async () => {
    const salon = await post("/salones", { nombre: `Sala E2E ${e2eState.runId}` }, 201);
    const profesor = await post("/profesores", { nombre: "Docente", apellido: `E2E ${e2eState.runId}` }, 200);
    const disciplina = await post("/disciplinas", {
      nombre: `Disciplina E2E ${e2eState.runId}`, salonId: id(salon.id), profesorId: id(profesor.id),
      valorCuota: "0.00", matricula: "0.00", claseSuelta: "0.00", clasePrueba: "0.00", horarios: [],
    }, 200);
    await post(`/disciplinas/${id(disciplina.id)}/tarifas`, {
      vigenteDesde: `${today.slice(0, 4)}-01-01`, valorCuota: "100.50", matricula: "20.00",
      claseSuelta: "0.00", clasePrueba: "0.00", motivo: "Aceptacion financiera sintetica E2E",
    }, 201);
    const metodo = await post("/metodos-pago", {
      descripcion: `Efectivo E2E ${e2eState.runId}`, activo: true, recargo: "0.00",
    }, 201);

    await page.goto("/inscripciones/formulario");
    await page.getByLabel("Alumno", { exact: true }).fill(`Alpha E2E ${e2eState.runId}`);
    await page.getByRole("button", { name: `Seleccionar ${studentName}`, exact: true }).click();
    await page.getByRole("combobox", { name: /^Disciplina/ }).selectOption(String(id(disciplina.id)));
    await page.getByLabel("Fecha de inscripción", { exact: true }).fill(today);
    const created = page.waitForResponse((response) => endpoint(response, "POST", "/inscripciones"));
    await page.getByRole("button", { name: "Guardar inscripción", exact: true }).click();
    const inscripcion = await json(await created, 201);
    expect(inscripcion).toMatchObject({ alumnoId, disciplinaId: disciplina.id, estado: "ACTIVA" });
    const mensualidadesResponse = await request.get(api(`/mensualidades/inscripcion/${id(inscripcion.id)}`), { headers });
    if (mensualidadesResponse.status() !== 200) throw new Error("Mensualidad de la inscripcion no disponible");
    const mensualidades = records(await mensualidadesResponse.json());
    expect(mensualidades).toHaveLength(1);
    cargos = records((await get(`/cargos/alumno/${alumnoId}/pendientes?page=0&size=50`)).content);
    expect(cargos).toHaveLength(2);
    expect(cargos.map((cargo) => ({ tipo: cargo.tipo, importe: cargo.importeOriginal, saldo: cargo.saldo, estado: cargo.estado })))
      .toEqual(expect.arrayContaining([
        { tipo: "MENSUALIDAD", importe: "100.50", saldo: "100.50", estado: "PENDIENTE" },
        { tipo: "MATRICULA", importe: "20.00", saldo: "20.00", estado: "PENDIENTE" },
      ]));
    expect(cargos.some((cargo) => cargo.id === mensualidades[0].cargoId && cargo.tipo === "MENSUALIDAD")).toBe(true);

    await page.goto("/pagos/formulario");
    await page.getByLabel("Alumno", { exact: true }).fill(`Alpha E2E ${e2eState.runId}`);
    await page.getByRole("button", { name: `Seleccionar ${studentName}`, exact: true }).click();
    await page.getByRole("combobox", { name: /^Método de pago/ }).selectOption(String(id(metodo.id)));
    await page.getByLabel("Monto recibido", { exact: true }).fill("120,50");
    for (const cargo of cargos) {
      if (typeof cargo.descripcion !== "string" || typeof cargo.saldo !== "string") {
        throw new Error("Cargo sin descripcion o importe canonico");
      }
      // The description selects a visible control; submitted relationships use the API's explicit cargo IDs.
      await page.getByLabel(`Aplicar a ${cargo.descripcion}`, { exact: true }).fill(cargo.saldo.replace(".", ","));
    }
    const registered = page.waitForResponse((response) => endpoint(response, "POST", "/pagos"));
    await page.getByRole("button", { name: "Registrar pago", exact: true }).click();
    const response = await registered;
    const submitted: unknown = response.request().postDataJSON();
    const submittedPayment = object(submitted);
    expect(submittedPayment).toMatchObject({ alumnoId, metodoPagoId: metodo.id, montoRecibido: "120.50", generarCredito: false });
    expect(submittedPayment.idempotencyKey).toEqual(expect.stringMatching(/^[a-f0-9-]{36}$/i));
    expect(records(submittedPayment.aplicaciones)).toHaveLength(2);
    expect(records(submittedPayment.aplicaciones)).toEqual(expect.arrayContaining(
      cargos.map((cargo) => ({ cargoId: cargo.id, importe: cargo.saldo })),
    ));
    pago = await json(response, 201);
  });

  await test.step("Verificar pago/cargos/caja reales y presentar el saldo en UI", async () => {
    const persisted = await get(`/pagos/${id(pago.id)}`);
    expect(persisted).toMatchObject({ alumnoId, estado: "REGISTRADO", montoRecibido: "120.50", creditoGenerado: "0.00" });
    const aplicaciones = records(persisted.aplicaciones);
    expect(aplicaciones).toHaveLength(2);
    for (const cargo of cargos) {
      expect(aplicaciones.find((item) => item.cargoId === cargo.id))
        .toMatchObject({ importeAplicado: cargo.importeOriginal, estado: "APLICADA", saldoCargo: "0.00" });
      expect(await get(`/cargos/${id(cargo.id)}`)).toMatchObject({ estado: "PAGADO", saldo: "0.00", importeOriginal: cargo.importeOriginal });
    }
    if (typeof persisted.fecha !== "string") throw new Error("Pago sin fecha de negocio");
    await page.goto("/caja");
    await page.getByLabel("Desde", { exact: true }).fill(persisted.fecha);
    await page.getByLabel("Hasta", { exact: true }).fill(persisted.fecha);
    const consulted = page.waitForResponse((response) => endpoint(response, "GET", "/caja/resumen"));
    await page.getByRole("button", { name: "Consultar", exact: true }).click();
    const caja = await json(await consulted, 200);
    expect(caja).toMatchObject({ totalIngresos: "120.50", totalEgresos: "0.00", saldo: "120.50" });
    const movimientos = records(object(caja.movimientos).content);
    expect(movimientos).toHaveLength(1);
    expect(movimientos[0]).toMatchObject({ tipo: "INGRESO_PAGO", pagoId: pago.id, importe: "120.50" });
    await expect(page.locator("article").filter({ has: page.getByText("Saldo", { exact: true }) })).toContainText("$ 120,50");
    await expect(page.getByRole("cell", { name: `Pago ${id(pago.id)}`, exact: true })).toBeVisible();
  });

  await test.step("Worker real genera PDF y navegador descarga exactamente esos bytes", async () => {
    let receipt: APIResponse | undefined;
    await expect.poll(async () => {
      receipt = await request.get(api(`/pagos/recibo/${id(pago.id)}`), { headers });
      return receipt.status();
    }, { message: "El outbox debe producir un recibo PDF real" }).toBe(200);
    if (!receipt) throw new Error("Recibo no consultado");
    const bytes = await receipt.body();
    expect(receipt.headers()["content-type"]).toContain("application/pdf");
    expect(bytes.subarray(0, 5).toString("ascii")).toBe("%PDF-");
    expect(bytes.length).toBeGreaterThan(100);
    await page.goto(`/pagos?alumnoId=${alumnoId}`);
    await page.getByRole("button", { name: /^Acciones del pago del / }).click();
    const downloaded = page.waitForEvent("download");
    await page.getByRole("menuitem", { name: "Descargar recibo", exact: true }).click();
    const download = await downloaded;
    expect(download.suggestedFilename()).toBe(`recibo_${id(pago.id)}.pdf`);
    const stream = await download.createReadStream();
    if (!stream) throw new Error("Descarga PDF sin stream");
    const chunks: Buffer[] = [];
    for await (const chunk of stream) chunks.push(Buffer.from(chunk));
    expect(Buffer.concat(chunks).equals(bytes)).toBe(true);
  });

  await test.step("Beta no accede al pago ni al PDF de Alpha y conserva caja vacia", async () => {
    for (const path of [`/pagos/${id(pago.id)}`, `/pagos/recibo/${id(pago.id)}`]) {
      const denied = await request.get(api(path), { headers: betaHeaders });
      expect(denied.status()).toBe(404);
    }
    const betaCaja = await json(await request.get(api(`/caja/resumen?desde=${pago.fecha}&hasta=${pago.fecha}`), { headers: betaHeaders }), 200);
    expect(betaCaja).toMatchObject({ totalIngresos: "0.00", totalEgresos: "0.00", saldo: "0.00" });
    expect(records(object(betaCaja.movimientos).content)).toHaveLength(0);
  });
}
