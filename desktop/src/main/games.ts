// Веб-клиент получает только номера найденных игр и время запуска. Пути процессов остаются в оболочке.
// Отправляем полный снимок при изменении, чтобы потерянное событие не оставило игру активной.
// Дочерний процесс завершается вместе с оболочкой и освобождает файлы для обновления.

import { app } from 'electron';
import { ChildProcessWithoutNullStreams, spawn } from 'child_process';
import * as path from 'path';
import * as readline from 'readline';
import type { RunningGame, WatchedGame } from '../shared/ipc';

const SCAN_INTERVAL_MS = 15_000;

const MAX_GAMES = 100_000;
const MAX_EXECUTABLES = 64;
const MAX_NAME = 255;

const MAX_DETAIL = 2000;

const EXIT_WAIT_MS = 1000;

interface Candidate {
  gameId: number;
  suffix: string;
  exact: boolean;
}

let byFile = new Map<string, Candidate[]>();
let child: ChildProcessWithoutNullStreams | null = null;
let timer: NodeJS.Timeout | null = null;

let collecting: { path: string; startedAt: number }[] | null = null;

let lastSent = '[]';

let broken = false;

let deliver: (games: RunningGame[]) => void = () => undefined;

export function initGames(to: { games: (games: RunningGame[]) => void }): void {
  deliver = to.games;
}

export function watchGames(request: unknown): void {
  const table = parse(request);
  if (table.size === 0) {
    stop();
    return;
  }
  byFile = table;
  if (broken) return;
  start();
  lastSent = '';
  scan();
}

export function stopGames(): void {
  stop();
}

function parse(request: unknown): Map<string, Candidate[]> {
  const table = new Map<string, Candidate[]>();
  if (!Array.isArray(request)) return table;
  for (const item of request.slice(0, MAX_GAMES)) {
    if (typeof item !== 'object' || item === null) continue;
    const { id, executables } = item as Partial<WatchedGame>;
    if (typeof id !== 'number' || !Number.isSafeInteger(id) || id <= 0) continue;
    if (!Array.isArray(executables)) continue;
    for (const raw of executables.slice(0, MAX_EXECUTABLES)) {
      if (typeof raw !== 'string' || raw.length === 0 || raw.length > MAX_NAME) continue;
      const exact = raw.startsWith('>');
      const suffix = (exact ? raw.slice(1) : raw).toLowerCase().replace(/\\/g, '/');
      const file = suffix.slice(suffix.lastIndexOf('/') + 1);
      if (file === '') continue;
      const list = table.get(file);
      const candidate = { gameId: id, suffix, exact };
      if (list === undefined) table.set(file, [candidate]);
      else list.push(candidate);
    }
  }
  return table;
}

function exePath(): string {
  return app.isPackaged
    ? path.join(process.resourcesPath, 'glitch-games.exe')
    : path.join(app.getAppPath(), 'build', 'games', 'glitch-games.exe');
}

function start(): void {
  if (child !== null) return;
  const proc = spawn(exePath(), [], { stdio: 'pipe', windowsHide: true });
  child = proc;
  collecting = null;
  proc.stdin.on('error', () => undefined);
  readline.createInterface({ input: proc.stdout }).on('line', (line) => onLine(proc, line));
  proc.on('error', (e) => fail(proc, e.stack ?? e.message));
  proc.on('exit', (code) => fail(proc, `glitch-games.exe exited with code ${code}`));
  timer = setInterval(scan, SCAN_INTERVAL_MS);
}

function scan(): void {
  if (child === null || collecting !== null) return;
  collecting = [];
  child.stdin.write('scan\n');
}

function onLine(proc: ChildProcessWithoutNullStreams, line: string): void {
  if (child !== proc) return;
  if (line.startsWith('p ')) {
    const space = line.indexOf(' ', 2);
    const startedAt = Number(line.slice(2, space));
    if (collecting !== null && space > 2 && Number.isFinite(startedAt)) {
      collecting.push({ path: line.slice(space + 1), startedAt });
    }
    return;
  }
  if (line === 'end') {
    const list = collecting ?? [];
    collecting = null;
    report(match(list));
    return;
  }
  if (line.startsWith('error ')) fail(proc, line.slice(6));
}

function ownDir(): string {
  return path.dirname(process.execPath).toLowerCase().replace(/\\/g, '/') + '/';
}

function match(processes: { path: string; startedAt: number }[]): RunningGame[] {
  const found = new Map<number, number>();
  const own = ownDir();
  for (const { path: raw, startedAt } of processes) {
    const full = raw.toLowerCase().replace(/\\/g, '/');
    if (full.startsWith(own)) continue;
    const file = full.slice(full.lastIndexOf('/') + 1);
    for (const c of byFile.get(file) ?? []) {
      const hit = c.exact || c.suffix === file || full.endsWith('/' + c.suffix) || full === c.suffix;
      if (!hit) continue;
      const before = found.get(c.gameId);
      if (before === undefined || startedAt < before) found.set(c.gameId, startedAt);
    }
  }
  return [...found]
    .map(([id, startedAt]) => ({ id, startedAt }))
    .sort((a, b) => a.startedAt - b.startedAt || a.id - b.id);
}

function report(games: RunningGame[]): void {
  const json = JSON.stringify(games);
  if (json === lastSent) return;
  lastSent = json;
  deliver(games);
}

function fail(proc: ChildProcessWithoutNullStreams, detail: string): void {
  if (child !== proc) return;
  clear();
  broken = true;
  console.error('Запущенные игры не узнаются:', detail.slice(0, MAX_DETAIL));
  proc.kill();
  report([]);
}

function stop(): void {
  const proc = child;
  byFile = new Map();
  if (proc === null) {
    report([]);
    return;
  }
  clear();
  proc.stdin.end();
  setTimeout(() => {
    if (proc.exitCode === null) proc.kill();
  }, EXIT_WAIT_MS).unref();
  report([]);
}

function clear(): void {
  child = null;
  collecting = null;
  if (timer !== null) clearInterval(timer);
  timer = null;
}
