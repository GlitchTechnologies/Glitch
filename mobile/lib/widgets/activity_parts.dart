import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../models/activity.dart';
import '../services/api_service.dart' show mediaCacheManager;
import '../services/user_activities.dart';
import '../theme/app_theme.dart';
import '../theme/glitch_icons.dart';
import 'elapsed_time.dart';


class UserActivityBuilder extends StatefulWidget {
  final int userId;
  final Widget Function(BuildContext context, List<UserActivity> activities) builder;

  const UserActivityBuilder({super.key, required this.userId, required this.builder});

  @override
  State<UserActivityBuilder> createState() => _UserActivityBuilderState();
}

class _UserActivityBuilderState extends State<UserActivityBuilder> {
  late List<UserActivity> _shown = userActivities.of(widget.userId);

  @override
  void initState() {
    super.initState();
    userActivities.addListener(_onChange);
  }

  @override
  void didUpdateWidget(UserActivityBuilder old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) _shown = userActivities.of(widget.userId);
  }

  @override
  void dispose() {
    userActivities.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    final now = userActivities.of(widget.userId);
    if (!identical(now, _shown) && mounted) setState(() => _shown = now);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _shown);
}

class ActivityLine extends StatelessWidget {
  final List<UserActivity> activities;

  const ActivityLine({super.key, required this.activities});

  static const double fontSize = 13;

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) return const SizedBox.shrink();
    final activity = activities.last;
    return Row(
      children: [
        Icon(GlitchIcons.playing, size: 14, color: GlitchColors.online),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            activity.game.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: fontSize, color: GlitchColors.textSecond),
          ),
        ),
      ],
    );
  }
}
class ActivityCard extends StatelessWidget {
  final UserActivity activity;
  final bool compact;

  const ActivityCard({super.key, required this.activity, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final coverHeight = compact ? 72.0 : 100.0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GlitchColors.bgInput,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.s.activityPlaying,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Cover(game: activity.game, height: coverHeight),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.game.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 14 : 15,
                        fontWeight: FontWeight.w600,
                        color: GlitchColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(GlitchIcons.playing, size: 15, color: GlitchColors.online),
                        const SizedBox(width: 5),
                        ElapsedTime(
                          since: activity.startedAt,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class RecentActivityCard extends StatelessWidget {
  final RecentActivity activity;

  const RecentActivityCard({super.key, required this.activity});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GlitchColors.bgInput,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _Cover(game: activity.game, height: 64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.game.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(GlitchIcons.playing, size: 15, color: GlitchColors.textHint),
                    const SizedBox(width: 5),
                    Text(
                      playedAgo(context.s, activity.lastPlayedAt, DateTime.now()),
                      style: TextStyle(fontSize: 13, color: GlitchColors.textHint),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Разница считается между локальными датами, чтобы дни с переходом часов не терялись.
String playedAgo(S s, DateTime lastPlayed, DateTime now) {
  DateTime day(DateTime t) {
    final l = t.toLocal();
    return DateTime.utc(l.year, l.month, l.day);
  }

  final days = day(now).difference(day(lastPlayed)).inDays;
  if (days <= 0) return s.activityPlayedToday;
  if (days <= 6) return s.activityPlayedDaysAgo(days);
  if (days <= 13) return s.activityPlayedWeekAgo;
  if (days <= 29) return s.activityPlayedTwoWeeksAgo;
  return s.activityPlayedMonthAgo;
}

class _Cover extends StatelessWidget {
  final ActivityGame game;
  final double height;

  const _Cover({required this.game, required this.height});

  static const double _fallbackAspect = 3 / 4;

  @override
  Widget build(BuildContext context) {
    final w = game.coverWidth;
    final h = game.coverHeight;
    final aspect = (w != null && h != null && w > 0 && h > 0) ? w / h : _fallbackAspect;
    final width = height * aspect;
    final placeholder = Container(
      width: width,
      height: height,
      color: GlitchColors.bgChip,
      alignment: Alignment.center,
      child: Icon(GlitchIcons.playing, size: height * 0.36, color: GlitchColors.textHint),
    );
    final url = game.cover;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url == null
          ? placeholder
          : CachedNetworkImage(
              imageUrl: url,
              cacheManager: mediaCacheManager,
              width: width,
              height: height,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              placeholder: (_, __) => placeholder,
              errorWidget: (_, __, ___) => placeholder,
            ),
    );
  }
}
