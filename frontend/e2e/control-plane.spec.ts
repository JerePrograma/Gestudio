import AxeBuilder from "@axe-core/playwright";
import {
  expect,
  test,
  type APIRequestContext,
  type APIResponse,
  type Browser,
  type BrowserContext,
  type Page,
  type Response,
} from "@playwright/test";
import { e2eState } from "./support/e2e-state";
import { TotpSequence } from "./support/totp";

interface ProvisionedTenant {
  id: string;
  code: string;
  name: string;
  activationToken: string;
}

interface TenantSession {
  context: BrowserContext;
  page: Page;
  accessToken: string;
}

type SensitiveAuditValues = Set<string>;

const endpoint = (response: Response, method: string, path: string): boolean =>
  response.request().method() === method && new URL(response.url()).pathname === `/api${path}`;

const requireObject = async (
  response: Response | APIResponse,
  purpose: string,
): Promise<Record<string, unknown>> => {
  let value: unknown;
  try {
    value = await response.json();
  } catch {
    throw new Error(`${purpose}: respuesta JSON invalida`);
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${purpose}: contrato de respuesta invalido`);
  }
  return value as Record<string, unknown>;
};

const requireString = (
  object: Record<string, unknown>,
  field: string,
  purpose: string,
): string => {
  const value = object[field];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${purpose}: falta ${field}`);
  }
  return value;
};

const isStepUpVerification = (response: Response): boolean =>
  response.request().method() === "POST" &&
  /^\/api\/platform\/auth\/step-up\/challenges\/[^/]+\/verify$/.test(
    new URL(response.url()).pathname,
  );

const bearer = (accessToken: string): Record<string, string> => ({
  Authorization: `Bearer ${accessToken}`,
});

const assertStatus = (
  actual: number,
  expected: number,
  purpose: string,
): void => {
  if (actual !== expected) throw new Error(`${purpose}: HTTP ${actual}, esperado ${expected}`);
};

const assertAxeWcagAAndAa = async (page: Page, scope: string): Promise<void> => {
  const result = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  const summary = result.violations.map(({ id, impact, nodes }) => ({
    id,
    impact,
    nodes: nodes.length,
  }));
  expect(summary, `${scope}: violaciones WCAG A/AA sin exclusiones`).toEqual([]);
};

const sensitiveAuditKeyPattern =
  /(authorization|cookie|credential|password|proof|recovery|secret|token|totp|api.?key)/i;
const bearerValuePattern = /\bbearer\s+\S+/i;
const jwtValuePattern = /\beyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/;
const recoveryValuePattern = /\b[A-Z2-7]{8}(?:-[A-Z2-7]{8}){2}-[A-Z2-7]{2}\b/;
const otpValuePattern = /\b(?:otp|totp)[=:\s-]+[0-9]{6,8}\b/i;
const otpauthValuePattern = /\botpauth:\/\/totp\//i;

const rememberSensitiveValue = (
  sensitiveValues: SensitiveAuditValues,
  value: string,
): string => {
  if (value.length > 0) sensitiveValues.add(value);
  return value;
};

const rememberSessionCookies = async (
  context: BrowserContext,
  sensitiveValues: SensitiveAuditValues,
): Promise<void> => {
  for (const cookie of await context.cookies()) {
    if (cookie.name.startsWith("gestudio_e2e_") && cookie.value.length > 0) {
      sensitiveValues.add(cookie.value);
    }
  }
};

const rememberStepUpProof = async (
  response: Response,
  sensitiveValues: SensitiveAuditValues,
): Promise<void> => {
  assertStatus(response.status(), 200, "Verificacion step-up");
  const body = await requireObject(response, "Verificacion step-up");
  rememberSensitiveValue(
    sensitiveValues,
    requireString(body, "stepUpToken", "Verificacion step-up"),
  );
};

