import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/permissions.dart';
import '../core/platform_info.dart';
import '../models/server.dart' show Room;
import '../models/voice_pass.dart' show VoiceStateInfo;
import '../providers/voice_channels.dart';
import '../services/api_service.dart' show api;
import '../services/auth_service.dart' show authService;
import '../theme/app_theme.dart';
import 'glitch_menu.dart';
import 'live_badge.dart';
import 'stream_watch_preview.dart';
import 'voice_controls.dart';

class StreamPreviewHover extends StatefulWidget {
  final Room room;
  final VoiceStateInfo state;
  final Widget child;

  const StreamPreviewHover({super.key, required this.room, required this.state, required this.child});

  @override
  State<StreamPreviewHover> createState() => _StreamPreviewHoverState();
}

class _StreamPreviewHoverState extends State<StreamPreviewHover> {
  static const _kOpenDelay = Duration(milliseconds: 300);

  static const _kCloseDelay = Duration(milliseconds: 200);

  static const double _kWidth = 280;

  Timer? _timer;

  bool _isOpen = false;

  Future<void> Function()? _close;
  bool _overRow = false;
  bool _overCard = false;

  bool get _shows {
    final v = widget.state;
    return hasPointerInput && (v.streaming || v.video) && v.userId != authService.currentUser?.id;
  }

  @override
  void didUpdateWidget(StreamPreviewHover old) {
    super.didUpdateWidget(old);
    if (!_shows) _hide();
  }

  @override
  void dispose() {
    _timer?.cancel();
    final close = _close;
    if (close != null) unawaited(close());
    super.dispose();
  }

  void _onRow(bool over) {
    _overRow = over;
    _schedule();
  }

  void _onCard(bool over) {
    _overCard = over;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final want = _overRow || _overCard;
    if (want && !_isOpen && _shows) {
      _timer = Timer(_kOpenDelay, _open);
    } else if (!want && _isOpen) {
      _timer = Timer(_kCloseDelay, _hide);
    }
  }

  void _hide() {
    _timer?.cancel();
    final close = _close;
    if (close != null) unawaited(close());
  }

  void _open() {
    if (!mounted || _isOpen || !_shows) return;
    _isOpen = true;
    final done = openGlitchPopup(
      context,
      width: _kWidth,
      side: GlitchPopupSide.right,
      tapOutsideCloses: false,
      builder: (close, maxHeight) {
        _close = close;
        if (!_shows || (!_overRow && !_overCard)) {
          _timer?.cancel();
          _timer = Timer(_kCloseDelay, _hide);
        }
        return MouseRegion(
          onEnter: (_) => _onCard(true),
          onExit: (_) => _onCard(false),
          child: GlitchPopupCard(
            maxHeight: maxHeight,
            child: _StreamPreviewCard(room: widget.room, state: widget.state, onWatch: _hide),
          ),
        );
      },
    );
    unawaited(done.then((_) {
      _isOpen = false;
      _close = null;
      _overCard = false;
      if (mounted) _schedule();
    }));
  }

  @override
  Widget build(BuildContext context) {
    if (!hasPointerInput) return widget.child;
    return MouseRegion(
      onEnter: (_) => _onRow(true),
      onExit: (_) => _onRow(false),
      child: widget.child,
    );
  }
}

class _StreamPreviewCard extends StatefulWidget {
  final Room room;
  final VoiceStateInfo state;
  final VoidCallback onWatch;

  const _StreamPreviewCard({required this.room, required this.state, required this.onWatch});

  @override
  State<_StreamPreviewCard> createState() => _StreamPreviewCardState();
}

class _StreamPreviewCardState extends State<_StreamPreviewCard> {
  late final Future<Uint8List?> _shot =
      api.getStreamPreview(widget.room.serverId, widget.room.id, widget.state.userId);

  @override
  Widget build(BuildContext context) {
    final v = widget.state;
    final room = widget.room;
    final here = voiceChannels.serverId == room.serverId && voiceChannels.roomId == room.id;
    final canWatch = here || room.permissions.can(Perm.connect);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.s.streamPreviewTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary),
                ),
              ),
              LiveBadge(v.streaming ? context.s.voiceBadgeScreen : context.s.voiceBadgeCamera),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: StreamWatchPreview(
                hoverOnly: true,
                onWatch: canWatch
                    ? () {
                        widget.onWatch();
                        unawaited(voiceControls.watchStream(room, v.userId, screen: v.streaming));
                      }
                    : null,
                background: ColoredBox(
                  color: Colors.black,
                  child: FutureBuilder<Uint8List?>(
                    future: _shot,
                    builder: (context, snap) {
                      final bytes = snap.data;
                      if (bytes != null) return Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true);
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                          ),
                        );
                      }
                      return Center(
                        child: Icon(
                          v.streaming ? Icons.desktop_windows_outlined : Icons.videocam_outlined,
                          size: 32,
                          color: Colors.white38,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
