
import { app, Menu, nativeImage, Notification, Tray } from 'electron';
import type { MenuItemConstructorOptions, NativeImage } from 'electron';
import type { TrayCommand, UnreadBadgeFrame, VoiceTrayState } from '../shared/ipc';
import { ICON_PATH, ICON_UNREAD_PATH } from './config';
import { logEvent } from './log';
import { getMainWindow } from './main-window';
import { store } from './store';
import { t } from './strings';

let tray: Tray | null = null;
let open: () => void = () => undefined;
let command: (c: TrayCommand) => void = () => undefined;

let voice: VoiceTrayState | null = null;
let unread = 0;
let badge: NativeImage | null = null;

export interface TrayHooks {
  onOpen: () => void;
  onCommand: (c: TrayCommand) => void;
}

export function createTray(hooks: TrayHooks): void {
  open = hooks.onOpen;
  command = hooks.onCommand;
  tray = new Tray(ICON_PATH);
  tray.setToolTip(t().trayTooltip);
  tray.on('click', () => {
    logEvent('трей: нажат значок');
    open();
  });
  updateMenu();
}

export function refreshTray(): void {
  if (!tray) return;
  tray.setToolTip(t().trayTooltip);
  updateMenu();
  applyUnreadBadge();
}

export function setTrayVoice(state: VoiceTrayState | null): void {
  voice = state;
  updateMenu();
}

export function setUnread(count: number, frames: UnreadBadgeFrame[] | null): void {
  unread = count;
  badge = count > 0 && frames ? badgeImage(frames) : null;
  applyUnreadBadge();
}

export function maybeShowTrayHint(): void {
  if (store.get().trayHintShown) return;
  store.update({ trayHintShown: true });
  if (!Notification.isSupported()) return;
  const s = t();
  const note = new Notification({ title: s.stillRunningTitle, body: s.stillRunningBody, icon: ICON_PATH });
  note.on('click', () => open());
  note.show();
}

export function destroyTray(): void {
  tray?.destroy();
  tray = null;
}


function updateMenu(): void {
  if (!tray) return;
  const s = t();
  const items: MenuItemConstructorOptions[] = [
    {
      label: s.trayOpen,
      click: () => {
        logEvent('трей: «Открыть Glitch»');
        open();
      },
    },
    { type: 'separator' },
  ];
  if (voice) {
    items.push(
      { label: s.trayMicOff, type: 'checkbox', checked: voice.micOff, click: () => command('toggle-mic') },
      { label: s.traySoundOff, type: 'checkbox', checked: voice.deafOff, click: () => command('toggle-deafen') },
      { type: 'separator' },
    );
  }
  items.push({
    label: s.trayQuit,
    click: () => {
      logEvent('трей: «Выйти из Glitch»');
      app.quit();
    },
  });
  tray.setContextMenu(Menu.buildFromTemplate(items));
}

export function applyUnreadBadge(): void {
  tray?.setImage(unread > 0 ? ICON_UNREAD_PATH : ICON_PATH);
  const win = getMainWindow();
  if (!win) return;
  if (unread > 0 && badge) win.setOverlayIcon(badge, t().unreadBadge);
  else win.setOverlayIcon(null, '');
}

/** Все размеры значка — в одну картинку: Windows сама берёт тот, что под
 *  масштаб экрана. Битый кадр пропускается; ни одного целого — значка нет. */
function badgeImage(frames: UnreadBadgeFrame[]): NativeImage | null {
  const image = nativeImage.createEmpty();
  for (const f of frames) {
    image.addRepresentation({ scaleFactor: f.scale, buffer: Buffer.from(f.png) });
  }
  return image.isEmpty() ? null : image;
}
