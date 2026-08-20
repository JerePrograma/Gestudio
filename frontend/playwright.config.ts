import { defineConfig, devices } from "@playwright/test";
import process from "node:process";

const baseURL = process.env.GESTUDIO_E2E_BASE_URL;
if (!baseURL) throw new Error("Falta GESTUDIO_E2E_BASE_URL");
const outputDir = process.env.GESTUDIO_E2E_OUTPUT_DIR ?? "./test-results/e2e";

export default defineConfig({
  testDir: "./e2e",
  testMatch: "**/*.spec.ts",
  fullyParallel: false,
  workers: 1,
  // El unico flujo es mutante. Un retry interno reutilizaria la misma DB;
  // cualquier reintento valido debe recrear el proyecto Compose completo.
  retries: 0,
  forbidOnly: Boolean(process.env.CI),
  timeout: 360_000,
  expect: { timeout: 15_000 },
  reporter: [["line"]],
  outputDir,
  preserveOutput: "never",
  use: {
    baseURL,
    trace: "off",
    video: "off",
    screenshot: "off",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
});
