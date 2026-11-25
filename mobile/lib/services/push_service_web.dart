import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/l10n.dart';
import '../models/incoming_call_payload.dart';
import '../providers/locale_provider.dart';
import '../core/avatar_sizes.dart';
import 'chat_viewing.dart';
import 'desktop_shell.dart';
import 'notification_icon.dart';
import 'push_target.dart';
import 'websocket_service.dart';

/// ВКЛАДКА БРАУЗЕРА. На телефоне пуши решают ровно одну задачу: доставить
/// событие, когда приложение ЗАКРЫТО или свёрнуто (Firebase, системные
/// уведомления, фоновый изолят). Во вкладке, пока она открыта, событие
/// приходит по живому сокету, и приложение реагирует напрямую — входящий
/// звонок сразу открывает своё окно, сообщение появляется в переписке. Когда
/// вкладка закрыта, страницы нет, и доставлять некуда. Поэтому во вкладке
/// всё ниже ничего не делает — это не недоделка, а устройство браузера.
/// Для уведомлений при закрытой вкладке нужен service worker.
class PushService {
  final _openStream = StreamController<PushTarget>.broadcast();
  Stream<PushTarget> get onOpen => _openStream.stream;

  final _targets = <String, PushTarget>{};

  final _callActionStream =
      StreamController<({String action, IncomingCallPayload payload})>.broadcast();
  Stream<({String action, IncomingCallPayload payload})> get onCallAction =>
      _callActionStream.stream;

  StreamSubscription<DesktopNotificationClick>? _clickSub;

  Future<void> startSession() async {
    final shell = desktopShell;
    if (shell == null) return;
    wsService.removeListener(_onWsEvent);
    wsService.addListener(_onWsEvent);
    await _clickSub?.cancel();
    _clickSub = shell.notificationClicks.listen(_onClick);
  }

  void _onClick(DesktopNotificationClick click) {
    final tag = click.tag;
    final chatId = click.chatId;
    final target = (tag != null ? _targets[tag] : null) ?? (chatId != null ? ChatPushTarget(chatId) : null);
    if (target != null) _openStream.add(target);
  }

  void endSession() {
    final shell = desktopShell;
    if (shell == null) return;
    _session++;
    wsService.removeListener(_onWsEvent);
    unawaited(_clickSub?.cancel());
    _clickSub = null;
    _targets.clear();
    shell.clearNotifications();
  }

  Future<void> resyncTokenIfNeeded() async {}

  Future<void> showIncomingCall({
    required int callId,
    required int chatId,
    required String callerName,
    String? callerAvatar,
  }) async {
    final shell = desktopShell;
    if (shell == null) return;
    shell.requestAttention();
    final s = await _strings();
    await _show(
      tag: _callTag(callId),
      title: callerName,
      body: s.callIncoming,
      target: ChatPushTarget(chatId),
      avatar: callerAvatar,
    );
  }

  Future<void> clearIncomingCall(int callId) async => _close(_callTag(callId));

  Future<void> clearNotification(int chatId) async => _close(_chatTag(chatId));

  static Future<int?> consumePendingAcceptedCall() async => null;

  static int? consumePendingDeclinedCall() => null;


  static String _chatTag(int chatId) => 'chat_$chatId';
  static String _callTag(int callId) => 'call_$callId';
  static String _friendTag(int userId) => 'friend_$userId';

  void _onWsEvent(Map<String, dynamic> event) {
    if (event['type'] == 'notification.friend') {
      unawaited(_showFriend(event));
      return;
    }
    if (event['type'] != 'notification.message') return;
    final shell = desktopShell;
    final chatId = (event['chat_id'] as num?)?.toInt();
    final title = event['title'];
    final body = event['body'];
    final target = messagePushTarget(chatId, event['server_id']);
    if (shell == null || chatId == null || target == null || title is! String || body is! String) return;
    if (chatViewing.isWatching(chatId)) return;
    unawaited(_show(
      tag: _chatTag(chatId),
      title: title,
      body: body,
      target: target,
      avatar: event['sender_avatar'] as String?,
      avatarSizes: parseAvatarSizes(event['sender_avatar_sizes']),
    ));
  }

  final _generation = <String, int>{};
  int _session = 0;

  int _bump(String tag) => _generation[tag] = (_generation[tag] ?? 0) + 1;

  Future<void> _show({
    required String tag,
    required String title,
    required String body,
    required PushTarget target,
    String? avatar,
    Map<String, String>? avatarSizes,
  }) async {
    final shell = desktopShell;
    if (shell == null) return;
    final gen = _bump(tag);
    final session = _session;
    final icon = await notificationIcon(avatar: avatar, avatarSizes: avatarSizes);
    if (_generation[tag] != gen || _session != session) return;
    _targets[tag] = target;
    shell.showNotification(
      tag: tag,
      title: title,
      body: body,
      chatId: target is ChatPushTarget ? target.chatId : null,
      icon: icon,
    );
  }

  Future<void> _showFriend(Map<String, dynamic> event) async {
    final shell = desktopShell;
    final user = event['user'];
    final kind = event['kind'];
    if (shell == null || !shell.hasTaggedNotifications || user is! Map<String, dynamic>) return;
    final userId = user['id'];
    final name = user['display_name'];
    if (userId is! int || name is! String) return;
    final request = kind == friendRequestPushType;
    if (!request && kind != friendAcceptPushType) return;
    final s = await _strings();
    await _show(
      tag: _friendTag(userId),
      title: name,
      body: request ? s.notifFriendRequest : s.notifFriendAccepted,
      target: FriendsPushTarget(pending: request),
      avatar: user['avatar'] as String?,
      avatarSizes: parseAvatarSizes(user['avatar_sizes']),
    );
  }

  void _close(String tag) {
    _bump(tag);
    _targets.remove(tag);
    desktopShell?.closeNotification(tag);
  }

  Future<S> _strings() async {
    try {
      return await S.delegate.load(localeProvider.locale);
    } catch (_) {
      return await S.delegate.load(const Locale('ru'));
    }
  }
}

final pushService = PushService();
