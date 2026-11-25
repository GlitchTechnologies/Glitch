import '../core/time_json.dart';

/// Сервер присылает готовые адреса и размеры изображений.
class Embed {
  final String? title;
  final String? description;

  final String? url;

  final int? color;

  final DateTime? timestamp;
  final EmbedAuthor? author;
  final EmbedFooter? footer;
  final EmbedMedia? image;
  final EmbedMedia? thumbnail;
  final List<EmbedField> fields;

  const Embed({
    this.title,
    this.description,
    this.url,
    this.color,
    this.timestamp,
    this.author,
    this.footer,
    this.image,
    this.thumbnail,
    this.fields = const [],
  });

  factory Embed.fromJson(Map<String, dynamic> j) => Embed(
        title: j['title'] as String?,
        description: j['description'] as String?,
        url: j['url'] as String?,
        color: j['color'] as int?,
        timestamp: j['timestamp'] != null ? parseUtcLocal(j['timestamp']) : null,
        author: j['author'] != null ? EmbedAuthor.fromJson(j['author'] as Map<String, dynamic>) : null,
        footer: j['footer'] != null ? EmbedFooter.fromJson(j['footer'] as Map<String, dynamic>) : null,
        image: j['image'] != null ? EmbedMedia.fromJson(j['image'] as Map<String, dynamic>) : null,
        thumbnail: j['thumbnail'] != null ? EmbedMedia.fromJson(j['thumbnail'] as Map<String, dynamic>) : null,
        fields: [
          for (final f in (j['fields'] as List? ?? const []))
            EmbedField.fromJson(f as Map<String, dynamic>),
        ],
      );

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (url != null) 'url': url,
        if (color != null) 'color': color,
        if (timestamp != null) 'timestamp': utcIso(timestamp!),
        if (author != null) 'author': author!.toJson(),
        if (footer != null) 'footer': footer!.toJson(),
        if (image != null) 'image': image!.toJson(),
        if (thumbnail != null) 'thumbnail': thumbnail!.toJson(),
        if (fields.isNotEmpty) 'fields': [for (final f in fields) f.toJson()],
      };

  static List<Embed> listFrom(dynamic raw) => [
        for (final e in (raw as List? ?? const [])) Embed.fromJson(e as Map<String, dynamic>),
      ];

  static String? summaryOf(List<Embed> embeds) {
    for (final e in embeds) {
      for (final text in [
        e.title,
        e.description,
        e.author?.name,
        e.fields.isNotEmpty ? e.fields.first.name : null,
        e.footer?.text,
      ]) {
        if (text != null && text.trim().isNotEmpty) return text.trim();
      }
    }
    return null;
  }
}

class EmbedAuthor {
  final String name;
  final String? url;
  final String? iconUrl;

  const EmbedAuthor({required this.name, this.url, this.iconUrl});

  factory EmbedAuthor.fromJson(Map<String, dynamic> j) =>
      EmbedAuthor(name: j['name'] as String? ?? '', url: j['url'] as String?, iconUrl: j['icon_url'] as String?);

  Map<String, dynamic> toJson() => {
        'name': name,
        if (url != null) 'url': url,
        if (iconUrl != null) 'icon_url': iconUrl,
      };
}

class EmbedFooter {
  final String text;
  final String? iconUrl;

  const EmbedFooter({required this.text, this.iconUrl});

  factory EmbedFooter.fromJson(Map<String, dynamic> j) =>
      EmbedFooter(text: j['text'] as String? ?? '', iconUrl: j['icon_url'] as String?);

  Map<String, dynamic> toJson() => {'text': text, if (iconUrl != null) 'icon_url': iconUrl};
}

class EmbedField {
  final String name;
  final String value;

  final bool inline;

  const EmbedField({required this.name, required this.value, this.inline = false});

  factory EmbedField.fromJson(Map<String, dynamic> j) => EmbedField(
        name: j['name'] as String? ?? '',
        value: j['value'] as String? ?? '',
        inline: j['inline'] == true,
      );

  Map<String, dynamic> toJson() => {'name': name, 'value': value, if (inline) 'inline': true};
}

class EmbedMedia {
  final String url;
  final int? width;
  final int? height;

  const EmbedMedia({required this.url, this.width, this.height});

  factory EmbedMedia.fromJson(Map<String, dynamic> j) =>
      EmbedMedia(url: j['url'] as String? ?? '', width: j['width'] as int?, height: j['height'] as int?);

  double? get aspectRatio =>
      width != null && height != null && width! > 0 && height! > 0 ? width! / height! : null;

  Map<String, dynamic> toJson() => {
        'url': url,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
      };
}
