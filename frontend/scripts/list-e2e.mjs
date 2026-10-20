import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import process from "node:process";
import { fileURLToPath } from "node:url";

const randomHex = () => randomBytes(24).toString("hex");
const base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
const randomBase32 = () =>
  Array.from(randomBytes(32), (value) => base32Alphabet[value % base32Alphabet.length]).join("");

const discoveryEnvironment = {
  GESTUDIO_E2E_BASE_URL: "http://127.0.0.1:18081",
  GESTUDIO_E2E_API_URL: "http://127.0.0.1:18080/api",
  GESTUDIO_E2E_COMPOSE_PROJECT: "gestudio-e2e-000000000000",
  GESTUDIO_E2E_RUN_ID: "000000000000",
  GESTUDIO_E2E_BOOTSTRAP_COUNTER: "1",
  GESTUDIO_E2E_PLATFORM_USERNAME: "static.e2e.platform",
  GESTUDIO_E2E_PLATFORM_PASSWORD: randomHex(),
  GESTUDIO_E2E_PLATFORM_TOTP_SECRET: randomBase32(),
  GESTUDIO_E2E_ALPHA_CODE: "static-alpha-e2e",
  GESTUDIO_E2E_ALPHA_NAME: "Escuela Danza Marcos Paz",
  GESTUDIO_E2E_ALPHA_USERNAME: "static.alpha.admin",
  GESTUDIO_E2E_ALPHA_PASSWORD: randomHex(),
  GESTUDIO_E2E_BETA_CODE: "static-beta-e2e",
  GESTUDIO_E2E_BETA_NAME: "Escuela Beta Demo",
  GESTUDIO_E2E_BETA_USERNAME: "static.beta.admin",
  GESTUDIO_E2E_BETA_PASSWORD: randomHex(),
};

const playwrightCli = fileURLToPath(new URL("../node_modules/playwright/cli.js", import.meta.url));
const result = spawnSync(process.execPath, [playwrightCli, "test", "--list"], {
  cwd: process.cwd(),
  env: { ...process.env, ...discoveryEnvironment },
  stdio: "inherit",
});

if (result.error) throw result.error;
process.exit(result.status ?? 1);
