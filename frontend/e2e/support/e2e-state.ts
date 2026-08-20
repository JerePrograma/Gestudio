import process from "node:process";

interface E2eState {
  baseUrl: string;
  apiUrl: string;
  composeProject: string;
  runId: string;
  bootstrapCounter: number;
  platform: Credentials & { totpSecret: string };
  alpha: TenantIdentity;
  beta: TenantIdentity;
}

interface Credentials {
  username: string;
  password: string;
}

interface TenantIdentity extends Credentials {
  code: string;
  name: string;
}

const required = (name: string): string => {
  const value = process.env[name];
  if (!value) throw new Error(`Falta variable E2E requerida: ${name}`);
  return value;
};

const localHttpUrl = (name: string): string => {
  const raw = required(name);
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new Error(`${name} no es una URL valida`);
  }
  if (url.protocol !== "http:" || !["127.0.0.1", "localhost"].includes(url.hostname)) {
    throw new Error(`${name} debe usar HTTP sobre loopback`);
  }
  return url.toString().replace(/\/$/, "");
};

const identifier = (name: string, pattern: RegExp): string => {
  const value = required(name);
  if (!pattern.test(value)) throw new Error(`${name} tiene formato invalido`);
  return value;
};

const composeProject = identifier(
  "GESTUDIO_E2E_COMPOSE_PROJECT",
  /^gestudio-e2e-[a-f0-9]{12}$/,
);
if (composeProject === "gestudio-remote-demo" || composeProject.includes("remote-demo")) {
  throw new Error("El proyecto protegido gestudio-remote-demo esta fuera del alcance E2E");
}

const bootstrapCounter = Number(required("GESTUDIO_E2E_BOOTSTRAP_COUNTER"));
if (!Number.isSafeInteger(bootstrapCounter) || bootstrapCounter < 1) {
  throw new Error("GESTUDIO_E2E_BOOTSTRAP_COUNTER tiene formato invalido");
}

export const e2eState: E2eState = Object.freeze({
  baseUrl: localHttpUrl("GESTUDIO_E2E_BASE_URL"),
  apiUrl: localHttpUrl("GESTUDIO_E2E_API_URL"),
  composeProject,
  runId: identifier("GESTUDIO_E2E_RUN_ID", /^[a-f0-9]{12}$/),
  bootstrapCounter,
  platform: {
    username: identifier("GESTUDIO_E2E_PLATFORM_USERNAME", /^[A-Za-z0-9._@+-]{3,100}$/),
    password: required("GESTUDIO_E2E_PLATFORM_PASSWORD"),
    totpSecret: required("GESTUDIO_E2E_PLATFORM_TOTP_SECRET"),
  },
  alpha: {
    code: identifier("GESTUDIO_E2E_ALPHA_CODE", /^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$/),
    name: required("GESTUDIO_E2E_ALPHA_NAME"),
    username: identifier("GESTUDIO_E2E_ALPHA_USERNAME", /^[A-Za-z0-9._@+-]{3,100}$/),
    password: required("GESTUDIO_E2E_ALPHA_PASSWORD"),
  },
  beta: {
    code: identifier("GESTUDIO_E2E_BETA_CODE", /^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$/),
    name: required("GESTUDIO_E2E_BETA_NAME"),
    username: identifier("GESTUDIO_E2E_BETA_USERNAME", /^[A-Za-z0-9._@+-]{3,100}$/),
    password: required("GESTUDIO_E2E_BETA_PASSWORD"),
  },
});
