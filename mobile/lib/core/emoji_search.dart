import 'emoji_data.dart';
import 'emoji_keywords.dart';
import 'text_match.dart';

/// ПОИСК ЭМОДЗИ — одно место (2026-10-16, вкладка «Эмодзи» окна выбора, как
/// у Discord). Ищет по названию и ключевым словам Unicode
/// (core/emoji_keywords.dart, собирает tool/emoji_keywords_build.py) на языке
/// приложения и вдобавок по-английски: люди часто набирают английское
/// название по привычке.
///
/// `matchRank` ставит точное слово выше начала слова и совпадения внутри.
/// При равных результатах сохраняется исходный порядок.
/// Одно уточнение для эмодзи: «ё» в запросе читается как «е» — в словаре
/// Unicode русские слова записаны через «е» («пес», «еж»).
List<String> searchEmoji(String query, String lang) {
  final q = query.replaceAll('ё', 'е').replaceAll('Ё', 'Е');
  if (normalizeTextQuery(q).isEmpty) return const [];
  final local = _wordsOf(lang);
  final english = lang == 'en' ? null : _wordsOf('en');
  final found = <({String emoji, int rank, int order})>[];
  var order = 0;
  for (final emoji in _allEmoji) {
    final words = [...?local?[emoji], ...?english?[emoji]];
    final rank = matchRank(q, words);
    if (rank != null) found.add((emoji: emoji, rank: rank, order: order));
    order++;
  }
  found.sort((a, b) => a.rank != b.rank ? a.rank - b.rank : a.order - b.order);
  return [for (final f in found) f.emoji];
}

final List<String> _allEmoji = () {
  final seen = <String>{};
  return [
    for (final cat in emojiCategories)
      for (final e in cat.emojis)
        if (seen.add(e)) e,
  ];
}();

final Map<String, Map<String, List<String>>> _parsed = {};

Map<String, List<String>>? _wordsOf(String lang) {
  final cached = _parsed[lang];
  if (cached != null) return cached;
  final raw = emojiKeywordsFor(lang);
  if (raw == null) return null;
  return _parsed[lang] = {for (final e in raw.entries) e.key: e.value.split('|')};
}
