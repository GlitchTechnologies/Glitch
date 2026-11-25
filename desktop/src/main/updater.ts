
import { app } from 'electron';
import { autoUpdater, BaseUpdater, CancellationToken, type ProgressInfo } from 'electron-updater';
import { UPDATE_CHECK_TIMEOUT_MS, UPDATE_STALL_TIMEOUT_MS } from './config';
import { markQuitting } from './main-window';
import { store } from './store';
import type { UpdateWindow } from './update-window';

export type UpdateOutcome = 'start' | 'installing';

export interface UpdateHooks {
  onChecking: () => void;
  onDownloading: (fraction: number) => void;
  onInstalling: () => Promise<UpdateWindow | null>;
}

const UPDATED_ARG = '--updated';

export async function updateBeforeStart(hooks: UpdateHooks, options: { hidden: boolean }): Promise<UpdateOutcome> {
  if (!app.isPackaged) return 'start';
  if (!(autoUpdater instanceof BaseUpdater)) return 'start';
  const updater = autoUpdater;

  updater.autoDownload = false;
  updater.autoInstallOnAppQuit = false;

  hooks.onChecking();
  const version = await newerVersion();
  if (!version) return 'start';

  if (!(await download(hooks))) return 'start';

  const installWindow = await hooks.onInstalling();
  if (options.hidden) store.update({ hiddenAfterUpdate: version });
  store.flush();
  if (!updater.install(true, true)) {
    console.warn('updater: движок установки не запустился');
    installWindow?.close();
    if (options.hidden) store.update({ hiddenAfterUpdate: undefined });
    return 'start';
  }
  markQuitting('ставим обновление');
  app.quit();
  return 'installing';
}

export function consumeHiddenAfterUpdate(argv: readonly string[]): boolean {
  const version = store.get().hiddenAfterUpdate;
  if (version === undefined) return false;
  store.update({ hiddenAfterUpdate: undefined });
  return argv.includes(UPDATED_ARG) && version === app.getVersion();
}


async function newerVersion(): Promise<string | null> {
  let timer: NodeJS.Timeout | null = null;
  const timeout = new Promise<null>((resolve) => {
    timer = setTimeout(() => resolve(null), UPDATE_CHECK_TIMEOUT_MS);
  });
  try {
    const result = await Promise.race([autoUpdater.checkForUpdates(), timeout]);
    if (!result || !result.isUpdateAvailable) return null;
    return result.updateInfo.version;
  } catch (e) {
    console.warn('updater: проверка не удалась', e);
    return null;
  } finally {
    if (timer) clearTimeout(timer);
  }
}

async function download(hooks: UpdateHooks): Promise<boolean> {
  const token = new CancellationToken();
  let stall: NodeJS.Timeout | null = null;
  const watchStall = (): void => {
    if (stall) clearTimeout(stall);
    stall = setTimeout(() => {
      console.warn('updater: загрузка встала — запускаемся без обновления');
      token.cancel();
    }, UPDATE_STALL_TIMEOUT_MS);
  };
  const onProgress = (p: ProgressInfo): void => {
    watchStall();
    hooks.onDownloading(Math.min(1, Math.max(0, p.percent / 100)));
  };

  hooks.onDownloading(0);
  watchStall();
  autoUpdater.on('download-progress', onProgress);
  try {
    await autoUpdater.downloadUpdate(token);
    return !token.cancelled;
  } catch (e) {
    console.warn('updater: загрузка не удалась', e);
    return false;
  } finally {
    autoUpdater.removeListener('download-progress', onProgress);
    if (stall) clearTimeout(stall);
  }
}
