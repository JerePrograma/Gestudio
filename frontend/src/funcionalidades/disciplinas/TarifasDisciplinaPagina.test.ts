import { describe, expect, it } from "vitest";
import { canUseTariffEffectiveDate, currentDateInTimeZone } from "./tariffEffectiveDate";

describe("vigencia histórica de tarifas", () => {
  it("rechaza una fecha pasada sin permiso histórico", () => {
    expect(canUseTariffEffectiveDate("2026-07-13", "2026-07-14", false)).toBe(false);
  });

  it("admite hoy o futuro y reserva el pasado al permiso histórico", () => {
    expect(canUseTariffEffectiveDate("2026-07-14", "2026-07-14", false)).toBe(true);
    expect(canUseTariffEffectiveDate("2026-07-15", "2026-07-14", false)).toBe(true);
    expect(canUseTariffEffectiveDate("2026-07-13", "2026-07-14", true)).toBe(true);
  });

  it("calcula hoy en la zona horaria configurada", () => {
    const nearMidnightUtc = new Date("2026-07-15T01:00:00Z");

    expect(currentDateInTimeZone("America/Argentina/Buenos_Aires", nearMidnightUtc)).toBe("2026-07-14");
  });
});
