import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'room_unread.dart';
import 'server_notifications.dart';
import 'voice_channels.dart';
import '../core/adaptive_open.dart' show CatalogScope, ServerScope, catalogScope, serverIdOfScope;
import '../models/chat_arrival.dart';
import '../models/server.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import '../services/user_updates.dart';
import '../services/websocket_service.dart';
import '../services/tab_session_web.dart' if (dart.library.io) '../services/tab_session_native.dart';

/// ⚠️ Каналы здесь НЕ фильтруются. Сервер присылает только видимые — значит
/// решать, что показывать, клиенту нечем и не нужно. Появится фильтрация на
/// клиенте — это будет второй источник правды о правах, а настоящий всё равно
/// останется на сервере.
class ServerProvider extends ChangeNotifier {
  final int serverId;

  ServerDetail? server;
  bool loading = true;
  String? error;

  final Set<int> collapsed = cache.loadCollapsedCategories();

  bool _disposed = false;

  bool _started = false;

  late final StreamSubscription<ServerProfile> _profileSub;

  late final StreamSubscription<int> _rolesSub;

  late final StreamSubscription<ServerRoomEvent> _roomsSub;

  ServerProvider(this.serverId) {
    _profileSub = serverRail.profileChanges.listen(_onProfile);
    _rolesSub = serverRail.roleChanges.listen((id) {
      if (id == serverId) load();
    });
    _roomsSub = serverRail.roomEvents.listen((e) {
      if (e.serverId == serverId) load();
    });
    wsService.addReconnectListener(_onReconnect);
  }

  @override
  void dispose() {
    _disposed = true;
    _profileSub.cancel();
    _rolesSub.cancel();
    _roomsSub.cancel();
    wsService.removeReconnectListener(_onReconnect);
    super.dispose();
  }

  void _onReconnect() => load();

  void _onProfile(ServerProfile p) {
    final current = server;
    if (p.id != serverId || current == null) return;
    server = current.withProfile(p);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    error = null;
    if (_started) _notify();
    _started = true;
    final voiceAttempt = voiceChannels.beginSnapshot();
    final unreadAttempt = roomUnread.beginSnapshot();
    try {
      final loaded = await api.getServer(serverId);
      if (_disposed) return;
      server = loaded;
      voiceChannels.applySnapshot(serverId, loaded.voiceStates, voiceAttempt);
      roomUnread.applySnapshot(
          serverId, loaded.allRooms.map((r) => r.id), loaded.unreadRoomIds, loaded.mentionCounts, unreadAttempt);
    } catch (e) {
      if (_disposed) return;
      error = errorMessage(e);
    } finally {
      voiceChannels.dropSnapshot(voiceAttempt);
      roomUnread.dropSnapshot(unreadAttempt);
      loading = false;
      _notify();
    }
  }

  Future<String?> moveRoom(int roomId, {required int? categoryId, required int? afterId}) =>
      _move(
        (current) => current.withRoomMoved(roomId, categoryId: categoryId, afterId: afterId),
        () => api.moveServerRoom(serverId, roomId, categoryId: categoryId, afterId: afterId),
      );

  Future<String?> moveCategory(int categoryId, {required int? afterId}) => _move(
        (current) => current.withCategoryMoved(categoryId, afterId: afterId),
        () => api.moveServerCategory(serverId, categoryId, afterId: afterId),
      );

  Future<String?> _move(
    ServerDetail Function(ServerDetail) local,
    Future<ServerDetail> Function() request,
  ) async {
    final current = server;
    if (current == null) return null;
    server = local(current);
    _notify();
    try {
      final fresh = await request();
      if (_disposed) return null;
      server = fresh;
      _notify();
      return null;
    } catch (e) {
      if (_disposed) return null;
      load();
      return errorMessage(e);
    }
  }

  void toggleCategory(int categoryId) {
    if (!collapsed.remove(categoryId)) collapsed.add(categoryId);
    _saveCollapsed();
  }

  void collapseAll() {
    collapsed.addAll([for (final c in server?.categories ?? const <RoomCategory>[]) c.id]);
    _saveCollapsed();
  }

  bool get allCollapsed =>
      (server?.categories ?? const <RoomCategory>[]).every((c) => collapsed.contains(c.id));

  void _saveCollapsed() {
    _notify();
    cache.saveCollapsedCategories(collapsed).catchError((_) {});
  }

  bool isCollapsed(int categoryId) => collapsed.contains(categoryId);

