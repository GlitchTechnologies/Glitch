import type { ProgramHotkey, ProgramHotkeyAction } from '../shared/ipc';
import { store } from './store';

const ACTIONS: readonly ProgramHotkeyAction[] = ['reload', 'zoom-in', 'zoom-out', 'zoom-reset'];

const DEFAULT_HOTKEYS: readonly { action: ProgramHotkeyAction; keys: string[] }[] = [
  { action: 'reload', keys: ['Control', 'KeyR'] },
  { action: 'zoom-in', keys: ['Control', 'Equal'] },
  { action: 'zoom-in', keys: ['Control', 'NumpadAdd'] },
  { action: 'zoom-out', keys: ['Control', 'Minus'] },
  { action: 'zoom-out', keys: ['Control', 'NumpadSubtract'] },
  { action: 'zoom-reset', keys: ['Control', 'Digit0'] },
  { action: 'zoom-reset', keys: ['Control', 'Numpad0'] },
];

const MODIFIERS: readonly string[] = ['Control', 'Shift', 'Alt', 'Meta'];

const MAX_HOTKEYS = 32;
const MAX_KEYS = 4;

type Bind = { action: ProgramHotkeyAction; keys: string[] };

function current(): readonly Bind[] {
  const saved = store.get().hotkeys;
  return saved !== undefined && validBinds(saved) ? saved : DEFAULT_HOTKEYS;
}

function mainKey(keys: readonly string[]): string {
  return keys.find((k) => !MODIFIERS.includes(k)) ?? '';
}

function validBind(v: unknown): v is Bind {
  if (!v || typeof v !== 'object') return false;
  const b = v as Record<string, unknown>;
  const keys = b.keys;
  return (
    typeof b.action === 'string' &&
    (ACTIONS as readonly string[]).includes(b.action) &&
    Array.isArray(keys) &&
    keys.length >= 1 &&
    keys.length <= MAX_KEYS &&
    keys.every((k: unknown) => typeof k === 'string' && /^[A-Za-z0-9]{1,32}$/.test(k)) &&
    new Set(keys).size === keys.length &&
    keys.filter((k) => !MODIFIERS.includes(k as string)).length === 1 &&
    !(keys as string[]).some((k) => k.startsWith('Mouse'))
  );
}

function validBinds(v: unknown): v is Bind[] {
  if (!Array.isArray(v) || v.length > MAX_HOTKEYS || !v.every(validBind)) return false;
  const seen = new Set(v.map((b: Bind) => [...b.keys].sort().join('+')));
  return seen.size === v.length;
}

export function programHotkeys(): ProgramHotkey[] {
  return current().map((b) => ({ action: b.action, keys: [...b.keys] }));
}

export function setProgramHotkeys(v: unknown): ProgramHotkey[] {
  if (Array.isArray(v)) {
    const binds = v.map((b: unknown) =>
      b && typeof b === 'object' ? { action: (b as Bind).action, keys: (b as Bind).keys } : b,
    );
    if (validBinds(binds)) store.update({ hotkeys: binds });
  }
  return programHotkeys();
}

let paused = false;

export function pauseProgramHotkeys(on: boolean): void {
  paused = on;
}

export function programHotkeyOf(input: Electron.Input): ProgramHotkeyAction | null {
  if (paused || input.type !== 'keyDown') return null;
  for (const b of current()) {
    if (mainKey(b.keys) !== input.code) continue;
    const has = (m: string) => b.keys.includes(m);
    if (input.control !== has('Control') || input.shift !== has('Shift')) continue;
    if (input.alt !== has('Alt') || input.meta !== has('Meta')) continue;
    return b.action;
  }
  return null;
}

export function reservedHotkeys(): string[][] {
  return current().map((b) => [...b.keys]);
}
