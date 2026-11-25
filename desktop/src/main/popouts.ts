
import { app, BrowserWindow, WebContents } from 'electron';
import type { PageChannels, PopoutKind } from '../shared/ipc';
import { APP_ORIGIN, APP_PRELOAD, DARK, DEVTOOLS_SWITCH, ICON_PATH, POPOUT_WINDOWS, TITLE_BAR_HEIGHT } from './config';
import { currentZoom, isAppUrl, openExternalSafe } from './main-window';
import { store } from './store';
import { initialBounds, trackWindowState } from './window-state';

const DATA_CHANNEL: keyof PageChannels = 'glitch:popout-data';

const ERR_ABORTED = -3;

const windows = new Map<PopoutKind, BrowserWindow>();

let onClosed: ((kind: PopoutKind) => void) | null = null;

export function initPopouts(hooks: { closed: (kind: PopoutKind) => void }): void {
  onClosed = hooks.closed;
}

export function isPopoutKind(v: unknown): v is PopoutKind {
  return typeof v === 'string' && Object.prototype.hasOwnProperty.call(POPOUT_WINDOWS, v);
}

function live(kind: PopoutKind): BrowserWindow | null {
  const win = windows.get(kind);
  return win && !win.isDestroyed() ? win : null;
}

export function popoutOf(contents: WebContents): PopoutKind | null {
  for (const [kind, win] of windows) {
    if (!win.isDestroyed() && win.webContents === contents) return kind;
  }
  return null;
}

export function openPopout(kind: PopoutKind): void {
  const existing = live(kind);
  if (existing) {
    if (existing.isMinimized()) existing.restore();
    existing.show();
    existing.focus();
    return;
  }

  const { size, min } = POPOUT_WINDOWS[kind];
  const saved = store.get().popouts?.[kind];
  const theme = store.get().theme;
  const background = theme?.background ?? DARK.card;
  const foreground = theme?.foreground ?? DARK.text;

  const win = new BrowserWindow({
    ...initialBounds(saved?.bounds, size, min),
    minWidth: min.width,
    minHeight: min.height,
    show: false,
    title: 'Glitch',
    icon: ICON_PATH,
    backgroundColor: background,
    titleBarStyle: 'hidden',
    titleBarOverlay: { color: background, symbolColor: foreground, height: TITLE_BAR_HEIGHT },
    webPreferences: {
      preload: APP_PRELOAD,
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      devTools: app.commandLine.hasSwitch(DEVTOOLS_SWITCH),
      spellcheck: false,
    },
  });
  windows.set(kind, win);
  trackWindowState(win, (state) => store.update({ popouts: { ...store.get().popouts, [kind]: state } }));

  win.once('ready-to-show', () => {
    if (saved?.maximized) win.maximize();
    win.show();
  });
  win.on('closed', () => {
    if (windows.get(kind) === win) windows.delete(kind);
    onClosed?.(kind);
  });

  const contents = win.webContents;
  contents.setWindowOpenHandler(({ url }) => {
    openExternalSafe(url);
    return { action: 'deny' };
  });
  const guard = (event: Electron.Event, url: string): void => {
    if (isAppUrl(url)) return;
    event.preventDefault();
    openExternalSafe(url);
  };
  contents.on('will-navigate', guard);
  contents.on('will-redirect', guard);
  contents.on('did-finish-load', () => contents.setZoomFactor(currentZoom()));
  contents.on('did-fail-load', (_event, code, _description, _url, isMainFrame) => {
    if (isMainFrame && code !== ERR_ABORTED && !win.isDestroyed()) win.close();
  });

  win.loadURL(`${APP_ORIGIN}/popout/${kind}`).catch((e) => console.error('popout: не загрузилось', kind, e));
}

export function closePopout(kind: PopoutKind): void {
  live(kind)?.close();
}

export function closeAllPopouts(): void {
  for (const win of windows.values()) {
    if (!win.isDestroyed()) win.close();
  }
}

export function postToPopout(kind: PopoutKind, data: string): void {
  const contents = live(kind)?.webContents;
  if (!contents || !isAppUrl(contents.getURL())) return;
  contents.send(DATA_CHANNEL, data);
}

export function recolorPopouts(): void {
  const theme = store.get().theme;
  if (!theme) return;
  for (const win of windows.values()) {
    if (win.isDestroyed()) continue;
    win.setTitleBarOverlay({ color: theme.background, symbolColor: theme.foreground, height: TITLE_BAR_HEIGHT });
    win.setBackgroundColor(theme.background);
  }
}
