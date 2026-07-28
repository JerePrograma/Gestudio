'use strict';

const { chromium } = require('playwright');
const path = require('node:path');
const fs = require('node:fs');
const {
  classifyDiagnosticEvent,
  formatDiagnosticEvent,
  getUnexpectedConsoleEvents,
} = require('./manual-diagnostics.cjs');

async function main() {
const baseUrl = process.env.MANUAL_BASE_URL;
const screenshotDirectory = process.env.MANUAL_SCREENSHOT_DIRECTORY;
const headed = process.env.MANUAL_HEADED === '1';
const resumeFrom = process.env.MANUAL_RESUME_FROM || '';

if (!baseUrl || !screenshotDirectory) {
  throw new Error('MANUAL_BASE_URL y MANUAL_SCREENSHOT_DIRECTORY son obligatorias.');
}

fs.mkdirSync(screenshotDirectory, { recursive: true });

const users = {
  secretaria: {
    username: 'demo-secretaria',
    role: 'SECRETARIA',
    passwordVariable: 'GESTUDIO_DEMO_SECRETARIA_PASSWORD',
  },
  caja: {
    username: 'demo-caja',
    role: 'CAJA',
    passwordVariable: 'GESTUDIO_DEMO_CAJA_PASSWORD',
  },
  administrador: {
    username: 'demo-administrador',
    role: 'ADMINISTRADOR',
    passwordVariable: 'GESTUDIO_DEMO_ADMINISTRADOR_PASSWORD',
  },
  direccion: {
    username: 'demo-direccion',
    role: 'DIRECCION',
    passwordVariable: 'GESTUDIO_DEMO_DIRECCION_PASSWORD',
  },
  superadmin: {
    username: 'demo-superadmin',
    role: 'SUPERADMIN',
    passwordVariable: 'GESTUDIO_DEMO_SUPERADMIN_PASSWORD',
  },
};

for (const account of Object.values(users)) {
  if (!process.env[account.passwordVariable]) {
    throw new Error(`Falta ${account.passwordVariable}.`);
  }
}

const expectedFiles = [
  '01-login.png',
  '02-panel-secretaria.png',
  '03-alumnos-listado.png',
  '04-alumnos-busqueda.png',
  '05-alumnos-sin-resultados.png',
  '06-alumno-formulario.png',
  '07-inscripciones-listado.png',
  '08-inscripcion-formulario.png',
  '09-asistencias.png',
  '10-pagos-consulta.png',
  '11-cobranza-formulario.png',
  '12-caja-secretaria.png',
  '13-reporte-disciplina.png',
  '14-no-autorizado-secretaria.png',
  '15-panel-caja.png',
  '16-metodos-pago.png',
  '17-stock.png',
  '32-no-autorizado-caja.png',
  '18-disciplinas.png',
  '19-tarifas.png',
  '20-usuarios.png',
  '21-no-autorizado-administrador.png',
  '22-roles.png',
  '23-profesores.png',
  '24-salones.png',
  '25-bonificaciones.png',
  '26-recargos.png',
  '27-conceptos.png',
  '28-egresos.png',
  '29-panel-direccion.png',
  '30-no-autorizado-direccion.png',
  '31-panel-superadmin.png',
];

const resumeIndex = resumeFrom ? expectedFiles.indexOf(resumeFrom) : 0;
if (resumeFrom && resumeIndex < 0) {
  throw new Error(`La captura de reanudación no pertenece al recorrido: ${resumeFrom}.`);
}

const browser = await chromium.launch({
  headless: !headed,
});

const consoleEvents = [];
const responseEvents = [];
const pageErrorEvents = [];
const requestFailureEvents = [];

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
    if (response.status() < 400) {
      return;
    }

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

  const diagnostics = {
    scope,
    phase: 'before-login',
    authenticated: false,
  };
  const page = await context.newPage();
  attachDiagnostics(page, diagnostics);
  return { context, page, diagnostics };
}

