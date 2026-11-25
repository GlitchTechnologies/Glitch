
import { contextBridge, ipcRenderer, sharedTexture } from 'electron';
import type {
  AppNotification,
  DesktopInfo,
  DxgiSettings,
  DxgiStreamResult,
  GlobalKeysStatus,
  InfoChannel,
  InvokeChannels,
  PageChannels,
  PopoutKind,
  ProgramHotkey,
  RunningGame,
  SendChannels,
  UnreadBadgeFrame,
  VoiceTrayState,
  WatchedGame,
} from '../shared/ipc';

function send<K extends keyof SendChannels>(channel: K, ...args: SendChannels[K]): void {
  ipcRenderer.send(channel, ...args);
}

function invoke<K extends keyof InvokeChannels>(
  channel: K,
  ...args: InvokeChannels[K]['args']
): Promise<InvokeChannels[K]['result']> {
  return ipcRenderer.invoke(channel, ...args) as Promise<InvokeChannels[K]['result']>;
}

function listen<K extends keyof PageChannels>(channel: K, listener: (...args: PageChannels[K]) => void): void {
  ipcRenderer.on(channel, (_event, ...args) => listener(...(args as PageChannels[K])));
}

const INFO: InfoChannel = 'glitch:info';
const info = ipcRenderer.sendSync(INFO) as DesktopInfo | null;

declare const MediaStreamTrackGenerator: {
  new (options: { kind: 'video' }): MediaStreamTrack & { writable: WritableStream<VideoFrame> };
  new (options: { kind: 'audio' }): MediaStreamTrack & { writable: WritableStream<AudioData> };
};

type DxgiAudioTrack = {
  track: MediaStreamTrack;
  writer: WritableStreamDefaultWriter<AudioData>;
  ready: (ready: boolean) => void;
  timer?: ReturnType<typeof setTimeout>;
  startupTimeout?: ReturnType<typeof setTimeout>;
};

type DxgiTrack = {
  id: string;
  track: MediaStreamTrack;
  writer: WritableStreamDefaultWriter<VideoFrame>;
  firstFrame: (ready: boolean) => void;
  timer: ReturnType<typeof setInterval> | undefined;
  committed: boolean;
  audio?: DxgiAudioTrack;
};

const canReceiveDxgi = info?.dxgiCapture === true &&
  typeof sharedTexture?.setSharedTextureReceiver === 'function' &&
  typeof MediaStreamTrackGenerator === 'function';
let dxgiTrack: DxgiTrack | null = null;

function closeDxgiAudio(capture: DxgiTrack, notify: boolean): void {
  const audio = capture.audio;
  if (!audio) return;
  capture.audio = undefined;
  clearTimeout(audio.timer);
  clearTimeout(audio.startupTimeout);
  audio.ready(false);
  const live = audio.track.readyState === 'live';
  audio.track.stop();
  if (notify && live) audio.track.dispatchEvent(new Event('ended'));
  void audio.writer.abort().catch(() => undefined).finally(() => audio.writer.releaseLock());
}

function stopDxgiAudio(capture: DxgiTrack): void {
  closeDxgiAudio(capture, capture.committed);
  void invoke('glitch:dxgi-audio-stop', capture.id).catch(() => undefined);
}

async function pumpDxgiAudio(capture: DxgiTrack, audio: DxgiAudioTrack): Promise<void> {
  try {
    if (audio.track.readyState === 'ended') {
      stopDxgiAudio(capture);
      return;
    }
    const sample = await invoke('glitch:dxgi-audio-read', capture.id);
    if (capture.audio !== audio) return;
    if (!sample) {
      stopDxgiAudio(capture);
      return;
    }
    for (const packet of sample.packets) {
      if (capture.audio !== audio) return;
      const data = new AudioData({
        format: 's16',
        sampleRate: sample.sampleRate,
        numberOfChannels: sample.channels,
        numberOfFrames: packet.frames,
        timestamp: packet.timestamp,
        data: packet.pcm,
      });
      try {
        await audio.writer.write(data);
      } finally {
        data.close();
      }
    }
    if (capture.audio !== audio) return;
    if (sample.ready) {
      clearTimeout(audio.startupTimeout);
      audio.ready(true);
    }
    audio.timer = setTimeout(() => void pumpDxgiAudio(capture, audio), 10);
  } catch {
    if (capture.audio === audio) stopDxgiAudio(capture);
  }
}

