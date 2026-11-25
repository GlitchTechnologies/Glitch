// Предзагрузка работает в песочнице. Она импортирует отсюда только типы.

export interface DesktopInfo {
  apiVersion: number;
  appVersion: string;
  chromeVersion: string;
  titleBarHeight: number;
  popout: PopoutKind | null;
  reservedHotkeys: string[][];
  dxgiCapture: boolean;
}

export type ProgramHotkeyAction = 'reload' | 'zoom-in' | 'zoom-out' | 'zoom-reset';

export interface ProgramHotkey {
  action: ProgramHotkeyAction;
  keys: string[];
}

export type PopoutKind = 'voice-debug' | 'theme-editor';

export interface UnreadBadgeFrame {
  scale: number;
  png: Uint8Array;
}

export interface ScreenSource {
  id: string;
  name: string;
  kind: 'window' | 'screen';
  thumbnail: string | null;
  icon: string | null;
}

export type DownloadResult = 'saved' | 'cancelled' | 'failed';

export interface AppNotification {
  tag: string;
  title: string;
  body: string;
  chatId?: number;
  icon?: Uint8Array;
}

export interface VoiceTrayState {
  micOff: boolean;
  deafOff: boolean;
}

export type TrayCommand = 'toggle-mic' | 'toggle-deafen';

export interface SystemSettings {
  openAtLogin: boolean;
  closeToTray: boolean;
}

export interface GlobalKeysStatus {
  state: 'running' | 'heard' | 'stopped' | 'failed' | 'rejected';
  detail?: string;
}

export interface WatchedGame {
  id: number;
  executables: string[];
}

/** Найденная запущенная игра: номер из справочника и когда запущена (мс от
 *  1970 по часам ЭТОГО компьютера — Glitch считает «сколько идёт» по тем же
 *  часам, поэтому сбитые часы ничего не портят). */
export interface RunningGame {
  id: number;
  startedAt: number;
}

export interface SendChannels {
  'glitch:ready': [];
  'glitch:set-theme': [background: string, foreground: string, visibleForeground?: string];
  'glitch:set-locale': [code: string];

  'glitch:notify': [notification: AppNotification];
  'glitch:notify-close': [tag: string];
  'glitch:notify-clear': [];
  'glitch:attention': [];
  'glitch:set-unread': [count: number, badge: UnreadBadgeFrame[] | null];
  'glitch:set-voice': [state: VoiceTrayState | null];

  'glitch:popout-open': [kind: PopoutKind];
  'glitch:popout-close': [kind: PopoutKind];
  'glitch:popout-post': [kind: PopoutKind, data: string];
  'glitch:popout-ready': [];
  'glitch:theme-editor-action': [data: string];

  'glitch:watch-global-keys': [keys: string[]];

  'glitch:pause-program-hotkeys': [paused: boolean];

  'glitch:watch-games': [games: WatchedGame[]];
}

export interface PageChannels {
  'glitch:dxgi-ended': [captureId: string];
  'glitch:notification-click': [chatId: number | null, tag: string];
  'glitch:tray-command': [command: TrayCommand];
  'glitch:open-link': [url: string];

  'glitch:popout-ready': [kind: PopoutKind];
  'glitch:popout-closed': [kind: PopoutKind];
  'glitch:popout-data': [data: string];
  'glitch:theme-editor-action': [data: string];

  'glitch:global-keys': [keys: string[]];
  'glitch:global-keys-status': [status: GlobalKeysStatus];

  'glitch:running-games': [games: RunningGame[]];
}

export interface ScreenCaptureTimings {
  attemptsPerSecond?: number;
  acquireMs?: number;
  prepareMs?: number;
  intervalMs?: number;
  configuredFps?: number;
  details?: ScreenCaptureDetails;
}

export interface ScreenCaptureDetails {
  backend: 'chromium' | 'dxgi';
  mode: 'installed' | 'dev';
  audio?: 'wasapi' | 'unavailable' | 'off';
  inputFps?: number;
  preparedFps?: number;
  sentFps?: number;
  noSlot?: number;
  replaced?: number;
  pacedOut?: number;
  sendDropped?: number;
  avgPrepareMs?: number;
  maxFrameGapMs?: number;
}

export interface DxgiSettings {
  fps: number;
  maxWidth: number | null;
  maxHeight: number | null;
}

export type DxgiStreamResult = 'video' | 'audio-video' | 'sound-dropped';

export interface WasapiRead {
  ready: boolean;
  sampleRate: number;
  channels: number;
  packets: { pcm: Uint8Array<ArrayBuffer>; frames: number; timestamp: number }[];
}

export interface InvokeChannels {
  'glitch:screen-list': { args: []; result: ScreenSource[] };
  'glitch:screen-choose': { args: [id: string, withAudio: boolean]; result: boolean };
  'glitch:screen-capture-timings': { args: [publicationId: string, trackId?: string]; result: ScreenCaptureTimings | null };
  'glitch:dxgi-start': {
    args: [captureId: string, quality: DxgiSettings, supportsAudio: boolean];
    result: { withAudio: boolean } | null;
  };
  'glitch:dxgi-ready': { args: [captureId: string, trackId: string]; result: boolean };
  'glitch:dxgi-stop': { args: [captureId: string]; result: void };
  'glitch:dxgi-audio-read': { args: [captureId: string]; result: WasapiRead | null };
  'glitch:dxgi-audio-stop': { args: [captureId: string]; result: void };
  'glitch:download': { args: [url: string, fileName: string]; result: DownloadResult };

  'glitch:system-settings': { args: []; result: SystemSettings };
  'glitch:set-open-at-login': { args: [on: boolean]; result: SystemSettings };
  'glitch:set-close-to-tray': { args: [on: boolean]; result: SystemSettings };

  'glitch:program-hotkeys': { args: []; result: ProgramHotkey[] };
  'glitch:set-program-hotkeys': { args: [hotkeys: ProgramHotkey[]]; result: ProgramHotkey[] };
}

export const INFO_CHANNEL = 'glitch:info';
export type InfoChannel = typeof INFO_CHANNEL;

export interface SplashState {
  text: string;
  retryLabel: string | null;
  progress: number | null;
}

export interface SplashSendChannels {
  'splash:retry': [];
}

export const SPLASH_STATE_CHANNEL = 'splash:state';
export type SplashStateChannel = typeof SPLASH_STATE_CHANNEL;
