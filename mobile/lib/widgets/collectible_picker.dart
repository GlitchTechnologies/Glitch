import 'package:flutter/material.dart';

import '../core/collectibles.dart';
import '../core/l10n.dart';
import '../core/name_color.dart';
import '../models/collectible.dart';
import '../theme/app_theme.dart';
import 'glitch_hover_row.dart';
import 'glitch_pressable.dart';
import 'server_roster_panel.dart' show RosterRowFrame;

/// Как в плитке нарисовать себя: аватарка (своя, с несохранённой заменой) с
/// украшением и без. Даёт редактор профиля — только он знает, какая
/// аватарка сейчас выбрана.
typedef CollectibleAvatarBuilder = Widget Function(double size, CollectibleLook? decoration, bool animate);

typedef CollectibleCardBuilder = Widget Function(CollectibleLook? effect, bool animate);

class CollectiblePicker extends StatelessWidget {
  final List<CollectionItem>? collection;
  final bool loadFailed;
  final VoidCallback onRetry;

  final CollectibleLook? Function(CollectibleKind kind) selectedOf;

  final void Function(CollectibleKind kind, CollectionItem? item)? onSelect;

  final void Function(CollectibleKind kind)? onShop;

  final CollectibleAvatarBuilder avatar;
  final CollectibleCardBuilder card;

  final String name;

  const CollectiblePicker({
    super.key,
    required this.collection,
    required this.loadFailed,
    required this.onRetry,
    required this.selectedOf,
    required this.onSelect,
    required this.onShop,
    required this.avatar,
    required this.card,
    required this.name,
  });

  static const double gap = 12;

  static const double _radius = GlitchHoverRow.radius;

  static double get contentWidth => RosterRowFrame.defaultWidth;

  static double get tileSize => (contentWidth - gap) / 2;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _section(
          key: const ValueKey('decoration'),
          title: s.profileDecorAvatar,
          kind: CollectibleKind.avatarDecoration,
          width: tileSize,
          preview: (look, animate) => SizedBox(
            width: tileSize,
            height: tileSize,
            child: Center(child: avatar(64, look, animate)),
          ),
        ),
        const SizedBox(key: ValueKey('gap1'), height: 26),
        _section(
          key: const ValueKey('effect'),
          title: s.profileDecorEffect,
          kind: CollectibleKind.profileEffect,
          width: tileSize,
          preview: (look, animate) => SizedBox(
            width: tileSize,
            child: FittedBox(fit: BoxFit.fitWidth, child: card(look, animate)),
          ),
        ),
        const SizedBox(key: ValueKey('gap2'), height: 26),
        _section(
          key: const ValueKey('nameplate'),
          title: s.profileDecorNameplate,
          kind: CollectibleKind.nameplate,
          width: contentWidth,
          preview: (look, animate) => SizedBox(
            width: contentWidth,
            height: RosterRowFrame.height,
            child: RosterRowFrame(
              nameplate: look,
              animate: animate,
              // В строке списка у человека его украшение — как увидят другие.
              avatar: avatar(
                RosterRowFrame.avatarSize,
                selectedOf(CollectibleKind.avatarDecoration),
                animate,
              ),
              name: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RosterRowFrame.nameStyle(nameColor(null)),
              ),
            ),
          ),
        ),
        if (loadFailed)
          Padding(
            key: const ValueKey('retry'),
            padding: const EdgeInsets.only(top: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.errorLoad, style: TextStyle(fontSize: 13.5, color: GlitchColors.textPrimary)),
                TextButton(onPressed: onRetry, child: Text(s.retry)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _section({
    required Key key,
    required String title,
    required CollectibleKind kind,
    required double width,
    required Widget Function(CollectibleLook? look, bool animate) preview,
  }) {
    final items = [
      for (final item in collection ?? const <CollectionItem>[])
        if (item.kind == kind.wire) item,
    ];
    final selected = selectedOf(kind)?.id;
    final select = onSelect;
    final shop = onShop;
    Widget pick(CollectionItem? item) => _Tile(
          key: ValueKey('${kind.wire}-${item?.id ?? 0}'),
          selected: item == null ? selected == null : selected == item.id,
          onTap: select == null ? null : () => select(kind, item),
          child: (active) => preview(item?.look, animateInList(active)),
        );
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: contentWidth,
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              pick(null),
              for (final item in items) pick(item),
              _Tile(
                key: ValueKey('${kind.wire}-shop'),
                selected: false,
                onTap: shop == null ? null : () => shop(kind),
                child: (_) => Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(key: const ValueKey('size'), opacity: 0, child: preview(null, false)),
                    Icon(
                      key: const ValueKey('plus'),
                      Icons.add_rounded,
                      size: 30,
                      color: GlitchColors.textPrimary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final bool selected;
  final VoidCallback? onTap;
  final Widget Function(bool active) child;

  const _Tile({super.key, required this.selected, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    const radius = CollectiblePicker._radius;
    return GlitchHoverArea(
      onTap: onTap,
      builder: (context, active) {
        final frame = selected
            ? GlitchColors.accentBlue
            : active
                ? GlitchColors.border
                : Colors.transparent;
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: GlitchColors.bgInput,
            borderRadius: BorderRadius.circular(radius),
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: frame, width: 2),
          ),
          child: child(active),
        );
      },
    );
  }
}
