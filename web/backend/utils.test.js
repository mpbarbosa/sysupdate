import { describe, it, expect } from 'vitest';
import {
  mapTerminalType,
  stripAnsi,
  trimArray,
  sanitizeSnippetId,
  isLoopbackHost,
  shellQuote,
  parseSudoPasswordRequest,
} from './utils.js';

describe('mapTerminalType', () => {
  it('maps prompt → prompt', () => {
    expect(mapTerminalType('prompt')).toBe('prompt');
  });

  it('maps info → info', () => {
    expect(mapTerminalType('info')).toBe('info');
  });

  it('maps section_header → info', () => {
    expect(mapTerminalType('section_header')).toBe('info');
  });

  it('maps operation_header → info', () => {
    expect(mapTerminalType('operation_header')).toBe('info');
  });

  it('maps success → success', () => {
    expect(mapTerminalType('success')).toBe('success');
  });

  it('maps warning → warning', () => {
    expect(mapTerminalType('warning')).toBe('warning');
  });

  it('maps error → error', () => {
    expect(mapTerminalType('error')).toBe('error');
  });

  it('maps dim → dim', () => {
    expect(mapTerminalType('dim')).toBe('dim');
  });

  it('maps unknown type → output', () => {
    expect(mapTerminalType('something_unknown')).toBe('output');
  });

  it('maps empty string → output', () => {
    expect(mapTerminalType('')).toBe('output');
  });
});

describe('stripAnsi', () => {
  it('strips a basic color escape', () => {
    expect(stripAnsi('\x1b[32mhello\x1b[0m')).toBe('hello');
  });

  it('strips bold + color sequence', () => {
    expect(stripAnsi('\x1b[1;34mtext\x1b[0m')).toBe('text');
  });

  it('returns plain text unchanged', () => {
    expect(stripAnsi('no escapes here')).toBe('no escapes here');
  });

  it('strips multiple sequences in one string', () => {
    expect(stripAnsi('\x1b[32mok\x1b[0m and \x1b[31mfail\x1b[0m')).toBe('ok and fail');
  });

  it('handles empty string', () => {
    expect(stripAnsi('')).toBe('');
  });
});

describe('trimArray', () => {
  it('returns array unchanged when within limit', () => {
    const arr = [1, 2, 3];
    expect(trimArray(arr, 5)).toEqual([1, 2, 3]);
  });

  it('returns array unchanged when exactly at limit', () => {
    const arr = [1, 2, 3];
    expect(trimArray(arr, 3)).toEqual([1, 2, 3]);
  });

  it('keeps the last N items when over limit', () => {
    expect(trimArray([1, 2, 3, 4, 5], 3)).toEqual([3, 4, 5]);
  });

  it('keeps the last 1 item', () => {
    expect(trimArray([1, 2, 3], 1)).toEqual([3]);
  });

  it('handles empty array', () => {
    expect(trimArray([], 10)).toEqual([]);
  });
});

describe('sanitizeSnippetId', () => {
  it('accepts a simple alphanumeric id', () => {
    expect(sanitizeSnippetId('rtk')).toBe('rtk');
  });

  it('accepts id with hyphens and dots', () => {
    expect(sanitizeSnippetId('vscode-insiders')).toBe('vscode-insiders');
    expect(sanitizeSnippetId('node.js')).toBe('node.js');
  });

  it('accepts id with underscores', () => {
    expect(sanitizeSnippetId('my_tool')).toBe('my_tool');
  });

  it('rejects id with spaces', () => {
    expect(sanitizeSnippetId('bad snippet')).toBeNull();
  });

  it('rejects id with special characters', () => {
    expect(sanitizeSnippetId('snippet!')).toBeNull();
    expect(sanitizeSnippetId('../etc/passwd')).toBeNull();
    expect(sanitizeSnippetId('id;rm -rf')).toBeNull();
  });

  it('rejects empty string', () => {
    expect(sanitizeSnippetId('')).toBeNull();
  });

  it('rejects non-string values', () => {
    expect(sanitizeSnippetId(null)).toBeNull();
    expect(sanitizeSnippetId(42)).toBeNull();
    expect(sanitizeSnippetId(undefined)).toBeNull();
  });
});

describe('isLoopbackHost', () => {
  it('accepts the default bridge address and localhost aliases', () => {
    expect(isLoopbackHost('127.0.0.1')).toBe(true);
    expect(isLoopbackHost('127.0.0.53')).toBe(true);
    expect(isLoopbackHost('localhost')).toBe(true);
    expect(isLoopbackHost('LOCALHOST')).toBe(true);
    expect(isLoopbackHost('::1')).toBe(true);
    expect(isLoopbackHost('[::1]')).toBe(true);
  });

  it('rejects anything reachable from the network', () => {
    expect(isLoopbackHost('0.0.0.0')).toBe(false);
    expect(isLoopbackHost('192.168.1.10')).toBe(false);
    expect(isLoopbackHost('::')).toBe(false);
    expect(isLoopbackHost('')).toBe(false);
    expect(isLoopbackHost(undefined)).toBe(false);
  });
});

describe('shellQuote', () => {
  it('wraps in single quotes', () => {
    expect(shellQuote('/tmp/a b')).toBe("'/tmp/a b'");
  });

  it('escapes embedded single quotes', () => {
    expect(shellQuote("it's")).toBe("'it'\\''s'");
  });
});

describe('parseSudoPasswordRequest', () => {
  it('returns requestId and password for a well-formed body', () => {
    expect(parseSudoPasswordRequest({ requestId: 'sudo-bridge-1-1', password: 'hunter2' })).toEqual({
      requestId: 'sudo-bridge-1-1',
      password: 'hunter2',
    });
  });

  it('maps cancel: true to a null password', () => {
    expect(parseSudoPasswordRequest({ requestId: 'sudo-1', cancel: true })).toEqual({ requestId: 'sudo-1', password: null });
  });

  it('rejects a missing or malformed requestId', () => {
    expect(parseSudoPasswordRequest({ password: 'x' }).error).toMatch(/requestId/);
    expect(parseSudoPasswordRequest({ requestId: '../x', password: 'x' }).error).toMatch(/requestId/);
    expect(parseSudoPasswordRequest(null).error).toMatch(/requestId/);
  });

  it('rejects an empty or non-string password without cancel', () => {
    expect(parseSudoPasswordRequest({ requestId: 'sudo-1' }).error).toMatch(/password/);
    expect(parseSudoPasswordRequest({ requestId: 'sudo-1', password: '' }).error).toMatch(/password/);
    expect(parseSudoPasswordRequest({ requestId: 'sudo-1', password: 42 }).error).toMatch(/password/);
  });
});
