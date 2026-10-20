'use strict';

const { chromium } = require('playwright');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { loadCaptureAccounts } = require('./manual-accounts.cjs');
const {
  classifyDiagnosticEvent,
  formatDiagnosticEvent,
  getUnexpectedConsoleEvents,
} = require('./manual-diagnostics.cjs');

const baseUrl = process.env.MANUAL_BASE_URL;
const screenshotDirectory = process.env.MANUAL_SCREENSHOT_DIRECTORY;
const accountsPath = process.env.MANUAL_ACCOUNTS_PATH;
const headed = process.env.MANUAL_HEADED === '1';
const resumeFrom = process.env.MANUAL_RESUME_FROM || '';

if (!baseUrl || !screenshotDirectory || !accountsPath) {
  throw new Error('MANUAL_BASE_URL, MANUAL_SCREENSHOT_DIRECTORY y MANUAL_ACCOUNTS_PATH son obligatorias.');
}

const captureAccounts = loadCaptureAccounts({
  documentedPath: accountsPath,
  credentialManifestPath: process.env.MANUAL_CREDENTIAL_MANIFEST_PATH,
  baseUrl,
});
const accountData = captureAccounts.data;

const account = (id) => {
  const match = accountData.accounts.find((candidate) => candidate.id === id);
  if (!match || !match.username || !match.password || !match.profile) {
    throw new Error('Falta una cuenta demo completa para ' + id + '.');
  }
  return match;
};

const accounts = {
  presentation: account('alpha-presentacion'),
  alphaAdmin: account('alpha-administrador'),
  betaAdmin: account('beta-administrador'),
  superadmin: account('alpha-superadmin'),
  direccion: account('alpha-direccion'),
  administrador: account('alpha-administrador-funcional'),
  secretaria: account('alpha-secretaria'),
  caja: account('alpha-caja'),
  platform: account('plataforma-superadmin'),
};
const sensitiveValues = new Set(Object.values(accounts)
  .flatMap(({ password, totpSecret }) => [password, totpSecret]).filter(Boolean));

if (!accounts.platform.totpSecret) {
  throw new Error('La cuenta de plataforma no define el secreto TOTP demo autorizado.');
}

const expectedFiles = [
  '01-login-academia.png',
  '02-panel-presentacion.png',
  '03-alumnos-alpha.png',
  '04-profesores-alpha.png',
  '05-salones-alpha.png',
  '06-disciplinas-alpha.png',
  '07-horarios-disciplina.png',
  '08-inscripciones-alpha.png',
  '09-tarifas-alpha.png',
  '10-condiciones-economicas-alpha.png',
  '11-cargos-cobranza.png',
  '12-pagos-alpha.png',
  '13-caja-alpha.png',
  '14-egresos-alpha.png',
  '15-bonificaciones-alpha.png',
  '16-recargos-alpha.png',
  '17-metodos-pago-alpha.png',
  '18-conceptos-alpha.png',
  '19-stock-alpha.png',
  '20-asistencias-alpha.png',
  '21-reporte-disciplina-alpha.png',
  '22-reporte-mensualidades-alpha.png',
  '23-usuarios-alpha.png',
  '24-roles-alpha.png',
  '25-panel-secretaria.png',
  '26-panel-caja.png',
  '27-panel-administracion.png',
  '28-panel-direccion.png',
  '29-panel-superadmin.png',
  '30-alumnos-beta.png',
  '31-acceso-no-autorizado.png',
  '32-login-plataforma.png',
  '33-organizaciones-plataforma.png',
  '34-detalle-alpha-plataforma.png',
  '35-administradores-plataforma.png',
  '36-auditoria-plataforma.png',
];

const captureOrder = [
  '01-login-academia.png',
  '02-panel-presentacion.png',
  '03-alumnos-alpha.png',
  '04-profesores-alpha.png',
  '05-salones-alpha.png',
  '06-disciplinas-alpha.png',
  '08-inscripciones-alpha.png',
  '12-pagos-alpha.png',
  '13-caja-alpha.png',
  '15-bonificaciones-alpha.png',
  '16-recargos-alpha.png',
  '17-metodos-pago-alpha.png',
  '18-conceptos-alpha.png',
  '19-stock-alpha.png',
  '20-asistencias-alpha.png',
  '21-reporte-disciplina-alpha.png',
  '22-reporte-mensualidades-alpha.png',
  '31-acceso-no-autorizado.png',
  '25-panel-secretaria.png',
  '26-panel-caja.png',
  '11-cargos-cobranza.png',
  '27-panel-administracion.png',
  '07-horarios-disciplina.png',
  '09-tarifas-alpha.png',
  '10-condiciones-economicas-alpha.png',
  '14-egresos-alpha.png',
  '23-usuarios-alpha.png',
  '28-panel-direccion.png',
  '29-panel-superadmin.png',
  '24-roles-alpha.png',
  '30-alumnos-beta.png',
  '32-login-plataforma.png',
  '33-organizaciones-plataforma.png',
  '34-detalle-alpha-plataforma.png',
  '35-administradores-plataforma.png',
  '36-auditoria-plataforma.png',
];

