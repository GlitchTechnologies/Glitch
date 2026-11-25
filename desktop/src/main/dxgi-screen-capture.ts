import { app, sharedTexture } from 'electron';
import type { WebFrameMain } from 'electron';
import { existsSync } from 'node:fs';
import type { DxgiSettings, PageChannels, ScreenCaptureTimings, WasapiRead } from '../shared/ipc';
import { DXGI_MODULE_PATH, DXGI_POLL_MS, DXGI_STOP_POLL_MS, DXGI_STOP_TIMEOUT_MS } from './config';
import { logEvent } from './log';

interface NativeFrame {
  id: number;
  handle: Buffer;
  width: number;
  height: number;
  timestamp: number;
  captureTimestamp?: number;
  recoveries: number;
}

interface NativeStats {
  frames: number;
  copied: number;
  pacedOut: number;
  noSlot: number;
  replaced: number;
  copyWaitMs: number;
  maxCopyWaitMs: number;
  maxFrameGapMs: number;
}

interface NativeMonitor {
  takeFrame(): NativeFrame | null;
  releaseFrame(id: number): void;
  stats(resetMax: boolean): NativeStats;
  requestStop(): void;
  isStopped(): boolean;
  stop(): void;
}

interface NativeAudio {
  read(): WasapiRead;
  stop(): void;
}

export function dxgiCaptureAvailable(): boolean {
  return process.platform === 'win32' && typeof sharedTexture?.importSharedTexture === 'function' &&
    existsSync(DXGI_MODULE_PATH);
}

export class DxgiScreenCapture {
  private readonly native: NativeMonitor;
  private readonly polling: NodeJS.Timeout;
  private audio: NativeAudio | undefined;
  private audioLogged = false;
  private stopped = false;
  private sending = false;
  private droppedByMain = 0;
  private sentFrames = 0;
  private recoveries = 0;
  private trackId: string | null = null;
  private previous: { at: number; stats: NativeStats; sent: number } | undefined;
  private waits: { at: number; copyMs: number; gapMs: number }[] = [];

  constructor(
    private readonly id: string,
    private readonly frame: WebFrameMain,
    private readonly settings: DxgiSettings,
    private readonly withAudio: boolean,
    private readonly onFailure: () => void,
  ) {
    logEvent('показ экрана: загрузка нативного модуля');
    const addon = require(DXGI_MODULE_PATH) as {
      captureApiVersion?: () => number;
      MonitorCapture: new (mode: string, slots: number, fps: number, singleMonitor: boolean) => NativeMonitor;
      WasapiCapture?: new () => NativeAudio;
    };
    if (addon.captureApiVersion?.() !== 5) {
      throw new Error('Для DXGI в Glitch нужно пересобрать модуль захвата');
    }
    logEvent('показ экрана: запуск DXGI');
    this.native = new addon.MonitorCapture('dxgi', 4, settings.fps, true);
    if (withAudio) {
      try {
        if (!addon.WasapiCapture) throw new Error('Модуль захвата нужно пересобрать для WASAPI');
        logEvent('показ экрана: запуск WASAPI');
        this.audio = new addon.WasapiCapture();
      } catch (error) {
        console.warn('Запуск WASAPI:', error);
      }
    }
    this.polling = setInterval(() => void this.poll(), DXGI_POLL_MS);
  }

  readAudio(): WasapiRead | null {
    try {
      const sample = this.audio?.read();
      if (sample?.ready && !this.audioLogged) {
        this.audioLogged = true;
        logEvent('показ экрана: захват WASAPI исключает дерево процессов Glitch');
      }
      return sample ?? null;
    } catch (error) {
      console.warn('Захват WASAPI:', error);
      this.stopAudio();
      return null;
    }
  }

  stopAudio(): void {
    const audio = this.audio;
    this.audio = undefined;
    if (!audio) return;
    audio.stop();
    logEvent('показ экрана: захват WASAPI остановлен');
  }

  commit(trackId: string): void {
    this.trackId = trackId;
    logEvent(`показ экрана: DXGI BGRA, задано ${this.settings.fps} кадр/с`);
  }

