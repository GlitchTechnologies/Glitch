import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../models/presence.dart';
import '../theme/app_theme.dart';
import '../theme/glitch_ink.dart';

String presenceLabel(BuildContext context, PresenceStatus status) => switch (status) {
      PresenceStatus.online => context.s.rosterOnline,
      PresenceStatus.idle => context.s.presenceIdle,
      PresenceStatus.dnd => context.s.presenceDnd,
      PresenceStatus.invisible => context.s.presenceInvisible,
      PresenceStatus.offline => context.s.rosterOffline,
    };

Color presenceColor(BuildContext context, PresenceStatus status) => switch (status) {
      PresenceStatus.online => GlitchColors.online,
      PresenceStatus.idle => GlitchColors.presenceIdle,
      PresenceStatus.dnd => GlitchColors.presenceDnd,
      PresenceStatus.invisible || PresenceStatus.offline => GlitchInk.of(context).textSecond,
    };

class PresenceIndicator extends StatelessWidget {
  final PresenceStatus status;
  final double size;

  const PresenceIndicator({super.key, required this.status, required this.size});

  @override
  Widget build(BuildContext context) {
    final icon = switch (status) {
      PresenceStatus.online => Icons.circle,
      PresenceStatus.idle => Icons.bedtime_rounded,
      PresenceStatus.dnd => Icons.do_not_disturb_on,
      PresenceStatus.invisible || PresenceStatus.offline => Icons.radio_button_unchecked,
    };
    return Icon(icon, size: size, color: presenceColor(context, status));
  }
}
