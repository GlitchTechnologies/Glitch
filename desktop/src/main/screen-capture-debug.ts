import { contentTracing } from 'electron';
import { mkdtemp, readFile, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { performance } from 'node:perf_hooks';
import type { ScreenCaptureTimings } from '../shared/ipc';

const SLICE_MS = 5000;
const REQUEST_TTL_MS = 3500;
const HISTORY_MS = 60000;
const BUFFER_KB = 1024;
const MAX_TRACE_BYTES = 4 * 1024 * 1024;

interface Sample {
  attemptsPerSecond: number;
  acquireMs: number;
  prepareMs: number;
  intervalMs: number;
}

/** Метки Chromium — в микросекундах. Сопоставляем начало и результат только
 * на одном потоке захвата, не включаем запросы принудительного обновления. */
export function summarizeCaptureTrace(raw: unknown, pid: number): Sample | null {
  if (!raw || typeof raw !== 'object' || !('traceEvents' in raw) || !Array.isArray(raw.traceEvents)) return null;
  const events = raw.traceEvents.filter((e) =>
    e?.pid === pid && e.ph === 'X' && Number.isFinite(e.ts) &&
    (e.name === 'CaptureFrame' || e.name === 'OnCaptureResult'));
  events.sort((a, b) => a.ts - b.ts);
  const threads = new Map<number, {
    first: number;
    last: number;
    count: number;
    pending: number | null;
    acquire: number;
    prepare: number;
    interval: number;
  }>();
  for (const e of events) {
    let thread = threads.get(e.tid);
    if (e.name === 'CaptureFrame') {
      if (!thread) {
        thread = { first: e.ts, last: e.ts, count: 0, pending: null, acquire: 0, prepare: 0, interval: 0 };
        threads.set(e.tid, thread);
      }
      if (e.args?.is_refresh_frame !== false) {
        thread.pending = null;
        continue;
      }
      if (thread.count === 0) thread.first = e.ts;
      else thread.interval = Math.max(thread.interval, e.ts - thread.last);
      thread.last = e.ts;
      thread.count++;
      thread.pending = e.ts;
    } else if (thread && thread.pending !== null && e.args?.frame_is_refresh === false) {
      thread.acquire = Math.max(thread.acquire, e.ts - thread.pending);
      if (Number.isFinite(e.dur)) thread.prepare = Math.max(thread.prepare, e.dur);
      thread.pending = null;
    }
  }
  const active = [...threads.values()].filter((t) => t.count >= 2 && t.last > t.first && t.acquire > 0);
  if (active.length !== 1) return null;
  const t = active[0];
  return {
    attemptsPerSecond: Math.round((t.count - 1) * 1000000 / (t.last - t.first)),
    acquireMs: Math.round(t.acquire / 1000),
    prepareMs: Math.round(t.prepare / 1000),
    intervalMs: Math.round(t.interval / 1000),
  };
}

let current: { track: string; requestedAt: number; samples: { at: number; data: Sample }[] } | null = null;
let recording = false;

export function readScreenCaptureTimings(track: string): ScreenCaptureTimings | null {
  const now = performance.now();
  if (current?.track !== track || now - current.requestedAt > REQUEST_TTL_MS) {
    current = { track, requestedAt: now, samples: [] };
  } else {
    current.requestedAt = now;
  }
  const state = current;
  state.samples = state.samples.filter((sample) => now - sample.at < HISTORY_MS);
  if (!recording) void record(state);
  const latest = state.samples.at(-1)?.data;
  if (!latest) return null;
  return {
    attemptsPerSecond: latest.attemptsPerSecond,
    acquireMs: Math.max(...state.samples.map((sample) => sample.data.acquireMs)),
    prepareMs: Math.max(...state.samples.map((sample) => sample.data.prepareMs)),
    intervalMs: Math.max(...state.samples.map((sample) => sample.data.intervalMs)),
  };
}

async function record(state: NonNullable<typeof current>): Promise<void> {
  recording = true;
  let folder: string | undefined;
  try {
    folder = await mkdtemp(join(tmpdir(), 'glitch-capture-'));
    const path = join(folder, 'capture.json');
    await contentTracing.startRecording({
      included_categories: ['webrtc'],
      excluded_categories: ['*'],
      included_process_ids: [process.pid],
      trace_buffer_size_in_kb: BUFFER_KB,
    });
    await new Promise<void>((resolve) => setTimeout(resolve, SLICE_MS));
    const output = await contentTracing.stopRecording(path);
    if (current !== state || performance.now() - state.requestedAt > REQUEST_TTL_MS) return;
    if ((await stat(output)).size > MAX_TRACE_BYTES) return;
    const data = summarizeCaptureTrace(JSON.parse(await readFile(output, 'utf8')), process.pid);
    if (data && current === state) state.samples.push({ at: performance.now(), data });
  } catch {
  } finally {
    if (folder) await rm(folder, { recursive: true, force: true }).catch(() => {});
    recording = false;
  }
}