  timings(trackId: string): ScreenCaptureTimings | null {
    if (trackId !== this.trackId) return null;
    const now = performance.now();
    this.waits = this.waits.filter((sample) => now - sample.at < 60_000);
    const stats = this.native.stats(true);
    if (stats.maxCopyWaitMs > 0 || stats.maxFrameGapMs > 0) {
      this.waits.push({ at: now, copyMs: stats.maxCopyWaitMs, gapMs: stats.maxFrameGapMs });
    }
    const previous = this.previous;
    this.previous = { at: now, stats, sent: this.sentFrames };
    const elapsed = previous ? (now - previous.at) / 1000 : 0;
    const fps = (count: number, before: number | undefined) =>
      before === undefined || elapsed <= 0 || count < before ? undefined : Math.round((count - before) / elapsed);
    const maximum = (key: 'copyMs' | 'gapMs') => {
      const value = Math.max(0, ...this.waits.map((sample) => sample[key]));
      return value > 0 ? Math.round(value) : undefined;
    };
    const copied = previous ? stats.copied - previous.stats.copied : 0;
    return {
      configuredFps: this.settings.fps,
      prepareMs: maximum('copyMs'),
      details: {
        backend: 'dxgi',
        mode: app.isPackaged ? 'installed' : 'dev',
        audio: this.audio && this.audioLogged ? 'wasapi' : this.withAudio ? 'unavailable' : 'off',
        inputFps: fps(stats.frames, previous?.stats.frames),
        preparedFps: fps(stats.copied, previous?.stats.copied),
        sentFps: fps(this.sentFrames, previous?.sent),
        noSlot: stats.noSlot,
        replaced: stats.replaced,
        pacedOut: stats.pacedOut,
        sendDropped: this.droppedByMain,
        avgPrepareMs: previous && copied > 0
          ? Math.round((stats.copyWaitMs - previous.stats.copyWaitMs) / copied) : undefined,
        maxFrameGapMs: maximum('gapMs'),
      },
    };
  }

  stop(onStopped: (clean: boolean) => void): void {
    if (this.stopped) return;
    this.stopped = true;
    clearInterval(this.polling);
    this.stopAudio();
    this.notifyEnded();
    logEvent('показ экрана: запрос остановки DXGI');
    try {
      this.native.requestStop();
      this.finishStop(performance.now(), onStopped);
    } catch (error) {
      console.warn('Остановка захвата DXGI:', error);
      onStopped(false);
    }
  }

  private finishStop(startedAt: number, onStopped: (clean: boolean) => void): void {
    let clean = false;
    try {
      if (!this.native.isStopped()) {
        if (performance.now() - startedAt < DXGI_STOP_TIMEOUT_MS) {
          setTimeout(() => this.finishStop(startedAt, onStopped), DXGI_STOP_POLL_MS).unref();
          return;
        }
        console.warn('Остановка захвата DXGI: Windows не завершила поток вовремя');
      } else {
        this.native.stop(); // Поток уже завершился. Главный процесс его не ждёт.
        const { frames, copied, pacedOut, noSlot, replaced, copyWaitMs } = this.native.stats(false);
        logEvent(`показ экрана DXGI: остановлен (получено: ${frames}, подготовлено: ${copied}, ` +
          `пропущено по FPS: ${pacedOut}, без буфера: ${noSlot}, заменено: ${replaced}, ` +
          `занята передача: ${this.droppedByMain}, подготовка, мс: ${copied ? (copyWaitMs / copied).toFixed(1) : '—'})`);
        clean = true;
      }
    } catch (error) {
      console.warn('Остановка захвата DXGI:', error);
    }
    onStopped(clean);
  }

  private notifyEnded(): void {
    if (!this.frame.detached) {
      try {
        this.frame.send('glitch:dxgi-ended' satisfies keyof PageChannels, this.id);
      } catch {
      }
    }
  }

  private async poll(): Promise<void> {
    let imported: Electron.SharedTextureImported | undefined;
    try {
      const frame = this.native.takeFrame();
      if (!frame) return;
      if (this.sending) {
        this.native.releaseFrame(frame.id);
        this.droppedByMain++;
        return;
      }
      this.sending = true;
      try {
        const { maxWidth, maxHeight } = this.settings;
        if ((maxWidth !== null && frame.width > maxWidth) || (maxHeight !== null && frame.height > maxHeight)) {
          throw new Error('Захват DXGI пока не масштабирует монитор до выбранного размера');
        }
        if (this.sentFrames === 0) logEvent('показ экрана: импорт первой GPU-текстуры в Electron');
        imported = sharedTexture.importSharedTexture({
          textureInfo: {
            handle: { ntHandle: frame.handle },
            pixelFormat: 'bgra',
            codedSize: { width: frame.width, height: frame.height },
            timestamp: frame.captureTimestamp ?? frame.timestamp,
          },
          allReferencesReleased: () => this.native.releaseFrame(frame.id),
        });
        if (this.sentFrames === 0) logEvent('показ экрана: передача первой GPU-текстуры на страницу');
        await sharedTexture.sendSharedTexture({ frame: this.frame, importedSharedTexture: imported }, this.id);
        this.sentFrames++;
        if (!this.stopped && frame.recoveries > this.recoveries) {
          this.recoveries = frame.recoveries;
          logEvent(`показ экрана: DXGI восстановил захват того же монитора (всего: ${this.recoveries})`);
        }
      } finally {
        if (imported) imported.release();
        else this.native.releaseFrame(frame.id);
        this.sending = false;
      }
    } catch (error) {
      if (this.stopped) return;
      console.warn('Захват DXGI:', error);
      this.onFailure();
    }
  }
}
