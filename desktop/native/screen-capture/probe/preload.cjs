'use strict';

const { contextBridge, ipcRenderer, sharedTexture } = require('electron');
const timing = process.argv.includes('--probe-timing') ? { rendererGetVideoFrameMs: [], rendererWriteAwaitMs: [] } : null;

let track;
let writer;
let written = 0;
const trackStats = {
  received: 0,
  skippedBusy: 0,
  totalWriteMs: 0,
  maxWriteMs: 0,
};
let finished = false;

function stop() {
  if (finished) return;
  finished = true;
  track?.stop();
  if (writer) {
    void writer.abort()
      .catch((error) => console.error('Закрытие видеодорожки:', error))
      .finally(() => writer.releaseLock());
  }
}

function finish(details) {
  if (finished) return;
  stop();
  ipcRenderer.send('probe:result', { ...details, written });
}

ipcRenderer.on('probe:stop', () => {
  stop();
  window.dispatchEvent(new Event('capture-probe-stop'));
});
ipcRenderer.on('probe:summary', (_event, ok, error) => {
  document.querySelector('#status').textContent = ok ? 'Проверка пройдена.' : `Ошибка: ${error}`;
});
window.addEventListener('pagehide', stop, { once: true });

contextBridge.exposeInMainWorld('captureProbe', {
  mode: process.argv.find((arg) => arg.startsWith('--probe-mode='))?.slice('--probe-mode='.length),
  autoStart: process.argv.includes('--probe-autostart'),
  async sample(reset) {
    const accepted = written;
    const stats = { ...trackStats };
    const rendererTiming = timing && Object.fromEntries(
      Object.entries(timing).map(([metric, values]) => [metric, reset ? [] : [...values]]),
    );
    if (reset) {
      trackStats.maxWriteMs = 0;
      if (timing) for (const values of Object.values(timing)) values.length = 0;
    }
    return { ...await ipcRenderer.invoke('probe:sample', reset), written: accepted, trackStats: stats, rendererTiming };
  },
  start() {
    if (track || finished) throw new Error('Стенд уже запущен');
    if (!sharedTexture) throw new Error('Предзагрузка не получила доступ к sharedTexture');
    if (typeof MediaStreamTrackGenerator !== 'function') throw new Error('Нет генератора видеодорожки');
    track = new MediaStreamTrackGenerator({ kind: 'video' });
    track.contentHint = 'motion';
    writer = track.writable.getWriter();
    document.querySelector('#local').srcObject = new MediaStream([track]);
    sharedTexture.setSharedTextureReceiver(async ({ importedSharedTexture }) => {
      let frame;
      try {
        if (finished) return;
        trackStats.received++;
        if (writer.desiredSize <= 0) {
          trackStats.skippedBusy++;
          return;
        }
        const importStarted = timing && performance.now();
        frame = importedSharedTexture.getVideoFrame();
        const startedAt = performance.now();
        if (timing && timing.rendererGetVideoFrameMs.length < 8192) {
          timing.rendererGetVideoFrameMs.push(startedAt - importStarted);
        }
        await writer.write(frame);
        const elapsed = performance.now() - startedAt;
        if (timing && timing.rendererWriteAwaitMs.length < 8192) timing.rendererWriteAwaitMs.push(elapsed);
        trackStats.totalWriteMs += elapsed;
        trackStats.maxWriteMs = Math.max(trackStats.maxWriteMs, elapsed);
        written++;
      } catch (error) {
        if (!finished) finish({ ok: false, error: `Видеодорожка: ${error.message}` });
      } finally {
        frame?.close();
        importedSharedTexture.release();
      }
    });
    ipcRenderer.send('probe:start');
  },
  finish,
});
