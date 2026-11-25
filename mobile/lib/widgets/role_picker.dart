import 'dart:async';

import 'package:flutter/material.dart';

import '../core/avatar_color.dart';
import '../core/l10n.dart';
import '../models/server.dart';
import '../theme/app_theme.dart';
import 'glitch_dialog.dart' show GlitchCheckMark;
import 'glitch_menu.dart';
import 'glitch_pressable.dart';
import 'glitch_search_field.dart';
import 'glitch_tooltip.dart';
import '../core/text_match.dart';

class RoleIcon extends StatelessWidget {
  final String? color;
  final double size;

  const RoleIcon({super.key, required this.color, this.size = 16});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RoleIconPainter(parseAvatarColor(color) ?? GlitchColors.textSecond),
        ),
      );
}

class _RoleIconPainter extends CustomPainter {
  final Color color;

  const _RoleIconPainter(this.color);

  static const _left = 0.05, _top = 0.06, _right = 0.95, _bottom = 0.94;
  static const _radius = 0.24;
  static const _cx = (_left + _right) / 2;
  static const _upTop = 0.30, _upBottom = 0.38; // по макушке — влево
  static const _lowTop = 0.66, _lowBottom = 0.74; // по плечам — вправо
  static const _shift = 0.05;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final w = size.width, h = size.height;
    final u0 = s * _upTop, u1 = s * _upBottom;
    final l0 = s * _lowTop, l1 = s * _lowBottom;

    // Значок рисуется по частям: три несдвинутых куска и две полосы со
    // сдвигом — тот же приём, что у логотипа (слои с обрезкой по высоте).
    // Обрезка без сглаживания — иначе на стыках частей видна тонкая щель.
    void part(double from, double to, double dx) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, from, w, to), doAntiAlias: false);
      canvas.translate(dx, 0);
      _body(canvas, s);
      canvas.restore();
    }

    part(0, u0, 0);
    part(u1, l0, 0);
    part(l1, h, 0);
    part(u0, u1, -s * _shift);
    part(l0, l1, s * _shift);
  }

  void _body(Canvas canvas, double s) {
    canvas.saveLayer(null, Paint());
    canvas.drawRRect(
      RRect.fromLTRBR(s * _left, s * _top, s * _right, s * _bottom, Radius.circular(s * _radius)),
      Paint()..color = color,
    );
    final cut = Paint()..blendMode = BlendMode.clear;
    canvas.drawCircle(Offset(s * _cx, s * 0.36), s * 0.13, cut);
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, s, s * 0.82));
    canvas.drawOval(Rect.fromLTRB(s * (_cx - 0.27), s * 0.58, s * (_cx + 0.27), s * 1.06), cut);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RoleIconPainter old) => old.color != color;
}

class RoleChip extends StatelessWidget {
  final Widget? lead;
  final String label;

  final VoidCallback? onRemove;

  final double scale;

  const RoleChip({super.key, this.lead, required this.label, this.scale = 1, this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
        decoration: BoxDecoration(
          color: GlitchColors.bgInput,
          borderRadius: BorderRadius.circular(8 * scale),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (lead != null) ...[
              lead!,
              SizedBox(width: 6 * scale),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5 * scale, color: GlitchColors.textPrimary),
              ),
            ),
            if (onRemove != null) ...[
              SizedBox(width: 4 * scale),
              GlitchTooltip(
                message: context.s.tipRemoveRole,
                child: GlitchPressable(
                  onTap: onRemove,
                  child: Icon(Icons.close_rounded, size: 13 * scale, color: GlitchColors.textPrimary),
                ),
              ),
            ],
          ],
        ),
      );
}

class MemberRoleChip extends StatelessWidget {
  final MemberRole role;

  final double scale;

  final VoidCallback? onRemove;

  const MemberRoleChip({super.key, required this.role, this.scale = 1, this.onRemove});

  @override
  Widget build(BuildContext context) => RoleChip(
        lead: RoleIcon(color: role.color, size: 12 * scale),
        label: role.name,
        scale: scale,
        onRemove: onRemove,
      );
}

class MemberRolesMore extends StatelessWidget {
  final List<MemberRole> roles;

  final int hidden;

  const MemberRolesMore({super.key, required this.roles, required this.hidden});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (btnContext) => GlitchPressable(
        onTap: () => openGlitchPopup(
          btnContext,
          growRight: true,
          width: _kPopupWidth,
          builder: (_, maxHeight) => _RoleListPopup(roles: roles, maxHeight: maxHeight),
        ),
        child: RoleChip(label: '+$hidden'),
      ),
    );
  }
}

class _RoleListPopup extends StatefulWidget {
  final List<MemberRole> roles;
  final double maxHeight;