const containsSensitiveAuditMaterial = (
  value: unknown,
  sensitiveValues: SensitiveAuditValues,
): boolean => {
  if (typeof value === "string") {
    if (
      bearerValuePattern.test(value) ||
      jwtValuePattern.test(value) ||
      recoveryValuePattern.test(value) ||
      otpValuePattern.test(value) ||
      otpauthValuePattern.test(value)
    ) {
      return true;
    }
    for (const secret of sensitiveValues) {
      if (secret.length >= 12 ? value.includes(secret) : value === secret) return true;
    }
    return false;
  }
  if (typeof value === "number" || typeof value === "bigint") {
    return sensitiveValues.has(String(value));
  }
  if (Array.isArray(value)) {
    return value.some((nested) => containsSensitiveAuditMaterial(nested, sensitiveValues));
  }
  if (!value || typeof value !== "object") return false;
  return Object.entries(value).some(
    ([key, nested]) =>
      sensitiveAuditKeyPattern.test(key) ||
      containsSensitiveAuditMaterial(nested, sensitiveValues),
  );
};

const assertSensitiveAuditScannerContract = (
  sensitiveValues: SensitiveAuditValues,
): void => {
  const knownSecret = sensitiveValues.values().next().value;
  if (typeof knownSecret !== "string" || knownSecret.length === 0) {
    throw new Error("El scanner de auditoria no recibio secretos conocidos");
  }
  const expectedSensitive: unknown[] = [
    { metadata: { value: knownSecret } },
    JSON.stringify({ metadata: { value: knownSecret } }),
    { metadata: { authorization: "redacted" } },
    "Bearer synthetic.audit.value",
    "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.synthetic_signature",
    "ABCDEFGH-JKLMNOPQ-RSTUVWXY-Z2",
    "TOTP: 123456",
    "otpauth://totp/Gestudio",
  ];
  if (
    expectedSensitive.some(
      (candidate) => !containsSensitiveAuditMaterial(candidate, sensitiveValues),
    )
  ) {
    throw new Error("El scanner de auditoria no detecta todas las formas sensibles requeridas");
  }
  if (containsSensitiveAuditMaterial({ metadata: { result: "ACTIVE" } }, sensitiveValues)) {
    throw new Error("El scanner de auditoria rechazo metadata no sensible");
  }
};

const platformLogin = async (
  page: Page,
  totp: TotpSequence,
  sensitiveValues: SensitiveAuditValues,
): Promise<string> => {
  await page.goto("/platform/login");
  await expect(page.getByRole("heading", { name: "Iniciar sesión en plataforma" })).toBeVisible();
  await assertAxeWcagAAndAa(page, "Login de plataforma sin datos ingresados");

  const code = rememberSensitiveValue(sensitiveValues, await totp.next());
  await page.getByLabel("Nombre de usuario").fill(e2eState.platform.username);
  await page.getByLabel("Contraseña").fill(e2eState.platform.password);
  await page.getByLabel("Código TOTP").fill(code);
  const responsePromise = page.waitForResponse((response) =>
    endpoint(response, "POST", "/platform/auth/login"));
  await page.getByRole("button", { name: "Acceder al control plane" }).click();
  const response = await responsePromise;
  assertStatus(response.status(), 200, "Login de plataforma");
  const body = await requireObject(response, "Login de plataforma");
  const accessToken = rememberSensitiveValue(
    sensitiveValues,
    requireString(body, "accessToken", "Login de plataforma"),
  );
  await rememberSessionCookies(page.context(), sensitiveValues);
  await expect(page.getByRole("heading", { name: "Organizaciones" })).toBeVisible();
  return accessToken;
};

