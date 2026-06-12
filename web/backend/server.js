import { spawn } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { WebSocketServer } from 'ws';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const WEB_DIR = path.resolve(__dirname, '..');
const REPO_ROOT = path.resolve(WEB_DIR, '..');
const SCRIPT_PATH = path.resolve(REPO_ROOT, 'scripts', 'system_update.sh');

const HOST = process.env.SYSUPDATE_WEB_HOST ?? '127.0.0.1';
const PORT = Number(process.env.SYSUPDATE_WEB_PORT ?? '4174');
const DEFAULT_LOG_LIMIT = Number(process.env.SYSUPDATE_LOG_LIMIT ?? '50');
const MAX_TERMINAL_LINES = 600;
const MAX_RAW_EVENTS = 1200;
const LOG_FILE =
  process.env.SYSUPDATE_LOG_FILE ??
  path.join(process.env.XDG_STATE_HOME ?? path.join(os.homedir(), '.local', 'state'), 'sysupdate', 'run-history.jsonl');

const clients = new Set();
const snippetIdByModule = new Map();

let activeChild = null;
let currentRun = null;

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

function mapTerminalType(lineType) {
  switch (lineType) {
    case 'prompt':
      return 'prompt';
    case 'info':
    case 'section_header':
    case 'operation_header':
      return 'info';
    case 'success':
      return 'success';
    case 'warning':
      return 'warning';
    case 'error':
      return 'error';
    case 'dim':
      return 'dim';
    default:
      return 'output';
  }
}

