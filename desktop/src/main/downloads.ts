
import { app, session } from 'electron';
import * as path from 'path';
import type { DownloadResult } from '../shared/ipc';
import { DOWNLOAD_START_TIMEOUT_MS } from './config';
import { getMainWindow } from './main-window';

interface Pending {
  fileName: string;
  resolve: (result: DownloadResult) => void;
  timer: NodeJS.Timeout;
}

const pending = new Map<string, Pending>();

const BAD_NAME_CHARS = /[<>:"/\\|?*\u0000-\u001f]/g;

function safeFileName(name: string): string {
  const cleaned = path.basename(name).replace(BAD_NAME_CHARS, '_').trim();
  return cleaned.length > 0 ? cleaned : 'glitch-file';
}

export function downloadFromApp(url: string, fileName: string): Promise<DownloadResult> {
  const main = getMainWindow();
  let protocol = '';
  try {
    protocol = new URL(url).protocol;
  } catch {
  }
  if (!main || protocol !== 'https:') return Promise.resolve('failed');
  pending.get(url)?.resolve('cancelled');
  return new Promise<DownloadResult>((resolve) => {
    const entry: Pending = {
      fileName: safeFileName(fileName),
      resolve: (result) => {
        clearTimeout(entry.timer);
        if (pending.get(url) === entry) pending.delete(url);
        resolve(result);
      },
      timer: setTimeout(() => entry.resolve('failed'), DOWNLOAD_START_TIMEOUT_MS),
    };
    pending.set(url, entry);
    main.webContents.downloadURL(url);
  });
}

export function installDownloadHandler(): void {
  session.defaultSession.on('will-download', (_event, item) => {
    const key = item.getURLChain()[0] ?? item.getURL();
    const started = pending.get(key);
    const name = started ? started.fileName : safeFileName(item.getFilename());
    item.setSaveDialogOptions({ defaultPath: path.join(app.getPath('downloads'), name) });
    if (!started) return;
    pending.delete(key);
    clearTimeout(started.timer);
    item.once('done', (_e, state) => {
      started.resolve(state === 'completed' ? 'saved' : state === 'cancelled' ? 'cancelled' : 'failed');
    });
  });
}
