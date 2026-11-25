import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/adaptive_open.dart';
import '../models/achievement.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'achievement_model_surface.dart';
import 'achievement_picture.dart';
import 'adaptive_sheet.dart';
import 'glitch_tooltip.dart';

Future<void> openAchievement(BuildContext context, Achievement achievement) {
  GlitchTooltip.hide();
  return openAdaptiveOverlay<void>(context, builder: (_) => _AchievementOverlay(achievement: achievement));
}

class _AchievementOverlay extends StatefulWidget {
  final Achievement achievement;
  const _AchievementOverlay({required this.achievement});
  @override
  State<_AchievementOverlay> createState() => _AchievementOverlayState();
}

class _AchievementOverlayState extends State<_AchievementOverlay> {
  bool _closing = false;
  void _close() {
    if (!mounted || _closing || ModalRoute.of(context)?.isCurrent != true) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final achievement = widget.achievement;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: FocusScope(
        autofocus: true,
        child: ModalStatusBarDim(
          child: Material(
            type: MaterialType.transparency,
            child: SafeArea(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: achievement.modelUrl == null
                        ? Center(child: AchievementPicture(achievement: achievement, size: 200))
                        : AchievementModelSurface(
                            url: api.mediaUrl(achievement.modelUrl!),
                            poster: api.mediaUrl(achievement.logo),
                            onClose: _close,
                          ),
                  ),
                  AdaptiveWindowCloseButton(onPressed: _close, overPlatformView: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