if (new Set(captureOrder).size !== expectedFiles.length
    || expectedFiles.some((fileName) => !captureOrder.includes(fileName))) {
  throw new Error('El orden de captura no coincide con la lista final esperada.');
}

const resumeIndex = resumeFrom ? captureOrder.indexOf(resumeFrom) : 0;
if (resumeFrom && resumeIndex < 0) {
  throw new Error('La captura de reanudación no pertenece al recorrido: ' + resumeFrom + '.');
}

fs.mkdirSync(screenshotDirectory, { recursive: true });

function decodeBase32(value) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  const normalized = value.toUpperCase().replace(/[\s=-]/g, '');
  let bits = '';
  for (const character of normalized) {
    const index = alphabet.indexOf(character);
    if (index < 0) throw new Error('El secreto TOTP demo no está en Base32.');
    bits += index.toString(2).padStart(5, '0');
  }
  const bytes = [];
  for (let index = 0; index + 8 <= bits.length; index += 8) {
    bytes.push(Number.parseInt(bits.slice(index, index + 8), 2));
  }
  return Buffer.from(bytes);
}

async function currentTotp(secret) {
  const seconds = Math.floor(Date.now() / 1000);
  const remaining = 30 - (seconds % 30);
  if (remaining <= 3) {
    await new Promise((resolve) => setTimeout(resolve, (remaining + 1) * 1000));
  }
  const counter = Math.floor(Date.now() / 1000 / 30);
  const message = Buffer.alloc(8);
  message.writeBigUInt64BE(BigInt(counter));
  const digest = crypto.createHmac('sha1', decodeBase32(secret)).update(message).digest();
  const offset = digest[digest.length - 1] & 0x0f;
  const number = (
    ((digest[offset] & 0x7f) << 24)
    | ((digest[offset + 1] & 0xff) << 16)
    | ((digest[offset + 2] & 0xff) << 8)
    | (digest[offset + 3] & 0xff)
  ) % 1000000;
  const code = String(number).padStart(6, '0');
  sensitiveValues.add(code);
  return code;
}