const createTenant = async (
  page: Page,
  totp: TotpSequence,
  tenant: typeof e2eState.alpha,
  sensitiveValues: SensitiveAuditValues,
): Promise<ProvisionedTenant> => {
  await page.goto("/platform/tenants/new");
  await page.getByLabel("Código").fill(tenant.code);
  await page.getByLabel("Nombre", { exact: true }).fill(tenant.name);
  await page.getByLabel("Nombre de usuario").fill(tenant.username);
  await page.getByRole("button", { name: "Revisar y crear" }).click();
  const confirmation = page.getByRole("dialog", { name: "Crear organización" });
  await expect(confirmation).toBeVisible();
  await confirmation.getByRole("button", { name: "Crear organización" }).click();

  const stepUp = page.getByRole("dialog", { name: "Confirmá esta acción sensible" });
  await expect(stepUp).toBeVisible();
  const code = rememberSensitiveValue(sensitiveValues, await totp.next());
  await stepUp.getByLabel("Código TOTP").fill(code);
  const proofPromise = page.waitForResponse(isStepUpVerification);
  const createdPromise = page.waitForResponse((response) =>
    endpoint(response, "POST", "/platform/tenants") && response.status() === 201);
  await stepUp.getByRole("button", { name: "Verificar y continuar" }).click();
  await rememberStepUpProof(await proofPromise, sensitiveValues);
  const response = await createdPromise;
  const body = await requireObject(response, "Alta de tenant");
  const rawTenant = body.tenant;
  const rawMembership = body.initialAdmin;
  const rawActivation = body.activation;
  if (!rawTenant || typeof rawTenant !== "object" || Array.isArray(rawTenant)) {
    throw new Error("Alta de tenant: tenant ausente");
  }
  if (!rawMembership || typeof rawMembership !== "object" || Array.isArray(rawMembership)) {
    throw new Error("Alta de tenant: membership inicial ausente");
  }
  if (!rawActivation || typeof rawActivation !== "object" || Array.isArray(rawActivation)) {
    throw new Error("Alta de tenant: activacion inicial ausente");
  }
  const tenantBody = rawTenant as Record<string, unknown>;
  const membershipBody = rawMembership as Record<string, unknown>;
  const activationBody = rawActivation as Record<string, unknown>;
  if (
    tenantBody.code !== tenant.code ||
    tenantBody.name !== tenant.name ||
    tenantBody.status !== "ACTIVE"
  ) {
    throw new Error("Alta de tenant: identidad o estado inesperado");
  }
  if (
    membershipBody.nombreUsuario !== tenant.username ||
    membershipBody.status !== "ACTIVE" ||
    !Array.isArray(membershipBody.roles) ||
    !membershipBody.roles.includes("ADMINISTRADOR")
  ) {
    throw new Error("Alta de tenant: administrador o rol inicial inesperado");
  }
  const result = {
    id: requireString(tenantBody, "id", "Alta de tenant"),
    code: tenant.code,
    name: tenant.name,
    activationToken: rememberSensitiveValue(
      sensitiveValues,
      requireString(activationBody, "token", "Alta de tenant"),
    ),
  };
  await expect(page.getByRole("heading", { name: "Organización creada" })).toBeVisible();
  await page.goto("/platform/tenants");
  await expect(page.getByRole("heading", { name: "Organizaciones" })).toBeVisible();
  return result;
};

const activateTenantIdentity = async (
  browser: Browser,
  activationToken: string,
  password: string,
): Promise<void> => {
  const context = await browser.newContext({ baseURL: e2eState.baseUrl });
  const page = await context.newPage();
  try {
    const activationUrl = `${e2eState.baseUrl}/platform/activate#token=${encodeURIComponent(activationToken)}`;
    try {
      await page.goto(activationUrl);
      await page.waitForURL(
        (url) =>
          url.pathname === "/platform/activate" && url.search === "" && url.hash === "",
      );
    } catch {
      throw new Error("No se pudo abrir y sanear el enlace de activacion");
    }
    await page.getByRole("radio", { name: "Activar identidad tenant" }).click();
    await page.getByLabel("Contraseña nueva", { exact: true }).fill(password);
    await page.getByLabel("Confirmar contraseña").fill(password);
    const responsePromise = page.waitForResponse((response) =>
      endpoint(response, "POST", "/platform/identity/activate"));
    await page.getByRole("button", { name: "Completar activación" }).click();
    const response = await responsePromise;
    assertStatus(response.status(), 200, "Activacion de identidad tenant");
    const body = await requireObject(response, "Activacion de identidad tenant");
    if (!Array.isArray(body.recoveryCodes) || body.recoveryCodes.length !== 0) {
      throw new Error("Activacion tenant emitio recovery codes inesperados");
    }
    await expect(page.getByRole("heading", { name: "Identidad activada" })).toBeVisible();
  } finally {
    await context.close();
  }
};

