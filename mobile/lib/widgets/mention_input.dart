import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n.dart';
import '../models/mention.dart';
import '../models/server.dart' show ServerUser;
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'glitch_hover_row.dart';
import 'glitch_menu.dart' show GlitchPopupCard;
import 'glitch_pressable.dart';
import 'linked_text.dart' show mentionStyle;
import 'role_picker.dart' show RoleIcon;
import 'server_user_avatar.dart';


class _Registered {
  int start;
  int end;
  final String wire;
  final Mention look;

  _Registered(this.start, this.end, this.wire, this.look);
}

typedef MentionDraft = ({String text, List<({int start, int end, String wire, Mention look})> mentions});

class MentionTextController extends TextEditingController {
  final List<_Registered> _mentions = [];

  String get wireText {
    if (_mentions.isEmpty) return text;
    final out = StringBuffer();
    var last = 0;
    for (final m in _mentions) {
      out.write(text.substring(last, m.start));
      out.write(m.wire);
      last = m.end;
    }
    out.write(text.substring(last));
    return out.toString();
  }

  List<Mention> get wireMentions {
    final out = <Mention>[];
    var shift = 0;
    for (final m in _mentions) {
      final start = m.start + shift;
      final end = start + m.wire.length;
      shift += m.wire.length - (m.end - m.start);
      final look = m.look;
      out.add(Mention(
        kind: look.kind,
        id: look.id,
        start: start,
        end: end,
        name: look.name,
        color: look.color,
        nickname: look.nickname,
      ));
    }
    return out;
  }

  bool isInMention(int offset) => _mentions.any((m) => offset >= m.start && offset < m.end);

  @override
  set value(TextEditingValue newValue) {
    _shift(super.value.text, newValue.text);
    super.value = newValue;
  }

  void _shift(String old, String now) {
    if (old == now || _mentions.isEmpty) return;
    var prefix = 0;
    final maxPrefix = old.length < now.length ? old.length : now.length;
    while (prefix < maxPrefix && old.codeUnitAt(prefix) == now.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < old.length - prefix && suffix < now.length - prefix &&
        old.codeUnitAt(old.length - 1 - suffix) == now.codeUnitAt(now.length - 1 - suffix)) {
      suffix++;
    }
    final changedEnd = old.length - suffix;
    final delta = now.length - old.length;
    _mentions.removeWhere((m) => m.end > prefix && m.start < changedEnd ||
        (prefix == changedEnd && m.start < prefix && m.end > prefix));
    for (final m in _mentions) {
      if (m.start >= changedEnd) {
        m.start += delta;
        m.end += delta;
      }
    }
  }

  void insertMention(TextRange range, String wire, Mention look) {
    final label = look.label;
    final next = text.replaceRange(range.start, range.end, '$label ');
    value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: range.start + label.length + 1),
    );
    _add(_Registered(range.start, range.start + label.length, wire, look));
  }

  void markTyped(TextRange range, String wire, Mention look) {
    if (range.end > text.length || isInMention(range.start)) return;
    _add(_Registered(range.start, range.end, wire, look));
  }

  void _add(_Registered m) {
    _mentions
      ..removeWhere((x) => x.start < m.end && x.end > m.start)
      ..add(m)
      ..sort((a, b) => a.start.compareTo(b.start));
    notifyListeners();
  }

  void setFromWire(String wire, List<Mention> mentions) {
    final shown = StringBuffer();
    final regs = <_Registered>[];
    var last = 0;
    for (final m in mentions) {
      if (m.start < last || m.end > wire.length) continue;
      shown.write(wire.substring(last, m.start));
      final start = shown.length;
      shown.write(m.label);
      regs.add(_Registered(start, shown.length, wire.substring(m.start, m.end), m));
      last = m.end;
    }
    shown.write(wire.substring(last));
    _mentions.clear();
    final next = shown.toString();
    value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: next.length));
    _mentions.addAll(regs);
    notifyListeners();
  }

  MentionDraft snapshot() => (
    text: text,
    mentions: [for (final m in _mentions) (start: m.start, end: m.end, wire: m.wire, look: m.look)],
  );

  void restore(MentionDraft draft) {
    _mentions.clear();
    value = TextEditingValue(text: draft.text, selection: TextSelection.collapsed(offset: draft.text.length));
    _mentions.addAll([for (final m in draft.mentions) _Registered(m.start, m.end, m.wire, m.look)]);
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (_mentions.isEmpty) return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    final composing = withComposing && value.isComposingRangeValid ? value.composing : TextRange.empty;
    final cuts = <int>{0, text.length};
    for (final m in _mentions) {
      cuts..add(m.start)..add(m.end);
    }
    if (composing.isValid && !composing.isCollapsed) cuts..add(composing.start)..add(composing.end);
    final sorted = cuts.where((c) => c >= 0 && c <= text.length).toList()..sort();
    final children = <TextSpan>[];
    for (var i = 0; i + 1 < sorted.length; i++) {
      final a = sorted[i], b = sorted[i + 1];
      if (a == b) continue;
      var piece = const TextStyle();
      for (final m in _mentions) {
        if (a >= m.start && b <= m.end) piece = piece.merge(mentionStyle(m.look));
      }
      if (composing.isValid && a >= composing.start && b <= composing.end) {
        piece = piece.merge(const TextStyle(decoration: TextDecoration.underline));
      }
      children.add(TextSpan(text: text.substring(a, b), style: piece));
    }
    return TextSpan(style: style, children: children);
  }
}


