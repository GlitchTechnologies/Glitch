
import { spawn } from 'child_process';
import type { ChildProcess } from 'child_process';
import { app } from 'electron';
import type { Rectangle } from 'electron';
import * as fs from 'fs';
import * as path from 'path';
import { DARK, UPDATE_WINDOW_READY_TIMEOUT_MS } from './config';
import { logEvent } from './log';

const EXE_NAME = 'glitch-update.exe';

export interface UpdateWindow {
  close(): void;
}

export async function showUpdateWindow(bounds: Rectangle, text: string): Promise<UpdateWindow | null> {
  if (!app.isPackaged) return null;
  const exe = copyToTemp();
  if (!exe) return null;

  const args = [
    `--bounds=${bounds.x},${bounds.y},${bounds.width},${bounds.height}`,
    `--card=${DARK.card}`,
    `--border=${DARK.border}`,
    `--text-color=${DARK.text}`,
    `--text=${text}`,
  ];
  let child: ChildProcess;
  try {
    child = spawn(exe, args, { detached: true, stdio: ['ignore', 'pipe', 'ignore'] });
  } catch (e) {
    console.error('update-window: окно не запустилось', e);
    return null;
  }
  const shown = await waitShown(child);
  if (!shown) {
    stop(child);
    return null;
  }
  logEvent('обновление: окно «Установка обновления» на экране');
  child.stdout?.destroy();
  child.unref();
  return { close: () => stop(child) };
}


function copyToTemp(): string | null {
  const source = path.join(process.resourcesPath, EXE_NAME);
  const dir = path.join(app.getPath('temp'), 'glitch-update');
  const target = path.join(dir, EXE_NAME);
  try {
    fs.mkdirSync(dir, { recursive: true });
    fs.copyFileSync(source, target);
    return target;
  } catch (e) {
    if (fs.existsSync(target)) return target;
    console.error('update-window: не удалось подготовить окно', e);
    return null;
  }
}

function waitShown(child: ChildProcess): Promise<boolean> {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (shown: boolean): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(shown);
    };
    const timer = setTimeout(() => {
      console.warn('update-window: окно не ответило вовремя');
      finish(false);
    }, UPDATE_WINDOW_READY_TIMEOUT_MS);
    child.once('error', (e) => {
      console.error('update-window: окно не запустилось', e);
      finish(false);
    });
    child.once('exit', () => finish(false));
    child.stdout?.on('data', (chunk: Buffer) => {
      if (chunk.toString('utf8').includes('ready')) finish(true);
    });
  });
}

function stop(child: ChildProcess): void {
  if (child.exitCode !== null || child.killed) return;
  try {
    child.kill();
  } catch (e) {
    console.error('update-window: не удалось закрыть окно', e);
  }
}
