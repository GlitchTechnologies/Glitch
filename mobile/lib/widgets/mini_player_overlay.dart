import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../main.dart';
import '../providers/mini_player_provider.dart';
import '../screens/media_viewer_screen.dart';
import 'floating_window.dart';
import 'glitch_pressable.dart' show ClickableCursor;

class MiniPlayerOverlay extends StatefulWidget {
  const MiniPlayerOverlay({super.key});

  @override
  State<MiniPlayerOverlay> createState() => _MiniPlayerOverlayState();
}

class _MiniPlayerOverlayState extends State<MiniPlayerOverlay> {
  static const _longSide = 165.0; // было 150 (+10%)
  static const _tapGrowFactor = 1.1;
  static const _controlsAnimDuration = Duration(milliseconds: 180);
  static const _controlsHideDelay = Duration(milliseconds: 2500);

  Size _windowSizeFor(double? aspectRatio) {
    final ar = (aspectRatio == null || aspectRatio <= 0)
        ? 16 / 9
        : aspectRatio.clamp(0.5, 1.9);
    return ar >= 1 ? Size(_longSide, _longSide / ar) : Size(_longSide * ar, _longSide);
  }

  bool _controlsVisible = false;
  Timer? _controlsHideTimer;

  @override
  void dispose() {
    _controlsHideTimer?.cancel();
    super.dispose();
  }

  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(_controlsHideDelay, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _onSingleTap() {
    setState(() => _controlsVisible = true);
    _scheduleControlsHide();
  }

  void _onDoubleTap() {
    _controlsHideTimer?.cancel();
    _controlsVisible = false;
    _expand();
  }

  void _togglePlayPause() {
    miniPlayer.togglePlay();
    _scheduleControlsHide(); // взаимодействие продлевает показ контролов
  }

  void _expand() {
    final url = miniPlayer.url;
    final ar = miniPlayer.aspectRatio;
    final release = miniPlayer.releaseForExpand();
    if (release == null) return;
    openMediaViewer(
      context,
      navigator: navigatorKey.currentState,
      items: [MediaItem(url: url ?? '', isVideo: true, aspectRatio: ar)],
      initialPosition: release.position,
      adoptedPlayer: release.player,
      adoptedVideoController: release.controller,
      senderName: _expandName,
      senderNickname: _expandNickname,
      senderAvatarUrl: _expandAvatar,
      senderAvatarSizes: _expandAvatarSizes,
      time: _expandTime,
      colorIndex: _expandColorIndex,
    );
  }

  String _expandName = '';
  String _expandNickname = '';
  String? _expandAvatar;
  Map<String, String>? _expandAvatarSizes;
  String _expandTime = '';
  int _expandColorIndex = 0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: miniPlayer,
      builder: (context, _) {
        if (!miniPlayer.isVisible || miniPlayer.videoController == null) {
          _controlsVisible = false;
          _controlsHideTimer?.cancel();
          return const SizedBox.shrink();
        }

        _expandName = miniPlayer.senderName;
        _expandNickname = miniPlayer.senderNickname;
        _expandAvatar = miniPlayer.senderAvatarUrl;
        _expandAvatarSizes = miniPlayer.senderAvatarSizes;
        _expandTime = miniPlayer.time;
        _expandColorIndex = miniPlayer.colorIndex;

        return FloatingWindow(
          size: _windowSizeFor(miniPlayer.aspectRatio),
          scale: miniPlayer.sizeScale,
          onScaleChanged: miniPlayer.setSizeScale,
          corner: miniPlayer.windowCorner,
          onCornerChanged: miniPlayer.setWindowCorner,
          onTap: _onSingleTap,
          onDoubleTap: _onDoubleTap,
          builder: (context, size) => AnimatedScale(
            scale: _controlsVisible ? _tapGrowFactor : 1.0,
            duration: _controlsAnimDuration,
            curve: Curves.easeOut,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: size.width,
                height: size.height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 18, offset: const Offset(0, 6)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: Colors.black),
                      Video(
                        controller: miniPlayer.videoController!,
                        controls: NoVideoControls,
                        fit: BoxFit.cover,
                      ),
                      AnimatedOpacity(
                        opacity: _controlsVisible ? 1.0 : 0.0,
                        duration: _controlsAnimDuration,
                        child: IgnorePointer(
                          ignoring: !_controlsVisible,
                          child: Container(color: Colors.black.withOpacity(0.25)),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: ClickableCursor(
                          child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => miniPlayer.close(),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.55),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                          ),
                        ),
                        ),
                      ),
                      if (!miniPlayer.playing && !_controlsVisible)
                        const Center(
                          child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
                        ),
                      if (_controlsVisible)
                        Center(
                          child: ClickableCursor(
                            child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _togglePlayPause,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                miniPlayer.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white, size: 22,
                              ),
                            ),
                          ),
                          ),
                        ),
                      if (_controlsVisible)
                        const Positioned(
                          left: 6,
                          bottom: 6,
                          child: IgnorePointer(
                            child: Icon(Icons.open_in_full_rounded, color: Colors.white, size: 15),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