const tenantLogin = async (
  browser: Browser,
  identity: typeof e2eState.alpha,
  tenantId: string,
  sensitiveValues: SensitiveAuditValues,
): Promise<TenantSession> => {
  const context = await browser.newContext({ baseURL: e2eState.baseUrl });
  const page = await context.newPage();
  try {
    await page.goto("/login");
    await page.getByLabel("Nombre de Usuario:").fill(identity.username);
    await page.getByLabel("Contraseña:").fill(identity.password);
    const responsePromise = page.waitForResponse((response) => endpoint(response, "POST", "/login"));
    await page.getByRole("button", { name: "Ingresar" }).click();
    const response = await responsePromise;
    assertStatus(response.status(), 200, "Login tenant");
    const body = await requireObject(response, "Login tenant");
    const accessToken = rememberSensitiveValue(
      sensitiveValues,
      requireString(body, "accessToken", "Login tenant"),
    );
    await rememberSessionCookies(context, sensitiveValues);
    const rawUser = body.usuario;
    if (!rawUser || typeof rawUser !== "object" || Array.isArray(rawUser)) {
      throw new Error("Login tenant: perfil ausente");
    }
    const user = rawUser as Record<string, unknown>;
    const active = user.tenantActivo;
    const available = user.tenantsDisponibles;
    if (
      !active || typeof active !== "object" || Array.isArray(active) ||
      (active as Record<string, unknown>).id !== tenantId ||
      !Array.isArray(available) || available.length !== 1 ||
      !available[0] || typeof available[0] !== "object" || Array.isArray(available[0]) ||
      (available[0] as Record<string, unknown>).id !== tenantId
    ) {
      throw new Error("Login tenant: aislamiento de membresias inesperado");
    }
    await expect(page.locator("header").getByText(identity.name, { exact: true })).toBeVisible();
    return { context, page, accessToken };
  } catch (error) {
    await context.close();
    throw error;
  }
};

const assertSuspendedLoginDenied = async (
  browser: Browser,
  identity: typeof e2eState.alpha,
): Promise<void> => {
  const context = await browser.newContext({ baseURL: e2eState.baseUrl });
  const page = await context.newPage();
  try {
    await page.goto("/login");
    await page.getByLabel("Nombre de Usuario:").fill(identity.username);
    await page.getByLabel("Contraseña:").fill(identity.password);
    const responsePromise = page.waitForResponse((response) => endpoint(response, "POST", "/login"));
    await page.getByRole("button", { name: "Ingresar" }).click();
    const response = await responsePromise;
    assertStatus(response.status(), 401, "Login con tenant suspendido");
    const body = await requireObject(response, "Login con tenant suspendido");
    if (body.code !== "UNAUTHORIZED") throw new Error("Login suspendido no fue UNAUTHORIZED");
    await expect(page.getByRole("alert")).toBeVisible();
  } finally {
    await context.close();
  }
};

const platformLogout = async (page: Page): Promise<void> => {
  const responsePromise = page.waitForResponse((response) =>
    endpoint(response, "POST", "/platform/auth/logout"));
  await page.getByRole("button", { name: "Cerrar sesión" }).first().click();
  const response = await responsePromise;
  assertStatus(response.status(), 204, "Logout de plataforma");
  await expect(page).toHaveURL(/\/platform\/login$/);
  const refreshCookie = (await page.context().cookies()).find((cookie) =>
    cookie.name.startsWith("gestudio_e2e_platform_"));
  if (refreshCookie) throw new Error("Logout de plataforma conservo la cookie refresh");
  const refresh = await page.context().request.post(`${e2eState.apiUrl}/platform/auth/refresh`, {
    headers: { Origin: e2eState.baseUrl },
  });
  assertStatus(refresh.status(), 401, "Refresh posterior a logout de plataforma");
  await page.goto("/platform/tenants");
  await expect(page).toHaveURL(/\/platform\/login$/);
};

