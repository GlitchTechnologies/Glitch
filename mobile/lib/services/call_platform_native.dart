import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc show RTCVideoRenderer;
import 'push_service_native.dart' show handleBackgroundPush;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:glitch_ringtone/glitch_ringtone.dart' show GlitchTelecom;
import 'package:permission_handler/permission_handler.dart';

import 'voice_connection.dart';
export 'call_foreground_service.dart' show CallForegroundService;
export 'package:glitch_ringtone/glitch_ringtone.dart'
    show GlitchRingtone, GlitchTelecom, IncomingNotice, TelecomEvent;

/// Подписка на сигналы из СЕРВИСНОГО изолята (кнопка «Завершить» на карточке
/// активного звонка). У изолята нет своей памяти — он умеет только прислать
/// сигнал сюда.
void bindCallServiceData(void Function(Object data) onData) {
  FlutterForegroundTask.removeTaskDataCallback(onData);
  FlutterForegroundTask.addTaskDataCallback(onData);
}

void unbindCallServiceData(void Function(Object data) onData) {
  FlutterForegroundTask.removeTaskDataCallback(onData);
}

const bool callSupportsSpeaker = true;

Future<void> setSpeakerphone(bool on) async {
  if (await GlitchTelecom.setSpeaker(on)) return;
  await voiceConnection.setSpeakerPreferred(on);
}

const bool callSupportsAudioInputSelection = false;

const bool callSupportsCameraSelection = false;

const bool callVideoZoomSupported = true;

Widget blurredVideo(rtc.RTCVideoRenderer renderer, Widget view, double sigma) => ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: ui.TileMode.clamp),
      child: view,
    );

Future<bool> ensureMicrophonePermission() async {
  final status = await Permission.microphone.request();
  return status.isGranted;
}

void bindPageHide(void Function() onHide) {}

void unbindPageHide() {}

Future<bool> ensureCameraPermission() async {
  final status = await Permission.camera.request();
  return status.isGranted;
}

Future<void> initNativeCallStack() async {
  await Firebase.initializeApp();

  FlutterForegroundTask.initCommunicationPort();

  FirebaseMessaging.onBackgroundMessage(handleBackgroundPush);
}
