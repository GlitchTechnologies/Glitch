import 'dart:async';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../models/server.dart';
import '../services/api_service.dart' show errorMessage;
import '../theme/app_theme.dart';
import 'glitch_menu.dart';
import 'glitch_pressable.dart';
import 'glitch_search_field.dart';
import 'role_picker.dart' show RoleIcon;
import 'server_user_avatar.dart';
import '../core/text_match.dart';


class OverwriteTarget {
  final OverwriteRole? role;
  final ServerUser? user;

  const OverwriteTarget.role(OverwriteRole this.role) : user = null;
  const OverwriteTarget.user(ServerUser this.user) : role = null;
}

const double kOverwriteTargetPopupWidth = 268;

class OverwriteTargetPopup extends StatefulWidget {
  final List<OverwriteRole> roles;

  final Set<int> excludeUsers;

  final bool withMembers;

  final Future<List<ServerUser>> Function(String query) searchMembers;

  final ValueChanged<OverwriteTarget> onPick;
  final double maxHeight;

  const OverwriteTargetPopup({
    super.key,
    required this.roles,
    required this.excludeUsers,
    required this.withMembers,
    required this.searchMembers,
    required this.onPick,
    required this.maxHeight,
  });

  @override
  State<OverwriteTargetPopup> createState() => _OverwriteTargetPopupState();
}

class _OverwriteTargetPopupState extends State<OverwriteTargetPopup> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';

  List<ServerUser> _people = const [];
  bool _loading = false;
  String? _error;

  Timer? _debounce;

  /// Номер последнего запроса: ответ на устаревший запрос (человек уже
  /// напечатал дальше) не должен затереть свежий.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    if (widget.withMembers) _loadPeople();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onQuery(String value) {
    setState(() => _query = value.trim());
    if (!widget.withMembers) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _loadPeople);
  }

  Future<void> _loadPeople() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final people = await widget.searchMembers(_query);
      if (!mounted || seq != _seq) return;
      setState(() {
        _people = people;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = errorMessage(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    // Совпадение — общее правило (core/text_match.dart).
    final roles = widget.roles.where((r) => matchesQuery(_query, [r.name])).toList();
    final people = [for (final u in _people) if (!widget.excludeUsers.contains(u.id)) u];
    final empty = roles.isEmpty && people.isEmpty && !_loading && _error == null;

    return GlitchPopupCard(
      maxHeight: widget.maxHeight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
            child: GlitchSearchField(
              controller: _search,
              hint: widget.withMembers ? s.placePermsAddHint : s.serverRolesSearch,
              height: 40,
              autofocus: true,
              loading: _loading,
              onChanged: _onQuery,
            ),
          ),
          if (empty)
            _hint(s.placePermsAddNothing)
          else
            Flexible(
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: ListView(
                  controller: _scroll,
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    for (final r in roles) _roleRow(r),
                    for (final u in people) _personRow(u),
                    if (_error != null) _hint(_error!),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, height: 1.3, color: GlitchColors.textSecond),
        ),
      );

  Widget _roleRow(OverwriteRole role) => _Line(
        leading: RoleIcon(color: role.color),
        title: role.name,
        trailing: context.s.placePermsRoleTag,
        dimmed: !role.canEdit,
        onTap: role.canEdit ? () => widget.onPick(OverwriteTarget.role(role)) : null,
      );

  Widget _personRow(ServerUser user) {
    final name = user.displayName.isNotEmpty ? user.displayName : user.nickname;
    return _Line(
      leading: ServerUserAvatar(user: user, name: name, size: 24),
      title: name,
      subtitle: user.nickname.isNotEmpty ? '@${user.nickname}' : null,
      onTap: () => widget.onPick(OverwriteTarget.user(user)),
    );
  }
}

class _Line extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final String? trailing;
  final bool dimmed;
  final VoidCallback? onTap;

  const _Line({
    required this.leading,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = dimmed ? GlitchColors.textHint : GlitchColors.textPrimary;
    return ClickableCursor(
      enabled: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: color),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: GlitchColors.textSecond),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Text(trailing!, style: TextStyle(fontSize: 12, color: GlitchColors.textSecond)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
