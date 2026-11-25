import 'package:shared_preferences/shared_preferences.dart';

class RecentEmojiService {
  static const _prefsKey = 'recent_emoji_v1';
  static const _maxItems = 24;

  List<String> _current = [];
  bool _loaded = false;

  List<String> get current => _current;

  Future<void> load() async {
    if (_loaded) return; // панель открывают часто, читать диск каждый раз незачем
    final prefs = await SharedPreferences.getInstance();
    _current = prefs.getStringList(_prefsKey) ?? [];
    _loaded = true;
  }

  Future<void> recordUsed(String emoji) async {
    final updated = [emoji, ..._current.where((e) => e != emoji)];
    if (updated.length > _maxItems) updated.removeRange(_maxItems, updated.length);
    _current = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _current);
  }
}

final recentEmoji = RecentEmojiService();
