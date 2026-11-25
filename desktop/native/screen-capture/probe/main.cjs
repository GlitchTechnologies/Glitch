'use strict';

const { app, BrowserWindow, contentTracing, desktopCapturer, ipcMain, screen, session, sharedTexture } = require('electron');
const { mkdtempSync, rmSync, writeFileSync } = require('node:fs');
const { randomUUID } = require('node:crypto');
const { tmpdir } = require('node:os');
const path = require('node:path');

const runTimeoutMs = 45000;
const releaseTimeoutMs = 3000;
const width = 1280;
const height = 720;
const fps = 60;

const sourcePage = `<!doctype html>
<meta charset="utf-8">
<style>
  body { margin: 0; overflow: hidden; background: #164b82; }
  div {
    position: absolute; inset: 15% 55% 15% 5%; border-radius: 20px;
    background: repeating-linear-gradient(45deg, #e87631 0 20px, #f5d97b 20px 40px);
    animation: slide 1s linear infinite alternate;
  }
  @keyframes slide { to { transform: translateX(120%); } }
</style>
<div></div>`;

async function run() {
  if (process.platform !== 'win32') throw new Error('Стенд GPU-текстур предназначен для Windows.');
  if (!sharedTexture) throw new Error('В установленном Electron отсутствует sharedTexture.');
  const mode = app.commandLine.getSwitchValue('capture-probe-mode') || 'synthetic';
  const traceRequested = app.commandLine.hasSwitch('capture-probe-trace');
  const timingRequested = app.commandLine.hasSwitch('capture-probe-timing');
  const queueTrace = app.commandLine.hasSwitch('capture-probe-queue');
  const priorityArg = app.commandLine.getSwitchValue('capture-probe-priority');
  const reportFile = app.commandLine.getSwitchValue('capture-probe-report');
  const autoStart = app.commandLine.hasSwitch('capture-probe-autostart');
  const gpu = app.commandLine.hasSwitch('capture-probe-priority')
    ? { priority: Number(priorityArg), traceQueue: queueTrace } : undefined;
  const eagerConversionDisabled = app.commandLine.getSwitchValue('disable-features')
    .split(',').includes('BreakoutBoxEagerConversion');
  const backend = ['dxgi-preview', 'dxgi-send-only'].includes(mode) ? 'dxgi' : mode;
  const slotsArg = app.commandLine.getSwitchValue('capture-probe-slots');
  const maxTextures = Number(slotsArg || '4');
  if (maxTextures !== 4 && (maxTextures !== 6 || backend !== 'dxgi')) {
    throw new Error('Для DXGI BGRA допустимы 4 или 6 буферов');
  }
  const nativeMode = ['wgc', 'dxgi', 'dxgi-nv12'].includes(backend);
  if (timingRequested && backend !== 'dxgi') throw new Error('Замеры времени доступны для DXGI BGRA.');
  if ((queueTrace && priorityArg !== '0') || (gpu && (!timingRequested || !['0', '1'].includes(priorityArg)))) {
    throw new Error('Для замеров приоритета и трассы нужны DXGI BGRA и приоритет 0 или 1.');
  }
  if (autoStart && (!gpu || !reportFile)) throw new Error('Автозапуск требует файла отчёта и замера приоритета.');
  if (!nativeMode && !['synthetic', 'baseline'].includes(mode)) {
    throw new Error('Режимы стенда: synthetic, baseline, wgc, dxgi, dxgi-preview, dxgi-send-only, dxgi-nv12');
  }

  const profile = mkdtempSync(path.join(tmpdir(), 'glitch-capture-probe-'));
  app.setPath('userData', profile);
  app.once('quit', () => {
    try {
      rmSync(profile, { recursive: true, force: true, maxRetries: 2 });
    } catch (error) {
      console.warn(`Временный профиль ${profile}: ${error.message}`);
    }
  });
  await app.whenReady();

  const isolatedSession = session.fromPartition('capture-probe');
  const allowDisplayCapture = (contents, permission) => mode === 'baseline'
    && contents === viewer.webContents && permission === 'display-capture';
  isolatedSession.setPermissionRequestHandler((contents, permission, reply) => reply(allowDisplayCapture(contents, permission)));
  isolatedSession.setPermissionCheckHandler(allowDisplayCapture);
  isolatedSession.webRequest.onBeforeRequest({ urls: ['http://*/*', 'https://*/*'] },
    (_request, reply) => reply({ cancel: true }));
  const preferences = {
    session: isolatedSession, contextIsolation: true, sandbox: true, nodeIntegration: false,
    backgroundThrottling: false,
  };
  const viewer = new BrowserWindow({
    width: 900, height: 440,
    webPreferences: {
      ...preferences, preload: path.join(__dirname, 'preload.cjs'),
      additionalArguments: [
        `--probe-mode=${mode}`,
        ...(timingRequested ? ['--probe-timing'] : []),
        ...(autoStart ? ['--probe-autostart'] : []),
      ],
    },
  });
  const source = mode === 'synthetic' ? new BrowserWindow({
    width, height, useContentSize: true, show: false,
    webPreferences: { ...preferences, offscreen: { useSharedTexture: true } },
  }) : null;
  source?.webContents.stopPainting();
  for (const win of [viewer, source].filter(Boolean)) {
    win.webContents.on('will-navigate', (event) => event.preventDefault());
    win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  }

  const counters = { textures: 0, withoutTexture: 0, dropped: 0, transferred: 0, released: 0 };
  const leases = new Map();
  const timing = timingRequested ? new Map() : null;
  function measure(metric, value) {
    if (!timing) return;
    if (!timing.has(metric)) timing.set(metric, []);
    const samples = timing.get(metric);
    if (samples.length < 8192) samples.push(value);
  }
  let totalLeaseMs = 0;
  let sending = false;
  let launching = false;
  let painting = false;
  let viewerGone = false;
  let finished = false;
  let published = false;
  let reportReady = false;
  let traceStart;
  let errorResult;
  let result;
  let releaseTimer;
  let runTimer;
  let monitor;
  let texturePixelFormat;
  const fromViewer = (event) => !viewer.isDestroyed()
    && event.sender === viewer.webContents && event.senderFrame === viewer.webContents.mainFrame;

  if (mode === 'baseline') {
    isolatedSession.setDisplayMediaRequestHandler(async (request, reply) => {
      const frame = viewer.webContents.mainFrame;
      if (request.frame !== frame || !request.videoRequested || request.audioRequested || !request.userGesture || launching) {
        reply(null);
        return;
      }
      launching = true;
      startTimeout();
      let primary;
      try {
        const primaryId = String(screen.getPrimaryDisplay().id);
        const sources = await desktopCapturer.getSources({ types: ['screen'], thumbnailSize: { width: 0, height: 0 } });
        primary = sources.find((entry) => entry.display_id === primaryId)
          ?? (sources.length === 1 && !sources[0].display_id ? sources[0] : null);
      } catch (error) {
        if (!viewer.isDestroyed() && request.frame) reply(null);
        if (!finished) finish(null, `Выбор основного монитора: ${error.message}`);
        return;
      }
      if (viewer.isDestroyed() || !request.frame) return;
      reply(!finished && primary && request.frame === viewer.webContents.mainFrame ? { video: primary } : null);
    });
  }

  async function publishResult() {
    if (published) return;
    clearTimeout(releaseTimer);
    const outstanding = leases.size;
    published = true;
    source?.destroy();
    let trace;
    if (traceRequested) {
      try {
        if (traceStart) {
          const startError = await traceStart;
          if (startError) throw startError;
          const buffer = await contentTracing.getTraceBufferUsage().catch(() => null);
          const file = await contentTracing.stopRecording(path.join(tmpdir(), `glitch-dxgi-${randomUUID()}.trace`));
          trace = { file, buffer };
        }
      } catch (error) {
        trace = { error: error.message };
      }
    }
    let diagnosticsError;
    if (result?.ok && gpu && result.gpuPriority !== gpu.priority) {
      diagnosticsError = 'DXGI не подтвердил запрошенный приоритет GPU';
    } else if (result?.ok && queueTrace && !(result.queueMarkedCopies > 0)) {
      diagnosticsError = 'В трассу ETW не записались метки копий Glitch';
    }
    const report = {
      mode, electron: process.versions.electron, windows: process.getSystemVersion(), requestedFps: fps,
      texturePixelFormat,
      ...(nativeMode && { textureSlots: maxTextures }),
      ...(traceRequested && { eagerConversionDisabled, trace }),
      ...(gpu && { requestedGpuPriority: gpu.priority, queueTrace, captureProcessId: process.pid }),
      ...result, ...counters, outstanding,
      ok: !errorResult && !diagnosticsError && result?.ok === true && outstanding === 0,
      error: errorResult ?? result?.error ?? diagnosticsError ?? (outstanding ? 'Текстуры не освободились за отведённое время' : undefined),
    };
    const json = JSON.stringify(report, null, 2);
    console.log(json);
    if (reportFile) {
      try {
        writeFileSync(reportFile, json + '\n', 'utf8');
      } catch (error) {
        console.error(`Сохранение отчёта: ${error.message}`);
        process.exitCode = 1;
      }
    }
    if (!viewerGone && !viewer.isDestroyed()) viewer.webContents.send('probe:summary', report.ok, report.error);
    if (!report.ok) process.exitCode = 1;
    reportReady = true;
    if (reportFile || viewer.isDestroyed()) app.exit(process.exitCode ?? 0);
  }

  function finish(details, error) {
    if (finished) return;
    finished = true;
    result = details;
    errorResult = error;
    clearTimeout(runTimer);
    source?.webContents.stopPainting();
    try {
      monitor?.stop();
    } catch (stopError) {
      errorResult = errorResult ?? `Остановка захвата: ${stopError.message}`;
    }
    if (!viewerGone && !viewer.isDestroyed()) viewer.webContents.send('probe:stop');
    if (!leases.size) publishResult();
    else releaseTimer = setTimeout(publishResult, releaseTimeoutMs);
  }

  function release(texture) {
    const leasedAt = leases.get(texture);
    if (leasedAt === undefined) return;
    leases.delete(texture);
    if (published) return;
    texture.release();
    counters.released++;
    const leaseMs = performance.now() - leasedAt;
    totalLeaseMs += leaseMs;
    measure('electronTextureLeaseMs', leaseMs);
    if (finished && !leases.size) publishResult();
  }

  function startTimeout() {
    clearTimeout(runTimer);
    runTimer = setTimeout(() => finish(null, 'Истекло время проверки'), runTimeoutMs);
  }
  app.on('window-all-closed', () => {});
  viewer.once('closed', () => {
    if (reportReady) app.exit(process.exitCode ?? 0);
    else finish(null, 'Окно проверки закрыто');
  });
  for (const [label, win] of [['Предпросмотр', viewer], ['Источник', source]]) {
    if (!win) continue;
    win.webContents.on('render-process-gone', (_event, details) => {
      if (win === viewer) viewerGone = true;
      finish(null, `${label}: ${details.reason}, код ${details.exitCode}`);
    });
  }
  viewer.webContents.on('preload-error', (_event, _file, error) => {
    finish(null, `Предзагрузка: ${error.message}`);
  });

  async function handleTexture(texture) {
    if (!texture) {
      counters.withoutTexture++;
      return;
    }
    counters.textures++;
    if (!painting || finished || sending || leases.size >= maxTextures) {
      counters.dropped++;
      texture.release();
      return;
    }

    sending = true;
    const receivedAt = performance.now();
    leases.set(texture, receivedAt);
    let imported;
    try {
      if (!texture.textureInfo.handle.ntHandle) throw new Error('Источник не предоставил NT-дескриптор текстуры');
      imported = sharedTexture.importSharedTexture({
        textureInfo: texture.textureInfo,
        allReferencesReleased: () => release(texture),
      });
      const importedAt = performance.now();
      measure('electronImportCallMs', importedAt - receivedAt);
      await sharedTexture.sendSharedTexture({ frame: viewer.webContents.mainFrame, importedSharedTexture: imported });
      measure('electronTransferAwaitMs', performance.now() - importedAt);
      texturePixelFormat = texture.textureInfo.pixelFormat;
      counters.transferred++;
    } catch (error) {
      finish(null, `Передача текстуры: ${error.message}`);
      if (imported) {
        if (!viewer.isDestroyed()) viewer.destroy();
      } else {
        release(texture);
      }
    } finally {
      imported?.release();
      sending = false;
    }
  }
  source?.webContents.on('paint', ({ texture }) => void handleTexture(texture));

  ipcMain.on('probe:start', async (event) => {
    if (!fromViewer(event) || launching || finished || mode === 'baseline') return;
    launching = true;
    startTimeout();
    try {
      if (traceRequested) {
        traceStart = contentTracing.startRecording({
          included_categories: ['media', 'webrtc', 'disabled-by-default-webrtc', 'gpu'],
          excluded_categories: ['*'],
          trace_buffer_size_in_kb: 8192,
        }).catch((error) => error);
        await traceStart;
        if (finished) return;
      }
      if (nativeMode) {
        const { monitorSource } = require('./monitor.cjs');
        monitor = monitorSource(backend, maxTextures, timingRequested, gpu, handleTexture,
          (error) => finish(null, `${backend.toUpperCase()}: ${error.message}`));
        painting = true;
        monitor.start();
      } else {
        await source.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(sourcePage)}`);
        if (finished) return;
        source.webContents.setFrameRate(fps);
        painting = true;
        source.webContents.startPainting();
      }
    } catch (error) {
      finish(null, `Источник: ${error.message}`);
    }
  });
  ipcMain.on('probe:result', (event, details) => {
    if (fromViewer(event)) finish(details);
  });
  ipcMain.handle('probe:sample', (event, reset) => {
    if (!fromViewer(event) || finished) return null;
    if (reset) timing?.clear();
    return {
      ...counters, totalLeaseMs, native: monitor?.stats(reset === true) ?? null,
      ...(timing && { timing: Object.fromEntries(timing) }),
    };
  });

  if (reportFile) {
    runTimer = setTimeout(() => finish(null, 'Кнопка «Начать замер» не нажата за 60 секунд'), 60_000);
  }
  await viewer.loadFile(path.join(__dirname, 'probe.html'));
}

run().catch((error) => {
  console.error(error.message);
  app.exit(1);
});
