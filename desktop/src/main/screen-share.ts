
import { app, desktopCapturer, screen, session } from 'electron';
import type { WebContents, WebFrameMain } from 'electron';
import type { DxgiSettings, ScreenSource } from '../shared/ipc';
import { DXGI_FIRST_FRAME_TIMEOUT_MS, SCREEN_CHOICE_TTL_MS, SCREEN_THUMB } from './config';
import { DxgiScreenCapture, dxgiCaptureAvailable } from './dxgi-screen-capture';
import { logEvent } from './log';
import { getMainWindow, isAppUrl } from './main-window';
import { store } from './store';

const THUMB_JPEG_QUALITY = 70;

interface Choice {
  id: string;
  name: string;
  withAudio: boolean;
  displayId: string;
  at: number;
}

let choice: Choice | null = null;
let choiceGeneration = 0;
let dxgiStopping = false;
let dxgi: {
  id: string;
  capture: DxgiScreenCapture;
  choice: Choice;
  firstFrameTimeout: NodeJS.Timeout | null;
} | null = null;

export async function listScreenSources(): Promise<ScreenSource[]> {
  const sources = await desktopCapturer.getSources({
    types: ['window', 'screen'],
    thumbnailSize: SCREEN_THUMB,
    fetchWindowIcons: true,
  });
  const own = getMainWindow()?.getMediaSourceId();
  return sources
    .filter((s) => s.id !== own)
    .map((s) => ({
      id: s.id,
      name: s.name,
      kind: s.id.startsWith('screen:') ? 'screen' : 'window',
      thumbnail: s.thumbnail.isEmpty()
        ? null
        : `data:image/jpeg;base64,${s.thumbnail.toJPEG(THUMB_JPEG_QUALITY).toString('base64')}`,
      icon: s.appIcon && !s.appIcon.isEmpty() ? s.appIcon.toDataURL() : null,
    }));
}

export async function chooseScreenSource(id: string, withAudio: boolean): Promise<boolean> {
  if (dxgi?.firstFrameTimeout) stopDxgi(dxgi.id);
  choice = null;
  const generation = ++choiceGeneration;
  const sources = await desktopCapturer.getSources({
    types: ['window', 'screen'],
    thumbnailSize: { width: 0, height: 0 },
  });
  if (generation !== choiceGeneration) return false;
  const found = sources.find((s) => s.id === id);
  if (!found) return false;
  choice = { id: found.id, name: found.name, withAudio, displayId: found.display_id, at: Date.now() };
  return true;
}

function freshChoice(picked: Choice | null): picked is Choice {
  return picked !== null && Date.now() - picked.at <= SCREEN_CHOICE_TTL_MS;
}

function isOnlyMonitor(picked: Choice): boolean {
  return screen.getAllDisplays().length === 1 &&
    picked.displayId === String(screen.getPrimaryDisplay().id);
}

function saveDxgiCheckpoint(state?: 'active' | 'blocked'): void {
  store.update({ dxgiCheckpoint: state ? { version: app.getVersion(), state } : undefined });
  store.flush();
}

function clearActiveDxgiCheckpoint(): void {
  if (store.get().dxgiCheckpoint?.state === 'active') saveDxgiCheckpoint();
}

function recoverDxgiCheckpoint(): void {
  const checkpoint = store.get().dxgiCheckpoint;
  if (!checkpoint) return;
  if (checkpoint.version !== app.getVersion()) {
    saveDxgiCheckpoint();
  } else if (checkpoint.state === 'active') {
    saveDxgiCheckpoint('blocked');
    logEvent('показ экрана: предыдущий запуск Glitch оборвался при активном DXGI, используется штатный захват');
  }
}

