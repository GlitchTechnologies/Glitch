
import { app } from 'electron';
import { LINK_SCHEME } from './config';

const MAX_LINK_LENGTH = 100;

const LINK_SHAPE = new RegExp(`^${LINK_SCHEME}://[A-Za-z0-9_\\-./@]+$`, 'i');

let deliver: (url: string) => void = () => undefined;
let attention: () => void = () => undefined;
let pageReady = false;
let pending: string | null = null;

export function initLinks(hooks: { deliver: (url: string) => void; attention: () => void }): void {
  deliver = hooks.deliver;
  attention = hooks.attention;
  if (app.isPackaged) app.setAsDefaultProtocolClient(LINK_SCHEME);
}

export function parseLink(raw: unknown): string | null {
  if (typeof raw !== 'string' || raw.length > MAX_LINK_LENGTH) return null;
  const trimmed = raw.replace(/\/+$/, '');
  return LINK_SHAPE.test(trimmed) ? trimmed : null;
}

export function linkFromArgs(argv: readonly string[]): string | null {
  for (const arg of argv) {
    const link = parseLink(arg);
    if (link) return link;
  }
  return null;
}

export function openLink(link: string): void {
  attention();
  if (pageReady) {
    deliver(link);
    return;
  }
  pending = link;
}

export function onPageReady(): void {
  pageReady = true;
  const link = pending;
  pending = null;
  if (link) deliver(link);
}

export function onPageGone(): void {
  pageReady = false;
}
