'use strict';

const fs = require('node:fs');

function loadCaptureAccounts({ documentedPath, credentialManifestPath, baseUrl }) {
  const data = JSON.parse(fs.readFileSync(documentedPath, 'utf8').replace(/^\uFEFF/, ''));
  if (!Array.isArray(data.accounts) || data.accounts.length !== 9) {
    throw new Error('La fuente del manual debe declarar exactamente nueve cuentas demo.');
  }

  if (!credentialManifestPath) return { data, source: 'PublicDemo' };

  const target = new URL(baseUrl);
  if (!['http:', 'https:'].includes(target.protocol)
      || !['localhost', '127.0.0.1', '[::1]'].includes(target.hostname)
      || target.username || target.password) {
    throw new Error('Las credenciales privadas del fixture sólo pueden utilizarse en una URL local.');
  }

  let manifest;
  try {
    manifest = JSON.parse(fs.readFileSync(credentialManifestPath, 'utf8').replace(/^\uFEFF/, ''));
  } catch {
    throw new Error('No se pudo leer el manifiesto privado del fixture multiorganización.');
  }
  if (manifest.schemaVersion !== 1 || manifest.composeProject !== 'gestudio-demo-local') {
    throw new Error('El manifiesto no pertenece al fixture multiorganización local esperado.');
  }

  const actor = (name) => ({ username: name, password: manifest.actors?.[name] });
  const publicAccount = manifest.publicDemo;
  const presentation = publicAccount?.username && publicAccount.password
    ? { username: publicAccount.username, password: publicAccount.password, profile: 'DEMO_COMERCIAL' }
    : { ...actor('demo-secretaria'), profile: 'SECRETARIA' };
  const overrides = {
    'alpha-presentacion': presentation,
    'alpha-administrador': manifest.alpha,
    'beta-administrador': manifest.beta,
    'alpha-superadmin': actor('demo-superadmin'),
    'alpha-direccion': actor('demo-direccion'),
    'alpha-administrador-funcional': actor('demo-administrador'),
    'alpha-secretaria': actor('demo-secretaria'),
    'alpha-caja': actor('demo-caja'),
    'plataforma-superadmin': manifest.platform,
  };

  data.accounts = data.accounts.map((account) => {
    const replacement = overrides[account.id];
    if (!replacement || typeof replacement.username !== 'string' || !replacement.username
        || typeof replacement.password !== 'string' || !replacement.password) {
      throw new Error('El manifiesto privado no contiene todas las cuentas requeridas para las capturas.');
    }
    const effective = {
      ...account,
      username: replacement.username,
      password: replacement.password,
      profile: replacement.profile || account.profile,
    };
    if (account.id === 'plataforma-superadmin') {
      if (typeof replacement.totpSecret !== 'string' || !replacement.totpSecret) {
        throw new Error('El manifiesto privado no contiene el segundo factor de plataforma.');
      }
      effective.totpSecret = replacement.totpSecret;
    }
    return effective;
  });

  return { data, source: 'LocalMultitenant' };
}

module.exports = { loadCaptureAccounts };
