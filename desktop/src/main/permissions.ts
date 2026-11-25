
import { session, WebContents } from 'electron';
import { getMainWindow, isAppUrl } from './main-window';
import { popoutOf } from './popouts';

const ALLOWED = new Set<string>([
  'media', // микрофон и камера (голос, звонки, голосовые, кружки)
  'display-capture', // показ экрана — окно выбора рисует сам Glitch
  'speaker-selection', // выбор устройства вывода звука
  'screen-wake-lock', // экран не гаснет, пока идёт видео
  'clipboard-read', // вставка картинок из буфера
  'clipboard-sanitized-write', // копирование картинок
  'fullscreen',
]);

const POPOUT_ALLOWED = new Set<string>(['clipboard-sanitized-write']);

function isMainPage(contents: WebContents | null, origin: string): boolean {
  const main = getMainWindow()?.webContents;
  return contents !== null && main !== undefined && contents === main && isAppUrl(origin);
}

function allowed(contents: WebContents | null, permission: string, origin: string): boolean {
  if (isMainPage(contents, origin)) return ALLOWED.has(permission);
  return contents !== null && isAppUrl(origin) && popoutOf(contents) !== null && POPOUT_ALLOWED.has(permission);
}

export function installPermissionHandlers(): void {
  const ses = session.defaultSession;
  ses.setPermissionRequestHandler((contents, permission, callback, details) => {
    callback(allowed(contents, permission, details.requestingUrl));
  });
  ses.setPermissionCheckHandler((contents, permission, requestingOrigin) => {
    return allowed(contents, permission, requestingOrigin);
  });
}
