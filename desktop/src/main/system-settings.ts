
import { app } from 'electron';
import type { SystemSettings } from '../shared/ipc';
import { AUTOSTART_ARG } from './config';
import { store } from './store';

const LOGIN_ITEM = { path: process.execPath, args: [AUTOSTART_ARG] };

export function readSystemSettings(): SystemSettings {
  return { openAtLogin: opensAtLogin(), closeToTray: closesToTray() };
}

export function setOpenAtLogin(on: boolean): SystemSettings {
  if (app.isPackaged) {
    try {
      app.setLoginItemSettings({ openAtLogin: on, enabled: on, ...LOGIN_ITEM });
    } catch (e) {
      console.error('system-settings: Windows не дала изменить автозапуск', e);
    }
  }
  return readSystemSettings();
}

export function setCloseToTray(on: boolean): SystemSettings {
  store.update({ closeToTray: on });
  return readSystemSettings();
}

export function closesToTray(): boolean {
  return store.get().closeToTray !== false;
}

export function launchedAtLogin(argv: readonly string[]): boolean {
  return argv.includes(AUTOSTART_ARG);
}

function opensAtLogin(): boolean {
  if (!app.isPackaged) return false;
  try {
    const s = app.getLoginItemSettings(LOGIN_ITEM);
    return s.openAtLogin && s.executableWillLaunchAtLogin;
  } catch (e) {
    console.error('system-settings: не удалось прочитать автозапуск', e);
    return false;
  }
}
