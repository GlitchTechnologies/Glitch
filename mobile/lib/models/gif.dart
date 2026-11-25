class GifItem {
  final String id;
  final String url;
  final String thumbnailUrl;

  const GifItem({required this.id, required this.url, required this.thumbnailUrl});

  factory GifItem.fromJson(Map<String, dynamic> j) => GifItem(
        id: j['id'] as String,
        url: j['url'] as String,
        thumbnailUrl: j['thumbnail_url'] as String,
      );
}

class GifCategory {
  final String name;
  final String searchterm;
  final String thumbnailUrl;

  const GifCategory({required this.name, required this.searchterm, required this.thumbnailUrl});

  factory GifCategory.fromJson(Map<String, dynamic> j) => GifCategory(
        name: j['name'] as String,
        searchterm: j['searchterm'] as String,
        thumbnailUrl: j['thumbnail_url'] as String,
      );
}

class GifPageResult {
  final List<GifItem> items;
  final String? next;
  const GifPageResult({required this.items, required this.next});
}
