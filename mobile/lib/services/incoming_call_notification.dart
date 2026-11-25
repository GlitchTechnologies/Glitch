export '../models/incoming_call_payload.dart';
export '../core/call_constants.dart';
import '../core/call_constants.dart';
import '../models/incoming_call_payload.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/l10n.dart';

/// ПОЧЕМУ ЭТО ОТДЕЛЬНЫЙ ФАЙЛ, А НЕ ЧАСТЬ push_service: показывать это
/// уведомление приходится из ДВУХ РАЗНЫХ ИЗОЛЯТОВ — обычного (приложение
/// живо, звонок пришёл по WebSocket) и фонового (приложение закрыто, Android
/// разбудил короткий код без интерфейса). У них не общая память и разные
/// экземпляры плагина уведомлений, поэтому весь код собран здесь и принимает
/// плагин параметром.


/// Через диск, а не через память, потому что «Принять» обрабатывается в
/// фоновом изоляте, а поднимает разговор потом основной — у них нет общей
/// памяти, и передать значение напрямую нельзя. Основной изолят читает ключ
/// при запуске и сам принимает звонок, когда сервер пришлёт его по WebSocket
/// (call_service.resend_incoming_to_session досылает входящий подключившемуся
/// устройству). Прочитав — обязательно стирает, иначе следующий запуск
/// приложения попытается «принять» давно завершённый звонок.
const String pendingCallAcceptKey = 'pending_call_accept';

const int callNotificationId = 0;

String callNotificationTag(int callId) => 'call_$callId';

/// Локализация для фонового изолята.
Future<S> loadLocalizations() async {
  String code = 'ru';
  try {
    final prefs = await SharedPreferences.getInstance();
    code = prefs.getString('locale') ?? 'ru';
  } catch (_) {
  }
  try {
    return await S.delegate.load(Locale(code));
  } catch (_) {
    return await S.delegate.load(const Locale('ru'));
  }
}

/// Настройки канала уведомлений о звонках — те же, что заводит push_service.
/// Канал уже создан основным изолятом при запуске приложения; здесь он нужен
/// лишь как ссылка по id.
const String callsChannelId = 'glitch_calls';
const String callsChannelName = 'Звонки Glitch';

/// [plugin] передаёт вызывающий: основной изолят — свой уже
/// проинициализированный экземпляр, фоновый — созданный на месте.
Future<void> showIncomingCallNotification({
  required FlutterLocalNotificationsPlugin plugin,
  required int callId,
  required int chatId,
  required String callerName,
}) async {
  final s = await loadLocalizations();

  final details = AndroidNotificationDetails(
    callsChannelId,
    callsChannelName,
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.call,
    fullScreenIntent: true,
    audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
    playSound: true,
    enableVibration: true,
    ongoing: true,
    autoCancel: false,
    visibility: NotificationVisibility.public,
    tag: callNotificationTag(callId),
    timeoutAfter: 60000,
    actions: <AndroidNotificationAction>[
      // Поэтому берём механизм, который на этом же телефоне работает надёжно —
      // тот же, что у кнопки «Принять»: система поднимает приложение, а оно
      // отклоняет звонок по уже живому WebSocket. Цена — приложение на миг
      // появляется на экране. Это честный размен: работающая кнопка важнее
      // незаметности, а вернуть приложение в фон можно будет отдельно, добавив
      // немного нативного кода.
      AndroidNotificationAction(
        callActionDecline,
        s.callDecline,
        showsUserInterface: true,
        cancelNotification: true,
      ),
      AndroidNotificationAction(
        callActionAccept,
        s.callAccept,
        showsUserInterface: true,
        cancelNotification: true,
      ),
    ],
  );

  await plugin.show(
    callNotificationId,
    callerName,
    s.callIncoming,
    NotificationDetails(android: details),
    payload: IncomingCallPayload(callId: callId, chatId: chatId).encode(),
  );
}

Future<void> cancelIncomingCallNotification({
  required FlutterLocalNotificationsPlugin plugin,
  required int callId,
}) async {
  try {
    await plugin.cancel(callNotificationId, tag: callNotificationTag(callId));
  } catch (_) {
  }
}
