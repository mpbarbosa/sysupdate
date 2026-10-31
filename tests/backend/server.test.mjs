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
import { chmodSync, readdirSync, readFileSync } from 'node:fs';
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

describe('raw output flood', { concurrency: false }, () => {
  it('keeps line ids unique once the terminal buffer starts trimming', async () => {
    const start = await fetch(`${BASE}/api/runs/check-only`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ snippetId: 'flood' }),
    });
    assert.strictEqual(start.status, 202);

    const run = await waitForFinished();
    const raw = run.terminalLines.filter((line) => line.text.startsWith('build-line-'));
    assert.strictEqual(raw.at(-1).text, 'build-line-700');
    assert.ok(raw.every((line) => line.type === 'dim'), 'plain tool output should be dimmed');
    const ids = run.terminalLines.map((line) => line.id);
    assert.strictEqual(new Set(ids).size, ids.length, 'line ids must be unique');
  });
});

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
// Run controls — pause/resume/stop signal the CLI's whole process group
// ---------------------------------------------------------------------------

const postControl = (route) => fetch(`${BASE}/api/runs/${route}`, { method: 'POST' });

const waitForSettled = () =>
  waitFor(
    (run) => run.status === 'completed' || run.status === 'failed' || run.status === 'stopped',
    'run to settle',
  );

/** Linux process state letter from /proc/<pid>/stat — 'T' once SIGSTOP lands. */
function processState(pid) {
  // The comm field can contain spaces and parentheses; state is the first
  // field after the closing paren.
  const stat = readFileSync(`/proc/${pid}/stat`, 'utf8');
  return stat.slice(stat.lastIndexOf(')') + 2).split(' ')[0];
}

function childPidsOf(parentPid) {
  return readdirSync('/proc')
    .filter((entry) => /^\d+$/.test(entry))
    .filter((entry) => {
      try {
        const stat = readFileSync(`/proc/${entry}/stat`, 'utf8');
        return Number(stat.slice(stat.lastIndexOf(')') + 2).split(' ')[1]) === parentPid;
      } catch {
        return false;
      }
    })
    .map(Number);
}

/** comm (the executable name) from /proc/<pid>/stat, or null once it is gone. */
function commOf(pid) {
  try {
    const stat = readFileSync(`/proc/${pid}/stat`, 'utf8');
    return stat.slice(stat.indexOf('(') + 1, stat.lastIndexOf(')'));
  } catch {
    return null;
  }
}

/**
 * The stub's `sleep` children specifically. Plain childPidsOf is not enough:
 * the stub opens with a `cat` heredoc, so "bash has a child" is true for a few
 * milliseconds for a reason that has nothing to do with the run being slow.
 */
const sleepChildrenOf = (parentPid) =>
  childPidsOf(parentPid).filter((pid) => commOf(pid) === 'sleep');

/**
 * Poll a synchronous predicate until it holds. The waitFor above watches run
 * state as the bridge reports it over HTTP; this one watches the OS directly,
 * for facts the bridge never reports — a grandchild being forked, a process
 * reaching state 'T'. Both are needed: a 202 from a control route means the
 * signal was sent, not that the kernel has already acted on it.
 */
async function waitUntil(predicate, description, maxMs = 5000) {
  const deadline = Date.now() + maxMs;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await new Promise((r) => setTimeout(r, 25));
  }
  throw new Error(`timed out waiting for ${description}`);
}

async function startSlowRun() {
  const res = await fetch(`${BASE}/api/runs/check-only`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ snippetId: 'slow' }),
  });
  assert.strictEqual(res.status, 202);
  const run = await waitFor((r) => r.status === 'running', 'the slow run to report running');

  // `running` is set when the bridge spawns Bash, before the stub has run a
  // line, so the `sleep` this run is named for may not exist yet. Waiting for
  // it keeps two tests honest: the pause test would otherwise race the fork,
  // and the stop test's "no child survived" would pass vacuously against a run
  // that never had a child to lose.
  if (process.platform === 'linux') {
    await waitUntil(
      () => sleepChildrenOf(run.pid).length > 0,
      "the slow stub's sleep child to be forked",
    );
  }
  return run;
}

