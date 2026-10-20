'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const { loadCaptureAccounts } = require('./manual-accounts.cjs');

const ids = [
  'alpha-presentacion', 'alpha-administrador', 'beta-administrador',
  'alpha-superadmin', 'alpha-direccion', 'alpha-administrador-funcional',
  'alpha-secretaria', 'alpha-caja', 'plataforma-superadmin',
];

function fixture(t, overrides = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'gestudio-manual-accounts-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const documentedPath = path.join(root, 'accounts.json');
  const credentialManifestPath = path.join(root, 'credentials.json');
  const data = { accounts: ids.map((id) => ({
    id, username: `public-${id}`, password: 'public-synthetic-password', profile: 'DOCUMENTED',
  })) };
  const manifest = {
    schemaVersion: 1, composeProject: 'gestudio-demo-local',
    alpha: { username: 'alpha-local', password: 'private-alpha' },
    beta: { username: 'beta-local', password: 'private-beta' },
    platform: { username: 'platform-local', password: 'private-platform', totpSecret: 'SYNTHETICFACTOR' },
    actors: Object.fromEntries([
      'demo-superadmin', 'demo-direccion', 'demo-administrador', 'demo-secretaria', 'demo-caja',
    ].map((name) => [name, `private-${name}`])),
    ...overrides,
  };
  fs.writeFileSync(documentedPath, JSON.stringify(data));
  fs.writeFileSync(credentialManifestPath, JSON.stringify(manifest));
  return { documentedPath, credentialManifestPath, baseUrl: 'http://localhost:18081', data };
}

test('public capture uses only the documented accounts', (t) => {
  const input = fixture(t);
  const result = loadCaptureAccounts({ documentedPath: input.documentedPath });
  assert.equal(result.source, 'PublicDemo');
  assert.deepEqual(result.data, input.data);
});

test('local capture uses private credentials in memory and reports the actual general profile', (t) => {
  const input = fixture(t);
  const before = fs.readFileSync(input.documentedPath, 'utf8');
  const result = loadCaptureAccounts(input);
  const presentation = result.data.accounts.find(({ id }) => id === 'alpha-presentacion');
  assert.equal(result.source, 'LocalMultitenant');
  assert.equal(presentation.username, 'demo-secretaria');
  assert.equal(presentation.profile, 'SECRETARIA');
  assert.equal(presentation.password, 'private-demo-secretaria');
  assert.equal(new Set(result.data.accounts.map(({ username }) => username)).size, 8);
  assert.equal(fs.readFileSync(input.documentedPath, 'utf8'), before);
});

test('local public fixture keeps its read-only presentation profile', (t) => {
  const input = fixture(t, { publicDemo: { username: 'local-presentation', password: 'private-presentation' } });
  const result = loadCaptureAccounts(input);
  const presentation = result.data.accounts[0];
  assert.equal(presentation.profile, 'DEMO_COMERCIAL');
  assert.equal(presentation.username, 'local-presentation');
  assert.equal(new Set(result.data.accounts.map(({ username }) => username)).size, 9);
});

test('private fixture credentials are rejected before reading for every external URL', (t) => {
  const input = fixture(t);
  for (const baseUrl of [
    'https://example.com', 'https://localhost.example.com',
    'http://127.0.0.1.example.com', 'http://localhost@evil.example', 'file:///localhost',
  ]) {
    assert.throws(() => loadCaptureAccounts({ ...input, baseUrl }), /sólo pueden utilizarse en una URL local/);
  }
});

test('foreign or incomplete manifests fail without disclosing their contents', (t) => {
  const input = fixture(t, { composeProject: 'production', password: 'DO-NOT-DISCLOSE' });
  assert.throws(() => loadCaptureAccounts(input), (error) =>
    !error.message.includes('DO-NOT-DISCLOSE') && /no pertenece/.test(error.message));
});
