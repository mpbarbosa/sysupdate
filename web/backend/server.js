import { spawn } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { WebSocketServer } from 'ws';
import {
  mapTerminalType,
  stripAnsi,
  trimArray,
  sanitizeSnippetId,
  isLoopbackHost,
  shellQuote,
  parseSudoPasswordRequest,
} from './utils.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const WEB_DIR = path.resolve(__dirname, '..');
const REPO_ROOT = path.resolve(WEB_DIR, '..');
const SCRIPT_PATH = process.env.SYSUPDATE_SCRIPT_PATH ?? path.resolve(REPO_ROOT, 'scripts', 'system_update.sh');

const HOST = process.env.SYSUPDATE_WEB_HOST ?? '127.0.0.1';
const PORT = Number(process.env.SYSUPDATE_WEB_PORT ?? '4174');
const DEFAULT_LOG_LIMIT = Number(process.env.SYSUPDATE_LOG_LIMIT ?? '50');
const MAX_TERMINAL_LINES = 600;
const MAX_RAW_EVENTS = 1200;
// wget dot-progress lines, e.g. "52500K .......... 18% 21,3M 26s". A large
// download under a piped (non-TTY) child can emit thousands of these on stderr;
// they carry no signal and would flood the terminal buffer and event stream.
// Snippets prefer -nv when non-interactive (download_with_progress); this is a
// defense-in-depth net for any tool that still emits progress dots.
const PROGRESS_LINE_RE = /^\s*\d+[KMG][ .]+\d+%/;
const LOG_FILE =
  process.env.SYSUPDATE_LOG_FILE ??
  path.join(process.env.XDG_STATE_HOME ?? path.join(os.homedir(), '.local', 'state'), 'sysupdate', 'run-history.jsonl');
// The child CLI has no terminal, so sudo cannot prompt for a password itself.
// The bridge hands it a SUDO_ASKPASS helper (sudo_askpass.mjs) that relays the
// prompt over a unix socket; the bridge shows it on the dashboard and passes
// the answer back. Passwords travel over the dashboard's plain HTTP connection,
// so the relay is only enabled on a loopback bind (or turned off explicitly).
const SUDO_RELAY_ENABLED = isLoopbackHost(HOST) && process.env.SYSUPDATE_SUDO_RELAY !== 'false';
const ASKPASS_HELPER_SCRIPT = path.join(__dirname, 'sudo_askpass.mjs');
const SUDO_REQUEST_MAX_BYTES = 4096;

const clients = new Set();
const snippetIdByModule = new Map();

let activeChild = null;
let currentRun = null;
let shuttingDown = false;
// { dir, socketPath, helperPath, server } once listening; null when disabled.
let askpassRelay = null;

