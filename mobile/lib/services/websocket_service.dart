import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'ws_connector_web.dart' if (dart.library.io) 'ws_connector_native.dart';
import 'ws_wakeup_web.dart' if (dart.library.io) 'ws_wakeup_native.dart';
import 'auth_service.dart';
import 'push_service.dart';

typedef WsEventCallback = void Function(Map<String, dynamic> event);
typedef WsReconnectCallback = void Function();

class WebSocketService {
  static const _wsBase = 'wss://glitchapp.online';

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final List<WsEventCallback> _listeners = [];
  final List<WsReconnectCallback> _reconnectListeners = [];
  final List<WsReconnectCallback> _connectListeners = [];
  String? _token;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  int _attempt = 0;
  bool _connecting = false;
  bool _connected = false;
  bool _everConnected = false;

  static const _silenceLimit = Duration(seconds: 60);
  static const _watchdogTick = Duration(seconds: 10);
  final _sinceHeard = Stopwatch();
  Timer? _watchdog;

  void _startWatchdog() {
    _watchdog?.cancel();
    _sinceHeard
      ..reset()
      ..start();
    _watchdog = Timer.periodic(_watchdogTick, (_) {
      final token = _token;
      if (!_connected || _connecting || token == null) return;
      if (_sinceHeard.elapsed <= _silenceLimit) return;
      _reconnectAttempt = 0;
      unawaited(_open(token));
    });
  }

