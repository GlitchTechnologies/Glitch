import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat.dart';
import '../models/folder.dart';
import '../models/message.dart';
import '../providers/composer_drafts.dart';

class CacheService {
  static const _chatsBox    = 'chats';
  static const _messagesBox = 'messages';

  late Box _chats;
  late Box _messages;

  Future<void> init() async {
    await Hive.initFlutter();
    _chats    = await Hive.openBox(_chatsBox);
    _messages = await Hive.openBox(_messagesBox);
  }


  static const _chatsListKey = 'list_v4';

  Future<void> saveChats(List<ChatListItem> chats) async {
    await _chats.put(_chatsListKey, jsonEncode([for (final c in chats) c.toJson()]));
  }

  List<ChatListItem>? loadChats() {
    final raw = _chats.get(_chatsListKey);
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List;
      return list.map((j) => ChatListItem.fromJson(j)).toList();
    } catch (_) {
      return null;
    }
  }


  static const _foldersKey = 'folders_v1';
  static const _pinsKey    = 'pins_v1';

  Future<void> saveFolders(List<ChatFolder> folders, List<ChatPin> pins) async {
    await _chats.put(_foldersKey, jsonEncode(folders.map((f) => f.toJson()).toList()));
    await _chats.put(_pinsKey, jsonEncode(pins.map((p) => p.toJson()).toList()));
  }

  ({List<ChatFolder> folders, List<ChatPin> pins})? loadFolders() {
    final rawFolders = _chats.get(_foldersKey);
    final rawPins = _chats.get(_pinsKey);
    if (rawFolders == null || rawPins == null) return null;
    try {
      final folders = (jsonDecode(rawFolders) as List)
          .map((j) => ChatFolder.fromJson(j as Map<String, dynamic>))
          .toList();
      final pins = (jsonDecode(rawPins) as List)
          .map((j) => ChatPin.fromJson(j as Map<String, dynamic>))
          .toList();
      return (folders: folders, pins: pins);
    } catch (_) {
      return null;
    }
  }


  static const _collapsedKey = 'collapsed_categories_v1';

  Set<int> loadCollapsedCategories() {
    final raw = _chats.get(_collapsedKey);
    if (raw == null) return <int>{};
    try {
      return (jsonDecode(raw) as List).whereType<int>().toSet();
    } catch (_) {
      return <int>{};
    }
  }

  Future<void> saveCollapsedCategories(Set<int> ids) =>
      _chats.put(_collapsedKey, jsonEncode(ids.toList()));


  static const _recentPlacesKey = 'recent_places_v1';

  List<String> loadRecentPlaces() {
    final raw = _chats.get(_recentPlacesKey);
    if (raw is! String) return const [];
    try {
      return (jsonDecode(raw) as List).whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveRecentPlaces(List<String> refs) =>
      _chats.put(_recentPlacesKey, jsonEncode(refs));


  static const _rosterHiddenKey = 'roster_panel_hidden_v1';

  bool loadRosterHidden() => _chats.get(_rosterHiddenKey) == 'true';

  Future<void> saveRosterHidden(bool hidden) =>
      _chats.put(_rosterHiddenKey, hidden ? 'true' : 'false');


  static const _dmProfileHiddenKey = 'dm_profile_panel_hidden_v1';

  bool loadDmProfileHidden() => _chats.get(_dmProfileHiddenKey) == 'true';

  Future<void> saveDmProfileHidden(bool hidden) =>
      _chats.put(_dmProfileHiddenKey, hidden ? 'true' : 'false');


  static const int cachedMessages = 100;

  Future<void> saveMessages(int chatId, List<Message> messages) async {
    final sent = messages.where((m) => m.status != 'sending' && m.status != 'failed').toList();
    final toSave = sent.length > cachedMessages ? sent.sublist(sent.length - cachedMessages) : sent;
    final data = [for (final m in toSave) m.toJson()];
    await _messages.put('chat_$chatId', jsonEncode(data));
  }

  List<Message>? loadMessages(int chatId) {
    final raw = _messages.get('chat_$chatId');
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List;
      return list.map((j) => Message.fromJson(j)).toList();
    } catch (_) {
      return null;
    }
  }

  // Сериализуем запись на один chatId — предотвращает race condition
  final Map<int, Future<void>> _appendLocks = {};

  Future<void> appendMessage(int chatId, Message msg) {
    final prev = _appendLocks[chatId] ?? Future.value();
    final next = prev.then((_) async {
      final existing = loadMessages(chatId) ?? [];
      if (existing.any((m) => m.id == msg.id)) return;
      existing.add(msg);
      await saveMessages(chatId, existing);
    });
    final guarded = next.catchError((_) {});
    _appendLocks[chatId] = guarded;
    guarded.whenComplete(() {
      if (_appendLocks[chatId] == guarded) _appendLocks.remove(chatId);
    });
    return next;
  }

  Future<void> removeMessage(int chatId, int messageId) {
    final prev = _appendLocks[chatId] ?? Future.value();
    final next = prev.then((_) async {
      final existing = loadMessages(chatId) ?? [];
      if (!existing.any((m) => m.id == messageId)) return;
      existing.removeWhere((m) => m.id == messageId);
      await saveMessages(chatId, existing);
    });
    final guarded = next.catchError((_) {});
    _appendLocks[chatId] = guarded;
    guarded.whenComplete(() {
      if (_appendLocks[chatId] == guarded) _appendLocks.remove(chatId);
    });
    return next;
  }

  Future<void> updateUnread(int chatId, int count) async {
    final chats = loadChats();
    if (chats == null) return;
    final idx = chats.indexWhere((c) => c.id == chatId);
    if (idx == -1) return;
    final updated = List<ChatListItem>.from(chats);
    updated[idx] = updated[idx].copyWith(unreadCount: count);
    await saveChats(updated);
  }

  /// Ключи кэша и черновиков — общие на всё приложение (список чатов лежит под
  /// одним ключом, сообщения и черновики — по chat_id), поэтому у другого
  /// аккаунта они не «свои отдельные», а ТЕ ЖЕ САМЫЕ: без этой чистки следующий
  /// вошедший на телефоне человек видел чужой список чатов, а при совпадении
  /// chat_id — и чужую переписку с черновиками.
  Future<void> clearAccountData() async {
    await _chats.clear();
    await _messages.clear();

    composerDrafts.clear();

    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (ComposerDrafts.savedPrefixes.any((prefix) => key.startsWith(prefix))) {
        await prefs.remove(key);
      }
    }
  }
}

final cache = CacheService();
