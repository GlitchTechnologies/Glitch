import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc show MediaStreamTrack;
import 'package:livekit_client/livekit_client.dart' as lk;

import '../core/platform_info.dart';
import '../core/stream_preview_size.dart';
import 'call_foreground_service.dart';
import 'voice_connection.dart';

/// В браузере показ экрана стоит одного вызова: окно выбора рисует сам браузер.
/// На Android за тем же `getDisplayMedia` стоит MediaProjection, и у неё есть
/// жёсткий порядок, введённый в Android 14 (у нас targetSdk 36):

final bool screenCaptureSupported = isAndroidPlatform;

Future<bool> prepareScreenCapture() async {
  if (!screenCaptureSupported) return false;
  if (!await voiceConnection.requestScreenCapturePermission()) return false;
  await CallForegroundService.setScreenCapture(true);
  return true;
}

Future<void> releaseScreenCapture() => CallForegroundService.setScreenCapture(false);

Future<bool> startScreenShare(lk.LocalParticipant local) async {
  await local.setScreenShareEnabled(true);
  return false;
}

const bool screenSourceChangeable = false;

class ScreenCapture {}

Future<ScreenCapture> captureScreen(lk.LocalParticipant local) =>
    throw UnsupportedError('screen source change is not supported here');

Future<bool> publishScreen(lk.LocalParticipant local, ScreenCapture capture) =>
    throw UnsupportedError('screen source change is not supported here');

Future<void> discardScreen(ScreenCapture capture) async {}

Future<Uint8List?> grabPreviewFrame(rtc.MediaStreamTrack track) async {
  final png = await track.captureFrame();
  final out = await FlutterImageCompress.compressWithList(
    png.asUint8List(),
    quality: (kStreamPreviewQuality * 100).round(),
    minWidth: kStreamPreviewWidth,
    minHeight: kStreamPreviewHeight,
    format: CompressFormat.jpeg,
  );
  return out.isEmpty ? null : out;
}
