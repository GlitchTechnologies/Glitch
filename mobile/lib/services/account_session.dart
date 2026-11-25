import 'dart:async';
import 'message_audio.dart';

import 'package:flutter/widgets.dart';

import '../core/shell_controller.dart' show shellController;
import '../providers/call_provider.dart';
import '../providers/friends.dart';
import '../providers/room_unread.dart';
import '../providers/server_notifications.dart';
import '../providers/server_provider.dart' show serverRail;
import '../providers/voice_channels.dart';
import 'auth_service.dart';
import 'desktop_window.dart';
import 'error_reporter.dart';
import 'game_activity.dart';
import 'keybind_commands.dart';
import 'message_cue.dart';
import 'notification_dismissal.dart';
import 'push_service.dart';
import 'stream_preview.dart';
import 'unread_summary.dart';
import 'user_activities.dart';
import 'user_presences.dart';
import 'user_updates.dart';
import 'voice_connection.dart';
import 'voice_resume.dart';
import 'websocket_service.dart';
import 'upload_limits.dart';

class AccountSession {
  bool _active = false;

  /// Начать сессию. Повторный вызов в той же сессии ничего не делает.
  void start() {
    if (_active) return;
    final token = authService.token;
    if (token == null) return;
    _active = true;
    messageAudio.attach();

    // Сначала подписки, потом сокет — ни одно событие первого подключения
    // не уйдёт в пустоту. Каждая подписка идемпотентна (remove перед add).
    callProvider.attach();
    serverRail.attach();
    voiceChannels.attach();
    voiceConnection.attach();
    streamPreviewUploader.attach();
    userUpdates.attach();
    userActivities.attach();
    userPresences.attach();
    notificationDismissal.attach();
    messageCue.attach();
    roomUnread.attach();
    serverNotifications.attach();
    friends.attach();
    unreadSummary.attach();
    desktopWindow.startSession();
    keybindCommands.startSession();
    gameActivity.startSession();
    wsService.connect(token);
    unawaited(uploadLimits.load());
    unawaited(pushService.startSession().catchError((Object e, StackTrace s) {
      errorReporter.report(e, stack: s, screen: 'push:startSession');
    }));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_active) unawaited(voiceResume.resumeOnStart());
    });
  }

  /// Закончить сессию: аккаунт покинут. Зовётся ДО ухода на экран входа.
  /// Идемпотентно: при добровольном выходе сокет уже закрыт внутри
  /// `AuthService.logout()`, повторное закрытие ничего не ломает.
  Future<void> end() async {
    _active = false;
    await messageAudio.reset();
    pushService.endSession();
    desktopWindow.endSession();
    keybindCommands.endSession();
    gameActivity.endSession();
    userActivities.reset();
    userPresences.reset();
    unreadSummary.detach();
    await wsService.disconnect();
    shellController.reset();
    serverRail.reset();
    uploadLimits.reset();
    roomUnread.reset();
    serverNotifications.reset();
    friends.reset();
    unawaited(voiceChannels.reset().then((_) => voiceConnection.reset()));
  }
}

final accountSession = AccountSession();
