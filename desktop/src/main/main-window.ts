import { app, BrowserWindow, shell } from 'electron';
import {
  APP_ORIGIN,
  APP_PRELOAD,
  DARK,
  DEVTOOLS_SWITCH,
  ICON_PATH,
  TITLE_BAR_HEIGHT,
  WINDOW_DEFAULT,
  WINDOW_MIN,
  ZOOM_STEPS,
} from './config';
import { programHotkeyOf } from './hotkeys';
import { store } from './store';
import { closesToTray } from './system-settings';
import { initialBounds, trackWindowState } from './window-state';
import { logEvent, yesNo } from './log';

let win: BrowserWindow | null = null;
let quitting = false;

export function markQuitting(reason: string): void {
  logEvent(`выход: пометка «идёт выход» (${reason}; была: ${yesNo(quitting)})`);
  quitting = true;
}

export function getMainWindow(): BrowserWindow | null {
  return win && !win.isDestroyed() ? win : null;
}

export function isAppUrl(url: string): boolean {
  try {
    return new URL(url).origin === APP_ORIGIN;
  } catch {
    return false;
  }
}

export function openExternalSafe(url: string): void {
  let protocol: string;
  try {
    protocol = new URL(url).protocol;
  } catch {
    return;
  }
  if (protocol !== 'https:' && protocol !== 'http:' && protocol !== 'mailto:') return;
  shell.openExternal(url).catch((e) => console.error('openExternal', e));
}

export interface MainWindowHooks {
  onHiddenByClose: () => void;
  onReloadRequested: () => void;
}

export function createMainWindow(hooks: MainWindowHooks): BrowserWindow {
  const bounds = initialBounds(store.get().window?.bounds, WINDOW_DEFAULT, WINDOW_MIN);
  const theme = store.get().theme;
  const background = theme?.background ?? DARK.card;
  const foreground = theme?.foreground ?? DARK.text;

  const created = new BrowserWindow({
    ...bounds,
    minWidth: WINDOW_MIN.width,
    minHeight: WINDOW_MIN.height,
    show: false,
    title: 'Glitch',
    icon: ICON_PATH,
    backgroundColor: background,
    titleBarStyle: 'hidden',
    titleBarOverlay: { color: '#00000000', symbolColor: foreground, height: TITLE_BAR_HEIGHT },
    webPreferences: {
      preload: APP_PRELOAD,
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      backgroundThrottling: false,
      devTools: app.commandLine.hasSwitch(DEVTOOLS_SWITCH),
      spellcheck: false,
    },
  });
  win = created;
  trackWindowState(created, (state) => store.update({ window: state }));

  created.on('close', (event) => {
    logEvent(`окно: закрытие (идёт выход: ${yesNo(quitting)}, ✕ в трей: ${yesNo(closesToTray())})`);
    if (quitting) return;
    event.preventDefault();
    if (!closesToTray()) {
      setImmediate(() => app.quit());
      return;
    }
    created.hide();
    hooks.onHiddenByClose();
  });
  created.on('closed', () => {
    logEvent('окно: уничтожено');
    if (win === created) win = null;
  });
  created.on('hide', () => logEvent('окно: спрятано'));
  created.on('show', () => logEvent('окно: показано'));
  created.on('minimize', () => logEvent('окно: свёрнуто'));
  created.on('restore', () => logEvent('окно: развёрнуто из свёрнутого'));
  created.on('query-session-end', (event: Electron.Event & { reasons?: readonly string[] }) =>
    markQuitting(`Windows спрашивает о завершении сеанса: ${event.reasons?.join(', ') || 'без причины'}`),
  );
  created.on('session-end', (event: Electron.Event & { reasons?: readonly string[] }) =>
    markQuitting(`Windows завершает сеанс: ${event.reasons?.join(', ') || 'без причины'}`),
  );

  created.on('page-title-updated', (event) => event.preventDefault());

  const contents = created.webContents;

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

  contents.on('before-input-event', (event, input) => {
    const action = programHotkeyOf(input);
    if (action === null) return;
    event.preventDefault();
    switch (action) {
      case 'reload':
        hooks.onReloadRequested();
        return;
      case 'zoom-in':
        stepZoom(+1);
        return;
      case 'zoom-out':
        stepZoom(-1);
        return;
      case 'zoom-reset':
        setZoom(1);
        return;
    }
  });
  contents.on('zoom-changed', (_event, direction) => stepZoom(direction === 'in' ? +1 : -1));
  contents.on('did-finish-load', () => applyZoom(currentZoom()));

  return created;
}


export function currentZoom(): number {
  const z = store.get().zoom;
  return typeof z === 'number' && ZOOM_STEPS.includes(z) ? z : 1;
}

function stepZoom(direction: 1 | -1): void {
  const index = ZOOM_STEPS.indexOf(currentZoom());
  const next = ZOOM_STEPS[Math.min(ZOOM_STEPS.length - 1, Math.max(0, index + direction))];
  setZoom(next);
}

function setZoom(factor: number): void {
  store.update({ zoom: factor });
  applyZoom(factor);
}

function applyZoom(factor: number): void {
  getMainWindow()?.webContents.setZoomFactor(factor);
}


const HEX_COLOR = /^#[0-9a-fA-F]{6}$/;

export function applyTheme(background: string, foreground: string, visibleForeground?: string): boolean {
  if (!HEX_COLOR.test(background) || !HEX_COLOR.test(foreground)) return false;
  const saved = store.get().theme;
  const changed = saved?.background !== background || saved?.foreground !== foreground;
  if (changed) store.update({ theme: { background, foreground } });
  const w = getMainWindow();
  if (w) {
    const symbolColor = visibleForeground && HEX_COLOR.test(visibleForeground) ? visibleForeground : foreground;
    w.setTitleBarOverlay({ color: '#00000000', symbolColor, height: TITLE_BAR_HEIGHT });
    if (changed) w.setBackgroundColor(background);
  }
  return changed;
}
