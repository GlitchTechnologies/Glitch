
import { BrowserWindow, screen } from 'electron';
import { store, WindowBounds, WindowState } from './store';

export interface WindowSize {
  width: number;
  height: number;
}

const MIN_VISIBLE = 100;

export function initialBounds(saved: WindowBounds | undefined, size: WindowSize, min: WindowSize): WindowBounds {
  if (saved && isUsable(saved)) {
    return {
      ...saved,
      width: Math.max(saved.width, min.width),
      height: Math.max(saved.height, min.height),
    };
  }
  const area = screen.getPrimaryDisplay().workArea;
  const width = Math.min(size.width, area.width);
  const height = Math.min(size.height, area.height);
  return {
    x: Math.round(area.x + (area.width - width) / 2),
    y: Math.round(area.y + (area.height - height) / 2),
    width,
    height,
  };
}

export function wasMaximized(): boolean {
  return store.get().window?.maximized === true;
}

export function trackWindowState(win: BrowserWindow, save: (state: WindowState) => void): void {
  const changed = (): void => {
    if (win.isDestroyed() || win.isMinimized()) return;
    save({ bounds: win.getNormalBounds(), maximized: win.isMaximized() });
  };
  win.on('resize', changed);
  win.on('move', changed);
  win.on('maximize', changed);
  win.on('unmaximize', changed);
  win.on('hide', changed);
  win.on('close', changed);
}

function isUsable(b: WindowBounds): boolean {
  if (![b.x, b.y, b.width, b.height].every(Number.isFinite)) return false;
  return screen.getAllDisplays().some(({ workArea: a }) => {
    const w = Math.min(b.x + b.width, a.x + a.width) - Math.max(b.x, a.x);
    const h = Math.min(b.y + b.height, a.y + a.height) - Math.max(b.y, a.y);
    return w >= MIN_VISIBLE && h >= MIN_VISIBLE;
  });
}
