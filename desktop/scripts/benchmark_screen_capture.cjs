'use strict';

const { app, BrowserWindow, contentTracing, desktopCapturer, session, webContents } = require('electron');
const fs = require('node:fs/promises');
const path = require('node:path');

const output = process.env.GLITCH_CAPTURE_BENCHMARK;
const mode = process.env.GLITCH_CAPTURE_MODE;
if (!output || !['baseline', 'texture'].includes(mode)) throw new Error('Run benchmark_screen_capture.ps1');

app.setPath('userData', path.join(output, 'electron-data'));
app.commandLine.appendSwitch(mode === 'texture' ? 'enable-features' : 'disable-features',
  'WebRtcAllowWgcUsingTexture');

const page = `<!doctype html>
<meta charset="utf-8">
<title>Glitch — замер захвата</title>
<style>
  body { color: #eee; background: #202123; font: 17px system-ui; margin: 28px; }
  select, button { font: inherit; max-width: 100%; margin-block: 8px; }
</style>
<h2 id="title"></h2>
<label for="source">Источник</label>
<select id="source"></select>
<button id="start">Начать замер</button>
<p id="status">Сразу после нажатия вернитесь в игру. Замер начнётся через 5 секунд и продлится 15 секунд.</p>
<script>
  const source = document.querySelector('#source');
  const start = document.querySelector('#start');
  const status = document.querySelector('#status');
  window.benchmarkResult = new Promise((resolve) => {
    start.onclick = async () => {
      start.disabled = source.disabled = true;
      const selectedSource = source.selectedOptions[0]?.textContent;
      let track;
      let reader;
      let timer;
      try {
        const stream = await navigator.mediaDevices.getDisplayMedia({
          video: { width: 1920, height: 1080, frameRate: 60 }, audio: false,
        });
        track = stream.getVideoTracks()[0];
        track.contentHint = 'motion';
        const settings = track.getSettings();
        reader = new MediaStreamTrackProcessor({ track, maxBufferSize: 1 }).readable.getReader();
        const from = performance.now() + 5000;
        const until = from + 15000;
        const timestamps = [];
        let running = true;
        timer = setTimeout(() => {
          running = false;
          void reader.cancel();
        }, until - performance.now());
        status.textContent = 'Идёт замер. Вернитесь в игру.';
        while (running) {
          const { done, value } = await reader.read();
          if (done) break;
          const now = performance.now();
          if (now >= from && now < until) timestamps.push(value.timestamp);
          value.close();
        }
        if (running || timestamps.length < 2) throw new Error('Источник закрылся или слишком мало кадров');
        const gaps = timestamps.slice(1).map((t, i) => (t - timestamps[i]) / 1000);
        const sorted = gaps.slice().sort((a, b) => a - b);
        const round = (n) => Math.round(n * 10) / 10;
        resolve({
          source: selectedSource,
          settings,
          frames: timestamps.length,
          fps: round(timestamps.length / 15),
          gapP95Ms: round(sorted[Math.ceil(sorted.length * 0.95) - 1]),
          gapMaxMs: round(sorted[sorted.length - 1]),
          gapsOver50Ms: gaps.filter((ms) => ms > 50).length,
        });
      } catch (error) {
        resolve({ source: selectedSource, error: String(error) });
      } finally {
        clearTimeout(timer);
        track?.stop();
        if (reader) await reader.cancel().catch(() => {});
      }
    };
  });
</script>`;

async function run() {
  const pagePath = path.join(output, 'benchmark.html');
  const tracePath = path.join(output, `trace-${mode}.json`);
  await fs.writeFile(pagePath, page);
  const win = new BrowserWindow({ width: 640, height: 300, webPreferences: { backgroundThrottling: false } });
  let tracing = false;
  let traceError;
  let sourceStatus = 'no-request';
  const sources = await desktopCapturer.getSources({
    types: ['screen', 'window'], thumbnailSize: { width: 0, height: 0 },
  });
  session.defaultSession.setDisplayMediaRequestHandler(async (request, reply) => {
    if (!request.frame || webContents.fromFrame(request.frame) !== win.webContents || !request.videoRequested) {
      sourceStatus = 'request-denied';
      reply({});
      return;
    }
    let selected;
    try {
      const index = await win.webContents.executeJavaScript('document.querySelector("#source").selectedIndex');
      const sourceId = sources[index]?.id;
      if (sourceId) {
        const currentSources = await desktopCapturer.getSources({
          types: [sourceId.startsWith('screen:') ? 'screen' : 'window'],
          thumbnailSize: { width: 0, height: 0 },
        });
        selected = currentSources.find((candidate) => candidate.id === sourceId);
      }
    } catch (error) {
      sourceStatus = String(error);
      reply({});
      return;
    }
    if (!selected) {
      sourceStatus = 'source-unavailable';
      reply({});
      return;
    }
    try {
      await contentTracing.startRecording({
        included_categories: ['disabled-by-default-video_and_image_capture'],
        excluded_categories: ['*'],
        included_process_ids: [process.pid],
        trace_buffer_size_in_kb: 2048,
      });
      tracing = true;
    } catch (error) {
      traceError = String(error);
    }
    sourceStatus = selected.id.startsWith('screen:') ? 'monitor-passed' : 'window-passed';
    reply({ video: selected });
  });
  await win.loadFile(pagePath);
  const names = sources.map((source) => `${source.id.startsWith('screen:') ? 'Экран' : 'Окно'} — ${source.name}`);
  const result = await win.webContents.executeJavaScript(`
    document.querySelector('#title').textContent = ${JSON.stringify(mode === 'texture' ? 'GPU-текстуры' : 'Обычный захват')};
    for (const name of ${JSON.stringify(names)}) document.querySelector('#source').add(new Option(name));
    window.benchmarkResult;
  `);
  let gpuTextureEvents = null;
  try {
    if (tracing) {
      const traceFile = await contentTracing.stopRecording(tracePath);
      const trace = JSON.parse(await fs.readFile(traceFile, 'utf8'));
      gpuTextureEvents = trace.traceEvents.filter((event) =>
        event.pid === process.pid && event.name === 'DesktopCaptureDevice::DeliverTextureToClient'
        && ['X', 'B'].includes(event.ph)).length;
    }
  } catch (error) {
    traceError = String(error);
  } finally {
    await fs.rm(tracePath, { force: true });
  }
  await fs.writeFile(path.join(output, `${mode}.json`), JSON.stringify({
    mode, electron: process.versions.electron, chromium: process.versions.chrome,
    windows: process.getSystemVersion(), gpuTextureEvents, sourceStatus, traceError, ...result,
  }, null, 2));
}

app.whenReady().then(run).then(() => app.quit(), (error) => {
  console.error(error);
  app.exit(1);
});
