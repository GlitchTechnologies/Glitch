import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/avatar_color.dart';
import '../core/glitch_link.dart';
import '../core/glitch_link_open.dart';
import '../core/l10n.dart';
import '../core/platform_info.dart';
import '../models/mention.dart';
import '../theme/app_theme.dart';
import 'glitch_toast.dart';

// ЧЕТВЁРТАЯ ВЕТКА — АДРЕС БЕЗ СХЕМЫ («example.com», «web.glitchapp.online»), и
// именно в ней 2026-08-29 нашлась ошибка: поддомены не распознавались.
//
// Было: `[a-zA-Z0-9][a-zA-Z0-9\-]*\.[a-zA-Z]{2,}` — РОВНО ОДНА точка. В
// «web.glitchapp.online» ссылкой становилось «web.glitchapp», а «.online»
// оставалось обычным текстом, и по такой ссылке нельзя было ни перейти, ни
// скопировать её целиком. Хуже того, в «a.b.c.example.com/path» подсвечивалось
// вообще не начало адреса, а кусок из середины («c.example»): движок начинал
// разбор с той точки, где выражение впервые сходилось.
final urlRegex = RegExp(
  r'(https?://\S+|www\.\S+|glitchapp\.online\S*|[a-zA-Z0-9][a-zA-Z0-9\-]*(?:\.[a-zA-Z0-9][a-zA-Z0-9\-]*)*\.[a-zA-Z]{2,}(?:/\S*)?)',
  caseSensitive: false,
);

