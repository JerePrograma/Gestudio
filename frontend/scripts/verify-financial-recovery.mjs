import assert from "node:assert/strict";
import { createHash, createHmac } from "node:crypto";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
let acceptancePhase = "preflight";
const required = (name) => {
  const value = process.env[name];
  if (!value) throw new Error(`Missing recovery input: ${name}`);
  return value;
};

export function validateFixture(fixture, project) {
  assert.match(project, /^gestudio-e2e-[a-f0-9]{12}$/);
  assert.equal(fixture.project, project);
  assert.match(fixture.alphaId, /^[a-f0-9-]{36}$/);
  assert.match(fixture.betaId, /^[a-f0-9-]{36}$/);
  assert.notEqual(fixture.alphaId, fixture.betaId);
  assert.ok(Number.isSafeInteger(fixture.paymentId) && fixture.paymentId > 0);
  assert.ok(Number.isSafeInteger(fixture.studentId) && fixture.studentId > 0);
  assert.match(fixture.pdfSha256, /^[a-f0-9]{64}$/);
  assert.match(fixture.paymentDate, /^\d{4}-\d{2}-\d{2}$/);
  assert.equal(fixture.applications.length, 2);
  assert.deepEqual(fixture.applications.map((item) => item.amount).sort(), ["100.50", "20.00"]);
  assert.equal(new Set(fixture.applications.map((item) => item.cargoId)).size, 2);
  for (const application of fixture.applications) {
    assert.ok(Number.isSafeInteger(application.cargoId) && application.cargoId > 0);
  }
}

export function validateTenantSession(body, tenantId) {
  assert.equal(typeof body.accessToken, "string");
  assert.ok(body.accessToken.length > 20);
  assert.equal(body.usuario.tenantActivo.id, tenantId);
  assert.deepEqual(body.usuario.tenantsDisponibles.map((tenant) => tenant.id), [tenantId]);
}

export function validatePayment(payment, fixture) {
  assert.equal(payment.id, fixture.paymentId);
  assert.equal(payment.alumnoId, fixture.studentId);
  assert.equal(payment.fecha, fixture.paymentDate);
  assert.equal(payment.estado, "REGISTRADO");
  assert.equal(payment.montoRecibido, "120.50");
  assert.equal(payment.creditoGenerado, "0.00");
  assert.equal(payment.aplicaciones.length, 2);
  for (const application of fixture.applications) {
    const actual = payment.aplicaciones.find((item) => item.cargoId === application.cargoId);
    assert.ok(actual);
    assert.equal(actual.importeAplicado, application.amount);
    assert.equal(actual.estado, "APLICADA");
    assert.equal(actual.saldoCargo, "0.00");
  }
}

export function validateCash(cash, paymentId, empty = false) {
  assert.equal(cash.totalIngresos, empty ? "0.00" : "120.50");
  assert.equal(cash.totalEgresos, "0.00");
  assert.equal(cash.saldo, empty ? "0.00" : "120.50");
  assert.equal(cash.movimientos.content.length, empty ? 0 : 1);
  if (!empty) {
    const movement = cash.movimientos.content[0];
    assert.equal(movement.pagoId, paymentId);
    assert.equal(movement.importe, "120.50");
    assert.equal(movement.tipo, "INGRESO_PAGO");
  }
}

export function validatePdf(bytes, contentType, expectedSha256) {
  assert.match(contentType, /^application\/pdf(?:;|$)/);
  assert.ok(bytes.length > 100);
  assert.equal(bytes.subarray(0, 5).toString("ascii"), "%PDF-");
  assert.equal(sha256(bytes), expectedSha256);
}

export function totp(secret, counter) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = "";
  for (const character of secret) {
    const index = alphabet.indexOf(character);
    assert.ok(index >= 0);
    bits += index.toString(2).padStart(5, "0");
  }
  const key = Buffer.from(bits.match(/.{8}/g).map((byte) => parseInt(byte, 2)));
  const value = Buffer.alloc(8);
  value.writeBigUInt64BE(BigInt(counter));
  const digest = createHmac("sha1", key).update(value).digest();
  const offset = digest[digest.length - 1] & 15;
  return ((digest.readUInt32BE(offset) & 0x7fffffff) % 1_000_000).toString().padStart(6, "0");
}

