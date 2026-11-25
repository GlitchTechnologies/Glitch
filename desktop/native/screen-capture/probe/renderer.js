'use strict';

function sendsWithoutPreview(mode) {
  return mode === 'dxgi-send-only' || mode === 'dxgi-nv12';
}

function summarizeTiming(series) {
  return Object.fromEntries(Object.entries(series).flatMap(([metric, values]) => {
    if (!values.length) return [];
    const sorted = [...values].sort((a, b) => a - b);
    const round = (value) => Math.round(value * 1000) / 1000;
    const percentile = (p) => round(sorted[Math.ceil(sorted.length * p) - 1]);
    return [[metric, {
      count: sorted.length,
      mean: round(sorted.reduce((sum, value) => sum + value, 0) / sorted.length),
      p50: percentile(0.5), p95: percentile(0.95), p99: percentile(0.99),
      max: round(sorted[sorted.length - 1]),
    }]];
  }));
}

function gatherIce(peer) {
  if (peer.iceGatheringState === 'complete') return Promise.resolve();
  return new Promise((resolve) => {
    function updated() {
      if (peer.iceGatheringState !== 'complete') return;
      peer.removeEventListener('icegatheringstatechange', updated);
      resolve();
    }
    peer.addEventListener('icegatheringstatechange', updated);
  });
}

async function connect(sender, receiver) {
  await sender.setLocalDescription(await sender.createOffer());
  await gatherIce(sender);
  await receiver.setRemoteDescription(sender.localDescription);
  await receiver.setLocalDescription(await receiver.createAnswer());
  await gatherIce(receiver);
  await sender.setRemoteDescription(receiver.localDescription);
}

function nextFrame(video) {
  return new Promise((resolve) => {
    video.requestVideoFrameCallback((_now, metadata) => resolve(metadata));
  });
}

function measureViewerDelay(video) {
  const delays = [];
  let callback;
  function collect(_now, frame) {
    const delay = frame.expectedDisplayTime - frame.captureTime;
    if (Number.isFinite(delay) && delay >= 0) delays.push(delay);
    callback = video.requestVideoFrameCallback(collect);
  }
  callback = video.requestVideoFrameCallback(collect);
  return () => {
    if (callback !== undefined) video.cancelVideoFrameCallback(callback);
    callback = undefined;
    delays.sort((a, b) => a - b);
    const p95 = delays[Math.ceil(delays.length * 0.95) - 1];
    return { samples: delays.length, estimatedCaptureToDisplayP95Ms: p95 === undefined ? null : Math.round(p95) };
  };
}

function drawSample(image, width, height, checkColor) {
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext('2d', { willReadFrequently: true });
  context.drawImage(image, 0, 0, width, height);
  if (checkColor) {
    const [red, green, blue] = context.getImageData(width >> 1, height >> 1, 1, 1).data;
    if (Math.max(red, green, blue) < 35) throw new Error('Получен чёрный кадр тестовой сцены');
  }
  return canvas;
}

async function takeSnapshot(track, checkColor) {
  const bitmap = await new ImageCapture(track).grabFrame();
  try {
    const canvas = drawSample(bitmap, 320, 180, checkColor);
    return await new Promise((resolve, reject) => {
      canvas.toBlob((blob) => {
        if (blob?.type === 'image/jpeg' && blob.size > 0) {
          resolve({ bytes: blob.size, width: bitmap.width, height: bitmap.height });
        }
        else reject(new Error('Пустой JPEG'));
      }, 'image/jpeg');
    });
  } finally {
    bitmap.close();
  }
}

