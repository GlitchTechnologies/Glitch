import 'dart:async';
import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:glitch_ringtone/glitch_ringtone.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'app_sounds.dart';
import 'incoming_call_notification.dart';
import 'push_target.dart';
import 'voice_cue.dart';

// Канал уведомлений Android (id должен совпадать с channel_id на сервере,
// см. fcm_service.py -> android.notification.channel_id)
const _channelId   = 'glitch_messages';
const _channelName = 'Сообщения Glitch';

const _callsChannelId   = 'glitch_calls';
const _callsChannelName = 'Звонки Glitch';

const _systemNewLoginId = -1;

// История (2026-07-16). Раньше фоновый обработчик рисовал поверх системного
// уведомления свой InboxStyle со счётчиком. На практике фоновый изолят
// оказался лотереей: на тестовом телефоне сработал для 2 сообщений из 7
// (дальше прошивка задушила процесс), а в шторке оставались ДВА уведомления
// одного чата — системное и наше, с задвоенным счётчиком («Имя · 2 · 2»).
// Обработчик убрали, и для СООБЩЕНИЙ это правило действует до сих пор:
// уведомления о сообщениях рисует только система, клиент к ним не притрагивается
// (кроме foreground с порванным WS — см. _handleForegroundPush).
//
// СНЯТИЕ уведомления (2026-10-10) — по той же логике «улучшает, а не
// заменяет»: чат прочитали до конца на другом устройстве, сервер шлёт тихий
// пуш `chat_dismiss` (notification_service.notify_chat_read), и обработчик
// убирает уведомление чата из шторки. Ничего не рисует; не сработал (прошивка
// задушила изолят) — уведомление просто повисит, как висело до этого.

AndroidNotificationChannel _buildChannel() => const AndroidNotificationChannel(
  _channelId,
  _channelName,
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

AndroidNotificationChannel _buildCallsChannel() => const AndroidNotificationChannel(
  _callsChannelId,
  _callsChannelName,
  description: 'Входящие и пропущенные вызовы',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

/// @pragma('vm:entry-point') обязателен: функцию вызывает не наш код, а
/// система в отдельном изоляте, и без пометки компилятор выбросит её при
/// сборке release как «неиспользуемую».
@pragma('vm:entry-point')
void _onBackgroundNotificationResponse(NotificationResponse response) {
  // Обязательно в фоновом изоляте, до обращения к любому плагину.
  //
  // Этот изолят поднят системой с нуля: в нём НЕ зарегистрированы плагины
  // приложения, и SharedPreferences (откуда берётся токен) без этой строки
  // просто бросает исключение. Именно поэтому кнопка «Отклонить» молчала:
  // ошибка гасилась try/catch, запрос до сервера не доходил ни разу — в
  // журнале сервера не было ни одного обращения к ручке отказа. Кнопка
  // «Принять» при этом работала, потому что приложение по ней запускает сама
  // Android, никакого нашего кода в фоне для неё не нужно.
  DartPluginRegistrant.ensureInitialized();
  // Тип обратного вызова у плагина — void, дождаться нашей асинхронной работы
  // он не может. Поэтому внутри handleCallNotificationAction всё сделано
  // максимально коротко, а сам изолят живёт ровно столько, сколько нужно
  // одному HTTP-запросу с жёстким таймаутом.
  unawaited(handleCallNotificationAction(response));
}

/// Общая обработка кнопок «Принять»/«Отклонить» — одна и та же и для живого
/// приложения, и для фонового изолята. Именно поэтому она вынесена в отдельную
/// функцию, а не продублирована в двух местах.
Future<void> handleCallNotificationAction(NotificationResponse response) async {
  final actionId = response.actionId;
  if (actionId != callActionAccept && actionId != callActionDecline) return;

  final payload = IncomingCallPayload.decode(response.payload);
  if (payload == null) {
    await _reportFromBackground('call action: payload не разобран',
        'actionId=$actionId raw=${response.payload}');
    return;
  }

  await GlitchRingtone.stop();

  try {
    if (actionId == callActionDecline) {
      await _declineCallOverHttp(payload);
    } else {
      // Принять можно только в живом приложении (нужны микрофон и WebRTC), а
      // оно как раз сейчас запускается системой (showsUserInterface: true).
      // Оставляем «записку» на диске — основной изолят прочитает её на старте.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(pendingCallAcceptKey, payload.callId);
    }
  } catch (e) {
    // Показать ошибку тут некому — изолят фоновый, интерфейса нет. Поэтому
    // отправляем её на сервер: иначе такие сбои не видны ВООБЩЕ никак, и
    // «кнопка не работает» приходится выяснять перебором гипотез.
    await _reportFromBackground('call action упал: $actionId', '$e');
  }
}

/// Отчёт о происходящем в фоновом изоляте — на сервер, во вкладку «Логи».
///
/// Единственный способ хоть что-то узнать о коде, который выполняется без
/// интерфейса, часто при закрытом приложении. Ручка приёма отчётов намеренно
/// не требует авторизации (см. app/api/logs.py), поэтому работает и здесь,
/// где токена может не быть вовсе.
Future<void> _reportFromBackground(String message, [String? details]) async {
  try {
    await http
        .post(
          Uri.parse('${ApiService.baseUrl}/logs/client'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'message': message,
            'details': details,
            'screen': 'background_isolate',
            'platform': 'android',
          }),
        )
        .timeout(const Duration(seconds: 5));
  } catch (_) {
  }
}

/// Токен берётся напрямую из SharedPreferences (тот же ключ, что у
/// auth_service): экземпляр api-сервиса живёт в основном изоляте и здесь
/// недоступен. Адрес — под префиксом /chats, который уже проксируется nginx
/// (см. шапку app/api/calls.py).
Future<void> _declineCallOverHttp(IncomingCallPayload payload) async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('aero_token');
  if (token == null || token.isEmpty) {
    await _reportFromBackground('call decline: нет токена в хранилище');
    return;
  }

  final uri = Uri.parse(
      '${ApiService.baseUrl}/chats/${payload.chatId}/calls/${payload.callId}/decline');
  final res = await http
      .post(uri, headers: {'Authorization': 'Bearer $token'})
      // Жёсткий таймаут: фоновому изоляту система даёт считанные секунды,
      // висеть на мёртвой сети нельзя.
      .timeout(const Duration(seconds: 8));
  if (res.statusCode != 200) {
    await _reportFromBackground(
        'call decline: сервер ответил ${res.statusCode}', res.body);
  }
}

