import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/date_text.dart';
import '../core/media_content.dart' show isGifUrl;
import '../models/embed.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'animated_network_image.dart';
import 'chat_metrics.dart';
import 'glitch_pressable.dart' show ClickableCursor, GlitchHoverArea;
import 'linked_text.dart';
import 'selectable_content.dart';
import 'viewport_gate.dart';

class EmbedCard extends StatelessWidget {
  final Embed embed;
  final bool inheritSelection;

  final void Function(EmbedMedia media) onOpenImage;

  const EmbedCard({super.key, required this.embed, required this.onOpenImage, this.inheritSelection = false});

  static const double _stripe = 4;
  static const double _radius = 6;
  static const double _thumb = 80;
  static const double _gap = 8;

  TextStyle get _textStyle => TextStyle(fontSize: 14, height: 1.375, color: GlitchColors.textPrimary);

  @override
  Widget build(BuildContext context) {
    final m = ChatMetrics.of(context);
    final e = embed;
    final color = e.color != null ? Color(0xFF000000 | e.color!) : GlitchColors.border;
    final thumb = e.thumbnail;

    final head = <Widget>[
      if (e.author != null) _author(context, e.author!),
      if (e.title != null) _title(context, e.title!, e.url),
      if (e.description != null) _text(e.description!),
      if (e.fields.isNotEmpty) _fields(e.fields, perRow: thumb != null ? 2 : 3),
    ];

    final body = <Widget>[
      if (head.isNotEmpty || thumb != null)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _spaced(head),
              ),
            ),
            if (thumb != null) ...[
              const SizedBox(width: 16),
              _picture(context, thumb, maxWidthOf: (_) => _thumb, maxHeight: _thumb),
            ],
          ],
        ),
      if (e.image != null)
        _picture(context, e.image!, maxWidthOf: m.embedImage, maxHeight: null),
      if (e.footer != null || e.timestamp != null) _footer(context, e.footer, e.timestamp),
    ];

    final card = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: m.embed),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: Container(
          decoration: BoxDecoration(
            color: GlitchColors.bgEmbed,
            border: Border(left: BorderSide(color: color, width: _stripe)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: _spaced(body),
            ),
          ),
        ),
      ),
    );
    return inheritSelection ? card : SelectableContent(fillWidth: true, child: card);
  }

  static List<Widget> _spaced(List<Widget> parts) => [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const SizedBox(height: _gap),
          parts[i],
        ],
      ];

  Widget _author(BuildContext context, EmbedAuthor a) {
    Widget row(bool hover) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (a.iconUrl != null) ...[
              _icon(a.iconUrl!, 24),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                a.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: GlitchColors.textPrimary,
                  decoration: hover ? TextDecoration.underline : null,
                  decorationColor: GlitchColors.textPrimary,
                ),
              ),
            ),
          ],
        );
    return a.url == null ? row(false) : _link(context, a.url!, row);
  }

  Widget _title(BuildContext context, String title, String? url) {
    Widget text(bool hover) => Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.3,
            color: url != null ? GlitchColors.accentBlue : GlitchColors.textPrimary,
            decoration: hover ? TextDecoration.underline : null,
            decorationColor: GlitchColors.accentBlue,
          ),
        );
    return url == null ? text(false) : _link(context, url, text);
  }

  Widget _text(String text, {TextStyle? style}) {
    final base = style ?? _textStyle;
    return LinkedText.needed(text, const [])
        ? LinkedText(text: text, baseStyle: base, onLaunch: launchSmartUrl)
        : Text(text, style: base);
  }

  Widget _fields(List<EmbedField> fields, {required int perRow}) {
    final rows = <List<EmbedField>>[];
    for (final f in fields) {
      final last = rows.isEmpty ? null : rows.last;
      if (f.inline && last != null && last.first.inline && last.length < perRow) {
        last.add(f);
      } else {
        rows.add([f]);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _spaced([
        for (final row in rows)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < row.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(child: _field(row[i])),
              ],
              if (row.first.inline)
                for (var i = row.length; i < perRow; i++) ...[
                  const SizedBox(width: 16),
                  const Expanded(child: SizedBox.shrink()),
                ],
            ],
          ),
      ]),
    );
  }

  Widget _field(EmbedField f) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(f.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary)),
          const SizedBox(height: 2),
          _text(f.value),
        ],
      );

  Widget _footer(BuildContext context, EmbedFooter? footer, DateTime? time) {
    final parts = [
      if (footer != null) footer.text,
      if (time != null) formatMessageStamp(context, time),
    ];
    return Row(
      children: [
        if (footer?.iconUrl != null) ...[
          _icon(footer!.iconUrl!, 20),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            parts.join(' • '),
            style: TextStyle(fontSize: 12, color: GlitchColors.textSecond),
          ),
        ),
      ],
    );
  }

  Widget _link(BuildContext context, String url, Widget Function(bool hover) child) => GlitchHoverArea(
        onTap: () => launchSmartUrl(context, url),
        builder: (_, hover) => child(hover),
      );

  Widget _icon(String url, double size) => ClipOval(
        child: _network(url, width: size, height: size, fit: BoxFit.cover),
      );

  Widget _picture(BuildContext context, EmbedMedia media,
      {required double Function(double? aspectRatio) maxWidthOf, required double? maxHeight}) {
    Widget sized(int? w, int? h) {
      final known = w != null && h != null && w > 0 && h > 0;
      final ar = known ? w / h : 16 / 9;
      var width = maxWidthOf(known ? ar : null);
      if (maxHeight != null && width / ar > maxHeight) width = maxHeight * ar;
      if (known && width > w) width = w.toDouble();
      final height = width / ar;
      return ClickableCursor(
        child: GestureDetector(
          onTap: () => onOpenImage(media),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: ViewportGate(
              placeholder: _stub(width, height),
              builder: (_) => _network(media.url, width: width, height: height, fit: BoxFit.cover),
            ),
          ),
        ),
      );
    }

    if (media.aspectRatio != null) return sized(media.width, media.height);
    return _NaturalSize(
      url: api.mediaUrl(media.url),
      builder: (size) => sized(size?.width.round(), size?.height.round()),
    );
  }

  Widget _stub(double width, double height) => Container(width: width, height: height, color: GlitchColors.bgInput);

  Widget _network(String url, {required double width, required double height, required BoxFit fit}) {
    final full = api.mediaUrl(url);
    if (isGifUrl(url)) {
      return AnimatedNetworkImage(
        url: full,
        headers: api.headersFor(full),
        width: width,
        height: height,
        fit: fit,
        placeholder: (_) => _stub(width, height),
        errorWidget: (_) => _stub(width, height),
      );
    }
    return CachedNetworkImage(
      imageUrl: full,
      cacheManager: mediaCacheManager,
      width: width,
      height: height,
      fit: fit,
      placeholder: (_, __) => _stub(width, height),
      errorWidget: (_, __, ___) => _stub(width, height),
    );
  }
}

class _NaturalSize extends StatefulWidget {
  final String url;
  final Widget Function(Size? size) builder;

  const _NaturalSize({required this.url, required this.builder});

  @override
  State<_NaturalSize> createState() => _NaturalSizeState();
}

class _NaturalSizeState extends State<_NaturalSize> {
  ImageStream? _stream;
  late final _listener = ImageStreamListener(_loaded, onError: (_, __) {});
  Size? _size;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_NaturalSize old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _size = null;
      _resolve();
    }
  }

  void _resolve() {
    final stream = CachedNetworkImageProvider(widget.url, cacheManager: mediaCacheManager)
        .resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _loaded(ImageInfo info, bool _) {
    final size = Size(info.image.width.toDouble(), info.image.height.toDouble());
    info.dispose();
    if (mounted && size != _size) setState(() => _size = size);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_size);
}
