import { describe, expect, it } from "vitest";

const productModules = import.meta.glob(
  [
    "../**/*.{ts,tsx}",
    "!../**/*.{test,spec}.{ts,tsx}",
    "!../test/**",
    "!../main.tsx",
    "!../**/*.d.ts",
  ],
  { eager: true },
);

describe("inventario de cobertura productiva", () => {
  it("importa cada módulo productivo incluido por el gate", () => {
    const paths = Object.keys(productModules).sort();

    expect(paths.length).toBeGreaterThan(0);
    expect(paths).toContain("../platform/pages/PlatformAdminsPage.tsx");
    expect(paths).toContain("../platform/pages/TenantDetailPage.tsx");
    expect(paths).toContain("../rutas/routes.ts");
    expect(paths).toContain("../types/types.ts");
    expect(paths.some((path) => /\.(test|spec)\.(ts|tsx)$/.test(path))).toBe(false);
    expect(paths.some((path) => path.startsWith("../test/"))).toBe(false);
    expect(paths).not.toContain("../main.tsx");
  });
});
