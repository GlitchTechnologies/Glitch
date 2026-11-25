import 'dart:js_interop';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc show RTCVideoRenderer;
// Браузерная половина RTCVideoRenderer — та же, что `rtc.RTCVideoRenderer` в
// веб-сборке (библиотека выбирает её сама). Прямо — ради [blurredVideo]:
// элемент страницы (`findHtmlView`) есть только у неё, а разбор кода без
// веб-сборки видел бы телефонную половину.
// ignore: implementation_imports
import 'package:flutter_webrtc/src/web/rtc_video_renderer_impl.dart' as rtc_web;
import 'package:media_kit/media_kit.dart';
import 'package:web/web.dart' as web;



class CallForegroundService {
  static Future<void> start({
    required String peerName,
    required String ongoingText,
    required String hangUpText,
  }) async {}

  static Future<void> stop() async {}
}

/// ИСПРАВЛЕНО 2026-08-22: раньше здесь были три пустых заглушки с комментарием
/// «о входящем сообщает уведомление браузера со звуком» — неправда, проверено
/// чтением `push_service_web.dart`: браузерных `Notification` там нет вообще
/// ни одной (осознанно — вкладка открыта, экран звонка и так виден). Из-за
/// этого несовпадения входящий звонок на вебе был полностью беззвучным: ни
/// нативного рингтона (это заглушка), ни browser-уведомления (его никогда и не
/// было). Теперь играем по-настоящему — те же файлы, что уже использует
/// нативный плагин на телефоне (`assets/sounds/glitch_voice_calling.mp3`/`ringback.ogg`,
/// объявлены в pubspec.yaml, лицензионно чистые и уже зациклены по построению).
enum IncomingNotice { first, ringing, handled }

class GlitchRingtone {
  static Player? _player;
  static String? _objectUrl;

  static final Set<int> _knownCalls = <int>{};
  static int? _ringingCallId;

  static Future<void> playIncoming({required int callId, bool silent = false}) async {
    _remember(callId);
    try {
      if (silent) {
        await stop();
        return;
      }
      await _play('assets/sounds/glitch_voice_calling.mp3', 'audio/mpeg');
    } finally {
      _ringingCallId = callId;
    }
  }

  static Future<void> playOutgoing() => _play('assets/sounds/ringback.ogg', 'audio/ogg');

  static Future<IncomingNotice> claimIncoming(int callId) async {
    if (_remember(callId)) return IncomingNotice.first;
    return _ringingCallId == callId ? IncomingNotice.ringing : IncomingNotice.handled;
  }

  static Future<bool> finishRinging(int callId) async {
    final ringing = _ringingCallId;
    if (ringing == null) return true;
    if (ringing != callId) return false;
    await stop();
    return true;
  }

  static bool _remember(int callId) {
    if (!_knownCalls.add(callId)) return false;
    if (_knownCalls.length > 64) _knownCalls.remove(_knownCalls.first);
    return true;
  }

  static Future<void> _play(String assetPath, String mimeType) async {
    await stop();

    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
    final objectUrl = web.URL.createObjectURL(blob);
    _objectUrl = objectUrl;

    final player = Player();
    _player = player;
    await player.setPlaylistMode(PlaylistMode.single);
    await player.open(Media(objectUrl));
    await player.play();
  }

  static Future<void> stop() async {
    _ringingCallId = null;
    final player = _player;
    _player = null;
    if (player != null) {
      try { await player.stop(); } catch (_) {}
      try { await player.dispose(); } catch (_) {}
    }
    final objectUrl = _objectUrl;
    _objectUrl = null;
    if (objectUrl != null) web.URL.revokeObjectURL(objectUrl);
  }
}

/// Сигналов из сервисного изолята в браузере не бывает — изолята нет, как нет
/// и карточки активного звонка в шторке. Пустые реализации здесь правильны.
void bindCallServiceData(void Function(Object data) onData) {}

void unbindCallServiceData(void Function(Object data) onData) {}

const bool callSupportsSpeaker = false;

Future<void> setSpeakerphone(bool on) async {}

const bool callSupportsAudioInputSelection = true;

const bool callSupportsCameraSelection = true;

const bool callVideoZoomSupported = false;

Widget blurredVideo(rtc.RTCVideoRenderer renderer, Widget view, double sigma) {
  (renderer as rtc_web.RTCVideoRenderer).findHtmlView()?.style.filter = 'blur(${sigma}px)';
  return view;
}

Future<bool> ensureMicrophonePermission() async => true;

JSFunction? _pageHideHandler;

void bindPageHide(void Function() onHide) {
  unbindPageHide();
  final handler = ((web.Event _) => onHide()).toJS;
  _pageHideHandler = handler;
  web.window.addEventListener('pagehide', handler);
}

void unbindPageHide() {
  final handler = _pageHideHandler;
  _pageHideHandler = null;
  if (handler != null) web.window.removeEventListener('pagehide', handler);
}

Future<bool> ensureCameraPermission() async => true;

Future<void> initNativeCallStack() async {}

enum TelecomEvent {
  answer,
  reject,
  disconnect,
  rejectedBySystem,
  muted,
  unmuted,
  showIncomingUi,
}

class GlitchTelecom {
  static Future<bool> register() async => false;
  static Future<bool> reportIncoming(String callerName) async => false;
  static Future<bool> reportOutgoing(String calleeName) async => false;
  static Future<void> setActive() async {}
  static Future<void> setEnded() async {}

  static Future<bool> setSpeaker(bool on) async => false;
  static void listen(void Function(TelecomEvent event) onEvent) {}
}