Future<void> launchSmartUrl(BuildContext context, String raw) async {
  final url = raw.startsWith('http') ? raw : 'https://$raw';
  final uri = Uri.tryParse(url);
  if (uri == null) return;

  final target = glitchTargetFromUri(uri);
  if (target != null) {
    await openGlitchLink(context, target, onNotFound: () {
      if (context.mounted) GlitchToast.show(context, context.s.linkNotFound);
    });
    return;
  }

  final host = uri.host.toLowerCase();
  if (host == linkDomain || host == 'www.$linkDomain') {
    if (uri.pathSegments.any((p) => p.isNotEmpty)) {
      if (context.mounted) GlitchToast.show(context, context.s.linkNotFound);
      return;
    }
  }

  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

TextStyle mentionStyle(Mention? mention) {
  final color = parseAvatarColor(mention?.color) ?? GlitchColors.accentBlue;
  return TextStyle(
    color: color,
    fontWeight: FontWeight.w500,
    backgroundColor: color.withOpacity(0.15),
  );
}

class LinkedText extends StatefulWidget {
  final String text;
  final TextStyle baseStyle;
  final void Function(BuildContext, String) onLaunch;
  final InlineSpan? suffix;

  final List<Mention> mentions;

  final void Function(BuildContext context, Mention mention, Rect rect)? onMentionTap;

  const LinkedText({super.key, required this.text, required this.baseStyle, required this.onLaunch, this.suffix,
      this.mentions = const [], this.onMentionTap});

  static bool needed(String text, List<Mention> mentions) => mentions.isNotEmpty || urlRegex.hasMatch(text);

  @override
  State<LinkedText> createState() => _LinkedTextState();
}

class _Piece {
  final String text;
  final String? url;
  final Mention? mention;
  const _Piece(this.text, {this.url, this.mention});
}

class _LinkedTextState extends State<LinkedText> {
  final List<TextRange> _linkRanges = [];
  final List<String> _linkUrls = [];
  final List<TextRange> _mentionRanges = [];
  final List<Mention> _mentionTargets = [];
  final List<_Piece> _pieces = [];
  final _textKey = GlobalKey();
  Offset? _downPosition;
  DateTime? _downTime;
  int _downButtons = 0;

  void _rebuild() {
    _linkRanges.clear();
    _linkUrls.clear();
    _mentionRanges.clear();
    _mentionTargets.clear();
    _pieces.clear();
    final text = widget.text;
    var shown = 0;
    void add(_Piece p) {
      if (p.url != null) {
        _linkUrls.add(p.url!);
        _linkRanges.add(TextRange(start: shown, end: shown + p.text.length));
      }
      if (p.mention?.opensProfile ?? false) {
        _mentionTargets.add(p.mention!);
        _mentionRanges.add(TextRange(start: shown, end: shown + p.text.length));
      }
      _pieces.add(p);
      shown += p.text.length;
    }

    void plain(String part) {
      var last = 0;
      for (final m in urlRegex.allMatches(part)) {
        if (m.start > last) add(_Piece(part.substring(last, m.start)));
        add(_Piece(m.group(0)!, url: m.group(0)!));
        last = m.end;
      }
      if (last < part.length) add(_Piece(part.substring(last)));
    }

    var last = 0;
    for (final m in widget.mentions) {
      if (m.start < last || m.end > text.length) continue;
      plain(text.substring(last, m.start));
      add(_Piece(m.label, mention: m));
      last = m.end;
    }
    plain(text.substring(last));
  }

  @override
  void initState() { super.initState(); _rebuild(); }

  @override
  void didUpdateWidget(LinkedText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || !identical(old.mentions, widget.mentions)) _rebuild();
  }

  void _tapAt(Offset globalPosition) {
    final obj = _textKey.currentContext?.findRenderObject();
    if (obj is! RenderParagraph) return;
    final local = obj.globalToLocal(globalPosition);
    final pos = obj.getPositionForOffset(local).offset;
    bool hit(TextRange r) => pos >= r.start && pos < r.end;
    for (var i = 0; i < _linkRanges.length; i++) {
      if (hit(_linkRanges[i])) {
        widget.onLaunch(context, _linkUrls[i]);
        return;
      }
    }
    final onMention = widget.onMentionTap;
    if (onMention == null) return;
    for (var i = 0; i < _mentionRanges.length; i++) {
      final r = _mentionRanges[i];
      if (!hit(r)) continue;
      final boxes = obj.getBoxesForSelection(TextSelection(baseOffset: r.start, extentOffset: r.end));
      if (boxes.isEmpty) return;
      final box = boxes.firstWhere((b) => b.toRect().contains(local), orElse: () => boxes.first).toRect();
      onMention(context, _mentionTargets[i], box.shift(obj.localToGlobal(Offset.zero)));
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    for (final p in _pieces) {
      final mention = p.mention;
      if (p.url != null) {
        spans.add(TextSpan(
          text: p.text,
          style: TextStyle(
            color: GlitchColors.accentBlue,
            decoration: TextDecoration.underline,
            decorationColor: GlitchColors.accentBlue,
          ),
          mouseCursor: SystemMouseCursors.click,
        ));
      } else if (mention != null) {
        spans.add(TextSpan(
          text: p.text,
          style: mentionStyle(mention),
          mouseCursor: widget.onMentionTap != null && mention.opensProfile ? SystemMouseCursors.click : null,
        ));
      } else {
        spans.add(TextSpan(text: p.text));
      }
    }
    if (widget.suffix != null) spans.add(widget.suffix!);
    final registrar = SelectionContainer.maybeOf(context);
    final richText = RichText(
      key: _textKey,
      text: TextSpan(style: widget.baseStyle, children: spans),
      textWidthBasis: TextWidthBasis.longestLine,
      selectionRegistrar: registrar,
      selectionColor: registrar == null
          ? null
          : (DefaultSelectionStyle.of(context).selectionColor ?? const Color(0x80AACCFF)),
    );

    return Listener(
      onPointerDown: (event) {
        _downPosition = event.position;
        _downTime = DateTime.now();
        _downButtons = event.buttons;
      },
      onPointerUp: (event) {
        final down = _downPosition;
        final downTime = _downTime;
        final downButtons = _downButtons;
        _downPosition = null;
        _downTime = null;
        _downButtons = 0;
        if (down == null || downTime == null) return;
        if ((event.position - down).distance > kTouchSlop) return; // это был скролл/выделение, не тап
        if (DateTime.now().difference(downTime) >= kLongPressTimeout) return;

        if (hasPointerInput && downButtons == 0x02) return;

        _tapAt(event.position);
      },
      onPointerCancel: (_) { _downPosition = null; _downTime = null; _downButtons = 0; },
      child: richText,
    );
  }
}
