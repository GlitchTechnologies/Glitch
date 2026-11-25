
import { app, ipcMain, IpcMainEvent, IpcMainInvokeEvent } from 'electron';
import type {
  AppNotification,
  DesktopInfo,
  DxgiSettings,
  InfoChannel,
  InvokeChannels,
  PageChannels,
  PopoutKind,
  SendChannels,
  UnreadBadgeFrame,
} from '../shared/ipc';
import { TITLE_BAR_HEIGHT } from './config';
import { downloadFromApp } from './downloads';
import { onPageReady } from './links';
import { applyTheme, getMainWindow, isAppUrl } from './main-window';
import { closeAllNotifications, closeNotification, requestAttention, showNotification } from './notifications';
import { closePopout, isPopoutKind, openPopout, popoutOf, postToPopout, recolorPopouts } from './popouts';
import {
  chooseScreenSource, commitDxgi, dxgiCaptureTimings, listScreenSources, readDxgiAudio, startDxgi, stopDxgi, stopDxgiAudio,
} from './screen-share';
import { readScreenCaptureTimings } from './screen-capture-debug';
import { dxgiCaptureAvailable } from './dxgi-screen-capture';
import { bringToFront, onAppReady } from './startup';
import { store } from './store';
import { isLang } from './strings';
import { watchGames } from './games';
import { watchGlobalKeys } from './global-keys';
import { pauseProgramHotkeys, programHotkeys, reservedHotkeys, setProgramHotkeys } from './hotkeys';
import { readSystemSettings, setCloseToTray, setOpenAtLogin } from './system-settings';
import { refreshTray, setTrayVoice, setUnread } from './tray';

/** Версия того, что умеет связь. Glitch на сайте обновляется раньше
 *  программы у человека и новое умение спрашивает по этому числу.
 *   1 — окно, тема, язык, выбор экрана, «Сохранить как» (этап 1);
 *   2 — уведомления, «внимание» при звонке, красная точка, микрофон и звук
 *       в меню трея, акцент в теме (этап 2; акцент не нужен с 2026-10-10 —
 *       меню трея стало обычным меню Windows);
 *   3 — наши ссылки открываются в программе (этап 3);
 *   4 — раздел «Система»: автозапуск и что делает ✕ (этап 3);
 *   5 — нажатие на уведомление возвращает и его метку, уведомление может
 *       быть не о чате (запросы дружбы, 2026-10-11);
 *   6 — отдельные окна Glitch (popouts.ts): «Отладка» голоса (2026-10-14);
 *   7 — занятые программой сочетания клавиш (hotkeys.ts) в сведениях —
 *       для горячих клавиш Glitch (режим рации, 2026-10-22);
 *   8 — горячие клавиши Glitch поверх других окон (global-keys.ts: рация
 *       в игре, 2026-10-22);
 *   9 — что с перехватом клавиш (`glitch:global-keys-status`) — для журнала
 *       Glitch (2026-10-22);
 *  10 — горячие клавиши программы меняются из Glitch (hotkeys.ts, раздел
 *       «Горячие клавиши», 2026-10-22);
 *  11 — запущенные игры для «Играет в» (games.ts, 2026-11-07);
 *  12 — отдельное окно редактора темы и передача его правок;
 *  13 — значки кнопок главного окна следуют предпросмотру темы;
 *  14 — замеры захвата экрана для «Отладки»;
 *  15 — видеодорожка DXGI на локальном стенде;
 *  16 — звук WASAPI для демонстрации через DXGI;
 *  17 — способ захвата и счётчики DXGI в «Отладке». */
const API_VERSION = 17;
const INFO: InfoChannel = 'glitch:info';

function fromApp(event: IpcMainEvent | IpcMainInvokeEvent): boolean {
  const main = getMainWindow()?.webContents;
  const frame = event.senderFrame;
  return main !== undefined && event.sender === main && frame === main.mainFrame && isAppUrl(frame.url);
}

function fromPopout(event: IpcMainEvent | IpcMainInvokeEvent): PopoutKind | null {
  const frame = event.senderFrame;
  if (frame === null || !isAppUrl(frame.url)) return null;
  return popoutOf(event.sender);
}

function on<K extends keyof SendChannels>(channel: K, handler: (...args: SendChannels[K]) => void): void {
  ipcMain.on(channel, (event, ...args) => {
    if (!fromApp(event)) return;
    handler(...(args as SendChannels[K]));
  });
}

