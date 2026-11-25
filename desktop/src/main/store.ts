
import { app } from 'electron';
import * as fs from 'fs';
import * as path from 'path';
import type { PopoutKind, ProgramHotkeyAction } from '../shared/ipc';

export interface WindowBounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface WindowState {
  bounds: WindowBounds;
  maximized: boolean;
}

export interface StoreData {
  window?: WindowState;
  popouts?: Partial<Record<PopoutKind, WindowState>>;
  zoom?: number;
  trayHintShown?: boolean;
  locale?: string;
  theme?: { background: string; foreground: string };
  closeToTray?: boolean;
  hiddenAfterUpdate?: string;
  dxgiCheckpoint?: { version: string; state: 'active' | 'blocked' };
  hotkeys?: { action: ProgramHotkeyAction; keys: string[] }[];
}

const WRITE_DELAY_MS = 500;

class Store {
  private data: StoreData = {};
  private file = '';
  private timer: NodeJS.Timeout | null = null;

  load(): void {
    this.file = path.join(app.getPath('userData'), 'glitch-desktop.json');
    try {
      const parsed: unknown = JSON.parse(fs.readFileSync(this.file, 'utf8'));
      this.data = parsed && typeof parsed === 'object' ? (parsed as StoreData) : {};
    } catch {
      this.data = {};
    }
  }

  get(): Readonly<StoreData> {
    return this.data;
  }

  update(patch: Partial<StoreData>): void {
    this.data = { ...this.data, ...patch };
    if (this.timer) clearTimeout(this.timer);
    this.timer = setTimeout(() => this.flush(), WRITE_DELAY_MS);
  }

  flush(): void {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = null;
    }
    if (!this.file) return;
    const tmp = `${this.file}.tmp`;
    try {
      fs.mkdirSync(path.dirname(this.file), { recursive: true });
      fs.writeFileSync(tmp, JSON.stringify(this.data, null, 2), 'utf8');
      fs.renameSync(tmp, this.file);
    } catch (e) {
      console.error('store: не удалось записать настройки', e);
    }
  }
}

export const store = new Store();
