import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../providers/achievement_collection.dart';
import '../providers/achievement_arrangement.dart';
import 'achievement_picture.dart';
import 'achievement_tooltip.dart';
import 'role_picker.dart' show RoleChip;
import 'glitch_pressable.dart';
import '../models/achievement.dart';
import '../theme/app_theme.dart';
import 'achievement_placeholders.dart';

class ProfileAchievements extends StatefulWidget {
  final int userId;
  final AchievementCollection? collection;
  final AchievementArrangement? arrangement;
  final bool editingEnabled;
  final VoidCallback onShowAll;
  final ValueChanged<Achievement> onOpenAchievement;
  const ProfileAchievements({super.key, required this.userId, this.collection, this.arrangement, this.editingEnabled = true, required this.onShowAll, required this.onOpenAchievement});

  @override
  State<ProfileAchievements> createState() => _ProfileAchievementsState();
}

class _ProfileAchievementsState extends State<ProfileAchievements> {
  late AchievementCollection _collection;

  @override
  void initState() {
    super.initState();
    _collection = widget.collection ?? AchievementCollection(widget.userId);
  }

  @override
  void didUpdateWidget(covariant ProfileAchievements oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId || oldWidget.collection != widget.collection) {
      if (oldWidget.collection == null) _collection.dispose();
      _collection = widget.collection ?? AchievementCollection(widget.userId);
    }
  }

  @override
  void dispose() {
    if (widget.collection == null) _collection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _collection,
        builder: (context, _) {
          final items = _collection.items == null ? null : widget.arrangement?.items ?? _collection.items;
          if (items == null || (items.isEmpty && _collection.failed)) return const SizedBox.shrink();
          return _AchievementShelf(
            child: LayoutBuilder(
              builder: (context, box) {
                const gap = 5.0;
                const compactSize = 40.48;
                final widthWithGap = box.maxWidth + gap;
                final slotsToKeep = (widthWithGap / (compactSize + gap)).floor().clamp(1, 4);
                final widthPerSlot = widthWithGap / slotsToKeep;
                final size = math.min(box.maxHeight * 0.92, math.max(compactSize, widthPerSlot - gap));
                if (items.isEmpty) return AchievementPlaceholders(size: size, gap: gap);
                final slots = (widthWithGap / (size + gap) + 1e-9).floor();
                final visible = items.length <= slots ? items.length : (slots > 0 ? slots - 1 : 0);
                final hidden = items.length - visible;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final (index, item) in items.take(visible).indexed)
                      Padding(
                        key: ValueKey('award-$index'),
                        padding: EdgeInsets.only(right: hidden > 0 || item != items[visible - 1] ? gap : 0),
                        child: _dropTarget(item, AchievementTooltip(
                          achievement: item,
                          child: _ShelfAward(
                            achievement: item,
                            size: size,
                            onTap: () {
                              if (!widget.editingEnabled) return;
                              final selected = widget.arrangement?.selectedId;
                              if (selected != null) {
                                widget.arrangement!.replace(item.id, selected);
                              } else {
                                widget.onOpenAchievement(item);
                              }
                            },
                          ),
                        )),
                      ),
                    if (hidden > 0)
                      SizedBox(
                        key: const ValueKey('more'),
                        width: box.maxWidth < size ? box.maxWidth : size,
                        height: size,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: GlitchPressable(
                            onTap: widget.onShowAll,
                            child: RoleChip(label: '+$hidden'),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          );
        },
      );

  Widget _dropTarget(Achievement item, Widget child) {
    final arrangement = widget.arrangement;
    if (arrangement == null) return child;
    return DragTarget<Achievement>(
      onWillAcceptWithDetails: (details) => widget.editingEnabled && arrangement.items.any((e) => e.id == details.data.id),
      onAcceptWithDetails: (details) {
        if (widget.editingEnabled) arrangement.replace(item.id, details.data.id);
      },
      builder: (context, candidates, rejected) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: candidates.isNotEmpty || arrangement.selectedId != null
              ? GlitchColors.accentBlue : Colors.transparent),
        ),
        child: child,
      ),
    );
  }
}

class _AchievementShelf extends StatelessWidget {
  final Widget child;
  const _AchievementShelf({required this.child});

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
                  stops: [0, 0.12, 0.88, 1],
                ).createShader(bounds),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [GlitchColors.bgInput.withOpacity(0), GlitchColors.bgInput.withOpacity(0.85)],
                    ),
                    border: Border(bottom: BorderSide(color: GlitchColors.border)),
                  ),
                ),
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: child),
        ],
      );
}

class _ShelfAward extends StatelessWidget {
  final Achievement achievement;
  final double size;
  final VoidCallback onTap;
  const _ShelfAward({required this.achievement, required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) => GlitchHoverArea(
        onTap: onTap,
        builder: (context, active) => TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: active ? 1 : 0),
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 180),
            child: AchievementPicture(key: ValueKey(achievement.id), achievement: achievement, size: size),
          ),
          builder: (context, lift, picture) => SizedBox(
            width: size,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: size * 0.22,
                  right: size * 0.22,
                  bottom: 0,
                  height: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18 * lift), blurRadius: 5)],
                    ),
                  ),
                ),
                Transform.translate(offset: Offset(0, -3 * lift), child: picture),
              ],
            ),
          ),
        ),
      );
}
