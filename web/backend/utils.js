/**
 * Pure utility functions shared between server.js and tests.
 * No I/O, no side effects — safe to import in any environment.
 */

export function mapTerminalType(lineType) {
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

export function stripAnsi(text) {
  return text.replace(/\x1b\[[0-9;]*m/g, '');
}

export function trimArray(items, limit) {
  if (items.length <= limit) {
    return items;
  }
  return items.slice(items.length - limit);
}

export function sanitizeSnippetId(value) {
  if (typeof value !== 'string' || value.length === 0) {
    return null;
  }
  if (!/^[a-zA-Z0-9._-]+$/.test(value)) {
    return null;
  }
  return value;
}

// True for bind addresses that only this machine can reach. The sudo askpass
// relay sends passwords over plain HTTP/WebSocket, so it is only enabled when
// the bridge listens on loopback.
export function isLoopbackHost(host) {
  if (typeof host !== 'string') {
    return false;
  }
  const normalized = host.trim().toLowerCase().replace(/^\[|\]$/g, '');
  return normalized === 'localhost' || normalized === '::1' || /^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(normalized);
}

// Single-quote a string for /bin/sh so it survives any character verbatim.
export function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

// Body validation for POST /api/runs/sudo-password. Returns { requestId,
// password } (password null = cancel) or { error } for a 400.
export function parseSudoPasswordRequest(body) {
  const requestId = body?.requestId;
  if (typeof requestId !== 'string' || !/^[a-zA-Z0-9._-]+$/.test(requestId)) {
    return { error: 'requestId must match /^[a-zA-Z0-9._-]+$/.' };
  }
  if (body.cancel === true) {
    return { requestId, password: null };
  }
  if (typeof body.password !== 'string' || body.password.length === 0) {
    return { error: 'password must be a non-empty string, or send { "cancel": true }.' };
  }
  return { requestId, password: body.password };
}
