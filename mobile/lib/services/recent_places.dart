import '../models/search.dart';
import 'api_service.dart';
import 'cache_service.dart';

class RecentPlaces {
  static const int maxPlaces = 20;

  List<PlaceRef> get _refs => [
        for (final raw in cache.loadRecentPlaces())
          if (PlaceRef.parse(raw) case final ref?) ref,
      ];

  Future<void> _save(List<PlaceRef> refs) =>
      cache.saveRecentPlaces([for (final r in refs.take(maxPlaces)) r.wire]);

  Future<void> record(PlaceRef place) {
    final refs = _refs..remove(place);
    return _save(refs..insert(0, place));
  }

  Future<List<SearchHit>> load() async {
    final asked = _refs;
    if (asked.isEmpty) return const [];
    final hits = await api.searchPlaces(asked);
    final alive = {for (final h in hits) h.place};
    final gone = asked.where((r) => !alive.contains(r)).toSet();
    if (gone.isNotEmpty) {
      await _save(_refs.where((r) => !gone.contains(r)).toList());
    }
    return hits;
  }
}

final recentPlaces = RecentPlaces();
