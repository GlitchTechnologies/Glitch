import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/user_activities.dart';
import '../services/user_updates.dart';
import '../services/user_presences.dart';
import '../services/websocket_service.dart';

class ContactProvider extends ChangeNotifier {
  final String nickname;
  final int? existingChatId;

  final bool findChat;

  User? user;
  bool loading = true;
  bool isBlocked = false;
  bool isMutedInAdvance = false; // заглушено заранее, реального чата ещё нет

  int? chatId;

  bool chatMuted = false;

  bool get notificationsOn => chatId != null ? !chatMuted : !isMutedInAdvance;

  List<Message> mediaMessages = [];
  List<Message> fileMessages = [];
  bool mediaLoading = false;

  bool _disposed = false;

  final _errorCtrl = StreamController<String>.broadcast();
  Stream<String> get errors => _errorCtrl.stream;

  /// Единственный способ сообщить об ошибке наружу — см. одноимённый метод в
  /// ChatProvider, там же разобрана причина. Здесь все вызовы и так стоят
  /// после `if (_disposed) return;`, то есть до закрытого потока дело не
  /// доходит, — гвард добавлен ради ОДНОГО правила на все провайдеры: голый
  /// `_errorCtrl.add()` не должен встречаться нигде, иначе следующая копия
  /// снова окажется незащищённой.
  void _emitError(String message) {
    if (_errorCtrl.isClosed) return;
    _errorCtrl.add(message);
  }

  ContactProvider({required this.nickname, this.existingChatId, this.findChat = false})
      : chatId = existingChatId;

  StreamSubscription<int>? _userSub;
  StreamSubscription<int>? _presenceSub;
  int _loadSeq = 0;

  void init() {
    wsService.addReconnectListener(_onReconnect);
    _presenceSub = userPresences.changes.listen((id) {
      if (!_disposed && id == user?.id) _load(refreshChat: false);
    });
    _userSub = userUpdates.changes.listen((id) {
      if (!_disposed && id == user?.id) _load();
    });
    _load();
  }

  Future<void> reload() => _load();

  void _onReconnect() => unawaited(_load(refreshChat: false));

  @override
  void dispose() {
    _disposed = true;
    _userSub?.cancel();
    _presenceSub?.cancel();
    wsService.removeReconnectListener(_onReconnect);
    _errorCtrl.close();
    super.dispose();
  }

  Future<void> _load({bool refreshChat = true}) async {
    final seq = ++_loadSeq;
    final snapshot = userActivities.beginSnapshot();
    final presenceSnapshot = userPresences.beginSnapshot();
    try {
      final loaded = await api.getUser(nickname);
      if (_disposed || seq != _loadSeq) return;
      if (!userActivities.acceptsSnapshot(loaded.id, snapshot)) {
        unawaited(_load(refreshChat: refreshChat));
        return;
      }
      user = loaded;
      final blocked = userPresences.blockedFor(loaded.id, loaded.isBlocked || loaded.isBlockedBy);
      userPresences.seed(loaded.id, loaded.presenceStatus, snapshot: presenceSnapshot,
          lastSeen: loaded.lastSeen, blocked: blocked);
      if (!blocked) userActivities.seed(loaded.id, loaded.activities, snapshot: snapshot);
      isBlocked = loaded.isBlocked;
      isMutedInAdvance = loaded.isMutedInAdvance;
      loading = false;
      notifyListeners();
      if (refreshChat) await _loadChat();
    } catch (_) {
      if (_disposed || seq != _loadSeq) return;
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadChat() async {
    try {
      if (chatId == null && findChat) {
        final found = await api.findPersonalChat(nickname);
        if (_disposed || found == null) return;
        chatId = found.id;
        chatMuted = found.isMuted;
        notifyListeners();
      } else if (chatId != null) {
        final chat = await api.getChat(chatId!);
        if (_disposed) return;
        chatMuted = chat.isMuted;
        notifyListeners();
      }
    } catch (_) {
      if (_disposed) return;
    }
    if (chatId != null) await loadMedia();
  }

  Future<void> loadMedia() async {
    final id = chatId;
    if (id == null) return;
    mediaLoading = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        api.getMessages(id, limit: 200),
        api.getChatFiles(id),
      ]);
      if (_disposed) return;
      mediaMessages = (results[0] as List<Message>)
          .where((m) => m.type == 'photo' || m.type == 'video' || m.type == 'album')
          .toList()
          .reversed
          .toList();
      fileMessages = results[1] as List<Message>;
      mediaLoading = false;
      notifyListeners();
    } catch (_) {
      if (_disposed) return;
      mediaLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleBlock() async {
    if (user == null) return;
    try {
      if (isBlocked) {
        await api.unblockUser(user!.nickname);
        isBlocked = false;
      } else {
        await api.blockUser(user!.nickname);
        isBlocked = true;
      }
      if (_disposed) return;
      notifyListeners();
    } on ApiException catch (e) {
      if (_disposed) return;
      _emitError(e.message);
    }
  }

  Future<void> toggleNotifications() async {
    final id = chatId;
    if (id == null) return toggleMuteInAdvance();
    chatMuted = !chatMuted;
    notifyListeners();
    try {
      await api.patch('/chats/$id/notifications');
    } catch (e) {
      if (_disposed) return;
      chatMuted = !chatMuted;
      notifyListeners();
      _emitError(errorMessage(e));
    }
  }

  Future<void> toggleMuteInAdvance() async {
    if (user == null) return;
    final newVal = !isMutedInAdvance;
    isMutedInAdvance = newVal;
    notifyListeners();
    try {
      if (newVal) {
        await api.muteUserInAdvance(user!.nickname);
      } else {
        await api.unmuteUserInAdvance(user!.nickname);
      }
    } on ApiException catch (e) {
      if (_disposed) return;
      isMutedInAdvance = !newVal;
      notifyListeners();
      _emitError(e.message);
    }
  }
}