async function inspect(peer, direction) {
  const stats = await peer.getStats();
  const rtp = [...stats.values()].find((entry) => entry.type === direction && entry.kind === 'video');
  return {
    frames: rtp?.framesEncoded ?? rtp?.framesDecoded ?? 0,
    id: rtp?.id,
    codec: rtp && stats.get(rtp.codecId)?.mimeType,
    totalEncodeTime: rtp?.totalEncodeTime,
    encoderImplementation: rtp?.encoderImplementation,
    powerEfficientEncoder: rtp?.powerEfficientEncoder,
    qualityLimitationReason: rtp?.qualityLimitationReason,
    jitterBufferDelay: rtp?.jitterBufferDelay,
    jitterBufferEmittedCount: rtp?.jitterBufferEmittedCount,
    sourceFrames: rtp && stats.get(rtp.mediaSourceId)?.frames,
    width: rtp?.frameWidth,
    height: rtp?.frameHeight,
  };
}

async function run() {
  const probe = window.captureProbe;
  const synthetic = probe.mode === 'synthetic';
  const previewOnly = probe.mode === 'dxgi-preview';
  const sendOnly = sendsWithoutPreview(probe.mode);
  const status = document.querySelector('#status');
  const local = document.querySelector('#local');
  const remote = document.querySelector('#remote');
  const sender = previewOnly ? null : new RTCPeerConnection({ iceServers: [] });
  const receiver = previewOnly ? null : new RTCPeerConnection({ iceServers: [] });
  let stage = 'Доступ к видеодорожке';
  let result;
  let track;
  let stopViewerMeasurement;

  function close() {
    stopViewerMeasurement?.();
    sender?.close();
    receiver?.close();
    track?.stop();
    local.srcObject = null;
    remote.srcObject?.getTracks().forEach((track) => track.stop());
    remote.srcObject = null;
  }

  window.addEventListener('pagehide', close, { once: true });
  window.addEventListener('capture-probe-stop', close, { once: true });
  try {
    if (probe.mode === 'baseline') {
      local.srcObject = await navigator.mediaDevices.getDisplayMedia({
        video: { frameRate: { ideal: 60, max: 60 } }, audio: false,
      });
    } else {
      if (sendOnly) local.autoplay = false;
      probe.start();
    }
    track = local.srcObject?.getVideoTracks()[0];
    if (!track) throw new Error('Дорожка недоступна за границей изоляции');
    if (sendOnly) local.srcObject = null;
    track.contentHint = 'motion';

    if (sender) {
      stage = 'Передача H.264 локальному зрителю';
      const transceiver = sender.addTransceiver(track, { direction: 'sendonly' });
      const codecs = RTCRtpSender.getCapabilities('video')?.codecs.filter((codec) => codec.mimeType === 'video/H264');
      if (!codecs?.length) throw new Error('В Electron нет видеокодека H.264');
      transceiver.setCodecPreferences(codecs);
      receiver.addEventListener('track', ({ track: received }) => {
        remote.srcObject = new MediaStream([received]);
      }, { once: true });
      await connect(sender, receiver);
    }

    stage = sendOnly ? 'Кадры у локального зрителя' : 'Кадры в предпросмотре';
    await Promise.all([!sendOnly && local.play(), receiver && remote.play()]);
    if (synthetic) {
      await Promise.all([nextFrame(local), nextFrame(remote)]);
      drawSample(local, 64, 36, true);
      drawSample(remote, 64, 36, true);
    }

    stage = 'Снимок предпросмотра';
    const snapshot = await takeSnapshot(track, synthetic);
    const settings = track.getSettings();
    const sourceSize = sendOnly
      ? { width: snapshot.width, height: snapshot.height }
      : { width: local.videoWidth, height: local.videoHeight };
    if (!synthetic) {
      status.textContent = 'Переключитесь в игру. Замер начнётся через 5 секунд.';
      await new Promise((resolve) => setTimeout(resolve, 5000));
      status.textContent = 'Идёт замер, оставайтесь в игре 15 секунд.';
    }
    async function sample(reset) {
      const now = performance.now();
      const [source, outgoing, incoming] = await Promise.all([
        probe.sample(reset),
        sender && inspect(sender, 'outbound-rtp'),
        receiver && inspect(receiver, 'inbound-rtp'),
      ]);
      return { now, source, outgoing, incoming };
    }
    const first = await sample(true);
    if (receiver && typeof remote.requestVideoFrameCallback === 'function') {
      stopViewerMeasurement = measureViewerDelay(remote);
    }
    await new Promise((resolve) => setTimeout(resolve, synthetic ? 2000 : 15000));
    const displayDelay = stopViewerMeasurement?.();
    stopViewerMeasurement = undefined;
    const last = await sample(false);
    const seconds = (last.now - first.now) / 1000;
    const round = (value) => Math.round(value * 10) / 10;
    const rate = (after, before) => Number.isFinite(after - before) ? round((after - before) / seconds) : null;
    const framesEncoded = sender ? last.outgoing.frames - first.outgoing.frames : null;
    const framesDecoded = receiver ? last.incoming.frames - first.incoming.frames : null;
    const jitterSeconds = last.incoming?.jitterBufferDelay - first.incoming?.jitterBufferDelay;
    const jitterFrames = last.incoming?.jitterBufferEmittedCount - first.incoming?.jitterBufferEmittedCount;
    const validJitter = jitterFrames > 0 && last.incoming.id === first.incoming.id
      && Number.isFinite(jitterSeconds) && jitterSeconds >= 0;
    if (sender && (last.outgoing.codec !== 'video/H264' || last.incoming.codec !== 'video/H264' || !framesEncoded || !framesDecoded)) {
      throw new Error('Нет подтверждения кодирования и декодирования H.264');
    }
    const nativeStart = first.source.native;
    const nativeEnd = last.source.native;
    const timing = last.source.timing && nativeEnd?.probeTimings;
    if (last.source.timing && !timing) throw new Error('Модуль стенда нужно пересобрать для подробных замеров');
    const timings = timing && summarizeTiming({
      ...Object.fromEntries(timing.map(({ metric, samples }) => [metric, samples])),
      ...last.source.timing,
      ...last.source.rendererTiming,
    });
    const prepared = nativeEnd?.copied - nativeStart?.copied;
    const released = last.source.released - first.source.released;
    const gpuStageAverageMs = prepared > 0 && nativeStart.gpuStageMs && nativeEnd.gpuStageMs
      ? Object.fromEntries(Object.entries(nativeEnd.gpuStageMs).map(([stage, total]) => [
        stage, round((total - nativeStart.gpuStageMs[stage]) / prepared),
      ]))
      : null;
    const trackStart = first.source.trackStats;
    const trackEnd = last.source.trackStats;
    const written = last.source.written - first.source.written;
    const encodeSeconds = last.outgoing?.totalEncodeTime - first.outgoing?.totalEncodeTime;
    const validEncodeTime = framesEncoded > 0 && last.outgoing.id === first.outgoing.id
      && Number.isFinite(encodeSeconds) && encodeSeconds >= 0;
    if (previewOnly && !written) throw new Error('За время замера в предпросмотр не поступили кадры');
    result = {
      ok: true, previewOnly, sendOnly, snapshotBytes: snapshot.bytes, seconds: round(seconds),
      framesEncoded, framesDecoded, sourceSize,
      captureTrackFps: settings.frameRate ?? null,
      trackFps: rate(last.outgoing?.sourceFrames, first.outgoing?.sourceFrames),
      encoderFps: rate(last.outgoing?.frames, first.outgoing?.frames),
      viewerFps: rate(last.incoming?.frames, first.incoming?.frames),
      viewerLatency: receiver ? {
        ...displayDelay,
        averageJitterBufferMs: validJitter ? round(jitterSeconds * 1000 / jitterFrames) : null,
      } : null,
      codec: last.incoming?.codec ?? null,
      encoder: sender ? {
        implementation: last.outgoing.encoderImplementation ?? null,
        powerEfficient: last.outgoing.powerEfficientEncoder ?? null,
        qualityLimitation: last.outgoing.qualityLimitationReason ?? null,
        averageEncodeMs: validEncodeTime ? round(encodeSeconds * 1000 / framesEncoded) : null,
      } : null,
      width: last.incoming?.width ?? null, height: last.incoming?.height ?? null,
      ...(timings && { timings }),
      ...(Number.isInteger(nativeEnd?.probeGpuPriority) && { gpuPriority: nativeEnd.probeGpuPriority }),
      ...(Number.isInteger(nativeEnd?.probeQueueMarkedCopies) && {
        queueMarkedCopies: nativeEnd.probeQueueMarkedCopies - nativeStart.probeQueueMarkedCopies,
      }),
      textureTrack: probe.mode !== 'baseline' && trackStart && trackEnd ? {
        received: trackEnd.received - trackStart.received,
        receivedFps: rate(trackEnd.received, trackStart.received),
        written,
        skippedBusy: trackEnd.skippedBusy - trackStart.skippedBusy,
        skippedBusyFps: rate(trackEnd.skippedBusy, trackStart.skippedBusy),
        averageWriteMs: written > 0 ? round((trackEnd.totalWriteMs - trackStart.totalWriteMs) / written) : null,
        maxWriteMs: written > 0 ? round(trackEnd.maxWriteMs) : null,
      } : null,
      native: nativeEnd && nativeStart && {
        windowsFps: rate(nativeEnd.frames, nativeStart.frames),
        importedFps: rate(last.source.transferred, first.source.transferred),
        writtenFps: rate(last.source.written, first.source.written),
        pacedOut: nativeEnd.pacedOut - nativeStart.pacedOut,
        noSlot: nativeEnd.noSlot - nativeStart.noSlot,
        replaced: nativeEnd.replaced - nativeStart.replaced,
        droppedByMain: last.source.dropped - first.source.dropped,
        averageTextureLeaseMs: released > 0
          ? round((last.source.totalLeaseMs - first.source.totalLeaseMs) / released) : null,
        averageCopyWaitMs: prepared > 0 ? round((nativeEnd.copyWaitMs - nativeStart.copyWaitMs) / prepared) : null,
        gpuStageAverageMs,
        maxCopyWaitMs: round(nativeEnd.maxCopyWaitMs),
        maxWindowsFrameGapMs: round(nativeEnd.maxFrameGapMs),
      },
    };
  } catch (error) {
    result = { ok: false, error: `${stage}: ${error.message}` };
  } finally {
    close();
    window.removeEventListener('pagehide', close);
    window.removeEventListener('capture-probe-stop', close);
    window.captureProbe?.finish(result);
  }
}