async function settle(page) {
  await page.waitForLoadState('domcontentloaded');
  await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => undefined);
  await page.addStyleTag({
    content: [
      '*,*::before,*::after{',
      'animation-duration:0s!important;',
      'animation-delay:0s!important;',
      'transition-duration:0s!important;',
      'caret-color:transparent!important;',
      '}',
    ].join(''),
  });
  await page.evaluate(async () => {
    if (document.fonts?.ready) {
      await document.fonts.ready;
    }
    window.scrollTo(0, 0);
  });
}

async function screenshot(page, fileName) {
  const fileIndex = expectedFiles.indexOf(fileName);
  if (fileIndex < 0) {
    throw new Error(`La captura no pertenece al recorrido esperado: ${fileName}.`);
  }

  const targetPath = path.join(screenshotDirectory, fileName);
  if (fileIndex < resumeIndex) {
    if (!fs.existsSync(targetPath)) {
      throw new Error(`No existe la captura previa requerida para reanudar: ${fileName}.`);
    }
    return;
  }

  await settle(page);
  await page.screenshot({
    path: targetPath,
    fullPage: true,
    animations: 'disabled',
  });
}

async function goto(page, route, heading) {
  const target = new URL(route, baseUrl).toString();
  await page.goto(target, { waitUntil: 'domcontentloaded' });

  if (heading) {
    await page.getByRole('heading', { name: heading, exact: true }).first().waitFor({
      state: 'visible',
      timeout: 20000,
    });
  } else {
    await page.getByRole('heading').first().waitFor({ state: 'visible', timeout: 20000 });
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

async function login(context, page, diagnostics, account) {
  await goto(page, '/login', 'Iniciar sesión');
  await page.getByLabel(/Nombre de Usuario/i).fill(account.username);
  await page.getByLabel(/Contraseña/i).fill(process.env[account.passwordVariable]);
  diagnostics.phase = 'login-submit';
  await page.getByRole('button', { name: 'Ingresar', exact: true }).click();

  await page.getByRole('heading', { name: 'Panel de control', exact: true }).waitFor({
    state: 'visible',
    timeout: 25000,
  });

  const cookies = await context.cookies(new URL('/api/login/refresh', baseUrl).toString());
  if (!cookies.some((cookie) => cookie.name === 'gestudio_demo_refresh')) {
    throw new Error(`El login de ${account.username} no estableció gestudio_demo_refresh.`);
  }

  diagnostics.authenticated = true;
  diagnostics.phase = 'authenticated';
  await closeBlockingModal(page);
  await page.getByText(account.username, { exact: true }).last().waitFor({ state: 'visible' });
  await page.getByText(account.role, { exact: true }).last().waitFor({ state: 'visible' });
  await settle(page);
}

async function logout(page) {
  const button = page.getByRole('button', { name: 'Cerrar sesión', exact: true });
  await button.waitFor({ state: 'visible', timeout: 10000 });
  await button.click();
  await page.getByRole('heading', { name: 'Iniciar sesión', exact: true }).waitFor({
    state: 'visible',
    timeout: 20000,
  });
}

async function assertUnauthorized(page, route, fileName) {
  await page.goto(new URL(route, baseUrl).toString(), { waitUntil: 'domcontentloaded' });
  await page.getByRole('heading', { name: 'Acceso no autorizado', exact: true }).waitFor({
    state: 'visible',
    timeout: 20000,
  });

  if (!new URL(page.url()).pathname.endsWith('/unauthorized')) {
    throw new Error(`La ruta ${route} no redirigió a /unauthorized.`);
  }

  await screenshot(page, fileName);
}

async function chooseStudent(page, query = 'Sofía') {
  const search = page.getByRole('searchbox').first();
  await search.fill(query);
  const option = page.getByRole('button', { name: /Seleccionar Sofía Benítez/i }).first();
  await option.waitFor({ state: 'visible', timeout: 20000 });
  await option.click();
  await page.getByText('Sofía Benítez', { exact: true }).last().waitFor({ state: 'visible' });
}

try {
  {
    const { context, page } = await makeContext('anonymous');
    await goto(page, '/login', 'Iniciar sesión');
    await screenshot(page, '01-login.png');
    await context.close();
  }

  {
    const { context, page, diagnostics } = await makeContext('secretaria');
    await login(context, page, diagnostics, users.secretaria);
    await screenshot(page, '02-panel-secretaria.png');

    await goto(page, '/alumnos', 'Alumnos');
    await screenshot(page, '03-alumnos-listado.png');

    const studentSearch = page.getByLabel('Buscar', { exact: true });
    await studentSearch.fill('Sofía');
    await page.getByText('Sofía Benítez', { exact: true }).first().waitFor({ state: 'visible' });
    await screenshot(page, '04-alumnos-busqueda.png');

    await studentSearch.fill('zz-manual-sin-resultados-zz');
    await page.getByText('No hay alumnos para mostrar.', { exact: true }).waitFor({ state: 'visible' });
    await screenshot(page, '05-alumnos-sin-resultados.png');

    await goto(page, '/alumnos/formulario', 'Nuevo alumno');
    await screenshot(page, '06-alumno-formulario.png');

    await goto(page, '/inscripciones', 'Inscripciones');
    await screenshot(page, '07-inscripciones-listado.png');

    await goto(page, '/inscripciones/formulario', 'Nueva inscripción');
    await page.getByLabel('Alumno', { exact: true }).fill('Sofía');
    const selectedStudent = page.getByRole('button', { name: /Seleccionar Sofía Benítez/i }).first();
    await selectedStudent.waitFor({ state: 'visible', timeout: 20000 });
    await selectedStudent.click();
    await screenshot(page, '08-inscripcion-formulario.png');

    await goto(page, '/asistencias/alumnos', 'Asistencia diaria');
    await screenshot(page, '09-asistencias.png');

    await goto(page, '/pagos', 'Pagos');
    await chooseStudent(page);
    await page.getByText(/Sofía Benítez/).last().waitFor({ state: 'visible' });
    await screenshot(page, '10-pagos-consulta.png');

    await goto(page, '/pagos/formulario', 'Registrar pago');
    await chooseStudent(page);
    await screenshot(page, '11-cobranza-formulario.png');

    await goto(page, '/caja', 'Caja');
    await page.getByRole('button', { name: 'Consultar', exact: true }).click();
    await page.getByRole('region', { name: 'Resumen de caja' }).waitFor({ state: 'visible', timeout: 20000 });
    await screenshot(page, '12-caja-secretaria.png');

    await goto(page, '/alumnos-por-disciplina', 'Alumnos por Disciplina');
    const disciplineSearch = page.getByLabel(/Selecciona la disciplina/i);
    await disciplineSearch.fill('Ballet Inicial');
    await page.getByText('Ballet Inicial (4 a 6 años)', { exact: true }).click();
    await page.getByText('Sofía Benítez', { exact: true }).first().waitFor({ state: 'visible', timeout: 20000 });
    await screenshot(page, '13-reporte-disciplina.png');

    await assertUnauthorized(page, '/usuarios', '14-no-autorizado-secretaria.png');
    await logout(page);
    await context.close();
  }

  {
    const { context, page, diagnostics } = await makeContext('caja');
    await login(context, page, diagnostics, users.caja);
    await screenshot(page, '15-panel-caja.png');

    await goto(page, '/metodos-pago');
    await screenshot(page, '16-metodos-pago.png');

    await goto(page, '/stocks');
    await screenshot(page, '17-stock.png');

    await goto(page, '/pagos', 'Pagos');
    await goto(page, '/caja', 'Caja');
    await assertUnauthorized(page, '/inscripciones', '32-no-autorizado-caja.png');

    await logout(page);
    await context.close();
  }

  {
    const { context, page, diagnostics } = await makeContext('administrador');
    await login(context, page, diagnostics, users.administrador);

    await goto(page, '/disciplinas', 'Disciplinas');
    await screenshot(page, '18-disciplinas.png');

    const actions = page.getByRole('button', { name: /Acciones de Ballet Inicial \(4 a 6 años\)/i });
    await actions.waitFor({ state: 'visible', timeout: 20000 });
    await actions.click();
    await page.getByRole('menuitem', { name: 'Tarifas', exact: true }).click();
    await page.getByRole('heading', { name: /Tarifas de Ballet Inicial/ }).waitFor({ state: 'visible' });
    await screenshot(page, '19-tarifas.png');

    await goto(page, '/usuarios', 'Usuarios');
    await screenshot(page, '20-usuarios.png');

    await goto(page, '/alumnos-por-disciplina', 'Alumnos por Disciplina');
    await goto(page, '/caja', 'Caja');
    await assertUnauthorized(page, '/roles', '21-no-autorizado-administrador.png');
    await logout(page);
    await context.close();
  }

  {
    const { context, page, diagnostics } = await makeContext('superadmin');
    await login(context, page, diagnostics, users.superadmin);
    await screenshot(page, '31-panel-superadmin.png');

    await goto(page, '/disciplinas', 'Disciplinas');
    const superadminActions = page.getByRole('button', { name: /Acciones de Ballet Inicial \(4 a 6 años\)/i });
    await superadminActions.waitFor({ state: 'visible', timeout: 20000 });
    await superadminActions.click();
    await page.getByRole('menuitem', { name: 'Tarifas', exact: true }).click();
    await page.getByRole('heading', { name: /Tarifas de Ballet Inicial/ }).waitFor({ state: 'visible' });
    await goto(page, '/usuarios', 'Usuarios');
    await goto(page, '/alumnos-por-disciplina', 'Alumnos por Disciplina');
    await goto(page, '/caja', 'Caja');

    await goto(page, '/roles', 'Roles y permisos');
    await screenshot(page, '22-roles.png');

    await goto(page, '/profesores');
    await screenshot(page, '23-profesores.png');

    await goto(page, '/salones');
    await screenshot(page, '24-salones.png');

    await goto(page, '/bonificaciones');
    await screenshot(page, '25-bonificaciones.png');

    await goto(page, '/recargos');
    await screenshot(page, '26-recargos.png');

    await goto(page, '/conceptos');
    await screenshot(page, '27-conceptos.png');

    await goto(page, '/egresos');
    await screenshot(page, '28-egresos.png');

    await logout(page);
    await context.close();
  }

  {
    const { context, page, diagnostics } = await makeContext('direccion');
    await login(context, page, diagnostics, users.direccion);
    await screenshot(page, '29-panel-direccion.png');
    await goto(page, '/disciplinas', 'Disciplinas');
    await goto(page, '/alumnos-por-disciplina', 'Alumnos por Disciplina');
    await goto(page, '/usuarios', 'Usuarios');
    await goto(page, '/caja', 'Caja');
    await assertUnauthorized(page, '/roles', '30-no-autorizado-direccion.png');
    await logout(page);
    await context.close();
  }
} finally {
  await browser.close();
}

const missing = expectedFiles.filter((fileName) => !fs.existsSync(path.join(screenshotDirectory, fileName)));
if (missing.length > 0) {
  throw new Error(`Faltan capturas esperadas: ${missing.join(', ')}`);
}

const responseClassifications = responseEvents.map((event) => ({
  event,
  classification: classifyDiagnosticEvent(event),
}));
const expectedProbeEvents = responseClassifications.filter(
  ({ classification }) => classification?.category === 'expected-anonymous-session-probe',
);
if (expectedProbeEvents.length !== 6) {
  throw new Error(
    `Se esperaban 6 probes anónimos POST /api/login/refresh y se observaron ${expectedProbeEvents.length}.`,
  );
}

const responseProblems = responseClassifications
  .filter(({ classification }) => classification?.fatal)
  .map(({ event }) => event);
const unexpectedConsoleEvents = getUnexpectedConsoleEvents(consoleEvents, responseEvents);
const browserProblems = [
  ...responseProblems,
  ...pageErrorEvents,
  ...requestFailureEvents,
  ...unexpectedConsoleEvents,
];

if (browserProblems.length > 0) {
  throw new Error(`Errores de navegador inesperados:
${browserProblems.map(formatDiagnosticEvent).join('\n')}`);
}
console.log(`Capturas reales completadas: ${expectedFiles.length}.`);

}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
