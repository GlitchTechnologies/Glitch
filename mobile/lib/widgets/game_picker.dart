import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../models/server.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'glitch_dialog.dart' show GlitchCheckMark;
import 'glitch_form_field.dart';
import 'glitch_pressable.dart';
import 'server_profile_card.dart' show ServerGameChips;
import '../providers/search_session.dart';
import 'glitch_icon_button.dart';

/// Ищет СЕРВЕР (`api.searchGames`, с 2026-11-07): игр больше десяти тысяч,
/// весь справочник на устройство не качается. Пауза в наборе, защита от
/// устаревших ответов, загрузка и ошибка — общий `SearchSession`, своих здесь
/// нет. Без запроса в списке — уже выбранные игры (снять галочку), а если их
/// нет — подсказка начать ввод.
class GamePicker extends StatefulWidget {
  final List<Game> selected;
  final ValueChanged<List<Game>> onChanged;
  final bool enabled;

  const GamePicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<GamePicker> createState() => _GamePickerState();
}

class _GamePickerState extends State<GamePicker> {
  final _search = TextEditingController();
  final _focus = FocusNode();

  final _listScroll = ScrollController();

  late final _session = SearchSession<Game>(search: api.searchGames);
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSession);
    _search.addListener(_onSearch);
    _focus.addListener(() {
      if (_focus.hasFocus && !_open && mounted) setState(() => _open = true);
    });
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    _session.dispose();
    _search.dispose();
    _focus.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  void _onSearch() {
    if (!mounted) return;
    _session.setQuery(_search.text);
    setState(() => _open = true);
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  void _toggle(Game game) {
    final ids = widget.selected.map((g) => g.id).toSet();
    final next = ids.contains(game.id)
        ? widget.selected.where((g) => g.id != game.id).toList()
        : [...widget.selected, game];
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final count = widget.selected.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlitchFormLabel(label: s.serverProfileGames, hint: s.serverProfileGamesHint),
        if (count > 0) ...[
          ServerGameChips(names: [for (final g in widget.selected) g.name]),
          const SizedBox(height: 10),
        ],
        TapRegion(
          onTapOutside: (_) {
            if (!_open) return;
            setState(() => _open = false);
            _focus.unfocus();
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(s),
              if (_open) ...[
                const SizedBox(height: 6),
                _list(s),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          s.serverProfileGamesCount(count, kMaxServerGames),
          style: TextStyle(fontSize: 12.5, color: GlitchColors.textSecond),
        ),
      ],
    );
  }

  Widget _field(S s) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      decoration: BoxDecoration(
        color: GlitchColors.bgInput,
        border: Border.all(color: _open ? GlitchColors.accentBlue : Colors.transparent, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _search,
              focusNode: _focus,
              enabled: widget.enabled,
              style: TextStyle(fontSize: 15, color: GlitchColors.textPrimary),
              decoration: InputDecoration(
                hintText: s.serverProfileGamesSearch,
                hintStyle: TextStyle(color: GlitchColors.textHint, fontSize: 16),
                filled: false,
                fillColor: Colors.transparent,
                hoverColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.fromLTRB(16, 15, 8, 15),
              ),
            ),
          ),
          GlitchIconButton(
            icon: Icon(
              _open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
            onTap: widget.enabled
                ? () {
                    setState(() => _open = !_open);
                    if (!_open) _focus.unfocus();
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _list(S s) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 264),
      decoration: BoxDecoration(
        color: GlitchColors.bgCard,
        border: Border.all(color: GlitchColors.borderCard),
      ),
      child: Builder(
        builder: (context) {
          final searching = !_session.isEmpty;
          final games = searching ? _session.hits : widget.selected;
          if (searching && _session.failed && games.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.errorLoad,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary),
                  ),
                  TextButton(
                    onPressed: _session.retry,
                    child: Text(s.retry, style: TextStyle(color: GlitchColors.accentBlue)),
                  ),
                ],
              ),
            );
          }
          if (searching && _session.loading && games.isEmpty) {
            return const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          if (games.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                searching ? s.serverProfileGamesNotFound : s.serverProfileGamesTypeToSearch,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary),
              ),
            );
          }
          final chosen = widget.selected.map((g) => g.id).toSet();
          final full = chosen.length >= kMaxServerGames;
          return Scrollbar(
            controller: _listScroll,
            thumbVisibility: true,
            child: ListView.builder(
              controller: _listScroll,
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: games.length,
              itemBuilder: (context, i) {
                final game = games[i];
                final checked = chosen.contains(game.id);
                final can = widget.enabled && (checked || !full);
                return ClickableCursor(
                  enabled: can,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: can ? () => _toggle(game) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              game.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                color: GlitchColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          GlitchCheckMark(value: checked, enabled: can),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