  void _stopWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
    _sinceHeard.stop();
  }

  bool get isConnected => _connected;

  void addReconnectListener(WsReconnectCallback cb) => _reconnectListeners.add(cb);
  void removeReconnectListener(WsReconnectCallback cb) => _reconnectListeners.remove(cb);

  void addConnectListener(WsReconnectCallback cb) => _connectListeners.add(cb);
  void removeConnectListener(WsReconnectCallback cb) => _connectListeners.remove(cb);

  Future<bool> waitUntilConnected({Duration timeout = const Duration(seconds: 5)}) async {
    if (_connected) return true;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_connected) return true;
    }
    return _connected;
  }

  void addListener(WsEventCallback cb) => _listeners.add(cb);
  void removeListener(WsEventCallback cb) => _listeners.remove(cb);

  static const _shortHide = Duration(seconds: 20);

  bool _wakeupBound = false;

  void _onWake(Duration hidden) {
    final token = _token;
    if (token == null) return;      // не залогинены — подключаться нечем
    if (_connecting) return;        // подключение уже идёт, не мешаем
    if (_connected && hidden <= _shortHide) return;
    _reconnectTimer?.cancel();
    _reconnectAttempt = 0;
    unawaited(_open(token));
  }

  Future<void> connect(String token) async {
    if (!_wakeupBound) {
      _wakeupBound = true;
      bindWsWakeup(_onWake);
      AppLifecycleListener(onStateChange: (_) => _reportAppState());
    }
    if (token == _token && (_connected || _connecting)) return;
    await _open(token);
  }

  static const _connectTimeout = Duration(seconds: 15);

  Future<void> _open(String token) async {
    _token = token;
    final attempt = ++_attempt;
    _reconnectTimer?.cancel();
    _stopWatchdog();
    _connecting = true;
    _connected = false;
    _sub?.cancel();
    _sub = null;
    final old = _channel;
    _channel = null;
    try { await old?.sink.close().timeout(const Duration(seconds: 3)); } catch (_) {}
    if (attempt != _attempt) return; // пока закрывали, начали новую попытку или вышли

    WebSocketChannel? channel;
    try {
      channel = await openWsChannel(wsBase: _wsBase, token: token);
      await channel.ready.timeout(_connectTimeout);
      if (attempt != _attempt) {
        _closeQuietly(channel);
        return;
      }
      _channel = channel;
      _reconnectAttempt = 0;
      _connecting = false;
      _connected = true;
      if (_everConnected) {
        for (final cb in List.of(_reconnectListeners)) { cb(); }
      }
      _everConnected = true;
      _sentInBackground = false;
      _reportAppState();
      for (final cb in List.of(_connectListeners)) { cb(); }
      // Сеть точно есть — досылаем FCM-токен, если прошлая попытка не дошла
      // (иначе пользователь молча оставался без пушей до перезапуска приложения)
      unawaited(pushService.resyncTokenIfNeeded());
      _sub = _channel!.stream.listen(
        _onMessage,
        onDone: _onDisconnect,
        onError: (_) => _onDisconnect(),
        cancelOnError: true, // после onError подписка отменяется, onDone не стреляет
      );
      _startWatchdog();
    } catch (_) {
      if (channel != null) _closeQuietly(channel);
      if (attempt != _attempt) return; // нас уже перебили — повтор не наш
      _connecting = false;
      _connected = false;
      _channel = null;
      _scheduleReconnect();
    }
  }

  void _closeQuietly(WebSocketChannel channel) {
    try {
      unawaited(channel.sink
          .close()
          .timeout(const Duration(seconds: 3))
          .catchError((_) {}));
    } catch (_) {}
  }

  void _onMessage(dynamic raw) {
    _sinceHeard.reset();
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      // Эту сессию завершили с другого устройства (Настройки → Безопасность →
      // Активные сессии) — разлогиниваемся сразу, не дожидаясь 401 на следующий запрос.
      if (data['type'] == 'session.revoked') {
        authService.forceLogout();
        return;
      }
      if (data['type'] == 'ping') {
        send({'type': 'pong'});
        return;
      }
      for (final cb in List.of(_listeners)) {
        cb(data);
      }
    } catch (_) {}
  }

  void _onDisconnect() {
    if (_connecting) return; // игнорируем события от старого канала пока новый подключается
    _connected = false;
    _stopWatchdog();
    _sub?.cancel();
    _sub = null;
    _channel = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectAttempt++;
    final base = (2 << (_reconnectAttempt - 1).clamp(0, 5)).toDouble();
    final jitter = base * 0.2 * (DateTime.now().millisecond / 1000);
    final delay = (base + jitter).clamp(2.0, 60.0);
    _reconnectTimer = Timer(Duration(milliseconds: (delay * 1000).toInt()), () {
      final token = _token;
      if (token != null) unawaited(_open(token));
    });
  }

  void send(Map<String, dynamic> data) {
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  // Сервер не шлёт пуш устройству, до которого сообщение дошло по сокету. Но
  // у свёрнутого телефона сокет живёт ещё секунды-минуты, и сообщения за это
  // время не показывались НИКАК: пуша нет (на связи), а своё уведомление
  // телефон по сокету не рисует. Поэтому приложение говорит серверу
  // «я в фоне» — и такому устройству сервер шлёт пуш, как отключённому
  // (manager.attentive_session_ids). Старые сборки не говорят ничего и
  // считаются на экране — как раньше.
  bool _sentInBackground = false;

  static bool get _inBackground => switch (WidgetsBinding.instance.lifecycleState) {
        AppLifecycleState.paused || AppLifecycleState.hidden || AppLifecycleState.detached => true,
        _ => false,
      };

  void _reportAppState() {
    if (!_connected) return;
    final inBackground = _inBackground;
    if (inBackground == _sentInBackground) return;
    _sentInBackground = inBackground;
    send({'type': 'session.state', 'in_background': inBackground});
  }

  void sendTypingStart(int chatId) {
    send({'type': 'typing.start', 'chat_id': chatId});
  }

  void sendTypingStop(int chatId) {
    send({'type': 'typing.stop', 'chat_id': chatId});
  }

  Future<void> disconnect() async {
    _attempt++;
    _reconnectTimer?.cancel();
    _stopWatchdog();
    _connecting = false;
    _connected = false;
    _token = null;
    _sub?.cancel();
    _sub = null;
    _listeners.clear();
    // _reconnectListeners НЕ чистим (реальный найденный баг, 2026-08-25) —
    // в отличие от _listeners (все её подписчики — провайдеры конкретных
    // экранов, снимаются своим же dispose() при закрытии), здесь есть и
    // ОДИН слушатель на весь процесс приложения (main.dart::_AeroAppState,
    // подписывается в initState() РОВНО ОДИН РАЗ за жизнь приложения). Если
    // чистить список здесь, этот слушатель терялся бы НАВСЕГДА после первого
    // же выхода из аккаунта — очистка кэша картинок при переподключении
    // (см. doc-комментарий addReconnectListener) молча переставала бы
    // работать до перезапуска приложения.
    _everConnected = false;
    try {
      await _channel?.sink.close().timeout(const Duration(seconds: 3));
    } catch (_) {}
    _channel = null;
  }
}

final wsService = WebSocketService();
