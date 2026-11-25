import 'package:flutter/material.dart';

import '../core/glitch_plus_gate.dart';
import '../core/l10n.dart';
import '../core/own_account_open.dart' show openMySettings;
import '../core/platform_info.dart' show hasPointerInput;
import '../models/server.dart';
import '../models/sticker.dart';
import '../models/user.dart' show User;
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glitch_action_button.dart';
import '../widgets/glitch_plus_badge.dart' show GlitchPlusBolt;
import '../widgets/glitch_pressable.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/settings_parts.dart';
import '../widgets/settings_two_pane.dart';
import '../widgets/sticker_form.dart';
import '../widgets/sticker_view.dart';
import 'user_settings_window.dart' show UserSettingsSection;

class ServerStickersSection extends StatefulWidget {
  final ServerDetail server;
  final Widget? header;

  const ServerStickersSection({super.key, required this.server, this.header});

  @override
  State<ServerStickersSection> createState() => _ServerStickersSectionState();
}

class _ServerStickersSectionState extends State<ServerStickersSection> {
  ServerStickersPage? _page;
  String? _error;

  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final page = await api.getServerStickers(widget.server.id);
      if (mounted) setState(() => _page = page);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  void _replace(List<Sticker> stickers) {
    final page = _page;
    if (page != null) setState(() => _page = page.withStickers(stickers));
  }

  Future<void> _add() async {
    final page = _page;
    if (page == null) return;
    if (page.stickers.length >= page.freeLimit) {
      final s = context.s;
      final allowed = await ensureGlitchPlus(
        context,
        title: s.stickersPlusPromoTitle,
        body: s.stickersPlusPromoBody(page.freeLimit, page.limit),
      );
      if (!allowed || !mounted) return;
    }
    final made = await openStickerForm(context, serverId: widget.server.id);
    if (made == null || !mounted) return;
    _replace([...?_page?.stickers, made]);
  }

  Future<void> _edit(Sticker sticker) async {
    final saved = await openStickerForm(context, serverId: widget.server.id, sticker: sticker);
    if (saved == null || !mounted) return;
    _replace([for (final st in _page?.stickers ?? const <Sticker>[]) st.id == saved.id ? saved : st]);
  }

  Future<void> _delete(Sticker sticker) async {
    if (!_busy.add(sticker.id)) return;
    try {
      await api.deleteSticker(widget.server.id, sticker.id);
      if (!mounted) return;
      _replace([for (final st in _page?.stickers ?? const <Sticker>[]) if (st.id != sticker.id) st]);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      _busy.remove(sticker.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final page = _page;
    final header = widget.header;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, header != null ? SettingsTwoPane.topPad : 18, 16, 40),
      children: [
        if (header != null) ...[header, const SizedBox(height: 22)],
        Text(s.stickersSectionHint, style: TextStyle(fontSize: 14.5, color: GlitchColors.textPrimary)),
        const SizedBox(height: 18),
        if (page == null)
          _error != null
              ? SettingsRetry(text: _error!, onRetry: _load)
              : const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
        else
          ValueListenableBuilder<User?>(
            valueListenable: authService.currentUserListenable,
            builder: (context, me, _) => _buildSlots(page, me?.isGlitchPlus == true),
          ),
      ],
    );
  }

  Widget _buildSlots(ServerStickersPage page, bool plus) {
    final s = context.s;
    final free = page.stickers.take(page.freeLimit).toList();
    final extra = page.stickers.skip(page.freeLimit).toList();
    final plusSlots = page.limit - page.freeLimit;
    final full = page.stickers.length >= page.limit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SlotsCard(
          title: Text(s.stickersFreeSlots, style: _titleStyle),
          subtitle: s.stickersSlotsUsed(free.length, page.freeLimit),
          trailing: page.canManage
              ? GlitchActionButton(label: s.stickerUploadAction, compact: true, onTap: full ? null : _add)
              : null,
          child: _SlotGrid(
            stickers: free,
            slots: page.freeLimit,
            cell: _cell,
            onEmptyTap: page.canManage && !full ? _add : null,
          ),
        ),
        const SizedBox(height: 20),
        _SlotsCard(
          title: Row(
            children: [
              const GlitchPlusBolt(size: 20),
              const SizedBox(width: 8),
              Text('Glitch+', style: _titleStyle),
            ],
          ),
          subtitle: plus || extra.isNotEmpty ? s.stickersSlotsUsed(extra.length, plusSlots) : null,
          trailing: plus ? null : Icon(Icons.lock_rounded, size: 22, color: GlitchColors.textSecond),
          child: plus
              ? _SlotGrid(
                  stickers: extra,
                  slots: (extra.length + 1).clamp(_SlotGrid.columnsMax, plusSlots).toInt(),
                  roundUpToRow: true,
                  cell: _cell,
                  onEmptyTap: page.canManage && !full ? _add : null,
                )
              : Column(
                  children: [
                    if (extra.isNotEmpty) ...[
                      _SlotGrid(stickers: extra, slots: extra.length, cell: _cell, onEmptyTap: null),
                      const SizedBox(height: 18),
                    ],
                    const _EmptySlotIcon(size: 64),
                    const SizedBox(height: 12),
                    Text(s.stickersPlusSlots(plusSlots),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary)),
                    const SizedBox(height: 14),
                    GlitchActionButton(
                      label: s.stickersPlusGet,
                      compact: true,
                      onTap: () => openMySettings(context, section: UserSettingsSection.glitchPlus),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
        ),
      ],
    );
  }