function startDxgiAudio(capture: DxgiTrack): Promise<boolean> {
  try {
    if (typeof AudioData !== 'function') throw new Error('Нет генератора звука');
    const track = new MediaStreamTrackGenerator({ kind: 'audio' });
    track.contentHint = 'music';
    const writer = track.writable.getWriter();
    return new Promise<boolean>((ready) => {
      const audio: DxgiAudioTrack = { track, writer, ready };
      capture.audio = audio;
      audio.startupTimeout = setTimeout(() => stopDxgiAudio(capture), 2400);
      void pumpDxgiAudio(capture, audio);
    });
  } catch {
    stopDxgiAudio(capture);
    return Promise.resolve(false);
  }
}

function closeDxgiTrack(capture: DxgiTrack, ended: boolean): void {
  if (dxgiTrack !== capture) return;
  dxgiTrack = null;
  clearInterval(capture.timer);
  capture.firstFrame(false);
  closeDxgiAudio(capture, ended && capture.committed);
  const notify = ended && capture.committed && capture.track.readyState === 'live';
  capture.track.stop();
  // stop() не посылает ended сам. При сбое источник должен сообщить LiveKit
  // о завершении, как это делает штатная дорожка браузера.
  if (notify) capture.track.dispatchEvent(new Event('ended'));
  void capture.writer.abort().catch(() => undefined).finally(() => capture.writer.releaseLock());
}

function requestDxgiStop(id: string): Promise<void> {
  return invoke('glitch:dxgi-stop', id).catch(() => undefined);
}

if (canReceiveDxgi) {
  listen('glitch:dxgi-ended', (id) => {
    if (dxgiTrack?.id === id) closeDxgiTrack(dxgiTrack, true);
  });
  sharedTexture.setSharedTextureReceiver(async ({ importedSharedTexture }, id: unknown) => {
    let frame: VideoFrame | undefined;
    const capture = dxgiTrack;
    try {
      if (!capture || capture.id !== id || capture.track.readyState !== 'live' ||
          (capture.writer.desiredSize ?? 0) <= 0) return;
      frame = importedSharedTexture.getVideoFrame();
      await capture.writer.write(frame);
      capture.firstFrame(true);
    } catch {
      if (capture && capture === dxgiTrack) {
        closeDxgiTrack(capture, true);
        void requestDxgiStop(capture.id);
      }
    } finally {
      frame?.close();
      importedSharedTexture.release();
    }
  });
  window.addEventListener('pagehide', () => {
    if (dxgiTrack) closeDxgiTrack(dxgiTrack, false);
  });
}

async function captureDxgiStream(
  elementId: string, settings: DxgiSettings, supportsAudio: boolean,
): Promise<DxgiStreamResult | null> {
  if (!canReceiveDxgi || dxgiTrack || typeof elementId !== 'string') return null;
  const element = document.getElementById(elementId);
  if (!(element instanceof HTMLVideoElement) || element.srcObject) return null;
  const id = crypto.randomUUID();
  const track = new MediaStreamTrackGenerator({ kind: 'video' });
  track.contentHint = 'motion';
  let firstFrame!: DxgiTrack['firstFrame'];
  const first = new Promise<boolean>((resolve) => { firstFrame = resolve; });
  const capture: DxgiTrack = {
    id, track, writer: track.writable.getWriter(), firstFrame, timer: undefined, committed: false,
  };
  dxgiTrack = capture;
  try {
    const started = await invoke('glitch:dxgi-start', id, settings, supportsAudio);
    if (!started || dxgiTrack !== capture) return null;
    const audio = started.withAudio ? startDxgiAudio(capture) : Promise.resolve(false);
    const [hasVideo, hasAudio] = await Promise.all([first, audio]);
    if (!hasVideo || dxgiTrack !== capture || !element.isConnected) return null;
    const audioTrack = hasAudio ? capture.audio?.track : undefined;
    const stream = new MediaStream(audioTrack ? [track, audioTrack] : [track]);
    element.srcObject = stream;
    if (!await invoke('glitch:dxgi-ready', id, track.id) || dxgiTrack !== capture) return null;
    capture.committed = true;
    capture.timer = setInterval(() => {
      if (track.readyState === 'ended') {
        closeDxgiTrack(capture, false);
        void requestDxgiStop(id);
      }
    }, 250);
    if (audioTrack?.readyState === 'live') return 'audio-video';
    if (audioTrack) stream.removeTrack(audioTrack);
    return started.withAudio ? 'sound-dropped' : 'video';
  } finally {
    if (!capture.committed) {
      element.srcObject = null;
      closeDxgiTrack(capture, false);
      await requestDxgiStop(id);
    }
  }
}


