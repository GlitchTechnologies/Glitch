import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_webrtc/dart_webrtc.dart' show MediaStreamTrackWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc show MediaStreamTrack, navigator;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:web/web.dart' as web;

import '../core/call_video_quality.dart';
import '../core/stream_preview_size.dart';
import 'desktop_shell.dart';
import 'error_reporter.dart';
import 'screen_share_quality.dart';


const bool screenCaptureSupported = true;

Future<bool> prepareScreenCapture() async => true;

Future<void> releaseScreenCapture() async {}

/// Свой вызов `getDisplayMedia`, а не `setScreenShareEnabled` медиасервера:
/// тот умеет просить у браузера звук только целиком «да / нет», а нам нужен
/// `restrictOwnAudio` (2026-10-07).
Future<bool> startScreenShare(lk.LocalParticipant local) async =>
    publishScreen(local, await captureScreen(local));

const bool screenSourceChangeable = true;

class ScreenCapture {
  final lk.LocalVideoTrack video;
  final lk.LocalAudioTrack? audio;

  final bool soundDropped;
  final lk.VideoParameters params;

  ScreenCapture._(this.video, this.audio, this.soundDropped, this.params);
}

Future<ScreenCapture> captureScreen(lk.LocalParticipant local) async {
  if (lk.lkPlatformIsWebMobile()) {
    throw lk.TrackCreateException('Screen sharing is not supported on mobile devices');
  }
  final quality = screenShareQuality.value;
  final params = CallVideoQuality.computerScreenOf(quality);
  final options = local.room.roomOptions.defaultScreenShareCaptureOptions.copyWith(params: params);
  final size = quality.resolution.size;
  final dxgi = await desktopShell?.captureDxgiScreen(fps: quality.fps, width: size?.width, height: size?.height);
  final stream = dxgi?.stream ?? await rtc.navigator.mediaDevices.getDisplayMedia(<String, dynamic>{
    'video': <String, dynamic>{
      if (size != null) 'width': size.width,
      if (size != null) 'height': size.height,
      'frameRate': quality.fps,
    },
    'audio': <String, dynamic>{'restrictOwnAudio': true},
  });
  final videoTracks = stream.getVideoTracks();
  final audioTracks = stream.getAudioTracks();
  var audio = audioTracks.isEmpty
      ? null
      : lk.LocalAudioTrack(lk.TrackSource.screenShareAudio, stream, audioTracks.first, const lk.AudioCaptureOptions());
  if (videoTracks.isEmpty) {
    await _release(audio);
    for (final t in stream.getTracks()) {
      await t.stop();
    }
    throw lk.TrackCreateException('Screen capture returned no video');
  }
  // Показ — движение, а не документ: иначе браузер ради резкости каждого
  // кадра выбрасывает кадры, и игра идёт слайд-шоу (call_video_quality,
  // «Движение важнее резкости»). До публикации: по подсказке браузер
  // настраивает кодировщик.
  (videoTracks.first as MediaStreamTrackWeb).jsTrack.contentHint = 'motion';
  final video = lk.LocalVideoTrack(lk.TrackSource.screenShareVideo, stream, videoTracks.first, options);
  // Мост отдаёт звук WASAPI только из сеанса с исключением процессов Glitch.
  // Для звука getDisplayMedia нужно подтверждение ограничения от браузера.
  var soundDropped = dxgi?.soundDropped ?? false;
  if (audio != null && dxgi == null && !_soundIsClean(videoTracks.first, audioTracks.first)) {
    await _release(audio);
    audio = null;
    soundDropped = true;
  }
  return ScreenCapture._(video, audio, soundDropped, params);
}

