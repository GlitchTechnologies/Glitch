import * as path from 'path';
import { app } from 'electron';
import type { PopoutKind } from '../shared/ipc';


export const APP_ORIGIN = 'https://web.glitchapp.online';
export const APP_URL = `${APP_ORIGIN}/`;

const captureModule = 'glitch_screen_capture.node';
export const DXGI_MODULE_PATH = app.isPackaged
  ? path.join(process.resourcesPath, 'screen-capture', captureModule)
  : path.join(app.getAppPath(), 'build', 'screen-capture', 'x86_64-pc-windows-msvc', 'release', captureModule);

export const APP_ID = 'ru.glitchapp.desktop';


export const TITLE_BAR_HEIGHT = 32;

export const WINDOW_DEFAULT = { width: 1280, height: 720 };
export const WINDOW_MIN = { width: 940, height: 500 };

export const POPOUT_WINDOWS: Record<PopoutKind, { size: { width: number; height: number }; min: { width: number; height: number } }> = {
  'voice-debug': { size: { width: 980, height: 760 }, min: { width: 760, height: 480 } },
  'theme-editor': { size: { width: 410, height: 780 }, min: { width: 340, height: 420 } },
};

export const SPLASH_SIZE = { width: 380, height: 380 };

export const DARK = {
  bg: '#151515',
  card: '#1C1C1C',
  border: '#2C2C2C',
  text: '#EDEDED',
  textSecond: '#8A8A8A',
  textHint: '#7A7A7A',
  accent: '#2FAE9A',
};


export const READY_TIMEOUT_MS = 15_000;

export const RETRY_DELAYS_S = [5, 10, 20, 30];

export const DEVTOOLS_SWITCH = 'glitch-devtools';


export const ZOOM_STEPS = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2];


export const LINK_SCHEME = 'glitch';


export const AUTOSTART_ARG = '--autostart';


export const UPDATE_CHECK_TIMEOUT_MS = 10_000;

export const UPDATE_STALL_TIMEOUT_MS = 60_000;

export const UPDATE_WINDOW_READY_TIMEOUT_MS = 3_000;


export const SCREEN_THUMB = { width: 320, height: 180 };

export const SCREEN_CHOICE_TTL_MS = 30_000;
export const DXGI_FIRST_FRAME_TIMEOUT_MS = 3000;
export const DXGI_POLL_MS = 4;
export const DXGI_STOP_TIMEOUT_MS = 2500;
export const DXGI_STOP_POLL_MS = 50;


export const DOWNLOAD_START_TIMEOUT_MS = 30_000;


export const LOG_MAX_BYTES = 1_000_000;


export const STATIC_DIR = path.join(__dirname, '..', '..', 'static');
export const ICON_PATH = path.join(STATIC_DIR, 'icon.ico');
export const ICON_UNREAD_PATH = path.join(STATIC_DIR, 'icon-unread.ico');
export const SPLASH_HTML = path.join(STATIC_DIR, 'splash.html');

export const APP_PRELOAD = path.join(__dirname, '..', 'preload', 'app-preload.js');
export const SPLASH_PRELOAD = path.join(__dirname, '..', 'preload', 'splash-preload.js');