@pragma('vm:entry-point')
Future<void> handleBackgroundPush(RemoteMessage message) async {
  final data = message.data;
  if (data['type'] == _chatDismissType) {
    final chatId = int.tryParse(data[_dismissChatIdKey] ?? '');
    if (chatId != null) await _cancelChatNotification(chatId);
    return;
  }
  final event = data['call_event'];
  if (event != 'incoming' && event != 'ended') return;

  // Тот же фоновый изолят, что и у кнопок, — плагины в нём нужно поднять явно.
  DartPluginRegistrant.ensureInitialized();

  final callId = int.tryParse(data['call_id'] ?? '');
  final chatId = int.tryParse(data['chat_id'] ?? '');
  if (callId == null || chatId == null) return;

  if (event == 'ended') {
    if (!await GlitchRingtone.finishRinging(callId)) return;
    await _cancelCallCard(callId);
    return;
  }

  final notice = await GlitchRingtone.claimIncoming(callId);
  if (notice == IncomingNotice.handled) {
    if (await GlitchRingtone.finishRinging(callId)) await _cancelCallCard(callId);
    return;
  }

  try {
    // В фоновом изоляте свой экземпляр плагина — тот, что в PushService,
    // живёт в другой памяти и отсюда недоступен.
    //
    // ОБРАБОТЧИКИ ЗДЕСЬ НЕ ПЕРЕДАЁМ, и это важно. Плагин при инициализации
    // сохраняет ссылку на функцию-обработчик кнопок в системное хранилище —
    // именно по ней Android потом находит, какой код выполнить при нажатии.
    // Повторная инициализация ИЗ ФОНОВОГО изолята перезаписывала эту ссылку
    // значением, посчитанным в другом изоляте, и нажатие «Отклонить»
    // переставало находить обработчик: система молча ничего не делала.
    // Ссылку ставит один раз основной изолят (PushService._init, из startSession) — здесь нужна
    // только возможность ПОКАЗАТЬ уведомление.
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await showIncomingCallNotification(
      plugin: plugin,
      callId: callId,
      chatId: chatId,
      callerName: (data['title'] as String?) ?? 'Glitch',
    );
    if (notice == IncomingNotice.first) {
      final silent = !await AppSounds.isOnStored(VoiceCue.ringtone);
      await GlitchRingtone.playIncoming(callId: callId, silent: silent);
    }
  } catch (_) {
  }
}

const _chatDismissType = 'chat_dismiss';

const _dismissChatIdKey = 'dismiss_chat_id';

String _chatTag(int chatId) => 'chat_$chatId';

/// Убрать уведомление чата из фонового изолята — своим экземпляром плагина
/// (тот, что в PushService, живёт в другой памяти).
Future<void> _cancelChatNotification(int chatId) async {
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await plugin.cancel(0, tag: _chatTag(chatId));
  } catch (_) {
  }
}