Future<bool> publishScreen(lk.LocalParticipant local, ScreenCapture capture) async {
  final track = (capture.video.mediaStreamTrack as MediaStreamTrackWeb).jsTrack;
  final lk.LocalTrackPublication<lk.LocalVideoTrack> publication;
  try {
    if (track.readyState == 'ended') throw lk.TrackCreateException('Screen capture ended before publishing');
    publication = await local.publishVideoTrack(
      capture.video,
      publishOptions: local.room.roomOptions.defaultVideoPublishOptions.copyWith(
        videoCodec: CallVideoQuality.computerScreenCodec,
        screenShareEncoding: capture.params.encoding,
      ),
    );
  } catch (_) {
    await discardScreen(capture);
    rethrow;
  }
  if (track.readyState == 'ended') {
    try {
      if (local.getTrackPublicationBySource(lk.TrackSource.screenShareVideo)?.sid == publication.sid) {
        await local.removePublishedTrack(publication.sid);
      }
    } finally {
      await _release(capture.audio);
    }
    throw lk.TrackCreateException('Screen capture ended while publishing');
  }
  final audio = capture.audio;
  if (audio == null) return capture.soundDropped;
  final audioTrack = (audio.mediaStreamTrack as MediaStreamTrackWeb).jsTrack;
  if (audioTrack.readyState == 'ended') {
    await _release(audio);
    return true;
  }
  try {
    final audioPublication = await local.publishAudioTrack(audio);
    if (audioTrack.readyState == 'ended' || track.readyState == 'ended') {
      if (local.getTrackPublicationBySource(lk.TrackSource.screenShareAudio)?.sid == audioPublication.sid) {
        await local.removePublishedTrack(audioPublication.sid);
      }
      return true;
    }
  } catch (e, s) {
    await _release(audio);
    errorReporter.report(e, stack: s, screen: 'voice:screenShareAudio');
    return true;
  }
  return false;
}

Future<void> discardScreen(ScreenCapture capture) async {
  await _release(capture.video);
  await _release(capture.audio);
}

bool _soundIsClean(rtc.MediaStreamTrack video, rtc.MediaStreamTrack audio) {
  final surface = _setting(video, 'displaySurface');
  if (surface == 'browser') return true;
  return _setting(audio, 'restrictOwnAudio') == true;
}

Object? _setting(rtc.MediaStreamTrack track, String name) {
  final settings = (track as MediaStreamTrackWeb).jsTrack.getSettings() as JSObject;
  return settings.getProperty<JSAny?>(name.toJS).dartify();
}

Future<void> _release(lk.LocalTrack? track) async {
  if (track == null) return;
  await track.stop();
  await track.dispose();
}

/// Снимок кадра своего показа (экрана или камеры) для окна при наведении —
/// уже уменьшенный JPEG (services/stream_preview.dart). null — браузер
/// снимать кадр не умеет (ImageCapture есть в Chrome, Яндекс Браузере, Edge и
/// программе для Windows; в Firefox нет).
Future<Uint8List?> grabPreviewFrame(rtc.MediaStreamTrack track) async {
  final ctor = globalContext['ImageCapture'];
  if (ctor == null || ctor.isUndefinedOrNull) return null;
  final capture = (ctor as JSFunction).callAsConstructor<JSObject>((track as MediaStreamTrackWeb).jsTrack);
  final bitmap = await capture.callMethod<JSPromise<web.ImageBitmap>>('grabFrame'.toJS).toDart;
  try {
    final w = bitmap.width, h = bitmap.height;
    if (w == 0 || h == 0) return null;
    final scale = math.min(1.0, math.min(kStreamPreviewWidth / w, kStreamPreviewHeight / h));
    final canvas = web.HTMLCanvasElement()
      ..width = (w * scale).round()
      ..height = (h * scale).round();
    (canvas.getContext('2d') as web.CanvasRenderingContext2D)
        .drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    final done = Completer<web.Blob?>();
    canvas.toBlob(((web.Blob? b) => done.complete(b)).toJS, 'image/jpeg', kStreamPreviewQuality.toJS);
    final blob = await done.future;
    if (blob == null) return null;
    return (await blob.arrayBuffer().toDart).toDart.asUint8List();
  } finally {
    bitmap.close();
  }
}
