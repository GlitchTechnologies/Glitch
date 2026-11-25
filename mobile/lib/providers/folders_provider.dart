import 'package:flutter/foundation.dart';
import '../models/chat.dart';
import '../models/folder.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';

class FoldersProvider extends ChangeNotifier {
  static const allFolderId = 0;

  List<ChatFolder> folders = [];
  List<ChatPin> pins = [];
  bool loading = true;

  bool _disposed = false;

  FoldersProvider() {
    final cached = cache.loadFolders();
    if (cached == null) return; // первый в жизни запуск — кэша нет, рывок неизбежен
    folders = cached.folders;
    pins = cached.pins;
    loading = false;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    try {
      final results = await Future.wait([api.getFolders(), api.getPins()]);
      if (_disposed) return;
      folders = results[0] as List<ChatFolder>;
      pins = results[1] as List<ChatPin>;
      await cache.saveFolders(folders, pins);
      if (_disposed) return;
    } catch (_) {
    }
    loading = false;
    _notify();
  }

  Future<ChatFolder> create(String name, List<int> chatIds) async {
    final folder = await api.createFolder(name, chatIds);
    await load();
    return folder;
  }

  Future<void> update(int folderId, {String? name, List<int>? chatIds}) async {
    await api.updateFolder(folderId, name: name, chatIds: chatIds);
    await load();
  }

  Future<void> remove(int folderId) async {
    await api.deleteFolder(folderId);
    await load();
  }

  /// Раньше в catch стоял load() — перечитать с сервера. Это молча оставляло
  /// на экране порядок, которого на сервере нет: load() свои сетевые ошибки
  /// намеренно глушит («оставляем то, что уже показано»), поэтому при обрыве
  /// связи он падал следом и ничего не откатывал. Человек видел новый порядок,
  /// уходил, а при следующем заходе получал прежний — без объяснений.
  /// Снимок корректен именно в самом частом случае отказа — когда сети нет.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final before = folders;

    final list = List<ChatFolder>.from(folders);
    if (newIndex > oldIndex) newIndex -= 1;
    list.insert(newIndex, list.removeAt(oldIndex));
    folders = list;
    _notify();
    try {
      final saved = await api.reorderFolders(list.map((f) => f.id).toList());
      if (_disposed) return;
      folders = saved;
      _notify();
    } catch (_) {
      if (_disposed) return;
      folders = before;
      _notify();
      rethrow;
    }
  }


  List<int> pinnedIn(int folderId) =>
      [for (final p in pins) if (p.folderId == folderId) p.chatId];

  bool isPinned(int folderId, int chatId) =>
      pins.any((p) => p.folderId == folderId && p.chatId == chatId);

  Future<void> setPins(int folderId, List<int> chatIds, bool pinned) async {
    final before = pins;

    final optimistic = List<ChatPin>.from(pins);
    if (!pinned) {
      final ids = chatIds.toSet();
      optimistic.removeWhere((p) => p.folderId == folderId && ids.contains(p.chatId));
    } else {
      final already = <int>{
        for (final p in optimistic) if (p.folderId == folderId) p.chatId,
      };
      // toSet() в Dart сохраняет порядок вставки — дубликаты во входе
      // схлопываются так же, как dict.fromkeys на сервере.
      final fresh = [for (final id in chatIds.toSet()) if (!already.contains(id)) id];
      optimistic.insertAll(0, [
        for (final id in fresh.reversed) ChatPin(folderId: folderId, chatId: id),
      ]);
    }
    pins = optimistic;
    _notify();

    try {
      final updated = await api.setPins(folderId, chatIds, pinned);
      if (_disposed) return;
      pins = updated;
      _notify();
    } catch (_) {
      if (_disposed) return;
      pins = before;
      _notify();
      rethrow;
    }
  }


  List<ChatListItem> _inFolder(List<ChatListItem> chats, ChatFolder? folder) {
    if (folder == null) return chats;
    // Set, а не List.contains: иначе на каждый чат шёл линейный поиск по
    // составу папки, и так на каждой отрисовке и для каждой вкладки сразу
    final ids = folder.chatIds.toSet();
    return chats.where((c) => ids.contains(c.id)).toList();
  }

  List<ChatListItem> apply(List<ChatListItem> chats, ChatFolder? folder) {
    final list = _inFolder(chats, folder);
    final order = pinnedIn(folder?.id ?? allFolderId);
    if (order.isEmpty) return list;

    final byId = {for (final c in list) c.id: c};
    final pinnedIds = order.toSet();
    return [
      for (final id in order) if (byId[id] != null) byId[id]!,
      ...list.where((c) => !pinnedIds.contains(c.id)),
    ];
  }

  int unreadCount(List<ChatListItem> chats, ChatFolder? folder) =>
      _inFolder(chats, folder).where((c) => c.unreadCount > 0).length;
}