const changeTenantStatus = async (
  page: Page,
  totp: TotpSequence,
  tenantId: string,
  action: "Suspender" | "Reactivar",
  expectedStatus: "SUSPENDED" | "ACTIVE",
  sensitiveValues: SensitiveAuditValues,
): Promise<void> => {
  await page.goto(`/platform/tenants/${tenantId}`);
  const actionName = `${action} organización`;
  await page.getByRole("button", { name: actionName }).click();
  const confirmation = page.getByRole("dialog", { name: actionName });
  await expect(confirmation).toBeVisible();
  await confirmation.getByRole("button", { name: action }).click();
  const stepUp = page.getByRole("dialog", { name: "Confirmá esta acción sensible" });
  await expect(stepUp).toBeVisible();
  const code = rememberSensitiveValue(sensitiveValues, await totp.next());
  await stepUp.getByLabel("Código TOTP").fill(code);
  const proofPromise = page.waitForResponse(isStepUpVerification);
  const responsePromise = page.waitForResponse((response) =>
    endpoint(response, "PATCH", `/platform/tenants/${tenantId}/status`) && response.status() === 200);
  await stepUp.getByRole("button", { name: "Verificar y continuar" }).click();
  await rememberStepUpProof(await proofPromise, sensitiveValues);
  const response = await responsePromise;
  const body = await requireObject(response, `Estado tenant ${expectedStatus}`);
  if (body.status !== expectedStatus) throw new Error("Transicion tenant devolvio estado inesperado");
  await expect(page.getByText(expectedStatus === "ACTIVE" ? "Activa" : "Suspendida", { exact: true }).first()).toBeVisible();
};

const assertAuditActions = async (
  request: APIRequestContext,
  platformToken: string,
  sensitiveValues: SensitiveAuditValues,
): Promise<void> => {
  const expected = new Map<string, { success: number; denied: number }>([
    ["PLATFORM_SUPERADMIN_BOOTSTRAP", { success: 1, denied: 0 }],
    ["TENANT_CREATE", { success: 2, denied: 2 }],
    ["TENANT_STATUS", { success: 2, denied: 2 }],
    ["PLATFORM_IDENTITY_ACTIVATED", { success: 2, denied: 0 }],
  ]);
  for (const [action, counts] of expected) {
    const response = await request.get(
      `${e2eState.apiUrl}/platform/audit?action=${encodeURIComponent(action)}&page=0&size=25`,
      { headers: bearer(platformToken) },
    );
    assertStatus(response.status(), 200, `Auditoria ${action}`);
    const body = await requireObject(response, `Auditoria ${action}`);
    if (!Array.isArray(body.content)) throw new Error(`Auditoria ${action}: pagina invalida`);
    const events = body.content.filter((item) => {
      if (!item || typeof item !== "object" || Array.isArray(item)) return false;
      const event = item as Record<string, unknown>;
      return event.action === action;
    });
    const successes = events.filter((item) => (item as Record<string, unknown>).result === "SUCCESS");
    const denials = events.filter((item) => (item as Record<string, unknown>).result === "DENIED");
    if (
      body.totalElements !== counts.success + counts.denied ||
      body.content.length !== counts.success + counts.denied ||
      events.length !== counts.success + counts.denied ||
      successes.length !== counts.success ||
      denials.length !== counts.denied
    ) {
      throw new Error(`Auditoria ${action}: cardinalidad o resultado inesperado`);
    }
    for (const item of events) {
      const event = item as Record<string, unknown>;
      if (containsSensitiveAuditMaterial(event, sensitiveValues)) {
        throw new Error(`Auditoria ${action}: contiene material sensible`);
      }
      const bootstrap = action === "PLATFORM_SUPERADMIN_BOOTSTRAP";
      const tenantMutation = action === "TENANT_CREATE" || action === "TENANT_STATUS";
      const tenantCreateBeforeInsert = action === "TENANT_CREATE" && event.result === "DENIED";
      const occurredAt = typeof event.occurredAt === "string" ? Date.parse(event.occurredAt) : NaN;
      const correlationId = typeof event.correlationId === "string" ? event.correlationId : "";
      const targetId = typeof event.targetId === "string" ? event.targetId : "";
      if (
        !Number.isFinite(occurredAt) ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(correlationId) ||
        !Number.isSafeInteger(event.actorId) ||
        typeof event.actorUsername !== "string" || event.actorUsername.length === 0 ||
        event.targetType !== (bootstrap ? "PLATFORM_ADMIN" : tenantMutation ? "TENANT" : "USUARIO") ||
        targetId.length === 0 ||
        (tenantMutation && !tenantCreateBeforeInsert &&
          (typeof event.tenantId !== "string" || event.tenantId !== targetId)) ||
        (tenantCreateBeforeInsert && event.tenantId != null) ||
        (!tenantMutation && event.tenantId != null)
      ) {
        throw new Error(`Auditoria ${action}: estructura de actor, target o correlacion invalida`);
      }
      if (event.detail != null) {
        if (typeof event.detail !== "string") {
          throw new Error(`Auditoria ${action}: metadata no serializada`);
        }
        let detail: unknown;
        try {
          detail = JSON.parse(event.detail);
        } catch {
          throw new Error(`Auditoria ${action}: metadata JSON invalida`);
        }
        if (containsSensitiveAuditMaterial(detail, sensitiveValues)) {
          throw new Error(`Auditoria ${action}: metadata contiene material sensible`);
        }
      }
    }
  }
};