const BADGE_SLOT = 16;
const BADGE_HEIGHT = 12;
const BADGE_RED = '#f23f43';
const BADGE_SCALES = [1, 1.25, 1.5, 2, 2.5, 3];
const BADGE_MAX = 99;

async function drawBadgeFrame(text: string, scale: number): Promise<UnreadBadgeFrame> {
  const side = Math.round(BADGE_SLOT * scale);
  const canvas = new OffscreenCanvas(side, side);
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('no 2d');
  const h = BADGE_HEIGHT * scale;
  let font = h * 0.72;
  const setFont = () => (ctx.font = `700 ${font}px "Segoe UI", sans-serif`);
  setFont();
  const room = side - h * 0.3;
  const measured = ctx.measureText(text).width;
  if (measured > room) {
    font *= room / measured;
    setFont();
  }
  const metrics = ctx.measureText(text);
  const w = Math.min(side, Math.max(h, metrics.width + h * 0.45));

  ctx.fillStyle = BADGE_RED;
  ctx.beginPath();
  ctx.roundRect((side - w) / 2, (side - h) / 2, w, h, h / 2);
  ctx.fill();

  ctx.fillStyle = '#ffffff';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'alphabetic';
  const y = side / 2 + (metrics.actualBoundingBoxAscent - metrics.actualBoundingBoxDescent) / 2;
  ctx.fillText(text, side / 2, y);

  const blob = await canvas.convertToBlob({ type: 'image/png' });
  return { scale, png: new Uint8Array(await blob.arrayBuffer()) };
}

let unreadSeq = 0;

async function setUnread(count: number): Promise<void> {
  const seq = ++unreadSeq;
  let badge: UnreadBadgeFrame[] | null = null;
  if (count > 0) {
    const text = count > BADGE_MAX ? `${BADGE_MAX}+` : String(count);
    try {
      badge = await Promise.all(BADGE_SCALES.map((scale) => drawBadgeFrame(text, scale)));
    } catch {
      badge = null;
    }
  }
  if (seq !== unreadSeq) return;
  send('glitch:set-unread', count, badge);
}

