import '../core/time_json.dart';

class CollectibleLook {
  final int id;
  final String asset;
  final String staticUrl;
  final String? animated;
  final List<EffectLayer> layers;
  final String? palette;

  const CollectibleLook({
    required this.id,
    required this.asset,
    required this.staticUrl,
    this.animated,
    this.layers = const [],
    this.palette,
  });

  static CollectibleLook? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final staticUrl = raw['static'];
    if (id is! int || staticUrl is! String || staticUrl.isEmpty) return null;
    final layers = raw['layers'];
    return CollectibleLook(
      id: id,
      asset: raw['asset'] as String? ?? '',
      staticUrl: staticUrl,
      animated: raw['animated'] as String?,
      layers: layers is List
          ? layers.map(EffectLayer.fromJson).whereType<EffectLayer>().toList()
          : const [],
      palette: raw['palette'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'asset': asset,
        'static': staticUrl,
        if (animated != null) 'animated': animated,
        if (layers.isNotEmpty) 'layers': [for (final l in layers) l.toJson()],
        if (palette != null) 'palette': palette,
      };

  bool sameAs(CollectibleLook? other) => other != null && other.id == id && other.asset == asset;
}

class EffectLayer {
  final String url;
  final bool loop;
  final int startMs;
  final int durationMs;

  const EffectLayer({required this.url, required this.loop, required this.startMs, required this.durationMs});

  static EffectLayer? fromJson(Object? raw) {
    if (raw is! Map || raw['url'] is! String) return null;
    return EffectLayer(
      url: raw['url'] as String,
      loop: raw['loop'] == true,
      startMs: (raw['start_ms'] as num?)?.toInt() ?? 0,
      durationMs: (raw['duration_ms'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'url': url, 'loop': loop, 'start_ms': startMs, 'duration_ms': durationMs};
}

class CollectionItem {
  final int id;
  final String kind;
  final String name;
  final CollectibleLook look;
  final DateTime acquiredAt;

  const CollectionItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.look,
    required this.acquiredAt,
  });

  static CollectionItem? fromJson(Map<String, dynamic> j) {
    final look = CollectibleLook.fromJson(j['look']);
    if (look == null) return null;
    return CollectionItem(
      id: j['id'] as int,
      kind: j['kind'] as String? ?? '',
      name: j['name'] as String? ?? '',
      look: look,
      acquiredAt: parseUtcLocal(j['acquired_at']),
    );
  }
}
