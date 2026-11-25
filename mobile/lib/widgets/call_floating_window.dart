import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' show VideoTrack;

import '../core/adaptive_open.dart' show isWideLayout;
import '../providers/call_provider.dart';
import '../services/stage_viewing.dart';
import '../services/voice_connection.dart';
import '../theme/app_theme.dart';
import 'call_stage.dart';
import 'floating_window.dart';
import 'voice_controls.dart';

const double _kWindowLongSide = 165;
const double _kWideWindowLongSide = 330;
const double _kWindowRadius = 12;
const double _kHangupSize = 28;

/// Как выбирается содержимое мини-окна.
///  * показываю экран сам — моя демонстрация;
///  * иначе наблюдаю чью-то (`voiceConnection.lastWatched`) — она; наблюдаю
///    несколько — та, что открыл последней;
///  * иначе, только на телефоне и только у звонка, — свёрнутый звонок, как
///    раньше (с отбоем): другой плашки «вы в звонке» на телефоне нет. На
///    широком окне это делает плашка «Голосовая связь» (`VoiceDock`).
/// Плитка — та же, что на сцене ([CallMiniStage]).
class CallFloatingWindow extends StatefulWidget {
  const CallFloatingWindow({super.key});

  @override
  State<CallFloatingWindow> createState() => _CallFloatingWindowState();
}

class _CallFloatingWindowState extends State<CallFloatingWindow> {
  FloatingCorner _corner = FloatingCorner.topRight;
  double _scale = 1;

  static VideoTrack? _stream() {
    final members = voiceConnection.members;
    for (final m in members) {
      if (m.isLocal && m.screen != null) return m.screen;
    }
    final watched = voiceConnection.lastWatched;
    if (watched == null) return null;
    for (final m in members) {
      if (m.identity == watched) return m.screen;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([voiceControls.changes, stageViewing]),
        builder: (context, _) {
          final where = voiceControls.where;
          if (where == VoiceWhere.none || stageViewing.isVisible(where)) return const SizedBox.shrink();
          final wide = isWideLayout(context);
          final stream = _stream();
          final callTile = stream == null && !wide && where == VoiceWhere.call && callProvider.chatId != null;
          if (stream == null && !callTile) return const SizedBox.shrink();
          final long = wide ? _kWideWindowLongSide : _kWindowLongSide;
          return FloatingWindow(
            size: Size(long, long / kCallTileAspect),
            scale: _scale,
            onScaleChanged: (k) => setState(() => _scale = k),
            corner: _corner,
            onCornerChanged: (c) => setState(() => _corner = c),
            onDoubleTap: voiceControls.openStage,
            builder: (context, size) => Material(
              color: Colors.transparent,
              child: Container(
                width: size.width,
                height: size.height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_kWindowRadius),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 18, offset: const Offset(0, 6)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_kWindowRadius),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: kCallBackground),
                      CallMiniStage(stream: stream),
                      if (callTile)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: CallButton(
                            key: const ValueKey('floating-hangup'),
                            size: _kHangupSize,
                            icon: Icons.call_end_rounded,
                            background: GlitchColors.error,
                            onTap: voiceControls.leave,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
}
