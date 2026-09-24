#!/usr/bin/env node
/**
 * sudo askpass helper for the sysupdate web bridge.
 *
 * sudo runs this (via the per-session wrapper the bridge writes next to its
 * unix socket) whenever the CLI it spawned needs a password: argv[2] is sudo's
 * prompt, and whatever this prints to stdout is the password. The helper does
 * not know the password — it asks the bridge over the unix socket named in
 * SYSUPDATE_ASKPASS_SOCKET, the bridge asks the dashboard, and the answer
 * comes back here. Exit 1 (no output) tells sudo the prompt was cancelled.
 *
 * Wire format, one JSON object per line each way:
 *   -> { "prompt": "<sudo prompt>", "sudoPid": <parent pid> }
 *   <- { "password": "<...>" }  or  { "cancelled": true }
 *
 * sudoPid lets the bridge tell "sudo is asking again because the password was
 * wrong" (same pid) from "a new sudo invocation" (new pid, answer from cache).
 */

import net from 'node:net';

const socketPath = process.env.SYSUPDATE_ASKPASS_SOCKET;
const prompt = process.argv[2] ?? '';

if (!socketPath) {
  process.exit(1);
}

let buffer = '';
let finished = false;
const socket = net.createConnection(socketPath);

function finish(exitCode) {
  if (finished) {
    return;
  }
  finished = true;
  socket.destroy();
  process.exit(exitCode);
}

socket.on('connect', () => {
  socket.write(`${JSON.stringify({ prompt, sudoPid: process.ppid })}\n`);
});

socket.on('data', (chunk) => {
  buffer += chunk.toString('utf8');
  const newline = buffer.indexOf('\n');
  if (newline === -1) {
    return;
  }

  let reply;
  try {
    reply = JSON.parse(buffer.slice(0, newline));
  } catch {
    finish(1);
    return;
  }

  if (reply && typeof reply.password === 'string') {
    // Askpass convention: password followed by a newline, which sudo strips.
    process.stdout.write(`${reply.password}\n`, () => finish(0));
    return;
  }
  finish(1);
});

socket.on('error', () => finish(1));
socket.on('close', () => finish(1));
