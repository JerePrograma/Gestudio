import { defineConfig } from "vitest/config";
import baseConfig from "./vite.config";

const encodedFiles = process.env.DIFF_COVERAGE_FILES;
if (!encodedFiles) {
  throw new Error("DIFF_COVERAGE_FILES es obligatorio para medir diff coverage");
}

const changedFiles: unknown = JSON.parse(encodedFiles);
if (
  !Array.isArray(changedFiles) ||
  changedFiles.length === 0 ||
  changedFiles.some(
    (file) =>
      typeof file !== "string" ||
      !/^src\/.+\.(ts|tsx)$/.test(file) ||
      /\.(test|spec)\.(ts|tsx)$/.test(file),
  )
) {
  throw new Error("DIFF_COVERAGE_FILES no contiene fuentes TypeScript válidas");
}

export default defineConfig({
  ...baseConfig,
  test: {
    ...baseConfig.test,
    coverage: {
      ...baseConfig.test?.coverage,
      // El script calcula el diff, incluyendo fuentes untracked. Ejecutamos toda
      // la suite y limitamos la instrumentación exactamente a esas fuentes.
      include: changedFiles,
      exclude: ["src/**/*.d.ts", "src/test/**"],
      reportsDirectory: "coverage/diff",
      // Este reporte conserva los mapas Istanbul de cada fuente modificada.
      // El orquestador aplica el umbral contractual sólo a ejecutables que
      // intersectan hunks añadidos, no al archivo completo.
      reporter: ["text", "json", "json-summary", "lcov", "html"],
      thresholds: undefined,
    },
  },
});