  const _RoleListPopup({required this.roles, required this.maxHeight});

  @override
  State<_RoleListPopup> createState() => _RoleListPopupState();
}

class _RoleListPopupState extends State<_RoleListPopup> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlitchPopupCard(
        maxHeight: widget.maxHeight,
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: ListView.builder(
            controller: _scroll,
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: widget.roles.length,
            itemBuilder: (context, i) =>
                _RoleLine(color: widget.roles[i].color, name: widget.roles[i].name),
          ),
        ),
      );
}

class _RoleLine extends StatelessWidget {
  final String? color;
  final String name;
  final Widget? trailing;

  final bool dimmed;
  final VoidCallback? onTap;

  const _RoleLine({
    required this.color,
    required this.name,
    this.trailing,
    this.dimmed = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClickableCursor(
      enabled: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              RoleIcon(color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: dimmed ? GlitchColors.textSecond : GlitchColors.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class MemberRolePicker extends StatelessWidget {
  final List<ServerRole> roles;

  final List<MemberRole> memberRoles;

  final Future<ServerMember> Function(ServerRole role, bool grant) onToggle;

  final String? error;

  final VoidCallback onRetry;

  const MemberRolePicker({
    super.key,
    required this.roles,
    required this.memberRoles,
    required this.onToggle,
    required this.onRetry,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (btnContext) => GlitchPressable(
        onTap: () => openGlitchPopup(
          btnContext,
          growRight: true,
          width: _kPopupWidth,
          builder: (close, maxHeight) => _RolePickerPopup(
            roles: roles,
            initial: {for (final r in memberRoles) r.id},
            onToggle: onToggle,
            close: close,
            error: error,
            onRetry: () {
              close();
              onRetry();
            },
            maxHeight: maxHeight,
          ),
        ),
        child: GlitchTooltip(
          message: context.s.tipAddRole,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: GlitchColors.bgInput,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.add_rounded, size: 18, color: GlitchColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

const int _kSearchFrom = 8;

const double _kPopupWidth = 268;

class _RolePickerPopup extends StatefulWidget {
  final List<ServerRole> roles;
  final Set<int> initial;
  final Future<ServerMember> Function(ServerRole role, bool grant) onToggle;
  final String? error;
  final VoidCallback onRetry;
  final double maxHeight;

  final Future<void> Function() close;

  const _RolePickerPopup({
    required this.roles,
    required this.initial,
    required this.onToggle,
    required this.close,
    required this.error,
    required this.onRetry,
    required this.maxHeight,
  });

  @override
  State<_RolePickerPopup> createState() => _RolePickerPopupState();
}

class _RolePickerPopupState extends State<_RolePickerPopup> {
  final _search = TextEditingController();
  final _listScroll = ScrollController();

  late final Set<int> _mine = {...widget.initial};

  bool _picked = false;

  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  Future<void> _toggle(ServerRole role) async {
    if (_picked) return;
    _picked = true;
    final grant = !_mine.contains(role.id);
    unawaited(widget.close());
    try {
      await widget.onToggle(role, grant);
    } catch (_) {
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    // Совпадение — общее правило (core/text_match.dart).
    final shown = widget.roles.where((r) => matchesQuery(_query, [r.name])).toList();
    final withSearch = widget.roles.length >= _kSearchFrom;

    return GlitchPopupCard(
      maxHeight: widget.maxHeight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (withSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: GlitchSearchField(
                controller: _search,
                hint: s.serverRolesSearch,
                height: 40,
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
          if (widget.error != null)
            _errorBlock(s, widget.error!)
          else if (widget.roles.isEmpty)
            _hint(s.serverMemberRolesEmpty)
          else if (shown.isEmpty)
            _hint(s.serverRolesNotFound)
          else
            Flexible(
              child: Scrollbar(
                controller: _listScroll,
                thumbVisibility: true,
                child: ListView.builder(
                  controller: _listScroll,
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: shown.length,
                  itemBuilder: (context, i) => _row(shown[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _errorBlock(S s, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.3, color: GlitchColors.textSecond),
            ),
            TextButton(
              onPressed: widget.onRetry,
              child: Text(s.retry, style: TextStyle(color: GlitchColors.accentBlue)),
            ),
          ],
        ),
      );

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, height: 1.3, color: GlitchColors.textSecond),
        ),
      );

  Widget _row(ServerRole role) {
    final checked = _mine.contains(role.id);
    final can = role.canEdit && !_picked;
    return _RoleLine(
      color: role.color,
      name: role.name,
      dimmed: !role.canEdit,
      onTap: can ? () => _toggle(role) : null,
      trailing: GlitchCheckMark(value: checked, enabled: role.canEdit),
    );
  }
}