function handle<K extends keyof InvokeChannels>(
  channel: K,
  handler: (...args: InvokeChannels[K]['args']) => Promise<InvokeChannels[K]['result']>,
): void {
  ipcMain.handle(channel, (event, ...args) => {
    if (!fromApp(event)) throw new Error('forbidden');
    return handler(...(args as InvokeChannels[K]['args']));
  });
}

export function sendToApp<K extends keyof PageChannels>(channel: K, ...args: PageChannels[K]): void {
  const contents = getMainWindow()?.webContents;
  if (!contents || !isAppUrl(contents.getURL())) return;
  contents.send(channel, ...args);
}

const isText = (v: unknown, max: number): v is string => typeof v === 'string' && v.length <= max;

const isCaptureId = (v: unknown): v is string => isText(v, 36) && /^[a-f\d-]{36}$/.test(v);
const isTrackId = (v: unknown): v is string => isText(v, 128) && v.length > 0;

function validDxgiSettings(v: unknown): v is DxgiSettings {
  if (!v || typeof v !== 'object') return false;
  const { fps, maxWidth, maxHeight } = v as Partial<DxgiSettings>;
  const dimension = (n: unknown): n is number =>
    typeof n === 'number' && Number.isInteger(n) && n > 0 && n <= 16384;
  return typeof fps === 'number' && Number.isInteger(fps) && fps >= 1 && fps <= 60 &&
    ((maxWidth === null && maxHeight === null) || (dimension(maxWidth) && dimension(maxHeight)));
}

const MAX_POPOUT_DATA = 1024 * 1024;

const MAX_NOTIFICATION_ICON_BYTES = 512 * 1024;

function validNotification(v: unknown): v is AppNotification {
  if (!v || typeof v !== 'object') return false;
  const n = v as Record<string, unknown>;
  return (
    isText(n.tag, 64) &&
    isText(n.title, 300) &&
    isText(n.body, 1000) &&
    (n.chatId === undefined || (typeof n.chatId === 'number' && Number.isSafeInteger(n.chatId))) &&
    (n.icon === undefined || (n.icon instanceof Uint8Array && n.icon.byteLength <= MAX_NOTIFICATION_ICON_BYTES))
  );
}

const MAX_BADGE_FRAMES = 8;
const MAX_BADGE_FRAME_BYTES = 64 * 1024;

function validBadge(v: unknown): v is UnreadBadgeFrame[] {
  return (
    Array.isArray(v) &&
    v.length > 0 &&
    v.length <= MAX_BADGE_FRAMES &&
    v.every((f: unknown) => {
      if (!f || typeof f !== 'object') return false;
      const frame = f as Record<string, unknown>;
      return (
        typeof frame.scale === 'number' &&
        frame.scale >= 1 &&
        frame.scale <= 4 &&
        frame.png instanceof Uint8Array &&
        frame.png.byteLength > 0 &&
        frame.png.byteLength <= MAX_BADGE_FRAME_BYTES
      );
    })
  );
}

