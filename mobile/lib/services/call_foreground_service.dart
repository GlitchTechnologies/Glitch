import '../core/call_constants.dart';
export '../core/call_constants.dart' show callServiceHangupSignal;
import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// ЭТО НЕ УКРАШЕНИЕ, А УСЛОВИЕ РАБОТЫ ЗВОНКА. С Android 11 система забирает
/// микрофон у приложения, ушедшего в фон: стоит свернуть Glitch во время
/// разговора — и собеседник перестаёт вас слышать. Единственный законный
/// способ этого избежать — foreground-сервис. А у него, по правилам самой
/// Android, ОБЯЗАНО быть постоянное видимое уведомление, иначе система его
/// убьёт. То есть карточка в шторке — это и есть «лицо» механизма, который
/// держит разговор живым.

const String _hangupButtonId = 'call_hangup';

/// Сообщение, которое сервисный изолят шлёт основному при нажатии кнопки.

/// Точка входа сервисного изолята.
///
/// @pragma('vm:entry-point') обязателен: функция вызывается не из нашего кода,
/// а движком Dart в ОТДЕЛЬНОМ изоляте, и без этой пометки компилятор выбросит
/// её как «никем не используемую» при сборке release-версии.
@pragma('vm:entry-point')
void callTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_CallTaskHandler());
}

/// Обработчик, живущий в сервисном изоляте.
///
/// Своей логики звонка здесь НЕТ и быть не должно: у этого изолята отдельная
/// память, он ничего не знает ни про CallProvider, ни про WebRTC-соединение.
/// Его единственная задача — поймать нажатие кнопки и передать его основному
/// изоляту, где живёт настоящий звонок.
class _CallTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == _hangupButtonId) {
      // Основной изолят слушает это через addTaskDataCallback и кладёт трубку
      // тем же путём, что и красная кнопка на экране звонка.
      FlutterForegroundTask.sendDataToMain(callServiceHangupSignal);
    }
  }
}

/// Управление сервисом из основного изолята.
class CallForegroundService {
  static bool _initialized = false;

  static bool _wanted = false;

  static bool _screenCapture = false;

  static String _peerName = '';
  static String _ongoingText = '';
  static String _hangUpText = '';

  static Future<void> _queue = Future<void>.value();

  /// Ошибку гасим ВНУТРИ, и это принципиально: упади операция наружу, хвост
  /// очереди остался бы «сломанным» навсегда, и все последующие запуски и
  /// остановки молча перестали бы выполняться вовсе.
  static Future<void> _enqueue(Future<void> Function() action) {
    final next = _queue.then((_) async {
      try {
        await action();
      } catch (_) {
      }
    });
    _queue = next;
    return next;
  }

  static List<ForegroundServiceTypes> get _types => _screenCapture
      ? [ForegroundServiceTypes.microphone, ForegroundServiceTypes.mediaProjection]
      : [ForegroundServiceTypes.microphone];

  /// Разовая настройка. Идемпотентна — повторные вызовы ничего не делают.
  static void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'glitch_call_ongoing',
        channelName: 'Активный звонок',
        channelDescription: 'Показывается, пока идёт разговор',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        playSound: false,
        enableVibration: false,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // nothing() — сервису не нужен повторяющийся тик, он лишь удерживает
        // процесс живым. Таймер разговора считает основной изолят.
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowAutoRestart: false,
      ),
    );
  }

  static Future<void> start({
    required String peerName,
    required String ongoingText,
    required String hangUpText,
  }) {
    _wanted = true;
    _peerName = peerName;
    _ongoingText = ongoingText;
    _hangUpText = hangUpText;
    _ensureInitialized();
    return _enqueue(() async {
      if (!_wanted) return;
      if (await FlutterForegroundTask.isRunningService) return;
      if (!_wanted) return; // проверяем СНОВА: выше была точка ожидания
      await _startWithCurrentTypes();
      if (!_wanted) await FlutterForegroundTask.stopService();
    });
  }

  static Future<void> _startWithCurrentTypes() {
    return FlutterForegroundTask.startService(
      serviceId: 1001,
      serviceTypes: _types,
      notificationTitle: _peerName.isEmpty ? _ongoingText : _peerName,
      notificationText: _ongoingText,
      notificationButtons: [
        NotificationButton(id: _hangupButtonId, text: _hangUpText),
      ],
      callback: callTaskCallback,
    );
  }

  static Future<void> setScreenCapture(bool on) {
    if (_screenCapture == on) return Future<void>.value();
    _screenCapture = on;
    return _enqueue(() async {
      if (!_wanted) return;
      if (_screenCapture != on) return;

      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
        if (!_wanted || _screenCapture != on) return;
      }
      await _startWithCurrentTypes();
      if (!_wanted) await FlutterForegroundTask.stopService();
    });
  }

  static Future<void> stop() {
    _wanted = false;
    _screenCapture = false;
    return _enqueue(() async {
      if (_wanted) return;
      if (!await FlutterForegroundTask.isRunningService) return;
      if (_wanted) return;
      await FlutterForegroundTask.stopService();
    });
  }
}
