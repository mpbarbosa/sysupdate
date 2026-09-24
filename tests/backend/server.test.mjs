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

// ---------------------------------------------------------------------------
// sudo askpass relay — stub calls $SUDO_ASKPASS the way sudo would
// ---------------------------------------------------------------------------

async function currentRun() {
  const res = await fetch(`${BASE}/api/runs/current`);
  return (await res.json()).run;
}

async function waitFor(predicate, description, maxMs = 5000) {
  const deadline = Date.now() + maxMs;
  while (Date.now() < deadline) {
    const run = await currentRun();
    if (run && predicate(run)) return run;
    await new Promise((r) => setTimeout(r, 50));
  }
  throw new Error(`timed out waiting for ${description}`);
}

const waitForPrompt = (exceptId) =>
  waitFor(
    (run) => run.sudoPrompt?.status === 'requested' && run.sudoPrompt.requestId !== exceptId,
    `a sudo prompt${exceptId ? ` other than ${exceptId}` : ''}`,
  );

const waitForFinished = () => waitFor((run) => run.status === 'completed' || run.status === 'failed', 'run to finish');

const answerSudo = (body) =>
  fetch(`${BASE}/api/runs/sudo-password`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });

const messages = (run) => run.terminalLines.map((line) => line.text);

describe('sudo askpass relay', { concurrency: false }, () => {
  it('advertises sudo-askpass support on a loopback bind', async () => {
    const res = await fetch(`${BASE}/api/bootstrap`);
    const body = await res.json();
    assert.ok(body.backend.supports.includes('sudo-askpass'));
  });

  it('relays the prompt to the dashboard, re-asks on rejection, answers repeats from cache', async () => {
    const start = await fetch(`${BASE}/api/runs/check-only`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ snippetId: 'sudo' }),
    });
    assert.strictEqual(start.status, 202);

    const first = await waitForPrompt();
    assert.strictEqual(first.sudoPrompt.rejected, false);
    assert.match(first.sudoPrompt.prompt, /Password/);
    assert.ok(!('cachedPassword' in first), 'snapshot must not expose bridge-internal sudo state');

    const answered = await answerSudo({ requestId: first.sudoPrompt.requestId, password: 'hunter2' });
    assert.strictEqual(answered.status, 202);
    const answeredBody = await answered.json();
    assert.strictEqual(answeredBody.run.sudoPrompt.status, 'resolved');

    // The stub's second call comes from the same parent pid: a retry after a
    // wrong password. The bridge must ask again, flagged as rejected.
    const second = await waitForPrompt(first.sudoPrompt.requestId);
    assert.strictEqual(second.sudoPrompt.rejected, true);
    assert.notStrictEqual(second.sudoPrompt.requestId, first.sudoPrompt.requestId);

    await answerSudo({ requestId: second.sudoPrompt.requestId, password: 'correct-horse' });

    const done = await waitForFinished();
    const texts = messages(done);
    assert.ok(texts.includes('askpass-1:hunter2'), `stub should have received the first answer: ${texts.join(' | ')}`);
    assert.ok(texts.includes('askpass-2:correct-horse'), 'stub should have received the second answer');
    assert.ok(texts.includes('askpass-3:correct-horse'), 'a new sudo invocation should be answered from the cache');
    assert.strictEqual(
      texts.filter((text) => text.startsWith('Sudo needs your password') || text.startsWith('Sudo rejected')).length,
      2,
      'the cached answer must not raise a third prompt',
    );

    // The bridge's own lines never carry the password.
    const bridgeLines = done.terminalLines.filter((line) => line.source === 'bridge').map((line) => line.text);
    assert.ok(bridgeLines.length > 0);
    assert.ok(bridgeLines.every((text) => !text.includes('hunter2') && !text.includes('correct-horse')));
  });

  it('cancelling the prompt makes the helper fail like a dismissed askpass', async () => {
    const start = await fetch(`${BASE}/api/runs/check-only`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ snippetId: 'sudo-cancel' }),
    });
    assert.strictEqual(start.status, 202);

    const prompt = await waitForPrompt();
    const res = await answerSudo({ requestId: prompt.sudoPrompt.requestId, cancel: true });
    assert.strictEqual(res.status, 202);

    const done = await waitForFinished();
    assert.ok(messages(done).includes('askpass-1:cancelled'));
    assert.strictEqual(done.sudoPrompt.status, 'cancelled');
  });

  it('rejects a malformed body → 400 and an unknown requestId → 404', async () => {
    const bad = await answerSudo({ requestId: 'sudo-x', password: '' });
    assert.strictEqual(bad.status, 400);
    const unknown = await answerSudo({ requestId: 'sudo-nope', password: 'x' });
    assert.strictEqual(unknown.status, 404);
  });
});

// ---------------------------------------------------------------------------
// POST /api/shutdown — must stay LAST: a successful call exits the server.
// ---------------------------------------------------------------------------

describe('POST /api/shutdown', { concurrency: false }, () => {
  it('refuses to stop the bridge mid-run without force → 409', async () => {
    const start = await fetch(`${BASE}/api/runs/check-only`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ snippetId: 'slow' }),
    });
    assert.strictEqual(start.status, 202);

    const res = await fetch(`${BASE}/api/shutdown`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    assert.strictEqual(res.status, 409);
    const body = await res.json();
    assert.match(body.error, /in progress/);

    // Still alive.
    const health = await fetch(`${BASE}/api/health`);
    assert.strictEqual(health.status, 200);
  });

  it('with force: tells clients, answers 202, stops the run and exits 0', async () => {
    const ws = new WebSocket(`ws://127.0.0.1:${PORT}/ws`);
    const messages = [];
    const wsClosed = new Promise((resolve) => ws.addEventListener('close', resolve));
    await new Promise((resolve, reject) => {
      ws.addEventListener('open', resolve);
      ws.addEventListener('error', reject);
    });
    ws.addEventListener('message', (e) => messages.push(JSON.parse(e.data)));

    const exited = new Promise((resolve) => serverProcess.once('exit', resolve));

    const res = await fetch(`${BASE}/api/shutdown`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ force: true }),
    });
    assert.strictEqual(res.status, 202);
    const body = await res.json();
    assert.strictEqual(body.shuttingDown, true);
    assert.strictEqual(body.runStopped, true);

    const exitCode = await Promise.race([
      exited,
      new Promise((_, reject) => setTimeout(() => reject(new Error('server did not exit within 4s')), 4000)),
    ]);
    assert.strictEqual(exitCode, 0);

    await wsClosed;
    assert.ok(
      messages.some((m) => m.type === 'bridge.shutdown'),
      `expected a bridge.shutdown message, got: ${messages.map((m) => m.type).join(', ')}`,
    );

    await assert.rejects(fetch(`${BASE}/api/health`), 'backend should no longer be listening');
  });
});