export function installBridge(): void {
  ipcMain.on(INFO, (event) => {
    const popout = fromPopout(event);
    const info: DesktopInfo = {
      apiVersion: API_VERSION,
      appVersion: app.getVersion(),
      chromeVersion: process.versions.chrome,
      titleBarHeight: TITLE_BAR_HEIGHT,
      popout,
      reservedHotkeys: reservedHotkeys(),
      dxgiCapture: popout === null && dxgiCaptureAvailable(),
    };
    event.returnValue = fromApp(event) || popout !== null ? info : null;
  });

  on('glitch:ready', () => {
    onAppReady();
    onPageReady();
  });

  on('glitch:set-theme', (background, foreground, visibleForeground) => {
    if (typeof background !== 'string' || typeof foreground !== 'string') return;
    const preview = typeof visibleForeground === 'string' ? visibleForeground : undefined;
    if (applyTheme(background, foreground, preview)) recolorPopouts();
  });

  on('glitch:set-locale', (code) => {
    if (typeof code !== 'string' || !isLang(code) || store.get().locale === code) return;
    store.update({ locale: code });
    refreshTray();
  });

  on('glitch:notify', (notification) => {
    if (validNotification(notification)) showNotification(notification);
  });

  on('glitch:notify-close', (tag) => {
    if (isText(tag, 64)) closeNotification(tag);
  });

  on('glitch:notify-clear', () => closeAllNotifications());

  on('glitch:attention', () => requestAttention(bringToFront));

  on('glitch:set-unread', (count, badge) => {
    if (typeof count !== 'number' || !Number.isSafeInteger(count) || count < 0) return;
    setUnread(count, validBadge(badge) ? badge : null);
  });

  on('glitch:set-voice', (state) => {
    if (state === null) {
      setTrayVoice(null);
      return;
    }
    if (!state || typeof state.micOff !== 'boolean' || typeof state.deafOff !== 'boolean') return;
    setTrayVoice({ micOff: state.micOff, deafOff: state.deafOff });
  });

  on('glitch:watch-global-keys', (keys) => watchGlobalKeys(keys));
  on('glitch:watch-games', (games) => watchGames(games));

  on('glitch:pause-program-hotkeys', (paused) => {
    if (typeof paused === 'boolean') pauseProgramHotkeys(paused);
  });

  on('glitch:popout-open', (kind) => {
    if (isPopoutKind(kind)) openPopout(kind);
  });

  on('glitch:popout-close', (kind) => {
    if (isPopoutKind(kind)) closePopout(kind);
  });

  on('glitch:popout-post', (kind, data) => {
    if (isPopoutKind(kind) && isText(data, MAX_POPOUT_DATA)) postToPopout(kind, data);
  });

  ipcMain.on('glitch:popout-ready' satisfies keyof SendChannels, (event) => {
    const kind = fromPopout(event);
    if (kind !== null) sendToApp('glitch:popout-ready', kind);
  });

  ipcMain.on('glitch:theme-editor-action' satisfies keyof SendChannels, (event, data: unknown) => {
    if (fromPopout(event) === 'theme-editor' && isText(data, 4096)) {
      sendToApp('glitch:theme-editor-action', data);
    }
  });

  handle('glitch:screen-list', () => listScreenSources());

  handle('glitch:screen-choose', async (id, withAudio) => {
    if (typeof id !== 'string' || typeof withAudio !== 'boolean') return false;
    return chooseScreenSource(id, withAudio);
  });
  handle('glitch:screen-capture-timings', async (publicationId, trackId) => {
    if (!isTrackId(publicationId)) return null;
    const native = isTrackId(trackId) ? dxgiCaptureTimings(trackId) : null;
    if (native) return native;
    return {
      ...readScreenCaptureTimings(publicationId),
      details: { backend: 'chromium', mode: app.isPackaged ? 'installed' : 'dev' },
    };
  });
  handle('glitch:dxgi-start', async (id, settings, supportsAudio) => {
    const frame = getMainWindow()?.webContents.mainFrame;
    if (!frame || !isCaptureId(id) || !validDxgiSettings(settings) || typeof supportsAudio !== 'boolean') return null;
    return startDxgi(id, settings, frame, supportsAudio);
  });
  handle('glitch:dxgi-audio-read', async (id) => isCaptureId(id) ? readDxgiAudio(id) : null);
  handle('glitch:dxgi-audio-stop', async (id) => {
    if (isCaptureId(id)) stopDxgiAudio(id);
  });
  handle('glitch:dxgi-ready', async (id, trackId) => isCaptureId(id) && isTrackId(trackId) && commitDxgi(id, trackId));
  handle('glitch:dxgi-stop', async (id) => {
    if (isCaptureId(id)) stopDxgi(id);
  });

  handle('glitch:download', async (url, fileName) => {
    if (typeof url !== 'string' || typeof fileName !== 'string') return 'failed';
    return downloadFromApp(url, fileName);
  });

  handle('glitch:system-settings', async () => readSystemSettings());

  handle('glitch:set-open-at-login', async (on) => {
    if (typeof on !== 'boolean') return readSystemSettings();
    return setOpenAtLogin(on);
  });

  handle('glitch:set-close-to-tray', async (on) => {
    if (typeof on !== 'boolean') return readSystemSettings();
    return setCloseToTray(on);
  });

  handle('glitch:program-hotkeys', async () => programHotkeys());

  handle('glitch:set-program-hotkeys', async (hotkeys) => setProgramHotkeys(hotkeys));
}