function stripAnsi(text) {
  return text.replace(/\u001b\[[0-9;]*m/g, '');
}

function trimArray(items, limit) {
  if (items.length <= limit) {
    return items;
  }

  return items.slice(items.length - limit);
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
    terminalLines: [],
    rawEvents: [],
    summariesByKey: {},
  };
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

function addTerminalLine(text, type, source = 'bridge') {
  if (!currentRun) {
    return;
  }

  currentRun.terminalLines = trimArray(
    [
      ...currentRun.terminalLines,
      {
        id: `${currentRun.id}-line-${currentRun.terminalLines.length + 1}`,
        text,
        type,
        source,
      },
    ],
    MAX_TERMINAL_LINES,
  );
}

function storeRawEvent(event) {
  if (!currentRun) {
    return;
  }

  currentRun.rawEvents = trimArray([...currentRun.rawEvents, event], MAX_RAW_EVENTS);
}

function handleCliEvent(event) {
  if (!currentRun) {
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

  storeRawEvent(enrichedEvent);

  switch (enrichedEvent.event_type) {
    case 'run.started':
      currentRun.status = 'running';
      currentRun.runId = enrichedEvent.run_id ?? currentRun.runId;
      break;
    case 'terminal.line':
      addTerminalLine(enrichedEvent.message ?? '', mapTerminalType(enrichedEvent.line_type), enrichedEvent.source ?? 'cli');
      break;
    case 'summary.updates': {
      const key = `${enrichedEvent.summary_name ?? 'summary'}:${enrichedEvent.target ?? enrichedEvent.package_manager ?? 'global'}`;
      currentRun.summariesByKey[key] = enrichedEvent;
      break;
    }
    case 'prompt.requested':
      currentRun.prompt = {
        status: 'requested',
        promptType: enrichedEvent.prompt_type ?? 'unknown',
        message: enrichedEvent.prompt_message ?? '',
        defaultResponse: enrichedEvent.default_response ?? '',
        options: enrichedEvent.options ?? '',
      };
      break;
    case 'prompt.resolved':
      currentRun.prompt = {
        status: 'resolved',
        promptType: enrichedEvent.prompt_type ?? 'unknown',
        message: enrichedEvent.prompt_message ?? '',
        defaultResponse: enrichedEvent.default_response ?? '',
        response: enrichedEvent.response ?? '',
        responseSource: enrichedEvent.response_source ?? '',
      };
      break;
    case 'run.completed':
      currentRun.status = 'completed';
      currentRun.completedAt = enrichedEvent.timestamp ?? new Date().toISOString();
      currentRun.exitCode = Number(enrichedEvent.exit_code ?? 0);
      break;
    case 'run.failed':
      currentRun.status = 'failed';
      currentRun.completedAt = enrichedEvent.timestamp ?? new Date().toISOString();
      currentRun.exitCode = Number(enrichedEvent.exit_code ?? 1);
      break;
    case 'log.entry':
      currentRun.lastLogEntry = enrichedEvent;
      break;
    default:
      break;
  }

  broadcast({ type: 'cli.event', payload: enrichedEvent });
  broadcastSnapshot(enrichedEvent.event_type);
}

function processOutputLine(line, streamName) {
  if (!currentRun) {
    return;
  }

  const cleaned = stripAnsi(line).trimEnd();
  if (!cleaned) {
    return;
  }

  if (streamName === 'stdout' && currentRun.args.includes('--json-events')) {
    return;
  }

  if (streamName === 'stderr') {
    try {
      const parsed = JSON.parse(cleaned);
      if (parsed && typeof parsed === 'object' && 'event_type' in parsed) {
        handleCliEvent(parsed);
        return;
      }
    } catch {
      // Non-JSON stderr lines are forwarded as bridge output below.
    }
  }

  addTerminalLine(cleaned, streamName === 'stderr' ? 'error' : 'output', streamName);
  broadcast({
    type: `${streamName}.line`,
    payload: { text: cleaned },
  });
  broadcastSnapshot(`${streamName}.line`);
}

function attachLineReader(stream, streamName) {
  let buffer = '';

  stream.on('data', (chunk) => {
    buffer += chunk.toString();
    const lines = buffer.split(/\r?\n/);
    buffer = lines.pop() ?? '';

    for (const line of lines) {
      processOutputLine(line, streamName);
    }
  });

  stream.on('end', () => {
    if (buffer) {
      processOutputLine(buffer, streamName);
    }
  });
}

function sanitizeSnippetId(value) {
  if (typeof value !== 'string' || value.length === 0) {
    return null;
  }

  if (!/^[a-zA-Z0-9._-]+$/.test(value)) {
    return null;
  }

  return value;
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

  currentRun = createRunState(args);
  broadcastSnapshot('run.prepared');

  const promptInput = options.autoConfirm ? createPromptInputFile(options.confirmResponse ?? 'y') : null;
  const cleanupPromptInput = () => {
    if (promptInput?.tempDir) {
      rmSync(promptInput.tempDir, { recursive: true, force: true });
    }
  };

  activeChild = spawn(SCRIPT_PATH, args, {
    cwd: REPO_ROOT,
    env: {
      ...process.env,
      SYSUPDATE_JSON_EVENTS: 'true',
      ...(promptInput ? { SYSUPDATE_PROMPT_INPUT: promptInput.promptInputPath } : {}),
    },
  });

  currentRun.status = 'running';
  currentRun.pid = activeChild.pid ?? null;

  attachLineReader(activeChild.stdout, 'stdout');
  attachLineReader(activeChild.stderr, 'stderr');

  activeChild.on('error', (error) => {
    if (!currentRun) {
      cleanupPromptInput();
      return;
    }

    currentRun.status = 'failed';
    currentRun.completedAt = new Date().toISOString();
    currentRun.exitCode = 1;
    addTerminalLine(`Failed to start sysupdate: ${error.message}`, 'error', 'bridge');
    broadcast({
      type: 'bridge.error',
      payload: { message: error.message },
    });
    activeChild = null;
    cleanupPromptInput();
    broadcastSnapshot('bridge.error');
  });

  activeChild.on('close', (code) => {
    if (!currentRun) {
      activeChild = null;
      return;
    }

    if (currentRun.status === 'running' || currentRun.status === 'starting') {
      currentRun.status = code === 0 ? 'completed' : 'failed';
      currentRun.completedAt = new Date().toISOString();
      currentRun.exitCode = code ?? 1;
    }

    activeChild = null;
    cleanupPromptInput();
    broadcastSnapshot('process.closed');
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
          supports: ['logs', 'check-only-run', 'snippet-upgrade-run', 'json-events', 'run-history'],
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
  socket.send(
    JSON.stringify({
      type: 'connected',
      payload: {
        backend: 'sysupdate-local-bridge',
        run: getRunSnapshot(),
      },
    }),
  );

  socket.on('close', () => {
    clients.delete(socket);
  });
});

server.listen(PORT, HOST, () => {
  console.log(`sysupdate local backend bridge listening on http://${HOST}:${PORT}`);
});

function shutdown() {
  if (activeChild?.pid) {
    activeChild.kill('SIGTERM');
  }

  websocketServer.close(() => {
    server.close(() => {
      process.exit(0);
    });
  });
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