async function launch() {
  const probe = window.captureProbe;
  if (!probe) throw new Error('Предзагрузка стенда недоступна');
  if (probe.mode === 'synthetic') return run();
  const button = document.querySelector('#start');
  const modeNames = {
    baseline: 'обычная демонстрация',
    wgc: 'Windows Graphics Capture',
    dxgi: 'DXGI — предпросмотр и отправка',
    'dxgi-preview': 'DXGI — только предпросмотр',
    'dxgi-send-only': 'DXGI — отправка без предпросмотра',
    'dxgi-nv12': 'DXGI — отправка NV12 без предпросмотра',
  };
  if (probe.mode === 'dxgi-preview') document.querySelector('#remote').closest('figure').hidden = true;
  if (sendsWithoutPreview(probe.mode)) document.querySelector('#local').closest('figure').style.visibility = 'hidden';
  document.querySelector('#status').textContent = `Захват основного монитора — ${modeNames[probe.mode]}`;
  if (probe.autoStart) return run();
  button.hidden = false;
  button.addEventListener('click', () => {
    button.disabled = true;
    void run().catch(showError);
  }, { once: true });
}

function showError(error) {
  document.querySelector('#status').textContent = `Ошибка: ${error.message}`;
  window.captureProbe?.finish({ ok: false, error: error.message });
}

Promise.resolve(launch()).catch(showError);