class MentionOption {
  final Mention look;      // как показать в поле (label, цвет роли)
  final String wire;       // что отправить
  final String title;
  final String? subtitle;
  final ServerUser? user;  // аватарка
  final String? roleColor;

  const MentionOption({
    required this.look,
    required this.wire,
    required this.title,
    this.subtitle,
    this.user,
    this.roleColor,
  });
}

/// СОСТОЯНИЕ ОКНА ПОДСКАЗОК — следит за полем: курсор сразу после «@набранное»
/// (без пробелов, не внутри упоминания) — спрашивает сервер, кого можно
/// упомянуть, и держит выбранную строку. Владелец (экран переписки) отдаёт
/// ему клавиши поля ([handleKey]) и освобождает в `dispose`.
class MentionAutocomplete extends ChangeNotifier {
  final MentionTextController controller;

  final int? Function() chatId;

  final FocusNode focusNode;

  MentionAutocomplete({required this.controller, required this.chatId, required this.focusNode}) {
    controller.addListener(_onText);
    focusNode.addListener(_onFocus);
  }

  void _onFocus() {
    if (!focusNode.hasFocus) _close();
  }

  static const int _maxQuery = 32;

  TextRange? _range;
  String? _query;
  List<MentionOption> options = const [];
  int selected = 0;
  int _seq = 0;
  Timer? _debounce;
  bool _disposed = false;

  int? _dismissedAt;

  bool get visible => _query != null && options.isNotEmpty;

  void _onText() {
    final found = _trigger();
    if (found == null) {
      _close();
      return;
    }
    if (_dismissedAt == found.range.start) return;
    _dismissedAt = null;
    final changed = found.query != _query;
    _range = found.range;
    _query = found.query;
    if (!changed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), _load);
  }

  ({TextRange range, String query})? _trigger() {
    final sel = controller.selection;
    if (!focusNode.hasFocus || !sel.isValid || !sel.isCollapsed || chatId() == null) return null;
    final text = controller.text;
    final caret = sel.baseOffset;
    var i = caret - 1;
    while (i >= 0 && caret - i <= _maxQuery + 1) {
      final c = text[i];
      if (c == '@') {
        final before = i == 0 ? ' ' : text[i - 1];
        if (_isWordChar(before) || controller.isInMention(i)) return null;
        return (range: TextRange(start: i, end: caret), query: text.substring(i + 1, caret));
      }
      if (c.trim().isEmpty) return null;
      i--;
    }
    return null;
  }

  static bool _isWordChar(String c) => RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(c);

  Future<void> _load() async {
    final id = chatId();
    final query = _query;
    if (id == null || query == null) return;
    final seq = ++_seq;
    try {
      final found = await api.getMentionCandidates(id, query);
      if (_disposed || seq != _seq || _query != query) return;
      options = _optionsFrom(found);
      selected = 0;
      _markTyped(query);
      notifyListeners();
    } catch (_) {
      if (_disposed || seq != _seq) return;
      options = const [];
      notifyListeners();
    }
  }

  List<MentionOption> _optionsFrom(MentionCandidates c) => [
    for (final u in c.users)
      MentionOption(
        look: Mention(kind: 'user', id: u.id, start: 0, end: 0, name: u.displayName),
        wire: '@${u.nickname}',
        title: u.displayName,
        subtitle: '@${u.nickname}',
        user: u,
      ),
    for (final r in c.roles)
      MentionOption(
        look: Mention(kind: 'role', id: r.id, start: 0, end: 0, name: r.name, color: r.color),
        wire: '@${r.name}',
        title: '@${r.name}',
        roleColor: r.color,
      ),
    if (c.everyone)
      const MentionOption(
        look: Mention(kind: 'everyone', start: 0, end: 0, name: 'everyone'),
        wire: '@everyone',
        title: '@everyone',
      ),
    if (c.here)
      const MentionOption(
        look: Mention(kind: 'here', start: 0, end: 0, name: 'here'),
        wire: '@here',
        title: '@here',
      ),
  ];

  void _markTyped(String query) {
    final range = _range;
    if (range == null) return;
    final typed = '@$query'.toLowerCase();
    for (final o in options) {
      if (o.wire.toLowerCase() == typed) {
        controller.markTyped(range, o.wire, o.look);
        return;
      }
    }
  }

  void pick(MentionOption option) {
    final range = _range;
    if (range == null) return;
    _close();
    controller.insertMention(range, option.wire, option.look);
  }

  KeyEventResult handleKey(KeyEvent event) {
    if (!visible || event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      selected = (selected + 1) % options.length;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      selected = (selected - 1 + options.length) % options.length;
    } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab) {
      if (event is KeyDownEvent) pick(options[selected]);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.escape) {
      _dismissedAt = _range?.start;
      _close();
      return KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }
    notifyListeners();
    return KeyEventResult.handled;
  }

  void _close() {
    _debounce?.cancel();
    _seq++;
    final had = visible || _query != null;
    _query = null;
    _range = null;
    options = const [];
    if (had) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    controller.removeListener(_onText);
    focusNode.removeListener(_onFocus);
    super.dispose();
  }
}