  Room? get firstTextRoom {
    for (final r in server?.allRooms ?? const <Room>[]) {
      if (r.kind == RoomKind.text) return r;
    }
    return null;
  }
}

/// Живёт ОДНИМ глобальным экземпляром [serverRail], как `shellController`:
/// рейл виден одновременно с содержимым левой колонки, и оба должны смотреть
/// на одно и то же состояние. Своих копий не заводить.
class ServersProvider extends ChangeNotifier {
  ServersProvider() {
    _restore();
  }

  List<ServerListItem> servers = [];

  Object? space;

  int? get selectedId => serverIdOfScope(space);

  bool get onCatalog => space is CatalogScope;

  final Map<int, int> _lastRoom = {};

  int? lastRoomOf(int serverId) => _lastRoom[serverId];

  void rememberRoom(int serverId, int roomId) {
    if (_lastRoom[serverId] == roomId) return;
    _lastRoom[serverId] = roomId;
    _persist();
  }


  static const _sessionKey = 'glitch_rail_v1';

  void _restore() {
    final raw = readTabSession(_sessionKey);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return;
      final rooms = j['rooms'];
      if (rooms is Map<String, dynamic>) {
        rooms.forEach((server, room) {
          final id = int.tryParse(server);
          if (id != null && room is int) _lastRoom[id] = room;
        });
      }
    } catch (_) {
      removeTabSession(_sessionKey);
    }
  }

  void _persist() {
    writeTabSession(_sessionKey, jsonEncode({
      'rooms': {for (final e in _lastRoom.entries) '${e.key}': e.value},
    }));
  }
  bool loading = true;
  String? error;

  bool _disposed = false;
  bool _started = false;

  final StreamController<ServerProfile> _profileCtrl = StreamController.broadcast();
  Stream<ServerProfile> get profileChanges => _profileCtrl.stream;

  final StreamController<MemberDisplayChange> _displayCtrl = StreamController.broadcast();
  Stream<MemberDisplayChange> get memberDisplay => _displayCtrl.stream;

  void _display({int? serverId, int? userId}) {
    if (!_displayCtrl.isClosed) {
      _displayCtrl.add(MemberDisplayChange(serverId: serverId, userId: userId));
    }
  }

  StreamSubscription<PersonLook>? _lookSub;

  final StreamController<int> _rolesCtrl = StreamController.broadcast();
  Stream<int> get roleChanges => _rolesCtrl.stream;

  final StreamController<ServerRoomEvent> _roomCtrl = StreamController.broadcast();
  Stream<ServerRoomEvent> get roomEvents => _roomCtrl.stream;

  final StreamController<ServerGone> _goneCtrl = StreamController.broadcast();
  Stream<ServerGone> get serverGone => _goneCtrl.stream;

  @override
  void dispose() {
    _disposed = true;
    _profileCtrl.close();
    _displayCtrl.close();
    _lookSub?.cancel();
    _rolesCtrl.close();
    _roomCtrl.close();
    _goneCtrl.close();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Идемпотентна (remove перед add) — лишней копии слушателя не будет.
  /// Слушатель переподключения disconnect() не чистит, поэтому и он снимается
  /// перед повторной постановкой.
  void attach() {
    wsService.removeListener(_onWsEvent);
    wsService.addListener(_onWsEvent);
    wsService.removeReconnectListener(_onReconnect);
    wsService.addReconnectListener(_onReconnect);
    _lookSub?.cancel();
    _lookSub = userUpdates.looks.listen((p) {
      final serverId = p.serverId;
      if (serverId != null) _display(serverId: serverId, userId: p.userId);
    });
  }

  void _onWsEvent(Map<String, dynamic> event) {
    final type = event['type'];
    if (type == 'server.updated') {
      final raw = event['server'];
      if (raw is! Map<String, dynamic> || raw['id'] is! int) return;
      applyProfile(ServerProfile.fromJson(raw));
    } else if (type == 'server.roles.changed') {
      final serverId = event['server_id'];
      if (serverId is! int) return;
      if (!_rolesCtrl.isClosed) _rolesCtrl.add(serverId);
      _display(serverId: serverId);
    } else if (type == 'server.permissions.changed' || type == 'server.layout.changed') {
      // Расклад (с 2026-10-01): канал или категорию создали или перетащили.
      // Данных в событии нет — колонка перезапрашивает сообщество и получает
      // только видимые мне каналы. Поток тот же: его же слушают настройки
      // канала и раздел «Права доступа», где видны категория канала и
      // отметка «синхронизирован» — после переноса они тоже меняются.
      final serverId = event['server_id'];
      if (serverId is! int) return;
      if (!_rolesCtrl.isClosed) _rolesCtrl.add(serverId);
    } else if (type == 'server.member.roles.changed') {
      final serverId = event['server_id'];
      if (serverId is! int) return;
      final raw = event['user_id'];
      final me = authService.currentUser?.id;
      final userId = raw is int ? raw : me;
      if (userId == me && !_rolesCtrl.isClosed) _rolesCtrl.add(serverId);
      _display(serverId: serverId, userId: userId);
    } else if (type == 'server.room.updated' || type == 'server.room.deleted') {
      final serverId = event['server_id'];
      if (serverId is! int) return;
      final deleted = type == 'server.room.deleted';
      final raw = deleted ? null : event['room'];
      final chatId = deleted ? event['chat_id'] : (raw is Map ? raw['id'] : null);
      if (chatId is! int) return;
      if (!_roomCtrl.isClosed) {
        _roomCtrl.add(ServerRoomEvent(
          serverId: serverId,
          chatId: chatId,
          deleted: deleted,
          name: raw is Map ? raw['name'] as String? : null,
          description: raw is Map ? raw['description'] as String? : null,
          userLimit: raw is Map ? (raw['user_limit'] as num?)?.toInt() : null,
        ));
      }
    } else if (type == 'server.category.updated' || type == 'server.category.deleted') {
      final serverId = event['server_id'];
      if (serverId is! int) return;
      final deleted = type == 'server.category.deleted';
      final raw = deleted ? null : event['category'];
      final chatId = deleted ? event['chat_id'] : (raw is Map ? raw['id'] : null);
      if (chatId is! int) return;
      if (!_roomCtrl.isClosed) {
        _roomCtrl.add(ServerRoomEvent(
          serverId: serverId,
          chatId: chatId,
          deleted: deleted,
          name: raw is Map ? raw['name'] as String? : null,
          description: null,
        ));
      }
    } else if (type == 'server.deleted') {
      final serverId = event['server_id'];
      if (serverId is int) forget(serverId, ServerGoneReason.deleted);
    } else if (type == 'server.member.removed' || type == 'server.member.joined') {
      final serverId = event['server_id'];
      final userId = event['user_id'];
      if (serverId is! int || userId is! int) return;
      final joined = type == 'server.member.joined';
      if (userId == authService.currentUser?.id) {
        if (!joined) {
          forget(serverId, ServerGoneReason.fromWire(event['reason']));
        } else if (!servers.any((s) => s.id == serverId)) {
          load();
        }
      }
      _display(serverId: serverId, userId: userId);
    }
  }

  /// Зовётся по событию об уходе (кик, бан, «покинуть» с любого устройства)
  /// и сразу после своего «Покинуть сообщество» (`core/server_leave.dart`);
  /// по событию об удалении сообщества и сразу после своего удаления
  /// (`confirmDeleteServer`). Других путей нет — иначе у каждого была бы
  /// своя, неполная уборка (канал останется открытым, окно настроек —
  /// висеть над пустотой). Повторный вызов безвреден: сообщества в рейле
  /// уже нет, имя пустое — рейл промолчит.
  void forget(int serverId, ServerGoneReason reason) {
    final i = servers.indexWhere((s) => s.id == serverId);
    final name = i >= 0 ? servers[i].name : '';
    if (i >= 0) servers = [...servers]..removeAt(i);
    forgetIfGone();
    roomUnread.forgetServer(serverId);
    serverNotifications.forgetServer(serverId);
    _notify();
    if (!_goneCtrl.isClosed) _goneCtrl.add(ServerGone(id: serverId, name: name, reason: reason));
    if (viewAs?.serverId == serverId) stopViewAs();
  }

  void _onReconnect() {
    load();
    _display();
  }

  void applyProfile(ServerProfile p) {
    final i = servers.indexWhere((s) => s.id == p.id);
    if (i >= 0) {
      servers = [...servers]..[i] = servers[i].withProfile(p);
      _notify();
    }
    if (!_profileCtrl.isClosed) _profileCtrl.add(p);
  }

  Future<void> load() async {
    loading = true;
    error = null;
    if (_started) _notify();
    _started = true;
    final mentionsAttempt = roomUnread.beginSnapshot();
    final notificationsAttempt = serverNotifications.beginSnapshot();
    final voiceAttempt = voiceChannels.beginSnapshot();
    try {
      final loaded = await api.getServers();
      if (_disposed) return;
      servers = loaded;
      roomUnread.applyServerTotals(
        {for (final item in loaded) item.id: item.mentionCount},
        {for (final item in loaded) if (item.hasUnread) item.id},
        mentionsAttempt,
      );
      serverNotifications.applySnapshot(
          {for (final item in loaded) item.id: item.notifications}, notificationsAttempt);
      voiceChannels.applySnapshots({
        for (final item in loaded)
          if (item.voiceStates != null) item.id: item.voiceStates!,
      }, voiceAttempt);
      forgetIfGone();
    } catch (e) {
      if (_disposed) return;
      error = errorMessage(e);
    } finally {
      roomUnread.dropSnapshot(mentionsAttempt);
      serverNotifications.dropSnapshot(notificationsAttempt);
      voiceChannels.dropSnapshot(voiceAttempt);
      loading = false;
      _notify();
    }
  }

  void select(int? id) => selectSpace(id == null ? null : ServerScope(id));

  void selectSpace(Object? next) {
    if (space == next) return;
    space = next;
    _notify();
  }

  RoomRequest? _roomRequest;

  void openRoom(int serverId, int roomId, {int? messageId, bool chosen = false, ChatArrival? arrival}) {
    _roomRequest = RoomRequest(serverId, roomId, messageId, chosen: chosen, arrival: arrival);
    if (!chosen) rememberRoom(serverId, roomId);
    space = ServerScope(serverId);
    _notify();
  }

  bool get hasRoomRequest => _roomRequest != null;

  RoomRequest? takeRoomRequest(int serverId) {
    final r = _roomRequest;
    if (r == null || r.serverId != serverId) return null;
    _roomRequest = null;
    return r;
  }

  void forgetIfGone() {
    if (selectedId == null) return;
    if (servers.any((s) => s.id == selectedId)) return;
    space = null;
  }

  void reset() {
    servers = [];
    space = null;
    _roomRequest = null;
    _lastRoom.clear();
    viewAs = null;
    api.viewAs = null;
    removeTabSession(_sessionKey);
    error = null;
    loading = true;
    _started = false;
    _notify();
  }

  // Единственное место, где режим включается, меняется и выключается: здесь же
  // ставится пометка для запросов (`api.viewAs`). Сами права в режиме считает
  // сервер (тот же расчёт, только с выбранными ролями) — клиент ничего не
  // «изображает», он лишь перечитывает всё, что зависит от прав, тем же
  // потоком [roleChanges], что и при правке ролей. Режим живёт, пока открыто
  // приложение (не хранится), и сбрасывается при выходе из аккаунта.

  ViewAsRoles? viewAs;

  void startViewAs(int serverId, List<ServerRole> roles, Set<int> selected) {
    viewAs = ViewAsRoles(
      serverId: serverId,
      roles: [for (final r in roles) if (!r.isDefault) r],
      selected: selected,
    );
    _applyViewAs();
  }

  void setViewAsRoles(Set<int> selected) {
    final v = viewAs;
    if (v == null) return;
    viewAs = ViewAsRoles(serverId: v.serverId, roles: v.roles, selected: selected);
    _applyViewAs();
  }

  void stopViewAs() {
    final v = viewAs;
    if (v == null) return;
    viewAs = null;
    api.viewAs = null;
    _notify();
    if (!_rolesCtrl.isClosed) _rolesCtrl.add(v.serverId);
  }

  void _applyViewAs() {
    final v = viewAs!;
    final roles = v.selected.toList()..sort();
    api.viewAs = '${v.serverId}:${roles.join(',')}';
    _notify();
    if (!_rolesCtrl.isClosed) _rolesCtrl.add(v.serverId);
  }

  void addCreated(ServerDetail created) {
    servers = [
      ...servers,
      ServerListItem(
        id: created.id,
        name: created.name,
        avatar: created.avatar,
        avatarSizes: created.avatarSizes,
        avatarColor: created.avatarColor,
        isOwner: created.isOwner,
      ),
    ];
    _notify();
  }
}


class ViewAsRoles {
  final int serverId;

  final List<ServerRole> roles;

  final Set<int> selected;

  const ViewAsRoles({required this.serverId, required this.roles, required this.selected});
}

class RoomRequest {
  final int serverId;
  final int roomId;

  final int? messageId;

  final bool chosen;

  final ChatArrival? arrival;

  const RoomRequest(this.serverId, this.roomId, this.messageId, {this.chosen = false, this.arrival});
}

final serverRail = ServersProvider();
