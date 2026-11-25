import 'package:flutter/foundation.dart';
import '../models/achievement.dart';
import 'achievement_collection.dart';

class AchievementArrangement extends ChangeNotifier {
  final AchievementCollection collection;
  List<int>? _order;
  int? selectedId;
  AchievementArrangement(this.collection) {
    collection.addListener(_updated);
  }

  List<Achievement> get items {
    final owned = collection.items ?? const <Achievement>[];
    final byId = {for (final item in owned) item.id: item};
    return [
      for (final id in _order ?? const <int>[]) if (byId.containsKey(id)) byId.remove(id)!,
      ...byId.values,
    ];
  }

  bool get dirty => _order != null && !listEquals(
      items.map((e) => e.id).toList(), collection.items?.map((e) => e.id).toList());
  List<int>? get order => dirty ? items.map((e) => e.id).toList() : null;

  void select(int id) {
    if (!(collection.items?.any((item) => item.id == id) ?? false)) return;
    selectedId = selectedId == id ? null : id;
    notifyListeners();
  }

  void replace(int targetId, int sourceId) {
    final ids = items.map((e) => e.id).toList();
    final target = ids.indexOf(targetId), source = ids.indexOf(sourceId);
    if (target < 0 || source < 0) return;
    ids[target] = sourceId;
    ids[source] = targetId;
    _order = ids;
    selectedId = null;
    notifyListeners();
  }

  void reset() {
    _order = null;
    selectedId = null;
    notifyListeners();
  }

  void _updated() {
    if (!(collection.items?.any((item) => item.id == selectedId) ?? false)) selectedId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    collection.removeListener(_updated);
    super.dispose();
  }
}