async function main() {
  const browser = await chromium.launch({ headless: !headed });
  const consoleEvents = [];
  const responseEvents = [];
  const pageErrorEvents = [];
  const requestFailureEvents = [];
  let verifiedAccounts = 0;

  function diagnosticSnapshot(diagnostics) {
    return {
      scope: diagnostics.scope,
      phase: diagnostics.phase,
      authenticated: diagnostics.authenticated,
    };
  }

  function attachDiagnostics(page, diagnostics) {
    page.on('console', (message) => {
      consoleEvents.push({
        kind: 'console',
        ...diagnosticSnapshot(diagnostics),
        type: message.type(),
        text: message.text(),
      });
    });
    page.on('pageerror', (error) => {
      pageErrorEvents.push({
        kind: 'pageerror',
        ...diagnosticSnapshot(diagnostics),
        message: error instanceof Error ? error.message : String(error),
      });
    });
    page.on('requestfailed', (request) => {
      requestFailureEvents.push({
        kind: 'requestfailed',
        ...diagnosticSnapshot(diagnostics),
        method: request.method(),
        url: request.url(),
        failure: request.failure()?.errorText || 'falló',
      });
    });
    page.on('response', (response) => {
      if (response.status() < 400) return;
      responseEvents.push({
        kind: 'response',
        ...diagnosticSnapshot(diagnostics),
        method: response.request().method(),
        pathname: new URL(response.url()).pathname,
        status: response.status(),
      });
    });
  }

  async function makeContext(scope) {
    const context = await browser.newContext({
      viewport: { width: 1440, height: 1000 },
      locale: 'es-AR',
      timezoneId: 'America/Argentina/Buenos_Aires',
      colorScheme: 'light',
      reducedMotion: 'reduce',
      serviceWorkers: 'block',
    });
    const diagnostics = { scope, phase: 'before-login', authenticated: false };
    const page = await context.newPage();
    attachDiagnostics(page, diagnostics);
    return { context, page, diagnostics };
  }

  async function settle(page) {
    await page.waitForLoadState('domcontentloaded');
    await page.waitForLoadState('networkidle', { timeout: 45000 }).catch(() => undefined);
    await page.addStyleTag({
      content: '*,*::before,*::after{animation-duration:0s!important;animation-delay:0s!important;transition-duration:0s!important;caret-color:transparent!important;}',
    });
    await page.evaluate(async () => {
      if (document.fonts?.ready) await document.fonts.ready;
      window.scrollTo(0, 0);
      for (const element of document.querySelectorAll('*')) {
        if (element.scrollTop) element.scrollTop = 0;
        if (element.scrollLeft) element.scrollLeft = 0;
      }
    });
  }

  async function redactInternalIdentifiers(page) {
    await page.evaluate(() => {
      const uuid = /\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b/gi;
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      const nodes = [];
      while (walker.nextNode()) nodes.push(walker.currentNode);
      for (const node of nodes) {
        if (uuid.test(node.nodeValue || '')) {
          node.nodeValue = (node.nodeValue || '').replace(uuid, 'identificador oculto');
        }
        uuid.lastIndex = 0;
      }
    });
  }

  async function screenshot(page, fileName) {
    const fileIndex = captureOrder.indexOf(fileName);
    if (fileIndex < 0) throw new Error('Captura inesperada: ' + fileName + '.');
    const targetPath = path.join(screenshotDirectory, fileName);
    if (fileIndex < resumeIndex) {
      if (!fs.existsSync(targetPath)) {
        throw new Error('No existe la captura previa requerida: ' + fileName + '.');
      }
      return;
    }
    await settle(page);
    await redactInternalIdentifiers(page);
    await page.screenshot({
      path: targetPath,
      fullPage: false,
      animations: 'disabled',
    });
  }

  async function go(page, route, heading) {
    await page.goto(new URL(route, baseUrl).toString(), { waitUntil: 'domcontentloaded' });
    if (heading) {
      await page.getByRole('heading', { name: heading, exact: typeof heading === 'string' }).first().waitFor({
        state: 'visible',
        timeout: 25000,
      });
    } else {
      await page.getByRole('heading').first().waitFor({ state: 'visible', timeout: 25000 });
    }
    await settle(page);
  }

  async function closeBlockingModal(page) {
    const dialog = page.getByRole('dialog', { name: /Cumpleañeros de hoy/i });
    if (await dialog.isVisible().catch(() => false)) {
      await dialog.getByRole('button', { name: 'Cerrar modal' }).click();
      await dialog.waitFor({ state: 'hidden' });
    }
  }

  async function waitForResult(page, successLocators, errorLocator, label) {
    let result = successLocators[0];
    for (const locator of successLocators.slice(1)) result = result.or(locator);
    if (errorLocator) result = result.or(errorLocator);

    await result.first().waitFor({ state: 'visible', timeout: 60000 });
    if (errorLocator && await errorLocator.isVisible().catch(() => false)) {
      throw new Error('La pantalla informó un error al cargar ' + label + '.');
    }
  }

  async function loginTenant(page, diagnostics, demoAccount) {
    await go(page, '/login', 'Iniciar sesión');
    await page.getByLabel(/Nombre de Usuario/i).fill(demoAccount.username);
    await page.getByLabel(/Contraseña/i).fill(demoAccount.password);
    diagnostics.phase = 'login-submit';
    await page.getByRole('button', { name: 'Ingresar', exact: true }).click();
    const panelHeading = page.getByRole('heading', { name: 'Panel de control', exact: true });
    const organization = page.locator('#tenantId');
    const nextStep = await Promise.race([
      panelHeading.waitFor({ state: 'visible', timeout: 25000 }).then(() => 'panel'),
      organization.waitFor({ state: 'visible', timeout: 25000 }).then(() => 'organization'),
    ]);

    if (nextStep === 'organization') {
      await organization.selectOption({ label: demoAccount.organization });
      await page.getByRole('button', { name: 'Ingresar a la organización', exact: true }).click();
      await panelHeading.waitFor({ state: 'visible', timeout: 25000 });
    }

    diagnostics.authenticated = true;
    diagnostics.phase = 'authenticated';
    await closeBlockingModal(page);
    await page.getByText(demoAccount.username, { exact: true }).last().waitFor({ state: 'visible' });
    await page.getByText(demoAccount.profile, { exact: true }).last().waitFor({ state: 'visible' });
    await page.getByText(demoAccount.organization, { exact: true }).first().waitFor({ state: 'visible' });
    verifiedAccounts += 1;
    await settle(page);
  }

  async function logoutTenant(page) {
    await page.getByRole('button', { name: 'Cerrar sesión', exact: true }).click();
    await page.getByRole('heading', { name: 'Iniciar sesión', exact: true }).waitFor({
      state: 'visible',
      timeout: 20000,
    });
  }

  async function chooseStudent(page, firstName = 'Sofía', fullName = 'Sofía Benítez') {
    const search = page.getByLabel('Alumno', { exact: true });
    await search.fill(firstName);
    const option = page.getByRole('button', { name: 'Seleccionar ' + fullName, exact: true });
    await option.waitFor({ state: 'visible', timeout: 20000 });
    await option.click();
  }

  async function capturePresentation() {
    const { context, page, diagnostics } = await makeContext('presentation');
    await loginTenant(page, diagnostics, accounts.presentation);
    await screenshot(page, '02-panel-presentacion.png');

    await go(page, '/alumnos', 'Alumnos');
    await screenshot(page, '03-alumnos-alpha.png');
    await go(page, '/profesores', 'Profesores');
    await screenshot(page, '04-profesores-alpha.png');
    await go(page, '/salones', 'Salones');
    await screenshot(page, '05-salones-alpha.png');
    await go(page, '/disciplinas', 'Disciplinas');
    await screenshot(page, '06-disciplinas-alpha.png');
    await go(page, '/inscripciones', 'Inscripciones');
    await screenshot(page, '08-inscripciones-alpha.png');

    await go(page, '/pagos', 'Pagos');
    await chooseStudent(page);
    await waitForResult(page, [
      page.getByText('El alumno no tiene pagos registrados.', { exact: true }),
      page.getByRole('columnheader', { name: 'Fecha', exact: true }),
    ], page.getByText('No se pudieron cargar los pagos.', { exact: true }), 'los pagos');
    await screenshot(page, '12-pagos-alpha.png');

    await go(page, '/caja', 'Caja');
    await page.getByRole('button', { name: 'Consultar', exact: true }).click();
    await page.getByRole('region', { name: 'Resumen de caja' }).waitFor({ state: 'visible', timeout: 20000 });
    await screenshot(page, '13-caja-alpha.png');

    await go(page, '/bonificaciones', 'Bonificaciones');
    await screenshot(page, '15-bonificaciones-alpha.png');
    await go(page, '/recargos', 'Recargos');
    await screenshot(page, '16-recargos-alpha.png');
    await go(page, '/metodos-pago', 'Métodos de pago');
    await screenshot(page, '17-metodos-pago-alpha.png');
    await go(page, '/conceptos', 'Conceptos');
    await screenshot(page, '18-conceptos-alpha.png');
    await go(page, '/stocks', 'Stock');
    await screenshot(page, '19-stock-alpha.png');
    await go(page, '/asistencias/alumnos', 'Asistencia diaria');
    await screenshot(page, '20-asistencias-alpha.png');

    await go(page, '/alumnos-por-disciplina', 'Alumnos por Disciplina');
    const disciplineSearch = page.getByLabel(/Selecciona la disciplina/i);
    await disciplineSearch.fill('Ballet Inicial');
    await page.getByText('Ballet Inicial (4 a 6 años)', { exact: true }).click();
    await waitForResult(page, [
      page.getByRole('button', { name: /Ordenar (?:Ascendente|Descendente)/ }),
    ], page.getByText('Ocurrió un error al cargar los alumnos. Por favor, intenta de nuevo.', { exact: true }), 'el reporte por disciplina');
    await screenshot(page, '21-reporte-disciplina-alpha.png');

    await go(page, '/reportes', 'Reporte de mensualidades');
    const from = page.getByLabel('Desde', { exact: true });
    const to = page.getByLabel('Hasta', { exact: true });
    const dateParts = Object.fromEntries(new Intl.DateTimeFormat('en-US', {
      timeZone: 'America/Argentina/Buenos_Aires',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(new Date()).map(({ type, value }) => [type, value]));
    if (!(await from.inputValue())) await from.fill(dateParts.year + '-01-01');
    if (!(await to.inputValue())) await to.fill(dateParts.year + '-' + dateParts.month + '-' + dateParts.day);
    await page.getByRole('button', { name: 'Consultar', exact: true }).click();
    await waitForResult(page, [
      page.getByText('No hay resultados para el rango consultado.', { exact: true }),
      page.getByRole('columnheader', { name: 'Fecha', exact: true }),
    ], null, 'el reporte de mensualidades');
    await screenshot(page, '22-reporte-mensualidades-alpha.png');

    await page.goto(new URL('/usuarios', baseUrl).toString(), { waitUntil: 'domcontentloaded' });
    await page.getByRole('heading', { name: 'Acceso no autorizado', exact: true }).waitFor({
      state: 'visible',
      timeout: 20000,
    });
    await screenshot(page, '31-acceso-no-autorizado.png');
    await logoutTenant(page);
    await context.close();
  }

  async function captureAdministrator() {
    const { context, page, diagnostics } = await makeContext('administrator');
    await loginTenant(page, diagnostics, accounts.administrador);
    await screenshot(page, '27-panel-administracion.png');

    await go(page, '/disciplinas', 'Disciplinas');
    let disciplineActions = page.getByRole('button', { name: /Acciones de Ballet Inicial/i }).first();
    await disciplineActions.click();
    await page.getByRole('menuitem', { name: 'Editar', exact: true }).click();
    await page.getByRole('heading', { name: 'Editar disciplina', exact: true }).waitFor({ state: 'visible' });
    await page.getByLabel('Nombre', { exact: true }).waitFor({ state: 'visible', timeout: 20000 });
    await page.getByRole('button', { name: 'Quitar', exact: true }).first().waitFor({ state: 'visible', timeout: 20000 });
    await screenshot(page, '07-horarios-disciplina.png');

    await go(page, '/disciplinas', 'Disciplinas');
    disciplineActions = page.getByRole('button', { name: /Acciones de Ballet Inicial/i }).first();
    await disciplineActions.click();
    await page.getByRole('menuitem', { name: 'Tarifas', exact: true }).click();
    await page.getByRole('heading', { name: /Tarifas de Ballet Inicial/i }).waitFor({ state: 'visible' });
    await screenshot(page, '09-tarifas-alpha.png');

    await go(page, '/inscripciones', 'Inscripciones');
    const enrollmentActions = page.getByRole('button', { name: /Acciones de inscripción/i }).first();
    await enrollmentActions.click();
    await page.getByRole('menuitem', { name: 'Condiciones', exact: true }).click();
    await page.getByRole('heading', { name: 'Condiciones económicas', exact: true }).waitFor({ state: 'visible' });
    await screenshot(page, '10-condiciones-economicas-alpha.png');

    await go(page, '/egresos', 'Egresos');
    await screenshot(page, '14-egresos-alpha.png');
    await go(page, '/usuarios', 'Usuarios');
    await screenshot(page, '23-usuarios-alpha.png');
    await logoutTenant(page);
    await context.close();
  }

  async function captureRolePanel(scope, demoAccount, fileName) {
    const { context, page, diagnostics } = await makeContext(scope);
    await loginTenant(page, diagnostics, demoAccount);
    if (fileName) await screenshot(page, fileName);
    await logoutTenant(page);
    await context.close();
  }

  async function captureCashier() {
    const { context, page, diagnostics } = await makeContext('cashier');
    await loginTenant(page, diagnostics, accounts.caja);
    await screenshot(page, '26-panel-caja.png');
    await go(page, '/pagos/formulario', 'Registrar pago');
    await chooseStudent(page, 'Micaela', 'Micaela Duarte');
    await waitForResult(page, [
      page.getByText('Sin cargos pendientes', { exact: true }),
      page.getByText('Saldo pendiente', { exact: true }).first(),
    ], page.getByText('No se pudieron cargar los cargos del alumno.', { exact: true }), 'los cargos pendientes');
    await screenshot(page, '11-cargos-cobranza.png');
    await logoutTenant(page);
    await context.close();
  }

  async function captureSuperadmin() {
    const { context, page, diagnostics } = await makeContext('superadmin');
    await loginTenant(page, diagnostics, accounts.superadmin);
    await screenshot(page, '29-panel-superadmin.png');
    await go(page, '/roles', 'Roles y permisos');
    await screenshot(page, '24-roles-alpha.png');
    await logoutTenant(page);
    await context.close();
  }

  async function captureBeta() {
    const { context, page, diagnostics } = await makeContext('beta');
    await loginTenant(page, diagnostics, accounts.betaAdmin);
    await go(page, '/alumnos', 'Alumnos');
    await screenshot(page, '30-alumnos-beta.png');
    await logoutTenant(page);
    await context.close();
  }

  async function capturePlatform() {
    const { context, page, diagnostics } = await makeContext('platform');
    await go(page, '/platform/login', 'Iniciar sesión en plataforma');
    await screenshot(page, '32-login-plataforma.png');
    await page.getByLabel('Nombre de usuario', { exact: true }).fill(accounts.platform.username);
    await page.getByLabel('Contraseña', { exact: true }).fill(accounts.platform.password);
    await page.getByLabel('Código TOTP', { exact: true }).fill(await currentTotp(accounts.platform.totpSecret));
    diagnostics.phase = 'platform-login-submit';
    await page.getByRole('button', { name: 'Acceder al control plane', exact: true }).click();
    await page.getByRole('heading', { name: 'Organizaciones', exact: true }).waitFor({
      state: 'visible',
      timeout: 25000,
    });
    diagnostics.authenticated = true;
    diagnostics.phase = 'authenticated';
    verifiedAccounts += 1;
    await screenshot(page, '33-organizaciones-plataforma.png');

    await page.getByRole('button', { name: 'Ver Escuela Danza Marcos Paz', exact: true }).click();
    await page.getByRole('heading', { name: 'Escuela Danza Marcos Paz', exact: true }).waitFor({
      state: 'visible',
      timeout: 25000,
    });
    await screenshot(page, '34-detalle-alpha-plataforma.png');
    await go(page, '/platform/admins', 'Administradores de plataforma');
    await screenshot(page, '35-administradores-plataforma.png');
    await go(page, '/platform/audit', 'Auditoría de plataforma');
    await screenshot(page, '36-auditoria-plataforma.png');
    await page.getByRole('button', { name: 'Cerrar sesión', exact: true }).first().click();
    await page.getByRole('heading', { name: 'Iniciar sesión en plataforma', exact: true }).waitFor({
      state: 'visible', timeout: 20000,
    });
    await context.close();
  }

  try {
    {
      const { context, page } = await makeContext('anonymous');
      await go(page, '/login', 'Iniciar sesión');
      await screenshot(page, '01-login-academia.png');
      await context.close();
    }
    await capturePresentation();
    await captureRolePanel('alpha-admin', accounts.alphaAdmin, null);
    await captureRolePanel('secretaria', accounts.secretaria, '25-panel-secretaria.png');
    await captureCashier();
    await captureAdministrator();
    await captureRolePanel('direccion', accounts.direccion, '28-panel-direccion.png');
    await captureSuperadmin();
    await captureBeta();
    await capturePlatform();
  } finally {
    await browser.close();
  }

  const missing = expectedFiles.filter((fileName) => !fs.existsSync(path.join(screenshotDirectory, fileName)));
  if (missing.length > 0) {
    throw new Error('Faltan capturas esperadas: ' + missing.join(', '));
  }
  if (verifiedAccounts !== 9) {
    throw new Error('Se verificaron ' + verifiedAccounts + ' cuentas; se esperaban 9.');
  }

  const responseProblems = responseEvents
    .map((event) => ({ event, classification: classifyDiagnosticEvent(event) }))
    .filter(({ event, classification }) => event.status >= 500 || (classification?.fatal && event.authenticated))
    .map(({ event }) => event);
  const unexpectedConsoleEvents = getUnexpectedConsoleEvents(consoleEvents, responseEvents);
  const browserProblems = [
    ...responseProblems,
    ...pageErrorEvents,
    ...requestFailureEvents,
    ...unexpectedConsoleEvents,
  ];
  if (browserProblems.length > 0) {
    throw new Error('Errores de navegador inesperados:\n' + browserProblems.map(formatDiagnosticEvent).join('\n'));
  }

  console.log('Capturas reales completadas: ' + expectedFiles.length + '.');
  console.log('Recorridos autenticados verificados visualmente: ' + verifiedAccounts + '.');
  console.log('MANUAL_CAPTURE_SUMMARY=' + JSON.stringify({
    CaptureSource: captureAccounts.source,
    GeneralCaptureProfile: accounts.presentation.profile,
    CapturedAccountCount: new Set(Object.values(accounts).map(({ username }) => username)).size,
  }));
}

main().catch((error) => {
  let message = error instanceof Error ? error.message : String(error);
  for (const value of sensitiveValues) message = message.split(value).join('[REDACTED]');
  console.error(message);
  process.exitCode = 1;
});