/// Убрать карточку вызова из фонового изолята — своим экземпляром плагина
/// уведомлений (тот, что в PushService, живёт в другой памяти).
Future<void> _cancelCallCard(int callId) async {
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await cancelIncomingCallNotification(plugin: plugin, callId: callId);
  } catch (_) {
  }
}

class PushService {
  final _fm = FirebaseMessaging.instance;
  bool _initialized = false;

  String? _lastToken;
  bool _tokenSynced = false;

  int? _launchAcceptedCallId;

  int? _launchDeclinedCallId;

  late FlutterLocalNotificationsPlugin _plugin;

  final _openStream = StreamController<PushTarget>.broadcast();
  Stream<PushTarget> get onOpen => _openStream.stream;

  final _callActionStream =
      StreamController<({String action, IncomingCallPayload payload})>.broadcast();
  Stream<({String action, IncomingCallPayload payload})> get onCallAction =>
      _callActionStream.stream;

  /// Показать полноэкранное уведомление о входящем звонке из ОСНОВНОГО изолята.
  Future<void> showIncomingCall({
    required int callId,
    required int chatId,
    required String callerName,
    String? callerAvatar,
  }) async {
    if (!_initialized) return;
    await showIncomingCallNotification(
      plugin: _plugin,
      callId: callId,
      chatId: chatId,
      callerName: callerName,
    );
  }

  Future<void> clearIncomingCall(int callId) async {
    if (!_initialized) return;
    await cancelIncomingCallNotification(plugin: _plugin, callId: callId);
  }

  /// Источников ДВА, и это не перестраховка:
  ///   1) launchDetails — приложение запущено самим нажатием кнопки «Принять».
  ///      Самый надёжный путь: значение уже лежит в системе к моменту старта.
  ///   2) SharedPreferences — «записка» от фонового изолята. Нужна там, где
  ///      launchDetails пуст (например, приложение подняли не тем же нажатием).
  /// Проверять только записку было бы гонкой: фоновый изолят пишет её примерно
  /// тогда же, когда система запускает приложение, и порядок не гарантирован.
  static Future<int?> consumePendingAcceptedCall() async {
    int? fromLaunch = pushService._launchAcceptedCallId;
    pushService._launchAcceptedCallId = null;

    int? fromPrefs;
    try {
      final prefs = await SharedPreferences.getInstance();
      fromPrefs = prefs.getInt(pendingCallAcceptKey);
      if (fromPrefs != null) await prefs.remove(pendingCallAcceptKey);
    } catch (_) {
    }
    return fromLaunch ?? fromPrefs;
  }

  /// Звонок, который отклонили кнопкой на уведомлении при закрытом приложении.
  /// Только из launchDetails: «Отклонить» теперь поднимает приложение, а не
  /// работает в фоне, поэтому «записка» на диске тут не нужна.
  static int? consumePendingDeclinedCall() {
    final id = pushService._launchDeclinedCallId;
    pushService._launchDeclinedCallId = null;
    return id;
  }

  void _dispatchTap(Map<String, dynamic> data) {
    final target = pushTargetFromData(data);
    if (target != null) _openStream.add(target);
  }

  Future<void> startSession() async {
    await _init();
    await resyncTokenIfNeeded();
  }

  void endSession() => _tokenSynced = false;