function setCorsHeaders(response) {
  response.setHeader('Access-Control-Allow-Origin', `http://${HOST}:5173`);
  response.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  response.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

function sendJson(response, statusCode, payload) {
  response.statusCode = statusCode;
  response.setHeader('Content-Type', 'application/json; charset=utf-8');
  setCorsHeaders(response);
  response.end(JSON.stringify(payload));
}

function createRunState(args) {
  return {
    id: `bridge-${Date.now()}`,
    status: 'starting',
    args,
    command: `${SCRIPT_PATH} ${args.join(' ')}`,
    startedAt: new Date().toISOString(),
    completedAt: null,
    exitCode: null,
    pid: null,
    runId: null,
    prompt: null,
    lastLogEntry: null,
    // The dashboard-facing view of the latest sudo prompt (never the password).
    sudoPrompt: null,
    terminalLines: [],
    rawEvents: [],
    summariesByKey: {},
    // In-memory only, wiped when the child exits. `answeredPids` records which
    // sudo invocations already got `cachedPassword`: the same one asking again
    // means it was rejected.
    sudo: {
      cachedPassword: null,
      answeredPids: new Set(),
      pending: new Map(),
      sequence: 0,
    },
  };
}

function isRunActive(run) {
  return run !== null && (run.status === 'starting' || run.status === 'running');
}

function resolveSnippetIdFromModule(moduleName) {
  if (typeof moduleName !== 'string' || moduleName.length === 0) {
    return null;
  }

  if (snippetIdByModule.has(moduleName)) {
    return snippetIdByModule.get(moduleName);
  }

  const modulePath = path.resolve(REPO_ROOT, 'scripts', 'upgrade_snippets', moduleName);
  let snippetId = null;

  if (existsSync(modulePath)) {
    const fileContent = readFileSync(modulePath, 'utf8');
    const match = fileContent.match(/^# SNIPPET_ID:\s*([a-zA-Z0-9._-]+)/m);
    if (match) {
      snippetId = match[1];
    }
  }

  snippetIdByModule.set(moduleName, snippetId);
  return snippetId;
}

function createPromptInputFile(response = 'y') {
  const tempDir = mkdtempSync(path.join(os.tmpdir(), 'sysupdate-web-'));
  const promptInputPath = path.join(tempDir, 'prompt-input.txt');
  writeFileSync(promptInputPath, `${response}\n`, 'utf8');
  return { tempDir, promptInputPath };
}

function getRunSnapshot() {
  if (!currentRun) {
    return null;
  }

  return {
    id: currentRun.id,
    status: currentRun.status,
    args: currentRun.args,
    command: currentRun.command,
    startedAt: currentRun.startedAt,
    completedAt: currentRun.completedAt,
    exitCode: currentRun.exitCode,
    pid: currentRun.pid,
    runId: currentRun.runId,
    prompt: currentRun.prompt,
    lastLogEntry: currentRun.lastLogEntry,
    sudoPrompt: currentRun.sudoPrompt,
    terminalLines: currentRun.terminalLines,
    summaries: Object.values(currentRun.summariesByKey),
  };
}

function broadcast(message) {
  const serialized = JSON.stringify(message);

  for (const client of clients) {
    if (client.readyState === client.OPEN) {
      client.send(serialized);
    }
  }
}

function broadcastSnapshot(reason) {
  broadcast({
    type: 'snapshot',
    reason,
    payload: getRunSnapshot(),
  });
}

// All output/lifecycle writes are bound to the run that produced them (`run`),
// not the global `currentRun`. Runs can overlap at the edges — a finishing
// child's stream can still emit lines (and fire `close`) after the next run has
// become current — and writing to `currentRun` in that window corrupts the new
// run's buffer. Defaulting to `currentRun` keeps bridge-originated callers working.
function addTerminalLine(text, type, source = 'bridge', run = currentRun) {
  if (!run) {
    return;
  }

  run.terminalLines = trimArray(
    [
      ...run.terminalLines,
      {
        id: `${run.id}-line-${run.terminalLines.length + 1}`,
        text,
        type,
        source,
      },
    ],
    MAX_TERMINAL_LINES,
  );
}

function storeRawEvent(event, run = currentRun) {
  if (!run) {
    return;
  }

  run.rawEvents = trimArray([...run.rawEvents, event], MAX_RAW_EVENTS);
}

function handleCliEvent(event, run = currentRun) {
  if (!run) {
    return;
  }

  const snippetId = resolveSnippetIdFromModule(event.module);
  const enrichedEvent =
    snippetId && !event.snippet_id
      ? {
          ...event,
          snippet_id: snippetId,
        }
      : event;

  storeRawEvent(enrichedEvent, run);

  switch (enrichedEvent.event_type) {
    case 'run.started':
      run.status = 'running';
      run.runId = enrichedEvent.run_id ?? run.runId;
      break;
    case 'terminal.line':
      addTerminalLine(enrichedEvent.message ?? '', mapTerminalType(enrichedEvent.line_type), enrichedEvent.source ?? 'cli', run);
      break;
    case 'summary.updates': {
      const key = `${enrichedEvent.summary_name ?? 'summary'}:${enrichedEvent.target ?? enrichedEvent.package_manager ?? 'global'}`;
      run.summariesByKey[key] = enrichedEvent;
      break;
    }
    case 'prompt.requested':
      run.prompt = {
        status: 'requested',
        promptType: enrichedEvent.prompt_type ?? 'unknown',
        message: enrichedEvent.prompt_message ?? '',
        defaultResponse: enrichedEvent.default_response ?? '',
        options: enrichedEvent.options ?? '',
      };
      break;
    case 'prompt.resolved':
      run.prompt = {
        status: 'resolved',
        promptType: enrichedEvent.prompt_type ?? 'unknown',
        message: enrichedEvent.prompt_message ?? '',
        defaultResponse: enrichedEvent.default_response ?? '',
        response: enrichedEvent.response ?? '',
        responseSource: enrichedEvent.response_source ?? '',
      };
      break;
    case 'run.completed':
      run.status = 'completed';
      run.completedAt = enrichedEvent.timestamp ?? new Date().toISOString();
      run.exitCode = Number(enrichedEvent.exit_code ?? 0);
      break;
    case 'run.failed':
      run.status = 'failed';
      run.completedAt = enrichedEvent.timestamp ?? new Date().toISOString();
      run.exitCode = Number(enrichedEvent.exit_code ?? 1);
      break;
    case 'log.entry':
      run.lastLogEntry = enrichedEvent;
      break;
    default:
      break;
  }

  // Only the active run drives the live view; late events from a superseded run
  // update its own (now historical) state without disturbing the current run.
  if (run === currentRun) {
    broadcast({ type: 'cli.event', payload: enrichedEvent });
    broadcastSnapshot(enrichedEvent.event_type);
  }
}

function processOutputLine(line, streamName, run = currentRun) {
  if (!run) {
    return;
  }

  const cleaned = stripAnsi(line).trimEnd();
  if (!cleaned) {
    return;
  }

  // Drop download progress-dot lines outright — high volume, zero signal.
  if (PROGRESS_LINE_RE.test(cleaned)) {
    return;
  }

  if (streamName === 'stdout' && run.args.includes('--json-events')) {
    return;
  }

  if (streamName === 'stderr') {
    try {
      const parsed = JSON.parse(cleaned);
      if (parsed && typeof parsed === 'object' && 'event_type' in parsed) {
        handleCliEvent(parsed, run);
        return;
      }
    } catch {
      // Non-JSON stderr lines are forwarded as bridge output below.
    }
  }

  addTerminalLine(cleaned, streamName === 'stderr' ? 'error' : 'output', streamName, run);
  if (run === currentRun) {
    broadcast({
      type: `${streamName}.line`,
      payload: { text: cleaned },
    });
    broadcastSnapshot(`${streamName}.line`);
  }
}

// ---------------------------------------------------------------------------
// sudo askpass relay
// ---------------------------------------------------------------------------

function replyToAskpass(socket, password) {
  try {
    socket.end(`${JSON.stringify(password === null ? { cancelled: true } : { password })}\n`);
  } catch {
    socket.destroy();
  }
}

function setSudoPromptStatus(run, requestId, status) {
  if (run.sudoPrompt?.requestId === requestId && run.sudoPrompt.status === 'requested') {
    run.sudoPrompt = { ...run.sudoPrompt, status };
    return true;
  }
  return false;
}

// A helper connected and asked for a password on behalf of one sudo invocation.
function handleSudoPasswordRequest(socket, request) {
  const run = currentRun;
  if (!isRunActive(run)) {
    replyToAskpass(socket, null);
    return;
  }

  const relay = run.sudo;
  const sudoPid = Number.isInteger(request.sudoPid) ? request.sudoPid : null;
  const prompt = typeof request.prompt === 'string' && request.prompt.trim() ? request.prompt.trim() : '[sudo] password:';
  const rejected = sudoPid !== null && relay.answeredPids.has(sudoPid);

  if (rejected) {
    // sudo asked the same invocation again: the last answer was wrong.
    relay.cachedPassword = null;
  } else if (relay.cachedPassword !== null) {
    if (sudoPid !== null) {
      relay.answeredPids.add(sudoPid);
    }
    replyToAskpass(socket, relay.cachedPassword);
    return;
  }

  relay.sequence += 1;
  const requestId = `sudo-${run.id}-${relay.sequence}`;
  relay.pending.set(requestId, { socket, sudoPid });
  run.sudoPrompt = { requestId, prompt, rejected, status: 'requested', requestedAt: new Date().toISOString() };

  // sudo gave up (timeout), the child died, or the bridge cancelled it.
  socket.on('close', () => {
    if (relay.pending.get(requestId)?.socket !== socket) {
      return;
    }
    relay.pending.delete(requestId);
    if (setSudoPromptStatus(run, requestId, 'expired')) {
      addTerminalLine('Sudo stopped waiting before the dashboard answered.', 'warning', 'bridge', run);
      if (run === currentRun) {
        broadcastSnapshot('sudo.prompt.expired');
      }
    }
  });

  addTerminalLine(
    rejected ? 'Sudo rejected that password. Asking the dashboard again...' : 'Sudo needs your password. Asking the dashboard...',
    rejected ? 'warning' : 'prompt',
    'bridge',
    run,
  );
  if (run === currentRun) {
    broadcastSnapshot('sudo.prompt.requested');
  }
}

function handleAskpassConnection(socket) {
  let buffer = '';
  socket.setEncoding('utf8');
  socket.on('error', () => {});
  const onData = (chunk) => {
    buffer += chunk;
    const newline = buffer.indexOf('\n');
    if (newline === -1) {
      if (buffer.length > SUDO_REQUEST_MAX_BYTES) {
        socket.destroy();
      }
      return;
    }
    socket.off('data', onData);

    let request;
    try {
      request = JSON.parse(buffer.slice(0, newline));
    } catch {
      socket.destroy();
      return;
    }
    handleSudoPasswordRequest(socket, request && typeof request === 'object' ? request : {});
  };
  socket.on('data', onData);
}

// Answer (password) or cancel (null) the pending prompt `requestId`.
function resolveSudoPrompt(requestId, password) {
  const run = currentRun;
  const entry = run?.sudo.pending.get(requestId);
  if (!entry) {
    return { ok: false, statusCode: 404, error: 'No sudo prompt is waiting for that requestId.' };
  }

  run.sudo.pending.delete(requestId);
  if (password === null) {
    replyToAskpass(entry.socket, null);
    setSudoPromptStatus(run, requestId, 'cancelled');
    addTerminalLine('Sudo prompt cancelled from the dashboard.', 'warning', 'bridge', run);
  } else {
    run.sudo.cachedPassword = password;
    if (entry.sudoPid !== null) {
      run.sudo.answeredPids.add(entry.sudoPid);
    }
    replyToAskpass(entry.socket, password);
    setSudoPromptStatus(run, requestId, 'resolved');
    addTerminalLine('Sudo password received from the dashboard.', 'dim', 'bridge', run);
  }
  broadcastSnapshot('sudo.prompt.resolved');
  return { ok: true, statusCode: 202 };
}

// Drop everything sudo-related a run holds: pending helpers get a cancel, the
// password leaves memory. Called when the child exits and at shutdown.
function clearSudoState(run) {
  if (!run) {
    return;
  }
  for (const [requestId, entry] of run.sudo.pending) {
    run.sudo.pending.delete(requestId);
    replyToAskpass(entry.socket, null);
    setSudoPromptStatus(run, requestId, 'expired');
  }
  run.sudo.cachedPassword = null;
  run.sudo.answeredPids.clear();
}

function startAskpassRelay() {
  const dir = mkdtempSync(path.join(os.tmpdir(), 'sysupdate-askpass-'));
  const socketPath = path.join(dir, 'askpass.sock');
  const helperPath = path.join(dir, 'askpass');

  // sudo runs SUDO_ASKPASS with no arguments of ours, so the socket path is
  // baked into a wrapper instead of relying on environment inheritance.
  writeFileSync(
    helperPath,
    [
      '#!/bin/sh',
      '# Generated by the sysupdate web bridge. Relays sudo password prompts to the dashboard.',
      `SYSUPDATE_ASKPASS_SOCKET=${shellQuote(socketPath)} exec ${shellQuote(process.execPath)} ${shellQuote(ASKPASS_HELPER_SCRIPT)} "$@"`,
      '',
    ].join('\n'),
    { mode: 0o700 },
  );

  const relayServer = net.createServer(handleAskpassConnection);
  relayServer.on('error', (error) => {
    console.error(`sysupdate backend: sudo askpass relay failed — ${error?.message ?? error}`);
    askpassRelay = null;
    rmSync(dir, { recursive: true, force: true });
  });
  relayServer.listen(socketPath, () => {
    askpassRelay = { dir, socketPath, helperPath, server: relayServer };
  });
}

function stopAskpassRelay() {
  const relay = askpassRelay;
  askpassRelay = null;
  if (!relay) {
    return;
  }
  relay.server.close();
  rmSync(relay.dir, { recursive: true, force: true });
}

function attachLineReader(stream, streamName, run) {
  let buffer = '';

  stream.on('data', (chunk) => {
    buffer += chunk.toString();
    const lines = buffer.split(/\r?\n/);
    buffer = lines.pop() ?? '';

    for (const line of lines) {
      processOutputLine(line, streamName, run);
    }
  });

  stream.on('end', () => {
    if (buffer) {
      processOutputLine(buffer, streamName, run);
    }
  });
}

function startRun(options = {}) {
  if (activeChild && currentRun && (currentRun.status === 'starting' || currentRun.status === 'running')) {
    return {
      ok: false,
      statusCode: 409,
      error: 'A sysupdate run is already in progress.',
    };
  }

  const args = ['--json-events'];
  if (options.checkOnly) {
    args.unshift('--check-only');
  }
  if (options.snippetId) {
    args.push('--snippet', options.snippetId);
  }

  const run = createRunState(args);
  currentRun = run;
  broadcastSnapshot('run.prepared');

  const promptInput = options.autoConfirm ? createPromptInputFile(options.confirmResponse ?? 'y') : null;
  const cleanupPromptInput = () => {
    if (promptInput?.tempDir) {
      rmSync(promptInput.tempDir, { recursive: true, force: true });
    }
  };

  const child = spawn(SCRIPT_PATH, args, {
    cwd: REPO_ROOT,
    env: {
      ...process.env,
      SYSUPDATE_JSON_EVENTS: 'true',
      ...(promptInput ? { SYSUPDATE_PROMPT_INPUT: promptInput.promptInputPath } : {}),
      ...(askpassRelay ? { SUDO_ASKPASS: askpassRelay.helperPath } : {}),
    },
  });
  activeChild = child;

  run.status = 'running';
  run.pid = child.pid ?? null;

  attachLineReader(child.stdout, 'stdout', run);
  attachLineReader(child.stderr, 'stderr', run);

  child.on('error', (error) => {
    run.status = 'failed';
    run.completedAt = new Date().toISOString();
    run.exitCode = 1;
    addTerminalLine(`Failed to start sysupdate: ${error.message}`, 'error', 'bridge', run);
    // Only clear the shared child handle if this run still owns it.
    if (activeChild === child) {
      activeChild = null;
    }
    cleanupPromptInput();
    if (run === currentRun) {
      broadcast({
        type: 'bridge.error',
        payload: { message: error.message },
      });
      broadcastSnapshot('bridge.error');
    }
  });

  child.on('close', (code) => {
    if (run.status === 'running' || run.status === 'starting') {
      run.status = code === 0 ? 'completed' : 'failed';
      run.completedAt = new Date().toISOString();
      run.exitCode = code ?? 1;
    }

    if (activeChild === child) {
      activeChild = null;
    }
    cleanupPromptInput();
    clearSudoState(run);
    if (run === currentRun) {
      broadcastSnapshot('process.closed');
    }
  });

  return {
    ok: true,
    statusCode: 202,
    payload: getRunSnapshot(),
  };
}

function startCheckOnlyRun(options = {}) {
  return startRun({
    ...options,
    checkOnly: true,
    autoConfirm: false,
  });
}

function startUpgradeRun(options = {}) {
  return startRun({
    ...options,
    checkOnly: false,
    autoConfirm: true,
  });
}

async function readLogHistory(limit = DEFAULT_LOG_LIMIT) {
  if (!existsSync(LOG_FILE)) {
    return [];
  }

  const raw = await readFile(LOG_FILE, 'utf8');
  const entries = raw
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => JSON.parse(line));

  return entries.slice(-limit).reverse();
}

async function readRequestJson(request) {
  const chunks = [];

  for await (const chunk of request) {
    chunks.push(chunk);
  }

  if (chunks.length === 0) {
    return {};
  }

  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

const server = createServer(async (request, response) => {
  setCorsHeaders(response);

  if (!request.url) {
    sendJson(response, 400, { error: 'Missing request URL.' });
    return;
  }

  if (request.method === 'OPTIONS') {
    response.statusCode = 204;
    response.end();
    return;
  }

  const requestUrl = new URL(request.url, `http://${request.headers.host ?? `${HOST}:${PORT}`}`);

  try {
    if (request.method === 'GET' && requestUrl.pathname === '/api/health') {
      sendJson(response, 200, {
        status: 'ok',
        backend: 'sysupdate-local-bridge',
        host: HOST,
        port: PORT,
        scriptPath: SCRIPT_PATH,
        logFile: LOG_FILE,
        activeRun: getRunSnapshot(),
      });
      return;
    }

    if (request.method === 'GET' && requestUrl.pathname === '/api/logs') {
      const limit = Number(requestUrl.searchParams.get('limit') ?? DEFAULT_LOG_LIMIT);
      const logs = await readLogHistory(Number.isFinite(limit) ? limit : DEFAULT_LOG_LIMIT);
      sendJson(response, 200, { logs });
      return;
    }

    if (request.method === 'GET' && requestUrl.pathname === '/api/runs/current') {
      sendJson(response, 200, { run: getRunSnapshot() });
      return;
    }

    if (request.method === 'GET' && requestUrl.pathname === '/api/bootstrap') {
      const limit = Number(requestUrl.searchParams.get('logLimit') ?? DEFAULT_LOG_LIMIT);
      const logs = await readLogHistory(Number.isFinite(limit) ? limit : DEFAULT_LOG_LIMIT);
      sendJson(response, 200, {
        backend: {
          name: 'sysupdate-local-bridge',
          host: HOST,
          port: PORT,
          websocketPath: '/ws',
          supports: [
            'logs',
            'check-only-run',
            'snippet-upgrade-run',
            'json-events',
            'run-history',
            'shutdown',
            ...(SUDO_RELAY_ENABLED ? ['sudo-askpass'] : []),
          ],
        },
        logs,
        run: getRunSnapshot(),
      });
      return;
    }

    if (request.method === 'POST' && requestUrl.pathname === '/api/runs/check-only') {
      const body = await readRequestJson(request);
      const snippetId = body.snippetId === undefined ? null : sanitizeSnippetId(body.snippetId);

      if (body.snippetId !== undefined && !snippetId) {
        sendJson(response, 400, { error: 'snippetId must match /^[a-zA-Z0-9._-]+$/.' });
        return;
      }

      const result = startCheckOnlyRun({ snippetId });
      if (!result.ok) {
        sendJson(response, result.statusCode, { error: result.error });
        return;
      }

      sendJson(response, result.statusCode, { run: result.payload });
      return;
    }

    if (request.method === 'POST' && requestUrl.pathname === '/api/runs/upgrade') {
      const body = await readRequestJson(request);
      const snippetId = sanitizeSnippetId(body.snippetId);

      if (!snippetId) {
        sendJson(response, 400, { error: 'snippetId must match /^[a-zA-Z0-9._-]+$/.' });
        return;
      }

      const result = startUpgradeRun({ snippetId });
      if (!result.ok) {
        sendJson(response, result.statusCode, { error: result.error });
        return;
      }

      sendJson(response, result.statusCode, { run: result.payload });
      return;
    }

    if (request.method === 'POST' && requestUrl.pathname === '/api/runs/sudo-password') {
      const parsed = parseSudoPasswordRequest(await readRequestJson(request));
      if (parsed.error) {
        sendJson(response, 400, { error: parsed.error });
        return;
      }

      const result = resolveSudoPrompt(parsed.requestId, parsed.password);
      if (!result.ok) {
        sendJson(response, result.statusCode, { error: result.error });
        return;
      }

      sendJson(response, result.statusCode, { run: getRunSnapshot() });
      return;
    }

    if (request.method === 'POST' && requestUrl.pathname === '/api/shutdown') {
      const body = await readRequestJson(request);
      const runActive =
        activeChild !== null && currentRun !== null && (currentRun.status === 'starting' || currentRun.status === 'running');

      // Stopping the bridge mid-run kills the child CLI, which can leave a
      // package manager half-way through an install. Callers must opt in.
      if (runActive && body.force !== true) {
        sendJson(response, 409, {
          error: 'A sysupdate run is in progress. Send { "force": true } to stop it and shut down anyway.',
        });
        return;
      }

      broadcast({
        type: 'bridge.shutdown',
        payload: { reason: 'requested', runStopped: runActive },
      });
      sendJson(response, 202, { shuttingDown: true, runStopped: runActive });
      // Let the response reach the socket before the listener goes away.
      setTimeout(shutdown, 100);
      return;
    }

    sendJson(response, 404, { error: 'Route not found.' });
  } catch (error) {
    sendJson(response, 500, {
      error: error instanceof Error ? error.message : 'Unexpected backend error.',
    });
  }
});

const websocketServer = new WebSocketServer({ server, path: '/ws' });

websocketServer.on('connection', (socket) => {
  clients.add(socket);

  // A ws socket emitting 'error' with no listener throws and crashes the bridge.
  // The common trigger is benign: React StrictMode opens then immediately closes
  // the socket in dev, so the frame below can hit a closed pipe (EPIPE/ECONNRESET).
  socket.on('error', () => {
    clients.delete(socket);
  });

  if (socket.readyState === socket.OPEN) {
    socket.send(
      JSON.stringify({
        type: 'connected',
        payload: {
          backend: 'sysupdate-local-bridge',
          run: getRunSnapshot(),
        },
      }),
    );
  }

  socket.on('close', () => {
    clients.delete(socket);
  });
});

// A failed listen (most commonly EADDRINUSE when a backend is already running)
// otherwise surfaces as an unhandled 'error' event that crashes with a stack
// trace. Handle it on both the HTTP server and the ws server (ws re-emits the
// server error) and exit cleanly with an actionable one-liner instead.
const handleListenError = (error) => {
  if (error && error.code === 'EADDRINUSE') {
    console.error(
      `sysupdate backend: ${HOST}:${PORT} is already in use — a backend bridge is likely already running.`,
    );
    console.error('Reuse it, or free the port (e.g. `pkill -f backend/server.js`), then retry.');
  } else {
    console.error(`sysupdate backend: failed to start — ${error?.message ?? error}`);
  }
  process.exit(1);
};
server.on('error', handleListenError);
websocketServer.on('error', handleListenError);

server.listen(PORT, HOST, () => {
  console.log(`sysupdate local backend bridge listening on http://${HOST}:${PORT}`);
  if (SUDO_RELAY_ENABLED) {
    startAskpassRelay();
  } else {
    console.log('sysupdate backend: sudo askpass relay disabled (non-loopback bind or SYSUPDATE_SUDO_RELAY=false)');
  }
});

function shutdown(reason = 'requested') {
  if (shuttingDown) {
    return;
  }
  shuttingDown = true;
  console.log(`sysupdate backend: shutting down (${reason})`);

  // Unblock any sudo waiting on the dashboard before signalling the child, so
  // the CLI can fail that step and exit instead of hanging inside sudo.
  clearSudoState(currentRun);
  stopAskpassRelay();

  if (activeChild?.pid) {
    activeChild.kill('SIGTERM');
  }

  for (const client of clients) {
    try {
      client.close(1001, 'Backend shutting down');
    } catch {
      clients.delete(client);
    }
  }

  // Idle keep-alive connections (the Vite proxy, a browser) would otherwise
  // hold server.close() open indefinitely; cap the wait.
  const forceExit = setTimeout(() => process.exit(0), 2000);
  forceExit.unref();

  websocketServer.close(() => {
    server.closeAllConnections?.();
    server.close(() => {
      process.exit(0);
    });
  });
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGHUP', () => shutdown('SIGHUP'));
