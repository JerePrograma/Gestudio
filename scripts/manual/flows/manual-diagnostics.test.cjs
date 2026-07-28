'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {
  classifyDiagnosticEvent,
  getUnexpectedConsoleEvents,
  isExpectedAnonymousSessionProbe,
} = require('./manual-diagnostics.cjs');

const expectedProbe = {
  kind: 'response',
  scope: 'secretaria',
  phase: 'before-login',
  authenticated: false,
  status: 401,
  method: 'POST',
  pathname: '/api/login/refresh',
};

test('el probe anónimo contractual exacto no es fatal', () => {
  assert.equal(isExpectedAnonymousSessionProbe(expectedProbe), true);
  assert.deepEqual(classifyDiagnosticEvent(expectedProbe), {
    fatal: false,
    category: 'expected-anonymous-session-probe',
  });

  const consoleEvent = {
    kind: 'console',
    type: 'error',
    text: 'Failed to load resource: the server responded with a status of 401 ()',
    scope: expectedProbe.scope,
    phase: expectedProbe.phase,
  };
  assert.deepEqual(getUnexpectedConsoleEvents([consoleEvent], [expectedProbe]), []);
});

test('el mismo endpoint con 401 después del login es fatal', () => {
  const result = classifyDiagnosticEvent({
    ...expectedProbe,
    phase: 'authenticated',
    authenticated: true,
  });
  assert.equal(result.fatal, true);
});

test('otro endpoint con 401 sigue siendo fatal', () => {
  const result = classifyDiagnosticEvent({
    ...expectedProbe,
    pathname: '/api/alumnos',
  });
  assert.equal(result.fatal, true);
});

test('un 403 no queda oculto', () => {
  const result = classifyDiagnosticEvent({
    ...expectedProbe,
    status: 403,
  });
  assert.equal(result.fatal, true);
});

test('un 500 sigue siendo fatal', () => {
  const result = classifyDiagnosticEvent({
    ...expectedProbe,
    status: 500,
  });
  assert.equal(result.fatal, true);
});

test('un pageerror sigue siendo fatal', () => {
  const result = classifyDiagnosticEvent({
    kind: 'pageerror',
    scope: 'secretaria',
    phase: 'authenticated',
    message: 'boom',
  });
  assert.equal(result.fatal, true);
});

test('un requestfailed real sigue siendo fatal', () => {
  const result = classifyDiagnosticEvent({
    kind: 'requestfailed',
    scope: 'secretaria',
    phase: 'authenticated',
    method: 'GET',
    url: 'http://localhost:18080/api/alumnos',
    failure: 'net::ERR_CONNECTION_REFUSED',
  });
  assert.equal(result.fatal, true);
});

test('los mensajes normales de consola no son errores', () => {
  assert.equal(
    classifyDiagnosticEvent({
      kind: 'console',
      scope: 'secretaria',
      phase: 'authenticated',
      type: 'log',
      text: 'ok',
    }),
    null,
  );
});

test('un error HTTP de consola sin respuesta correlacionada sigue siendo fatal', () => {
  const consoleEvent = {
    kind: 'console',
    type: 'error',
    text: 'Failed to load resource: the server responded with a status of 401 ()',
    scope: 'secretaria',
    phase: 'authenticated',
  };
  assert.deepEqual(getUnexpectedConsoleEvents([consoleEvent], []), [consoleEvent]);
});