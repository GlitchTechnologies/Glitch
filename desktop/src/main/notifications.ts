
import { Notification, nativeImage } from 'electron';
import type { AppNotification } from '../shared/ipc';
import { ICON_PATH } from './config';
import { getMainWindow } from './main-window';

const shown = new Map<string, Notification>();

let onClick: (chatId: number | null, tag: string) => void = () => undefined;

let flashing = false;

export function setNotificationClickHandler(handler: (chatId: number | null, tag: string) => void): void {
  onClick = handler;
}

export function showNotification(n: AppNotification): void {
  if (!Notification.isSupported()) return;
  closeNotification(n.tag);
  const note = new Notification({ title: n.title, body: n.body, icon: iconOf(n), silent: n.chatId != null });
  note.on('click', () => {
    if (shown.get(n.tag) === note) shown.delete(n.tag);
    onClick(n.chatId ?? null, n.tag);
  });
  shown.set(n.tag, note);
  note.show();
}

function iconOf(n: AppNotification): Electron.NativeImage | string {
  if (!n.icon) return ICON_PATH;
  const image = nativeImage.createFromBuffer(Buffer.from(n.icon));
  return image.isEmpty() ? ICON_PATH : image;
}

export function closeNotification(tag: string): void {
  const note = shown.get(tag);
  if (!note) return;
  shown.delete(tag);
  note.close();
}

export function closeAllNotifications(): void {
  for (const note of shown.values()) note.close();
  shown.clear();
}

export function requestAttention(bringToFront: () => void): void {
  bringToFront();
  const win = getMainWindow();
  if (!win || win.isFocused() || flashing) return;
  flashing = true;
  win.flashFrame(true);
  win.once('focus', () => {
    flashing = false;
    if (!win.isDestroyed()) win.flashFrame(false);
  });
}