describe('run controls — idle bridge', { concurrency: false }, () => {
  it('refuses pause, resume and stop with no run in progress → 409', async () => {
    for (const route of ['pause', 'resume', 'stop']) {
      const res = await postControl(route);
      assert.strictEqual(res.status, 409, `${route} should be 409 when idle`);
      assert.match((await res.json()).error, /no sysupdate run is in progress/i);
    }
  });
});

describe('POST /api/runs/pause and /resume', { concurrency: false }, () => {
  it('suspends the whole process group and resumes it', async () => {
    const started = await startSlowRun();

    const paused = await postControl('pause');
    assert.strictEqual(paused.status, 202);
    assert.strictEqual((await paused.json()).run.status, 'paused');

    const snapshot = await currentRun();
    assert.strictEqual(snapshot.status, 'paused');
    assert.ok(snapshot.pausedAt, 'a paused run should carry pausedAt');
    assert.ok(
      messages(snapshot).some((text) => text.includes('Run paused')),
      'the pause should be reported in the terminal',
    );

    // The point of the detached process group: the CLI's children are
    // suspended too, not just the Bash process the bridge spawned.
    if (process.platform === 'linux') {
      await waitUntil(() => processState(started.pid) === 'T', 'the CLI process to be stopped');
      const children = sleepChildrenOf(started.pid);
      assert.ok(children.length > 0, 'the slow stub should have a sleep child');
      for (const child of children) {
        await waitUntil(() => processState(child) === 'T', `child ${child} to be stopped too`);
      }
    }

    // Pausing twice is idempotent rather than an error.
    const again = await postControl('pause');
    assert.strictEqual(again.status, 200);
    assert.strictEqual((await again.json()).run.status, 'paused');

    const resumed = await postControl('resume');
    assert.strictEqual(resumed.status, 202);
    assert.strictEqual((await resumed.json()).run.status, 'running');
    assert.strictEqual((await currentRun()).pausedAt, null);
    if (process.platform === 'linux') {
      await waitUntil(() => processState(started.pid) !== 'T', 'the CLI process to be running again');
    }

    // Resuming a run that is not paused is a no-op, not a 409.
    const noop = await postControl('resume');
    assert.strictEqual(noop.status, 200);

    await postControl('stop');
    await waitForSettled();
  });
});

describe('POST /api/runs/stop', { concurrency: false }, () => {
  it('interrupts the run and reports stopped rather than failed', async () => {
    const started = await startSlowRun();

    const res = await postControl('stop');
    assert.strictEqual(res.status, 202);

    const settled = await waitForSettled();
    assert.strictEqual(settled.status, 'stopped', 'a requested interrupt is not a failure');
    assert.ok(settled.completedAt, 'a stopped run should be timestamped');
    assert.ok(
      messages(settled).some((text) => text.includes('Stop requested')),
      'the stop should be reported in the terminal',
    );
    // SIGTERM reached the group, so the stub never got to emit run.completed.
    assert.ok(
      !messages(settled).some((text) => text.includes('build-line-')),
      'the interrupted run should not have continued',
    );

    if (process.platform === 'linux') {
      await waitUntil(
        () => childPidsOf(started.pid).length === 0,
        'no child of the CLI to survive the stop',
      );
    }
  });

  it('stops a paused run, which cannot act on SIGTERM until it is woken', async () => {
    await startSlowRun();
    assert.strictEqual((await postControl('pause')).status, 202);

    const res = await postControl('stop');
    assert.strictEqual(res.status, 202);

    const settled = await waitForSettled();
    assert.strictEqual(settled.status, 'stopped');
  });

  it('is refused once the run has already settled → 409', async () => {
    const res = await postControl('stop');
    assert.strictEqual(res.status, 409);
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