export async function verifyFinancialRecovery() {
  const fixture = JSON.parse(await readFile(required("GESTUDIO_RECOVERY_FIXTURE"), "utf8"));
  validateFixture(fixture, required("GESTUDIO_E2E_COMPOSE_PROJECT"));
  const api = new URL(required("GESTUDIO_E2E_API_URL"));
  assert.equal(api.protocol, "http:");
  assert.ok(["127.0.0.1", "localhost"].includes(api.hostname));
  assert.equal(api.pathname, "/api");
  const origin = new URL(required("GESTUDIO_E2E_BASE_URL")).origin;
  assert.ok(["127.0.0.1", "localhost"].includes(new URL(origin).hostname));

  const call = async (path, status, token, data) => {
    const response = await fetch(`${api}${path}`, {
      method: data ? "POST" : "GET",
      headers: { Origin: origin, ...(data ? { "Content-Type": "application/json" } : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      ...(data ? { body: JSON.stringify(data) } : {}),
      redirect: "error",
      signal: AbortSignal.timeout(15_000),
    });
    // Never include credentials, response bodies, tokens or assertions' values in logs.
    if (response.status !== status) throw new Error(`Recovery HTTP contract failed: ${path} (${response.status})`);
    return response;
  };
  const tenantLogin = async (prefix, tenantId) => {
    const response = await call("/login", 200, null, {
      nombreUsuario: required(`GESTUDIO_E2E_${prefix}_USERNAME`),
      contrasena: required(`GESTUDIO_E2E_${prefix}_PASSWORD`),
      tenantId,
    });
    const body = await response.json();
    validateTenantSession(body, tenantId);
    return body.accessToken;
  };
  acceptancePhase = "tenant login and memberships";
  const alpha = await tenantLogin("ALPHA", fixture.alphaId);
  const beta = await tenantLogin("BETA", fixture.betaId);
  await call("/platform/me", 403, alpha);
  await call("/platform/me", 403, beta);
  await call(`/pagos/${fixture.paymentId}`, 401);
  acceptancePhase = "payment, applications and paid charges";
  const payment = await (await call(`/pagos/${fixture.paymentId}`, 200, alpha)).json();
  validatePayment(payment, fixture);
  for (const application of fixture.applications) {
    const cargo = await (await call(`/cargos/${application.cargoId}`, 200, alpha)).json();
    assert.equal(cargo.estado, "PAGADO");
    assert.equal(cargo.saldo, "0.00");
    assert.equal(cargo.importeOriginal, application.amount);
    await call(`/cargos/${application.cargoId}`, 404, beta);
  }
  const cashPath = `/caja/resumen?desde=${fixture.paymentDate}&hasta=${fixture.paymentDate}`;
  acceptancePhase = "cash and identical PDF";
  validateCash(await (await call(cashPath, 200, alpha)).json(), fixture.paymentId);
  const pdf = await call(`/pagos/recibo/${fixture.paymentId}`, 200, alpha);
  validatePdf(Buffer.from(await pdf.arrayBuffer()), pdf.headers.get("content-type"), fixture.pdfSha256);
  // Beta checks follow Alpha200: privacy cannot pass merely because a file is missing.
  acceptancePhase = "Beta isolation";
  await call(`/pagos/${fixture.paymentId}`, 404, beta);
  const deniedPdf = await call(`/pagos/recibo/${fixture.paymentId}`, 404, beta);
  assert.equal((await deniedPdf.arrayBuffer()).byteLength, 0);
  validateCash(await (await call(cashPath, 200, beta)).json(), fixture.paymentId, true);

  acceptancePhase = "platform TOTP anti-replay and scope";
  const previousCounter = Number(required("GESTUDIO_RECOVERY_MIN_COUNTER"));
  assert.ok(Number.isSafeInteger(previousCounter) && previousCounter > 0);
  const deadline = Date.now() + 65_000;
  while (Math.floor(Date.now() / 30_000) <= previousCounter) {
    if (Date.now() > deadline) throw new Error("No fresh TOTP counter within recovery acceptance window");
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  const platform = await (await call("/platform/auth/login", 200, null, {
    nombreUsuario: required("GESTUDIO_E2E_PLATFORM_USERNAME"),
    contrasena: required("GESTUDIO_E2E_PLATFORM_PASSWORD"),
    metodo: "TOTP",
    codigo: totp(required("GESTUDIO_E2E_PLATFORM_TOTP_SECRET"), Math.floor(Date.now() / 30_000)),
  })).json();
  assert.equal(platform.profile.scope, "PLATFORM");
  assert.equal(platform.profile.mfaEnabled, true);
  assert.deepEqual(platform.profile.authorities, ["PLATFORM_SUPERADMIN"]);
  const profile = await (await call("/platform/me", 200, platform.accessToken)).json();
  assert.equal(profile.scope, "PLATFORM");
  await call(`/pagos/${fixture.paymentId}`, 403, platform.accessToken);
  console.log("PASS: recovery login Alpha/Beta, financial contracts, identical PDF, tenant denial, platform MFA decrypt and scope");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  verifyFinancialRecovery().catch((error) => {
    const httpContract = error instanceof Error && error.message.startsWith("Recovery HTTP contract failed:")
      ? `; ${error.message}` : "";
    console.error(`FAIL: financial recovery acceptance in ${acceptancePhase}${httpContract} (sensitive details suppressed)`);
    process.exitCode = 1;
  });
}
