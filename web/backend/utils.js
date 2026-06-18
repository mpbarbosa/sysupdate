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