  static TextStyle get _titleStyle =>
      TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary);

  Widget _cell(Sticker st) {
    final page = _page;
    final manage = page != null && page.canManage;
    return _StickerCell(
      sticker: st,
      onEdit: manage ? () => _edit(st) : null,
      onDelete: manage ? () => _delete(st) : null,
    );
  }
}

class _SlotsCard extends StatelessWidget {
  final Widget title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  const _SlotsCard({required this.title, required this.subtitle, required this.trailing, required this.child});

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    final end = trailing;
    return Container(
      decoration: BoxDecoration(
        color: GlitchColors.bgCard,
        border: Border.all(color: GlitchColors.borderCard),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      if (sub != null) ...[
                        const SizedBox(height: 3),
                        Text(sub, style: TextStyle(fontSize: 13, color: GlitchColors.textSecond)),
                      ],
                    ],
                  ),
                ),
                if (end != null) ...[const SizedBox(width: 12), end],
              ],
            ),
          ),
          Container(height: 1, color: GlitchColors.border),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}

class _SlotGrid extends StatelessWidget {
  final List<Sticker> stickers;
  final int slots;
  final bool roundUpToRow;
  final Widget Function(Sticker) cell;
  final VoidCallback? onEmptyTap;

  const _SlotGrid({
    required this.stickers,
    required this.slots,
    this.roundUpToRow = false,
    required this.cell,
    required this.onEmptyTap,
  });

  static const int columnsMax = 5;
  static const double _gap = 10;
  static const double _minCell = 96;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final columns = ((box.maxWidth + _gap) / (_minCell + _gap)).floor().clamp(3, columnsMax).toInt();
        final side = (box.maxWidth - _gap * (columns - 1)) / columns;
        var total = slots < stickers.length ? stickers.length : slots;
        if (roundUpToRow) total = (total / columns).ceil() * columns;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (var i = 0; i < total; i++)
              SizedBox(
                key: ValueKey(i < stickers.length ? 'st-${stickers[i].id}' : 'empty-$i'),
                width: side,
                height: side,
                child: i < stickers.length ? cell(stickers[i]) : _EmptySlot(onTap: onEmptyTap),
              ),
          ],
        );
      });
}

class _StickerCell extends StatelessWidget {
  final Sticker sticker;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _StickerCell({required this.sticker, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final edit = onEdit;
    final delete = onDelete;
    return GlitchHoverArea(
      onTap: edit,
      builder: (_, active) => Stack(
        children: [
          Positioned.fill(
            key: const ValueKey('body'),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
              decoration: BoxDecoration(
                color: GlitchColors.bgInput,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (_, box) => StickerView(sticker: sticker.toParsed(), size: box.biggest.shortestSide),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${sticker.emoji} ${sticker.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary),
                  ),
                ],
              ),
            ),
          ),
          if (edit != null && delete != null && (active || !hasPointerInput))
            Positioned(
              key: const ValueKey('actions'),
              top: 4,
              right: 4,
              child: Column(
                children: [
                  _CircleAction(icon: Icons.edit_rounded, color: GlitchColors.textPrimary, onTap: edit),
                  const SizedBox(height: 4),
                  _CircleAction(icon: Icons.close_rounded, color: GlitchColors.error, onTap: delete),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CircleAction({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GlitchPressable(
        onTap: onTap,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: GlitchColors.bgMenu,
            shape: BoxShape.circle,
            border: Border.all(color: GlitchColors.borderMenu),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
      );
}

class _EmptySlot extends StatelessWidget {
  final VoidCallback? onTap;

  const _EmptySlot({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final slot = CustomPaint(
      painter: _DashedRRectPainter(color: GlitchColors.borderCard, radius: 10),
      child: const Center(child: _EmptySlotIcon(size: 40)),
    );
    return onTap == null ? slot : GlitchPressable(onTap: onTap, child: slot);
  }
}

class _EmptySlotIcon extends StatelessWidget {
  final double size;

  const _EmptySlotIcon({required this.size});

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.sticky_note_2_outlined, size: size, color: GlitchColors.textSecond);
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedRRectPainter({required this.color, required this.radius});

  static const double _dash = 6;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(0.6));
    for (final m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += _dash + _gap) {
        canvas.drawPath(m.extractPath(d, (d + _dash).clamp(0, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) => old.color != color || old.radius != radius;
}