class MentionSuggestions extends StatefulWidget {
  final MentionAutocomplete autocomplete;
  final Widget child;

  const MentionSuggestions({super.key, required this.autocomplete, required this.child});

  @override
  State<MentionSuggestions> createState() => _MentionSuggestionsState();
}

class _MentionSuggestionsState extends State<MentionSuggestions> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _scroll = ScrollController();
  double _width = 0;

  static const double _maxHeight = 320;
  static const double _rowHeight = 44;

  @override
  void initState() {
    super.initState();
    widget.autocomplete.addListener(_sync);
  }

  @override
  void didUpdateWidget(MentionSuggestions old) {
    super.didUpdateWidget(old);
    if (old.autocomplete != widget.autocomplete) {
      old.autocomplete.removeListener(_sync);
      widget.autocomplete.addListener(_sync);
    }
  }

  @override
  void dispose() {
    widget.autocomplete.removeListener(_sync);
    _scroll.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    if (widget.autocomplete.visible) {
      _portal.show();
      _keepSelectedInView();
    } else {
      _portal.hide();
    }
    setState(() {});
  }

  void _keepSelectedInView() {
    if (!_scroll.hasClients) return;
    final top = widget.autocomplete.selected * _rowHeight;
    final view = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + _rowHeight > _scroll.offset + view) {
      _scroll.jumpTo(top + _rowHeight - view);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      _width = box.maxWidth;
      return CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (_) => Positioned(
            left: 0,
            top: 0,
            child: CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomLeft,
              offset: const Offset(0, -6),
              child: TextFieldTapRegion(
                child: SizedBox(width: _width, child: _list(context)),
              ),
            ),
          ),
          child: widget.child,
        ),
      );
    });
  }

  Widget _list(BuildContext context) {
    final ac = widget.autocomplete;
    final options = ac.options;
    return GlitchPopupCard(
      maxHeight: _maxHeight,
      child: ListView.builder(
        controller: _scroll,
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: options.length,
        itemExtent: _rowHeight,
        itemBuilder: (context, i) => _row(context, options[i], i == ac.selected),
      ),
    );
  }

  Widget _row(BuildContext context, MentionOption o, bool selected) {
    final s = context.s;
    final Widget lead;
    final user = o.user;
    if (user != null) {
      lead = ServerUserAvatar(user: user, name: user.displayName, size: 26);
    } else if (o.look.kind == 'role') {
      lead = SizedBox.square(dimension: 26, child: Center(child: RoleIcon(color: o.roleColor, size: 18)));
    } else {
      lead = SizedBox.square(
        dimension: 26,
        child: Icon(Icons.alternate_email_rounded, size: 20, color: GlitchColors.textPrimary),
      );
    }
    final subtitle = o.subtitle ??
        switch (o.look.kind) {
          'everyone' => s.mentionEveryoneHint,
          'here' => s.mentionHereHint,
          _ => null,
        };
    return GlitchHoverArea(
      onTap: () => widget.autocomplete.pick(o),
      builder: (context, active) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: GlitchHoverRow.highlight(context, active: active, selected: selected),
          borderRadius: BorderRadius.circular(GlitchHoverRow.radius),
        ),
        child: Row(
          children: [
            lead,
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                o.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: GlitchColors.textPrimary),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 13, color: GlitchColors.textSecond),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
