import { describe, expect, it } from "vitest";
import { currentDateInTimeZone, formatLocalDate } from "./civilDate";

const BUENOS_AIRES = "America/Argentina/Buenos_Aires";

describe("fechas civiles", () => {
  it("mantiene el día de Buenos Aires cuando UTC cambia a medianoche", () => {
    expect(currentDateInTimeZone(BUENOS_AIRES, new Date("2026-07-20T23:59:00Z"))).toBe("2026-07-20");
    expect(currentDateInTimeZone(BUENOS_AIRES, new Date("2026-07-21T00:00:00Z"))).toBe("2026-07-20");
  });

  it("mantiene el año de Buenos Aires durante el cambio de año UTC", () => {
    expect(currentDateInTimeZone(BUENOS_AIRES, new Date("2027-01-01T00:00:00Z"))).toBe("2026-12-31");
  });

  it("preserva la fecha civil elegida localmente antes y después de las 21", () => {
    expect(formatLocalDate(new Date(2026, 6, 20, 20, 59))).toBe("2026-07-20");
    expect(formatLocalDate(new Date(2026, 6, 20, 21, 0))).toBe("2026-07-20");
    expect(formatLocalDate(new Date(2026, 11, 31, 21, 0))).toBe("2026-12-31");
  });
});
