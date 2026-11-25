import '../core/collectibles.dart';
import 'collectible.dart';

class ShopProduct {
  final int id;
  final String name;

  /// `null` — набор, иначе вид единственного предмета.
  final CollectibleKind? kind;

  /// В копейках.
  final int price;
  final String currency;
  final List<ShopItem> items;

  final bool owned;

  const ShopProduct({
    required this.id,
    required this.name,
    required this.kind,
    required this.price,
    required this.currency,
    required this.items,
    required this.owned,
  });

  bool get isBundle => kind == null;

  ShopItem? firstOf(CollectibleKind kind) {
    for (final item in items) {
      if (item.kind == kind) return item;
    }
    return null;
  }

  static ShopProduct? fromJson(Map<String, dynamic> j) {
    final rawKind = j['kind'] as String? ?? '';
    final kind = CollectibleKind.fromWire(rawKind);
    if (kind == null && rawKind != 'bundle') return null;
    final items = (j['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ShopItem.fromJson)
        .whereType<ShopItem>()
        .toList();
    if (items.isEmpty) return null;
    return ShopProduct(
      id: j['id'] as int,
      name: j['name'] as String? ?? '',
      kind: kind,
      price: (j['price'] as num?)?.toInt() ?? 0,
      currency: j['currency'] as String? ?? 'RUB',
      items: items,
      owned: j['owned'] == true,
    );
  }
}

class ShopItem {
  final int id;
  final CollectibleKind kind;
  final String name;
  final CollectibleLook look;

  final bool owned;

  const ShopItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.look,
    this.owned = false,
  });

  static ShopItem? fromJson(Map<String, dynamic> j) {
    final kind = CollectibleKind.fromWire(j['kind'] as String? ?? '');
    final look = CollectibleLook.fromJson(j['look']);
    if (kind == null || look == null) return null;
    return ShopItem(
      id: j['id'] as int,
      kind: kind,
      name: j['name'] as String? ?? '',
      look: look,
      owned: j['owned'] == true,
    );
  }
}
