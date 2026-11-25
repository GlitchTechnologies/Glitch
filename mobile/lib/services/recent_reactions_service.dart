import 'package:shared_preferences/shared_preferences.dart';

class RecentReactionsService {
  static const defaults = ['❤️', '👍', '👎', '🔥', '🤩', '👏', '😄'];
  static const _prefsKey = 'recent_reactions_v1';

  List<String> _current = defaults;

  List<String> get current => _current;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_prefsKey);
    if (saved != null && saved.length == defaults.length) _current = saved;
  }

  Future<void> recordUsed(String emoji) async {
    if (_current.contains(emoji)) return;
    _current = [emoji, ..._current.sublist(0, _current.length - 1)];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _current);
  }
}

final recentReactions = RecentReactionsService();
