import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { validateFixture, validateTenantSession, validatePayment, validateCash, validatePdf, totp } from "./verify-financial-recovery.mjs";

const fixture = {
  project: "gestudio-e2e-0123456789ab", alphaId: "00000000-0000-0000-0000-000000000001",
  betaId: "00000000-0000-0000-0000-000000000002", paymentId: 7, studentId: 3,
  paymentDate: "2026-10-23", pdfSha256: "a".repeat(64),
  applications: [{ cargoId: 11, amount: "100.50" }, { cargoId: 12, amount: "20.00" }],
};
test("recovery rejects persistent projects and tenant/relationship confusion", () => {
  validateFixture(fixture, fixture.project);
  for (const project of ["gestudio-demo-local", "gestudio-remote-demo", "crm", "gestudio-e2e-0123456789ac"]) {
    assert.throws(() => validateFixture(fixture, project));
  }
  assert.throws(() => validateFixture({ ...fixture, betaId: fixture.alphaId }, fixture.project));
  assert.throws(() => validateFixture({ ...fixture, paymentId: "7" }, fixture.project));
  assert.throws(() => validateFixture({ ...fixture, applications: [fixture.applications[0], fixture.applications[0]] }, fixture.project));
});
test("restored login requires exactly its own active tenant membership", () => {
  const body = { accessToken: "a".repeat(30), usuario: { tenantActivo: { id: fixture.alphaId }, tenantsDisponibles: [{ id: fixture.alphaId }] } };
  validateTenantSession(body, fixture.alphaId);
  assert.throws(() => validateTenantSession(body, fixture.betaId));
  assert.throws(() => validateTenantSession({ ...body, usuario: { ...body.usuario, tenantsDisponibles: [{ id: fixture.alphaId }, { id: fixture.betaId }] } }, fixture.alphaId));
});
test("payment reconciliation detects swapped IDs, altered money and incomplete applications", () => {
  const payment = { id: 7, alumnoId: 3, fecha: fixture.paymentDate, estado: "REGISTRADO", montoRecibido: "120.50", creditoGenerado: "0.00", aplicaciones: fixture.applications.map((application) => ({ cargoId: application.cargoId, importeAplicado: application.amount, estado: "APLICADA", saldoCargo: "0.00" })) };
  validatePayment(payment, fixture);
  for (const delta of [{ id: 8 }, { montoRecibido: 120.5 }, { creditoGenerado: "0.01" }, { aplicaciones: payment.aplicaciones.slice(0, 1) }, { fecha: "2026-10-24" }]) {
    assert.throws(() => validatePayment({ ...payment, ...delta }, fixture));
  }
});
test("cash reconciliation requires exact movement reference and empty Beta", () => {
  const cash = { totalIngresos: "120.50", totalEgresos: "0.00", saldo: "120.50", movimientos: { content: [{ pagoId: 7, tipo: "INGRESO_PAGO", importe: "120.50" }] } };
  validateCash(cash, 7);
  assert.throws(() => validateCash(cash, 8));
  assert.throws(() => validateCash(cash, 7, true));
  validateCash({ totalIngresos: "0.00", totalEgresos: "0.00", saldo: "0.00", movimientos: { content: [] } }, 7, true);
});
test("PDF recovery requires identical bytes, signature and media type", () => {
  const pdf = Buffer.from(`%PDF-1.7\n${"synthetic".repeat(20)}`);
  const hash = createHash("sha256").update(pdf).digest("hex");
  validatePdf(pdf, "application/pdf", hash);
  assert.throws(() => validatePdf(pdf, "text/plain", hash));
  assert.throws(() => validatePdf(Buffer.concat([pdf, Buffer.from("altered")]), "application/pdf", hash));
  assert.throws(() => validatePdf(Buffer.from("pdf-test"), "application/pdf", hash));
});
test("TOTP uses RFC6238 SHA1 vector without logging real secrets", () => {
  assert.equal(totp("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", 1), "287082");
});