export function startDxgi(id: string, settings: DxgiSettings, frame: WebFrameMain, supportsAudio: boolean): { withAudio: boolean } | null {
  const picked = choice;
  if (store.get().dxgiCheckpoint?.state === 'blocked' || !dxgiCaptureAvailable() || dxgi || dxgiStopping ||
      !freshChoice(picked) || (picked.withAudio && !supportsAudio) ||
      !picked.id.startsWith('screen:') || !isOnlyMonitor(picked)) return null;
  saveDxgiCheckpoint('active');
  try {
    const capture = new DxgiScreenCapture(id, frame, settings, picked.withAudio, () => stopDxgi(id));
    const firstFrameTimeout = setTimeout(() => {
      console.warn('Захват DXGI: не получен первый кадр');
      stopDxgi(id);
    }, DXGI_FIRST_FRAME_TIMEOUT_MS);
    dxgi = { id, capture, choice: picked, firstFrameTimeout };
    return { withAudio: picked.withAudio };
  } catch (error) {
    console.warn('Запуск захвата DXGI:', error);
    clearActiveDxgiCheckpoint();
    return null;
  }
}

export function readDxgiAudio(id: string) {
  return dxgi?.id === id ? dxgi.capture.readAudio() : null;
}

export function stopDxgiAudio(id: string): void {
  if (dxgi?.id === id) dxgi.capture.stopAudio();
}

/** Подтверждение одноразовое. До первого кадра тот же выбор остаётся
 *  доступен штатному захвату, если запуск DXGI не удался. */
export function commitDxgi(id: string, trackId: string): boolean {
  if (dxgi?.id !== id || !dxgi.firstFrameTimeout || choice !== dxgi.choice ||
      !freshChoice(choice) || !isOnlyMonitor(choice)) return false;
  clearTimeout(dxgi.firstFrameTimeout);
  dxgi.firstFrameTimeout = null;
  dxgi.capture.commit(trackId);
  choice = null;
  return true;
}

export function stopDxgi(id: string): void {
  if (dxgi?.id !== id) return;
  const { capture, firstFrameTimeout } = dxgi;
  dxgi = null;
  if (firstFrameTimeout) clearTimeout(firstFrameTimeout);
  dxgiStopping = true;
  capture.stop((clean) => {
    dxgiStopping = false;
    if (clean) clearActiveDxgiCheckpoint();
    else saveDxgiCheckpoint('blocked');
  });
}

export function dxgiCaptureTimings(trackId: string) {
  return dxgi?.capture.timings(trackId) ?? null;
}

function resetScreenShare(): void {
  ++choiceGeneration;
  choice = null;
  if (dxgi) stopDxgi(dxgi.id);
}

export function finishScreenShareOnQuit(): void {
  resetScreenShare();
  clearActiveDxgiCheckpoint();
}

export function bindScreenShareLifecycle(contents: WebContents): void {
  contents.on('render-process-gone', (_event, details) => {
    if (dxgi && details.reason !== 'clean-exit') {
      saveDxgiCheckpoint('blocked');
      logEvent('показ экрана: после сбоя страницы в этой версии Glitch используется штатный захват');
    }
    resetScreenShare();
  });
  contents.on('destroyed', resetScreenShare);
  contents.on('did-start-navigation', (details) => {
    if (details.isMainFrame && !details.isSameDocument) resetScreenShare();
  });
}

/** Ответ на getDisplayMedia страницы — только выбранным в окне Glitch. */
export function installDisplayMediaHandler(): void {
  recoverDxgiCheckpoint();
  if (dxgiCaptureAvailable()) {
    // Смена режима того же экрана восстанавливается внутри DXGI-сеанса.
    screen.on('display-added', resetScreenShare);
    screen.on('display-removed', resetScreenShare);
  }
  session.defaultSession.setDisplayMediaRequestHandler((request, callback) => {
    const main = getMainWindow()?.webContents;
    const fromApp =
      main !== undefined &&
      request.frame === main.mainFrame &&
      isAppUrl(request.securityOrigin);
    const picked = choice;
    if (!fromApp || !freshChoice(picked) || !request.videoRequested) {
      // Отказ: у страницы getDisplayMedia завершится ошибкой AbortError.
      callback(null);
      return;
    }
    if (dxgi?.firstFrameTimeout) stopDxgi(dxgi.id);
    choice = null;
    const streams: Electron.Streams = { video: { id: picked.id, name: picked.name } };
    if (picked.withAudio && request.audioRequested) streams.audio = 'loopback';
    callback(streams);
  });
}
