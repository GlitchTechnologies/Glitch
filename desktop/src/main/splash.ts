import { BrowserWindow, ipcMain } from 'electron';
import type { Rectangle } from 'electron';
import type { SplashSendChannels, SplashState, SplashStateChannel } from '../shared/ipc';
import { DARK, ICON_PATH, SPLASH_HTML, SPLASH_PRELOAD, SPLASH_SIZE } from './config';

const STATE_CHANNEL: SplashStateChannel = 'splash:state';
const RETRY_CHANNEL: keyof SplashSendChannels = 'splash:retry';

let win: BrowserWindow | null = null;
let lastState: SplashState | null = null;
let pageReady = false;
let onRetry: (() => void) | null = null;

export function setSplashRetryHandler(handler: () => void): void {
  onRetry = handler;
}

ipcMain.on(RETRY_CHANNEL, (event) => {
  if (!win || win.isDestroyed() || event.sender !== win.webContents) return;
  onRetry?.();
});

export function openSplash(state: SplashState): void {
  lastState = state;
  if (win && !win.isDestroyed()) {
    sendState();
    win.show();
    win.focus();
    return;
  }
  win = new BrowserWindow({
    width: SPLASH_SIZE.width,
    height: SPLASH_SIZE.height,
    center: true,
    frame: false,
    resizable: false,
    maximizable: false,
    minimizable: true,
    fullscreenable: false,
    transparent: true,
    backgroundColor: '#00000000',
    show: false,
    title: 'Glitch',
    icon: ICON_PATH,
    webPreferences: {
      preload: SPLASH_PRELOAD,
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      devTools: false,
      spellcheck: false,
    },
  });
  const created = win;
  pageReady = false;
  created.once('ready-to-show', () => {
    if (!created.isDestroyed()) created.show();
  });
  created.webContents.on('did-finish-load', () => {
    if (win !== created) return;
    pageReady = true;
    sendState();
  });
  created.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  created.webContents.on('will-navigate', (e) => e.preventDefault());
  created.on('closed', () => {
    if (win === created) win = null;
  });
  void created.loadFile(SPLASH_HTML, {
    query: { card: DARK.card, border: DARK.border, text: DARK.text, second: DARK.textSecond, accent: DARK.accent },
  });
}

export function setSplashState(state: SplashState): void {
  lastState = state;
  sendState();
}

function sendState(): void {
  if (!win || win.isDestroyed() || !lastState || !pageReady) return;
  win.webContents.send(STATE_CHANNEL, lastState);
}

export function splashBounds(): Rectangle | null {
  return win && !win.isDestroyed() ? win.getBounds() : null;
}

export function isSplashOpen(): boolean {
  return win !== null && !win.isDestroyed();
}

export function focusSplash(): void {
  if (!win || win.isDestroyed()) return;
  if (win.isMinimized()) win.restore();
  win.show();
  win.focus();
}

export function closeSplash(): void {
  if (win && !win.isDestroyed()) win.destroy();
  win = null;
  lastState = null;
  pageReady = false;
}
