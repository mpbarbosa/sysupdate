/**
 * Integration tests for the sysupdate backend bridge (web/backend/server.js).
 *
 * Spawns the real server on a test port with a stub script so no system
 * mutations occur. Uses Node's built-in test runner (node:test) and global
 * fetch (Node 22+).
 *
 * Run from repo root: node --test tests/backend/server.test.mjs
 */

import { before, after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { chmodSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, '../..');
const SERVER_PATH = path.join(REPO_ROOT, 'web', 'backend', 'server.js');
const STUB_SCRIPT = path.join(__dirname, 'fixtures', 'stub_script.sh');
const PORT = 14174;
const BASE = `http://127.0.0.1:${PORT}`;

let serverProcess;

async function waitForServer(maxMs = 8000) {
  const deadline = Date.now() + maxMs;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(`${BASE}/api/health`);
      if (res.ok) return;
    } catch {
      // not ready yet
    }
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error('Backend server did not start within the timeout');
}

before(async () => {
  chmodSync(STUB_SCRIPT, 0o755);

  serverProcess = spawn('node', [SERVER_PATH], {
    env: {
      ...process.env,
      SYSUPDATE_WEB_PORT: String(PORT),
      SYSUPDATE_SCRIPT_PATH: STUB_SCRIPT,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  await waitForServer();
});

after(() => {
  serverProcess?.kill('SIGTERM');
});

// ---------------------------------------------------------------------------
// GET /api/health
// ---------------------------------------------------------------------------

describe('GET /api/health', { concurrency: false }, () => {
  it('returns 200 with ok status', async () => {
    const res = await fetch(`${BASE}/api/health`);
    assert.strictEqual(res.status, 200);
    const body = await res.json();
    assert.strictEqual(body.status, 'ok');
    assert.strictEqual(body.backend, 'sysupdate-local-bridge');
  });

  it('includes scriptPath pointing to stub', async () => {
    const res = await fetch(`${BASE}/api/health`);
    const body = await res.json();
    assert.strictEqual(body.scriptPath, STUB_SCRIPT);
  });
});

// ---------------------------------------------------------------------------
// GET /api/bootstrap
// ---------------------------------------------------------------------------

describe('GET /api/bootstrap', { concurrency: false }, () => {
  it('returns 200 with required structure', async () => {
    const res = await fetch(`${BASE}/api/bootstrap`);
    assert.strictEqual(res.status, 200);
    const body = await res.json();
    assert.ok(Array.isArray(body.logs), 'logs should be an array');
    assert.ok('run' in body, 'body should have a run property');
    assert.ok('backend' in body, 'body should have a backend property');
  });

  it('backend.name is sysupdate-local-bridge', async () => {
    const res = await fetch(`${BASE}/api/bootstrap`);
    const body = await res.json();
    assert.strictEqual(body.backend.name, 'sysupdate-local-bridge');
  });
});

// ---------------------------------------------------------------------------
// GET /api/logs
// ---------------------------------------------------------------------------

describe('GET /api/logs', { concurrency: false }, () => {
  it('returns 200 with logs array', async () => {
    const res = await fetch(`${BASE}/api/logs`);
    assert.strictEqual(res.status, 200);
    const body = await res.json();
    assert.ok(Array.isArray(body.logs));
  });
});

// ---------------------------------------------------------------------------
// GET /api/runs/current (no active run)
// ---------------------------------------------------------------------------

describe('GET /api/runs/current', { concurrency: false }, () => {
  it('returns 200 with null run when idle', async () => {
    const res = await fetch(`${BASE}/api/runs/current`);
    assert.strictEqual(res.status, 200);
    const body = await res.json();
    assert.ok('run' in body);
    // null when nothing is running
    assert.equal(body.run, null);
  });
});

// ---------------------------------------------------------------------------
// Input validation
// ---------------------------------------------------------------------------

describe('POST /api/runs/check-only — validation', { concurrency: false }, () => {
  it('rejects snippetId with spaces → 400', async () => {
    const res = await fetch(`${BASE}/api/runs/check-only`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ snippetId: 'bad snippet' }),
    });
    assert.strictEqual(res.status, 400);
    const body = await res.json();
    assert.ok(body.error);
  });

  it('rejects snippetId with path traversal → 400', async () => {
    const res = await fetch(`${BASE}/api/runs/check-only`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ snippetId: '../etc/passwd' }),
    });
    assert.strictEqual(res.status, 400);
  });
});

describe('POST /api/runs/upgrade — validation', { concurrency: false }, () => {
  it('rejects missing snippetId → 400', async () => {
    const res = await fetch(`${BASE}/api/runs/upgrade`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    assert.strictEqual(res.status, 400);
    const body = await res.json();
    assert.ok(body.error);
  });
});

// ---------------------------------------------------------------------------
// Unknown route
// ---------------------------------------------------------------------------

describe('unknown route', { concurrency: false }, () => {
  it('returns 404', async () => {
    const res = await fetch(`${BASE}/api/does-not-exist`);
    assert.strictEqual(res.status, 404);
  });
});

// ---------------------------------------------------------------------------
// WebSocket — connected message
// ---------------------------------------------------------------------------

describe('WebSocket /ws', { concurrency: false }, () => {
  it('sends connected message on connection', async () => {
    const ws = new WebSocket(`ws://127.0.0.1:${PORT}/ws`);
    const msg = await new Promise((resolve, reject) => {
      ws.addEventListener('message', (e) => resolve(e.data));
      ws.addEventListener('error', reject);
      setTimeout(() => reject(new Error('WebSocket message timeout')), 3000);
    });
    ws.close();
    const parsed = JSON.parse(msg);
    assert.strictEqual(parsed.type, 'connected');
    assert.ok(parsed.payload);
  });
});

// ---------------------------------------------------------------------------
// POST /api/runs/check-only — starts a run with stub script
// ---------------------------------------------------------------------------

describe('POST /api/runs/check-only — stub run', { concurrency: false }, () => {
  it('returns 202 with a run snapshot', async () => {
    const res = await fetch(`${BASE}/api/runs/check-only`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    assert.strictEqual(res.status, 202);
    const body = await res.json();
    assert.ok(body.run, 'response should have a run object');
    assert.ok(body.run.id, 'run should have an id');
    assert.ok(['starting', 'running', 'completed'].includes(body.run.status));

    // Wait for run to complete before next test
    await new Promise((r) => setTimeout(r, 800));
  });
});
