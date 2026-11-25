// Журнал пишется синхронно, чтобы сохранить последние события при сбое.
// В нём нет полных адресов, входящих ссылок и текста уведомлений.

import { app } from 'electron';
import * as fs from 'fs';
import * as path from 'path';
import { format } from 'util';
import { LOG_MAX_BYTES } from './config';

const FILE_NAME = 'desktop.log';
const OLD_FILE_NAME = 'desktop.old.log';

let file = '';
let size = 0;
let writeFailed = false;

const consoleWarn = console.warn.bind(console);
const consoleError = console.error.bind(console);

/** Открыть журнал. Зовётся первым делом при запуске — и в копии, которая
 *  сразу отдаёт себя уже работающей (её запись — доказательство, что ярлык
 *  программу вообще запускал). Повторный вызов ничего не делает. */
export function initLog(): void {
  if (file) return;
  try {
    const dir = path.join(app.getPath('userData'), 'logs');
    fs.mkdirSync(dir, { recursive: true });
    file = path.join(dir, FILE_NAME);
    size = fs.existsSync(file) ? fs.statSync(file).size : 0;
    if (size > LOG_MAX_BYTES) rotate();
  } catch (e) {
    file = '';
    consoleError('log: журнал не открылся', e);
    return;
  }
  console.warn = (...args: unknown[]): void => {
    consoleWarn(...args);
    write('ПРЕДУПРЕЖДЕНИЕ', format(...args));
  };
  console.error = (...args: unknown[]): void => {
    consoleError(...args);
    write('ОШИБКА', format(...args));
  };
  process.on('uncaughtExceptionMonitor', (error, origin) => {
    write('ИСКЛЮЧЕНИЕ', `${origin}: ${error?.stack ?? String(error)}`);
  });
  const offset = -new Date().getTimezoneOffset() / 60;
  write(
    'ЗАПУСК',
    `Glitch ${app.getVersion()}, процесс ${process.pid}, упакована: ${yesNo(app.isPackaged)}, ` +
      `часовой пояс UTC${offset >= 0 ? '+' : ''}${offset}`,
  );
}

export function logEvent(text: string): void {
  write('', text);
}

export function yesNo(value: boolean): string {
  return value ? 'да' : 'нет';
}


function write(kind: string, text: string): void {
  if (!file) return;
  const line = `${stamp()}  ${kind ? `${kind}: ` : ''}${text}\n`;
  try {
    fs.appendFileSync(file, line, 'utf8');
    size += Buffer.byteLength(line, 'utf8');
    if (size > LOG_MAX_BYTES) rotate();
  } catch (e) {
    if (writeFailed) return;
    writeFailed = true;
    consoleError('log: не удалось записать журнал', e);
  }
}

function rotate(): void {
  const old = path.join(path.dirname(file), OLD_FILE_NAME);
  fs.rmSync(old, { force: true });
  fs.renameSync(file, old);
  size = 0;
}

function stamp(): string {
  const d = new Date();
  const p = (n: number, w = 2): string => String(n).padStart(w, '0');
  return (
    `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ` +
    `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}.${p(d.getMilliseconds(), 3)}`
  );
}