if (info && info.popout) {
  contextBridge.exposeInMainWorld('glitchDesktop', {
    apiVersion: info.apiVersion,
    appVersion: info.appVersion,
    chromeVersion: info.chromeVersion,
    titleBarHeight: info.titleBarHeight,
    popout: info.popout,
    popoutReady: () => send('glitch:popout-ready'),
    onPopoutData: (listener: (data: string) => void) => listen('glitch:popout-data', listener),
    ...(info.popout === 'theme-editor'
      ? { sendThemeEditorAction: (data: string) => send('glitch:theme-editor-action', data) }
      : {}),
  });
} else if (info) {
  contextBridge.exposeInMainWorld('glitchDesktop', {
    apiVersion: info.apiVersion,
    appVersion: info.appVersion,
    chromeVersion: info.chromeVersion,
    titleBarHeight: info.titleBarHeight,
    ready: () => send('glitch:ready'),
    setTheme: (background: string, foreground: string, visibleForeground?: string) =>
      send('glitch:set-theme', background, foreground, visibleForeground),
    setLocale: (code: string) => send('glitch:set-locale', code),
    listScreenSources: () => invoke('glitch:screen-list'),
    chooseScreenSource: (id: string, withAudio: boolean) => invoke('glitch:screen-choose', id, withAudio),
    screenCaptureTimings: (publicationId: string, trackId?: string) =>
      invoke('glitch:screen-capture-timings', publicationId, trackId),
    ...(canReceiveDxgi ? {
      captureDxgiVideo: async (id: string, settings: DxgiSettings) => (await captureDxgiStream(id, settings, false)) !== null,
      captureDxgiStream: (id: string, settings: DxgiSettings) => captureDxgiStream(id, settings, true),
    } : {}),
    download: (url: string, fileName: string) => invoke('glitch:download', url, fileName),
    // ── apiVersion 2 ──
    notify: (notification: AppNotification) => send('glitch:notify', notification),
    closeNotification: (tag: string) => send('glitch:notify-close', tag),
    clearNotifications: () => send('glitch:notify-clear'),
    requestAttention: () => send('glitch:attention'),
    setUnread: (count: number) => void setUnread(count),
    setVoice: (state: VoiceTrayState | null) => send('glitch:set-voice', state),
    onNotificationClick: (listener: (chatId: number | null, tag: string) => void) =>
      listen('glitch:notification-click', listener),
    onTrayCommand: (listener: (command: string) => void) => listen('glitch:tray-command', listener),
    // ── apiVersion 3 ──
    onOpenLink: (listener: (url: string) => void) => listen('glitch:open-link', listener),
    // ── apiVersion 4 ──
    getSystemSettings: () => invoke('glitch:system-settings'),
    setOpenAtLogin: (on: boolean) => invoke('glitch:set-open-at-login', on),
    setCloseToTray: (on: boolean) => invoke('glitch:set-close-to-tray', on),
    // ── apiVersion 6 ──
    openPopout: (kind: PopoutKind) => send('glitch:popout-open', kind),
    closePopout: (kind: PopoutKind) => send('glitch:popout-close', kind),
    postToPopout: (kind: PopoutKind, data: string) => send('glitch:popout-post', kind, data),
    onPopoutReady: (listener: (kind: PopoutKind) => void) => listen('glitch:popout-ready', listener),
    onPopoutClosed: (listener: (kind: PopoutKind) => void) => listen('glitch:popout-closed', listener),
    onThemeEditorAction: (listener: (data: string) => void) => listen('glitch:theme-editor-action', listener),
    // ── apiVersion 7 ──
    reservedHotkeys: info.reservedHotkeys,
    // ── apiVersion 8 ──
    watchGlobalKeys: (keys: string[]) => send('glitch:watch-global-keys', keys),
    onGlobalKeys: (listener: (keys: string[]) => void) => listen('glitch:global-keys', listener),
    // ── apiVersion 9 ──
    onGlobalKeysStatus: (listener: (status: GlobalKeysStatus) => void) =>
      listen('glitch:global-keys-status', listener),
    // ── apiVersion 10 ──
    getProgramHotkeys: () => invoke('glitch:program-hotkeys'),
    setProgramHotkeys: (hotkeys: ProgramHotkey[]) => invoke('glitch:set-program-hotkeys', hotkeys),
    pauseProgramHotkeys: (paused: boolean) => send('glitch:pause-program-hotkeys', paused),
    // ── apiVersion 11 ──
    watchGames: (games: WatchedGame[]) => send('glitch:watch-games', games),
    onRunningGames: (listener: (games: RunningGame[]) => void) => listen('glitch:running-games', listener),
  });
}

if (info) {
  window.addEventListener('DOMContentLoaded', () => {
    const drag = document.createElement('div');
    drag.setAttribute('aria-hidden', 'true');
    drag.style.cssText = [
      'position:fixed',
      'top:0',
      'left:0',
      'right:0',
      `height:${info.titleBarHeight}px`,
      'z-index:2147483647',
      'app-region:drag',
      '-webkit-app-region:drag',
    ].join(';');
    document.body.appendChild(drag);
    document.addEventListener('fullscreenchange', () => {
      drag.style.display = document.fullscreenElement ? 'none' : '';
    });
  });
}
