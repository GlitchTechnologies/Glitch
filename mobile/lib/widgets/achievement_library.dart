import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/platform_info.dart';
import '../core/date_text.dart';
import '../models/achievement.dart';
import '../providers/achievement_collection.dart';
import '../providers/achievement_arrangement.dart';
import 'glitch_tooltip.dart';
import '../theme/app_theme.dart';
import 'achievement_picture.dart';
import 'glitch_action_button.dart';
import 'glitch_pressable.dart';
import 'mouse_draggable.dart';

class AchievementLibrary extends StatelessWidget {
  final AchievementCollection collection;
  final AchievementArrangement? arrangement;
  final bool editingEnabled;
  final ValueChanged<Achievement> onOpenAchievement;

  const AchievementLibrary({super.key, required this.collection, this.arrangement, this.editingEnabled = true, required this.onOpenAchievement});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: collection,
        builder: (context, _) {
          final items = collection.items;
          if (items == null && collection.loading) {
            return Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue)),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (arrangement != null && items != null && items.isNotEmpty)
                Padding(
                  key: const ValueKey('arrangeHint'),
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(context.s.achievementArrangeHint,
                      style: TextStyle(color: GlitchColors.textSecond, height: 1.4)),
                ),
              if (collection.failed)
                Padding(
                  key: const ValueKey('error'),
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      Text(context.s.errorLoad, style: TextStyle(color: GlitchColors.textPrimary)),
                      const SizedBox(height: 12),
                      GlitchActionButton(
                        label: context.s.retry,
                        soft: true,
                        compact: true,
                        onTap: () { collection.load(); },
                      ),
                    ],
                  ),
                ),
              if (items != null && items.isEmpty)
                Padding(
                  key: const ValueKey('empty'),
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    context.s.achievementsEmpty,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary),
                  ),
                ),
              if (items != null && items.isNotEmpty)
                LayoutBuilder(
                  key: const ValueKey('items'),
                  builder: (context, box) {
                    const gap = 12.0;
                    final columns = ((box.maxWidth + gap) / (170 + gap)).floor().clamp(1, 4);
                    final width = (box.maxWidth - gap * (columns - 1)) / columns;
                    final categories = [
                      ('cup', context.s.achievementCups),
                      ('medal', context.s.achievementMedals),
                      ('badge', context.s.achievementBadges),
                    ];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final category in categories)
                          if (items.any((item) => item.category == category.$1))
                            Padding(
                              key: ValueKey(category.$1),
                              padding: const EdgeInsets.only(bottom: 24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(category.$2, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: gap,
                                    runSpacing: gap,
                                    children: [
                                      for (final item in items.where((item) => item.category == category.$1))
                                        SizedBox(
                                          key: ValueKey(item.id),
                                          width: width,
                                          child: _editableTile(context, item),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                      ],
                    );
                  },
                ),
              if (items != null && items.any((item) => item.acquiredAt != null))
                _AchievementHistory(key: const ValueKey('history'), items: items),
            ],
          );
        },
      );

  Widget _editableTile(BuildContext context, Achievement item) {
    final tile = GlitchPressable(onTap: editingEnabled ? () => onOpenAchievement(item) : null,
        child: _AchievementTile(achievement: item));
    final draft = arrangement;
    if (draft == null) return tile;
    final feedback = Transform.translate(
      offset: const Offset(-28, -28),
      child: Material(
        type: MaterialType.transparency,
        child: AchievementPicture(achievement: item, size: 56),
      ),
    );
    final faded = Opacity(opacity: 0.4, child: tile);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasPointerInput)
          MouseDraggable<Achievement>(
            key: ValueKey(('mouse', item.id)),
            data: item,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            maxSimultaneousDrags: editingEnabled ? 1 : 0,
            onDragStarted: GlitchTooltip.hide,
            feedback: feedback,
            childWhenDragging: faded,
            child: tile,
          )
        else LongPressDraggable<Achievement>(
          key: ValueKey(('touch', item.id)),
          data: item,
          delay: const Duration(milliseconds: 400),
          dragAnchorStrategy: pointerDragAnchorStrategy,
          maxSimultaneousDrags: editingEnabled ? 1 : 0,
          onDragStarted: GlitchTooltip.hide,
          feedback: feedback,
          childWhenDragging: faded,
          child: tile,
        ),
        const SizedBox(height: 8),
        GlitchActionButton(
          label: draft.selectedId == item.id ? context.s.cancel : context.s.achievementPlace,
          soft: true, compact: true,
          onTap: editingEnabled ? () => draft.select(item.id) : null,
        ),
      ],
    );
  }
}

class _AchievementHistory extends StatelessWidget {
  final List<Achievement> items;
  const _AchievementHistory({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final history = items.where((item) => item.acquiredAt != null).toList()
      ..sort((a, b) => b.acquiredAt!.compareTo(a.acquiredAt!));
    final now = DateTime.now();
    // Разница местных календарных дат. UTC здесь лишь для арифметики:
    // переход летнего времени не превращает сутки в 23 или 25 часов.
    final today = DateTime.utc(now.year, now.month, now.day);
    String stamp(DateTime date) {
      final days = today.difference(DateTime.utc(date.year, date.month, date.day)).inDays;
      return '${formatDay(date)} (${context.s.achievementDaysAgo(days < 0 ? 0 : days)})';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: GlitchColors.border),
        const SizedBox(height: 24),
        Text(context.s.achievementHistory, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
        const SizedBox(height: 12),
        for (final item in history)
          Padding(
            key: ValueKey(item.id),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary)),
                const SizedBox(height: 4),
                Text(
                  stamp(item.acquiredAt!),
                  style: TextStyle(fontSize: 12.5, color: GlitchColors.textSecond),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AchievementTile extends StatelessWidget {
  final Achievement achievement;
  const _AchievementTile({required this.achievement});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: GlitchColors.bgCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: AchievementPicture(achievement: achievement, size: 100)),
            const SizedBox(height: 14),
            Text(achievement.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
            const SizedBox(height: 6),
            Text(achievement.description, style: TextStyle(fontSize: 13, height: 1.4, color: GlitchColors.textPrimary)),
          ],
        ),
      );
}
