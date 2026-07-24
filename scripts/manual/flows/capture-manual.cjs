'use strict';

const { chromium } = require('playwright');
const path = require('node:path');
const fs = require('node:fs');

async function main() {
const baseUrl = process.env.MANUAL_BASE_URL;
const screenshotDirectory = process.env.MANUAL_SCREENSHOT_DIRECTORY;
const headed = process.env.MANUAL_HEADED === '1';

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

const browser = await chromium.launch({
  headless: !headed,
});

const consoleProblems = [];
const requestProblems = [];

function attachDiagnostics(page, scope) {
  page.on('console', (message) => {
    if (message.type() === 'error') {
      consoleProblems.push(`${scope}: ${message.text()}`);
    }
  });

  page.on('requestfailed', (request) => {
    requestProblems.push(`${scope}: ${request.method()} ${request.url()} - ${request.failure()?.errorText || 'falló'}`);
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

  const page = await context.newPage();
  attachDiagnostics(page, scope);
  return { context, page };
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
  await settle(page);
  await page.screenshot({
    path: path.join(screenshotDirectory, fileName),
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

async function login(page, account) {
  await goto(page, '/login', 'Iniciar sesión');
  await page.getByLabel(/Nombre de Usuario/i).fill(account.username);
  await page.getByLabel(/Contraseña/i).fill(process.env[account.passwordVariable]);
  await page.getByRole('button', { name: 'Ingresar', exact: true }).click();

  await page.getByRole('heading', { name: 'Panel de control', exact: true }).waitFor({
    state: 'visible',
    timeout: 25000,
  });

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
    const { context, page } = await makeContext('secretaria');
    await login(page, users.secretaria);
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
    const { context, page } = await makeContext('caja');
    await login(page, users.caja);
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
    const { context, page } = await makeContext('administrador');
    await login(page, users.administrador);

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
    const { context, page } = await makeContext('superadmin');
    await login(page, users.superadmin);
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
    const { context, page } = await makeContext('direccion');
    await login(page, users.direccion);
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

const unexpectedConsole = consoleProblems.filter((line) => !line.includes('/api/login/refresh'));
if (unexpectedConsole.length > 0) {
  throw new Error(`Errores de consola inesperados:\n${unexpectedConsole.join('\n')}`);
}

if (requestProblems.length > 0) {
  throw new Error(`Solicitudes de red fallidas:\n${requestProblems.join('\n')}`);
}

console.log(`Capturas reales completadas: ${expectedFiles.length}.`);

}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
