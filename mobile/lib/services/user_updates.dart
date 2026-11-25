import 'dart:async';

import '../models/message.dart' show AuthorLook;
import '../models/server.dart' show ServerUser;
import 'auth_service.dart';
import 'websocket_service.dart';

class PersonLook {
  final int userId;
  final int? serverId;

  final ServerUser? person;

  const PersonLook({required this.userId, this.serverId, this.person});

  AuthorLook? get look {
    final u = person;
    if (u == null) return null;
    return (
      displayName: u.displayName,
      avatar: u.avatar,
      avatarSizes: u.avatarSizes,
      avatarDecoration: u.avatarDecoration,
    );
  }
}

ServerUser? _personFrom(dynamic raw) {
  if (raw is! Map<String, dynamic> || raw['id'] is! int) return null;
  return ServerUser.fromJson(raw);
}

/// Голосовые каналы событие не слушают: им сервер присылает обычный
/// `voice.state` с новой карточкой, а плиткам — медиасервер.
class UserUpdates {
  final _ctrl = StreamController<int>.broadcast();
  final _lookCtrl = StreamController<PersonLook>.broadcast();

  Stream<int> get changes => _ctrl.stream;

  Stream<PersonLook> get looks => _lookCtrl.stream;

  /// Подписаться на сокет. Идемпотентно (remove перед add).
  void attach() {
    wsService.removeListener(_onWsEvent);
    wsService.addListener(_onWsEvent);
  }

  void _onWsEvent(Map<String, dynamic> event) {
    final type = event['type'];
    final userId = event['user_id'];
    if (userId is! int) return;
    if (type == 'user.updated') {
      if (userId == authService.currentUser?.id) authService.refreshCurrentUser();
      _ctrl.add(userId);
      _lookCtrl.add(PersonLook(userId: userId, person: _personFrom(event['brief'])));
    } else if (type == 'server.member.updated') {
      final serverId = event['server_id'];
      if (serverId is! int) return;
      _lookCtrl.add(PersonLook(userId: userId, serverId: serverId, person: _personFrom(event['user'])));
    }
  }
}

final userUpdates = UserUpdates();