test("fresh -> bootstrap/MFA -> Alpha/Beta -> RLS -> lifecycle -> audit; axe A/AA sin exclusiones", async ({
  browser,
  page,
  request,
}) => {
  const totp = new TotpSequence(e2eState.platform.totpSecret, e2eState.bootstrapCounter);
  const sensitiveValues: SensitiveAuditValues = new Set([
    e2eState.platform.password,
    e2eState.platform.totpSecret,
    e2eState.alpha.password,
    e2eState.beta.password,
  ]);
  assertSensitiveAuditScannerContract(sensitiveValues);

  await page.goto("/platform/tenants");
  await expect(page).toHaveURL(/\/platform\/login$/);
  const platformToken = await platformLogin(page, totp, sensitiveValues);
  const platformProfile = await request.get(`${e2eState.apiUrl}/platform/me`, {
    headers: bearer(platformToken),
  });
  assertStatus(platformProfile.status(), 200, "Token de plataforma capturado por login UI");
  await assertAxeWcagAAndAa(page, "Listado de organizaciones autenticado");

  const alpha = await createTenant(page, totp, e2eState.alpha, sensitiveValues);
  const beta = await createTenant(page, totp, e2eState.beta, sensitiveValues);
  await activateTenantIdentity(browser, alpha.activationToken, e2eState.alpha.password);
  alpha.activationToken = "";
  await activateTenantIdentity(browser, beta.activationToken, e2eState.beta.password);
  beta.activationToken = "";

  const betaSession = await tenantLogin(browser, e2eState.beta, beta.id, sensitiveValues);
  let betaAlumnoId: number;
  try {
    const createMarker = await request.post(`${e2eState.apiUrl}/alumnos`, {
      headers: bearer(betaSession.accessToken),
      data: {
        nombre: "Marcador",
        apellido: `Beta E2E ${e2eState.runId}`,
      },
    });
    assertStatus(createMarker.status(), 200, "Alta marcador Beta");
    const marker = await requireObject(createMarker, "Alta marcador Beta");
    if (!Number.isSafeInteger(marker.id)) throw new Error("Alta marcador Beta: id invalido");
    betaAlumnoId = marker.id as number;
    const betaRead = await request.get(`${e2eState.apiUrl}/alumnos/${betaAlumnoId}`, {
      headers: bearer(betaSession.accessToken),
    });
    assertStatus(betaRead.status(), 200, "Lectura propia Beta");
    const betaMarker = await requireObject(betaRead, "Lectura propia Beta");
    if (
      betaMarker.id !== betaAlumnoId || betaMarker.nombre !== "Marcador" ||
      betaMarker.apellido !== `Beta E2E ${e2eState.runId}` || betaMarker.activo !== true
    ) {
      throw new Error("Lectura propia Beta: marcador inesperado");
    }
  } finally {
    await betaSession.context.close();
  }
  const alphaSession = await tenantLogin(browser, e2eState.alpha, alpha.id, sensitiveValues);
  let alphaAlumnoId: number;
  try {
    await assertAxeWcagAAndAa(alphaSession.page, "Panel tenant Alpha autenticado");
    const crossScope = await request.get(`${e2eState.apiUrl}/platform/tenants?page=0&size=1`, {
      headers: bearer(alphaSession.accessToken),
    });
    assertStatus(crossScope.status(), 403, "Token Alpha contra control plane");
    const crossScopeBody = await requireObject(crossScope, "Token Alpha contra control plane");
    if (crossScopeBody.code !== "TOKEN_SCOPE_FORBIDDEN") {
      throw new Error("Denegacion cross-scope no fue TOKEN_SCOPE_FORBIDDEN");
    }
    const crossTenant = await request.get(`${e2eState.apiUrl}/alumnos/${betaAlumnoId}`, {
      headers: bearer(alphaSession.accessToken),
    });
    assertStatus(crossTenant.status(), 404, "Token Alpha contra marcador Beta");
    const denial = await requireObject(crossTenant, "Denegacion RLS Alpha/Beta");
    if (denial.code !== "NOT_FOUND") throw new Error("Denegacion RLS no fue NOT_FOUND");
    const createAlphaMarker = await request.post(`${e2eState.apiUrl}/alumnos`, {
      headers: bearer(alphaSession.accessToken),
      data: { nombre: "Marcador", apellido: `Alpha E2E ${e2eState.runId}` },
    });
    assertStatus(createAlphaMarker.status(), 200, "Alta marcador Alpha antes de suspension");
    const alphaMarker = await requireObject(createAlphaMarker, "Alta marcador Alpha antes de suspension");
    if (!Number.isSafeInteger(alphaMarker.id)) throw new Error("Alta marcador Alpha: id invalido");
    alphaAlumnoId = alphaMarker.id as number;
  } finally {
    await alphaSession.context.close();
  }
  const alphaBeforeSuspension = await tenantLogin(
    browser,
    e2eState.alpha,
    alpha.id,
    sensitiveValues,
  );
  const staleAlphaToken = alphaBeforeSuspension.accessToken;
  await alphaBeforeSuspension.context.close();
  await page.goto(`/platform/tenants/${alpha.id}`);
  await expect(page.getByRole("heading", { name: e2eState.alpha.name })).toBeVisible();
  await assertAxeWcagAAndAa(page, "Detalle de organizacion Alpha");
  await platformLogout(page);
  const lifecyclePlatformToken = await platformLogin(page, totp, sensitiveValues);
  await changeTenantStatus(
    page,
    totp,
    alpha.id,
    "Suspender",
    "SUSPENDED",
    sensitiveValues,
  );
  const staleRequest = await request.get(`${e2eState.apiUrl}/alumnos?page=0&size=1`, {
    headers: bearer(staleAlphaToken),
  });
  assertStatus(staleRequest.status(), 401, "Token Alpha emitido antes de suspension");
  const staleBody = await requireObject(staleRequest, "Token Alpha emitido antes de suspension");
  if (staleBody.code !== "UNAUTHORIZED") throw new Error("Token suspendido no fue UNAUTHORIZED");
  await assertSuspendedLoginDenied(browser, e2eState.alpha);

  await changeTenantStatus(
    page,
    totp,
    alpha.id,
    "Reactivar",
    "ACTIVE",
    sensitiveValues,
  );
  const recoveredAlpha = await tenantLogin(
    browser,
    e2eState.alpha,
    alpha.id,
    sensitiveValues,
  );
  try {
    const recoveredMarker = await request.get(`${e2eState.apiUrl}/alumnos/${alphaAlumnoId}`, {
      headers: bearer(recoveredAlpha.accessToken),
    });
    assertStatus(recoveredMarker.status(), 200, "Marcador Alpha preservado tras reactivacion");
    const recoveredBody = await requireObject(recoveredMarker, "Marcador Alpha preservado");
    if (
      recoveredBody.id !== alphaAlumnoId || recoveredBody.nombre !== "Marcador" ||
      recoveredBody.apellido !== `Alpha E2E ${e2eState.runId}` || recoveredBody.activo !== true
    ) {
      throw new Error("Marcador Alpha no fue preservado por el lifecycle");
    }
  } finally {
    await recoveredAlpha.context.close();
  }

  await page.goto("/platform/audit");
  await expect(page.getByRole("heading", { name: "Auditoría de plataforma" })).toBeVisible();
  const filteredPromise = page.waitForResponse((response) =>
    endpoint(response, "GET", "/platform/audit") && new URL(response.url()).searchParams.get("action") === "TENANT_STATUS");
  await page.getByLabel("Acción").fill("TENANT_STATUS");
  const filtered = await filteredPromise;
  assertStatus(filtered.status(), 200, "Filtro UI de auditoria");
  await expect(page.getByText("TENANT_STATUS", { exact: true }).first()).toBeVisible();
  await assertAxeWcagAAndAa(page, "Auditoria de plataforma filtrada");
  await assertAuditActions(request, lifecyclePlatformToken, sensitiveValues);
});
