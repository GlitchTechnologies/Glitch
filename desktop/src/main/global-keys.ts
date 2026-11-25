// Веб-клиент получает состояние только назначенных клавиш. Raw Input не перехватывает нажатия у игры.
// При блокировке экрана или переходе в сон считаем клавиши отпущенными.

import { app, powerMonitor } from 'electron';
import { ChildProcessWithoutNullStreams, spawn } from 'child_process';
import * as path from 'path';
import * as readline from 'readline';
import type { GlobalKeysStatus } from '../shared/ipc';

const MAX_WATCHED = 32;

const MAX_DETAIL = 2000;

const NAME = /^[A-Za-z0-9]{1,32}$/;

const EXIT_WAIT_MS = 1000;

let child: ChildProcessWithoutNullStreams | null = null;

let broken: string | null = null;

let deliver: (keys: string[]) => void = () => undefined;
let tell: (status: GlobalKeysStatus) => void = () => undefined;

export function initGlobalKeys(to: {
  keys: (keys: string[]) => void;
  status: (status: GlobalKeysStatus) => void;
}): void {
  deliver = to.keys;
  tell = to.status;
  powerMonitor.on('lock-screen', releaseAll);
  powerMonitor.on('suspend', releaseAll);
}

export function watchGlobalKeys(request: unknown): void {
  if (!Array.isArray(request)) return;
  const names = request
    .slice(0, MAX_WATCHED)
    .filter((k: unknown): k is string => typeof k === 'string' && NAME.test(k));
  if (names.length === 0) {
    stop();
    return;
  }
  if (broken !== null) {
    tell({ state: 'failed', detail: broken });
    return;
  }
  start().stdin.write(`watch ${names.join(' ')}\n`);
}

export function stopGlobalKeys(): void {
  stop();
}

function exePath(): string {
  return app.isPackaged
    ? path.join(process.resourcesPath, 'glitch-keys.exe')
    : path.join(app.getAppPath(), 'build', 'keys', 'glitch-keys.exe');
}

function start(): ChildProcessWithoutNullStreams {
  if (child !== null) return child;
  const proc = spawn(exePath(), [], { stdio: 'pipe', windowsHide: true });
  child = proc;
  proc.stdin.on('error', () => undefined);
  readline.createInterface({ input: proc.stdout }).on('line', (line) => onLine(proc, line));
  proc.on('error', (e) => fail(proc, e.stack ?? e.message));
  proc.on('exit', (code) => fail(proc, `glitch-keys.exe exited with code ${code}`));
  return proc;
}

function onLine(proc: ChildProcessWithoutNullStreams, line: string): void {
  if (child !== proc) return;
  const space = line.indexOf(' ');
  const word = space < 0 ? line : line.slice(0, space);
  const rest = space < 0 ? '' : line.slice(space + 1);
  switch (word) {
    case 'ready':
      tell({ state: 'running' });
      return;
    case 'heard':
      tell({ state: 'heard' });
      return;
    case 'unknown':
      tell({ state: 'rejected', detail: rest.slice(0, MAX_DETAIL) });
      return;
    case 'keys':
      deliver(rest === '' ? [] : rest.split(' '));
      return;
    case 'error':
      fail(proc, rest);
      return;
  }
}

function fail(proc: ChildProcessWithoutNullStreams, detail: string): void {
  if (child !== proc) return;
  child = null;
  broken = detail.slice(0, MAX_DETAIL);
  console.error('Клавиши поверх окон не работают:', broken);
  proc.kill();
  deliver([]);
  tell({ state: 'failed', detail: broken });
}

function stop(): void {
  const proc = child;
  if (proc === null) return;
  child = null;
  proc.stdin.end();
  setTimeout(() => {
    if (proc.exitCode === null) proc.kill();
  }, EXIT_WAIT_MS).unref();
  deliver([]);
  tell({ state: 'stopped' });
}

function releaseAll(): void {
  child?.stdin.write('reset\n');
}
