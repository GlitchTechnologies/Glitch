
import { BrowserWindow } from 'electron';
import type { SplashState } from '../shared/ipc';
import { APP_URL, READY_TIMEOUT_MS, RETRY_DELAYS_S } from './config';
import { isAppUrl } from './main-window';
import {
  closeSplash,
  focusSplash,
  isSplashOpen,
  openSplash,
  setSplashRetryHandler,
  setSplashState,
  splashBounds,
} from './splash';
import { showUpdateWindow } from './update-window';
import { t } from './strings';
import { updateBeforeStart } from './updater';
import { wasMaximized } from './window-state';
import { logEvent, yesNo } from './log';

const ERR_ABORTED = -3;

let main: BrowserWindow | null = null;
let revealed = false;
let wantVisible = true;
let shownOnce = false;
let loadFailed = false;
let failures = 0;
let splashState: SplashState = { text: '', retryLabel: null, progress: null };

let readyTimer: NodeJS.Timeout | null = null;
let retryTimer: NodeJS.Timeout | null = null;

export function startApp(win: BrowserWindow, options: { hidden: boolean }): void {
  main = win;
  wantVisible = !options.hidden;
  setSplashRetryHandler(retryNow);
  const contents = win.webContents;

  contents.on('did-fail-load', (_event, code, description, _url, isMainFrame) => {
    if (!isMainFrame || code === ERR_ABORTED) return;
    console.warn(`Glitch не загрузился: ${code} ${description}`);
    onLoadFailed();
  });
  contents.on('did-finish-load', () => {
    if (loadFailed || !isAppUrl(contents.getURL())) return;
    logEvent(`страница: загружена (окно показано раньше: ${yesNo(revealed)})`);
    failures = 0;
    clearTimer('ready');
    if (revealed) return;
    readyTimer = setTimeout(reveal, READY_TIMEOUT_MS);
  });
  contents.on('render-process-gone', (_event, details) => {
    if (details.reason === 'clean-exit') return;
    console.error('Страница Glitch упала:', details.reason, 'код:', details.exitCode);
    load();
  });

  void updateBeforeStart(
    {
      onChecking: () => showSplash({ text: t().splashCheckingUpdates, retryLabel: null, progress: null }),
      onDownloading: (fraction) =>
        showSplash({ text: t().splashDownloadingUpdate, retryLabel: null, progress: fraction }),
      onInstalling: () => {
        const text = t().splashInstallingUpdate;
        showSplash({ text, retryLabel: null, progress: null });
        const bounds = wantVisible ? splashBounds() : null;
        return bounds ? showUpdateWindow(bounds, text) : Promise.resolve(null);
      },
    },
    options,
  ).then((outcome) => {
    logEvent(`обновление: ${outcome === 'installing' ? 'ставим новую версию' : 'запускаемся как есть'}`);
    if (outcome === 'installing') return;
    showSplash({ text: t().splashStarting, retryLabel: null, progress: null });
    load();
  });
}

export function onAppReady(): void {
  logEvent('страница: Glitch нарисован');
  reveal();
}

/** Ctrl+R. */
export function reloadApp(): void {
  if (!main || main.isDestroyed()) return;
  loadFailed = false;
  main.webContents.reload();
}

export function bringToFront(): void {
  logEvent(`показать: ${describeMain()}, заставка открыта: ${yesNo(isSplashOpen())}`);
  if (!main || main.isDestroyed()) return;
  wantVisible = true;
  if (revealed) {
    showMain();
    return;
  }
  if (isSplashOpen()) focusSplash();
  else showSplash(splashState);
}


function load(): void {
  if (!main || main.isDestroyed()) return;
  clearTimer('ready');
  clearTimer('retry');
  loadFailed = false;
  main.loadURL(APP_URL).catch(() => undefined);
}

function onLoadFailed(): void {
  if (!main || main.isDestroyed()) return;
  loadFailed = true;
  clearTimer('ready');
  if (revealed) {
    revealed = false;
    wantVisible = main.isVisible();
    main.hide();
  }
  failures += 1;
  const delay = RETRY_DELAYS_S[Math.min(failures, RETRY_DELAYS_S.length) - 1];
  countdown(delay);
}

function countdown(seconds: number): void {
  clearTimer('retry');
  const s = t();
  showSplash({ text: s.splashOffline(seconds), retryLabel: s.splashRetryNow, progress: null });
  retryTimer = setTimeout(() => {
    if (seconds > 1) {
      countdown(seconds - 1);
    } else {
      showSplash({ text: t().splashConnecting, retryLabel: null, progress: null });
      load();
    }
  }, 1000);
}

function retryNow(): void {
  showSplash({ text: t().splashConnecting, retryLabel: null, progress: null });
  load();
}

function reveal(): void {
  clearTimer('ready');
  if (revealed || !main || main.isDestroyed() || loadFailed) return;
  revealed = true;
  logEvent(`запуск: Glitch готов, показываем окно: ${yesNo(wantVisible)}`);
  closeSplash();
  if (wantVisible) showMain();
}

function showMain(): void {
  if (!main || main.isDestroyed()) return;
  if (!shownOnce && wasMaximized()) {
    main.maximize();
  } else if (main.isMinimized()) {
    main.restore();
  }
  shownOnce = true;
  main.show();
  main.focus();
  logEvent(`показать: после показа — ${describeMain()}`);
}

function describeMain(): string {
  if (!main) return 'окна нет';
  if (main.isDestroyed()) return 'окно уничтожено';
  return (
    `окно показано раньше: ${yesNo(revealed)}, видно: ${yesNo(main.isVisible())}, ` +
    `свёрнуто: ${yesNo(main.isMinimized())}, развёрнуто: ${yesNo(main.isMaximized())}`
  );
}

function showSplash(state: SplashState): void {
  splashState = state;
  if (!wantVisible) return;
  if (isSplashOpen()) setSplashState(state);
  else openSplash(state);
}

function clearTimer(which: 'ready' | 'retry'): void {
  if (which === 'ready' && readyTimer) {
    clearTimeout(readyTimer);
    readyTimer = null;
  }
  if (which === 'retry' && retryTimer) {
    clearTimeout(retryTimer);
    retryTimer = null;
  }
}