  Future<void> _init() async {
    if (_initialized) return;
    _initialized = true;
    PushTarget? launchTarget;

    // Локальные уведомления инициализируем ПЕРВЫМИ и отдельно от Firebase:
    // если Firebase-часть упадёт (нет Google-сервисов и т.п.), обработчики
    // тапов по уже показанным уведомлениям всё равно должны работать.
    _plugin = FlutterLocalNotificationsPlugin();
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (details) {
        // Кнопки звонка — отдельным путём, и обрабатываются они ИНАЧЕ, чем в
        // фоновом изоляте. Приложение живо, значит есть WebSocket и известное
        // состояние звонка: принять/отклонить нужно сразу и напрямую, а не
        // через записку на диске и HTTP-запрос, как это делается при закрытом
        // приложении. Сам разбор — в CallProvider, он слушает этот поток.
        if (details.actionId == callActionAccept || details.actionId == callActionDecline) {
          final payload = IncomingCallPayload.decode(details.payload);
          if (payload != null) {
            _callActionStream.add((action: details.actionId!, payload: payload));
          }
          return;
        }
        final target = pushTargetFromPayload(details.payload);
        if (target != null) _openStream.add(target);
      },
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationResponse,
    );
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_buildChannel());
    await androidPlugin?.createNotificationChannel(_buildCallsChannel());

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final response = launchDetails!.notificationResponse;
      if (response?.actionId == callActionAccept) {
        _launchAcceptedCallId = IncomingCallPayload.decode(response?.payload)?.callId;
        await GlitchRingtone.stop();
      } else if (response?.actionId == callActionDecline) {
        _launchDeclinedCallId = IncomingCallPayload.decode(response?.payload)?.callId;
        await GlitchRingtone.stop();
      } else {
        launchTarget = pushTargetFromPayload(response?.payload);
      }
    }

    try {
      await _fm.requestPermission(alert: true, badge: true, sound: true);
      _fm.onTokenRefresh.listen(_sendToken);

      final initialMsg = await _fm.getInitialMessage();
      if (initialMsg != null) launchTarget ??= pushTargetFromData(initialMsg.data);

      FirebaseMessaging.onMessageOpenedApp.listen((msg) => _dispatchTap(msg.data));

      // Foreground: система на Android в foreground уведомления сама не
      // показывает. Пуш сюда приходит только если WS-сокет порван (иначе
      // сервер этой сессии не шлёт вовсе) — сообщение в UI появится лишь
      // после реконнекта, так что показываем уведомление сами, в том же
      // формате (id=0 + tag), что и системные — открытие чата гасит одинаково.
      FirebaseMessaging.onMessage.listen((msg) => _handleForegroundPush(msg.data));

      final token = await _fm.getToken();
      if (token != null) await _sendToken(token);
    } catch (_) {
    }
    if (launchTarget != null) _openStream.add(launchTarget);
  }

  Future<void> _handleForegroundPush(Map<String, dynamic> data) async {
    final title = data['title'] as String? ?? 'Glitch';
    final body  = data['body']  as String? ?? '';
    final chatId = int.tryParse(data['chat_id'] ?? '') ?? 0;

    final callId = int.tryParse(data['call_id'] ?? '');

    if (data['type'] == _chatDismissType) {
      final dismissed = int.tryParse(data[_dismissChatIdKey] ?? '');
      if (dismissed != null) await clearNotification(dismissed);
      return;
    }

    if (data['call_event'] == 'ended') {
      final ours = callId == null || await GlitchRingtone.finishRinging(callId);
      if (ours && callId != null) await clearIncomingCall(callId);
      return;
    }

    if (data['call_event'] == 'incoming' &&
        callId != null &&
        await GlitchRingtone.claimIncoming(callId) != IncomingNotice.first) {
      return;
    }

    if (data['call_event'] != null && chatId > 0) {
      await _plugin.show(
        0, title, body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _callsChannelId, _callsChannelName,
            importance: Importance.max, playSound: true,
            tag: callId != null ? callNotificationTag(callId) : 'call_$chatId',
          ),
        ),
        payload: pushTargetPayload(ChatPushTarget(chatId)),
      );
      return;
    }

    if (chatId > 0) {
      await _plugin.show(
        0, title, body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId, _channelName,
            importance: Importance.max, playSound: true,
            tag: _chatTag(chatId),
          ),
        ),
        payload: pushTargetPayload(messagePushTarget(chatId, data['server_id']) ?? ChatPushTarget(chatId)),
      );
    } else if (pushTargetFromData(data) case final FriendsPushTarget friendsTarget) {
      await _plugin.show(
        0, title, body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId, _channelName,
            importance: Importance.max, playSound: true,
            tag: 'friend_${data['user_id']}',
          ),
        ),
        payload: pushTargetPayload(friendsTarget),
      );
    } else if (data['type'] == 'new_login') {
      await _plugin.show(
        _systemNewLoginId, title, body,
        const NotificationDetails(
          android: AndroidNotificationDetails(_channelId, _channelName,
              importance: Importance.max, playSound: true),
        ),
      );
    }
  }

  Future<void> clearNotification(int chatId) async {
    if (!_initialized) return;
    await _plugin.cancel(0, tag: _chatTag(chatId));
  }

  Future<void> _sendToken(String token) async {
    _lastToken = token;
    _tokenSynced = false;
    try {
      await api.updateFcmToken(token);
      _tokenSynced = true;
    } catch (_) {
    }
  }

  Future<void> resyncTokenIfNeeded() async {
    if (!_initialized) return;
    final token = _lastToken;
    if (token != null) {
      if (!_tokenSynced) await _sendToken(token);
      return;
    }
    try {
      final fresh = await _fm.getToken();
      if (fresh != null) await _sendToken(fresh);
    } catch (_) {}
  }
}

final pushService = PushService();
