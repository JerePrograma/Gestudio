'use strict';

const HTTP_RESOURCE_CONSOLE_PATTERN =
  /^Failed to load resource: the server responded with a status of (?<status>[1-5][0-9]{2}) \((?<reason>.*)\)$/;

function isExpectedAnonymousSessionProbe(event) {
  return (
    event.kind === 'response' &&
    event.phase === 'before-login' &&
    event.authenticated === false &&
    event.status === 401 &&
    event.method === 'POST' &&
    event.pathname === '/api/login/refresh'
  );
}

function classifyDiagnosticEvent(event) {
  switch (event.kind) {
    case 'response':
      if (event.status < 400) {
        return null;
      }
      if (isExpectedAnonymousSessionProbe(event)) {
        return { fatal: false, category: 'expected-anonymous-session-probe' };
      }
      return { fatal: true, category: 'http-response' };
    case 'pageerror':
      return { fatal: true, category: 'pageerror' };
    case 'requestfailed':
      return { fatal: true, category: 'requestfailed' };
    case 'console':
      return event.type === 'error' ? { fatal: true, category: 'console' } : null;
    default:
      throw new Error(`Tipo de diagnóstico desconocido: ${event.kind}`);
  }
}

function responseConsoleKey(event, status) {
  return `${event.scope}\u0000${event.phase}\u0000${status}`;
}

function getUnexpectedConsoleEvents(consoleEvents, responseEvents) {
  const availableResponses = new Map();

  for (const response of responseEvents) {
    if (response.status < 400) {
      continue;
    }
    const key = responseConsoleKey(response, response.status);
    availableResponses.set(key, (availableResponses.get(key) || 0) + 1);
  }

  return consoleEvents.filter((event) => {
    const classification = classifyDiagnosticEvent(event);
    if (!classification?.fatal) {
      return false;
    }

    const match = HTTP_RESOURCE_CONSOLE_PATTERN.exec(event.text);
    if (!match) {
      return true;
    }

    const status = Number(match.groups.status);
    const key = responseConsoleKey(event, status);
    const available = availableResponses.get(key) || 0;
    if (available === 0) {
      return true;
    }

    availableResponses.set(key, available - 1);
    return false;
  });
}

function formatDiagnosticEvent(event) {
  switch (event.kind) {
    case 'response':
      return `${event.scope}: ${event.method} ${event.pathname} -> ${event.status} (phase=${event.phase}, authenticated=${event.authenticated})`;
    case 'pageerror':
      return `${event.scope}: pageerror (phase=${event.phase}) - ${event.message}`;
    case 'requestfailed':
      return `${event.scope}: ${event.method} ${event.url} (phase=${event.phase}) - ${event.failure}`;
    case 'console':
      return `${event.scope}: console.${event.type} (phase=${event.phase}) - ${event.text}`;
    default:
      throw new Error(`Tipo de diagnóstico desconocido: ${event.kind}`);
  }
}

module.exports = {
  classifyDiagnosticEvent,
  formatDiagnosticEvent,
  getUnexpectedConsoleEvents,
  isExpectedAnonymousSessionProbe,
};