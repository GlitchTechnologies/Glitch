import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show PointerDeviceKind, PointerEvent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc show RTCVideoRenderer;
import 'package:livekit_client/livekit_client.dart'
    show AdaptiveStreamPixelDensity, VideoTrack, VideoTrackRenderer, VideoViewFit, VideoViewMirrorMode;

import '../core/avatar_color.dart';
import '../core/l10n.dart';
import 'elapsed_time.dart';
import 'glitch_tooltip.dart';
import 'stream_watch_preview.dart';
import '../models/voice_pass.dart';
import '../providers/call_provider.dart';
import '../providers/voice_channels.dart';
import '../services/app_fullscreen.dart';
import '../services/auth_service.dart';
import '../services/stage_viewing.dart';
import '../services/voice_connection.dart' show VoiceMember, voiceConnection;
import '../services/voice_debug.dart' show VideoShape, VoiceDebug;
import '../services/call_platform_web.dart'
    if (dart.library.io) '../services/call_platform_native.dart';
import '../theme/app_theme.dart';
import '../theme/glitch_icons.dart';
import '../theme/glitch_ink.dart';
import '../theme/glitch_palette.dart';
import 'glitch_avatar.dart';
import 'glitch_bar_buttons.dart' show GlitchFilledButton;
import 'glitch_hover_row.dart';
import 'glitch_split_button.dart';
import 'glitch_pressable.dart';
import 'live_badge.dart';
import 'speaking_builder.dart';
import 'glitch_menu.dart';
import 'voice_controls.dart';
import 'glitch_icon_button.dart';
import 'voice_audio_menu.dart' show VoiceAudioMenuKind, showVoiceAudioMenu, voiceAudioMenuAvailable;
import 'voice_member_menu.dart' show voiceStreamAudioItems;



const double _kTileGap = 12;

const double _kTileRadius = 10;

const double _kStripTileRadius = 8;

const double kCallTileAspect = 16 / 9;


const Color kCallBackground = Colors.black;

final GlitchPalette callInk = GlitchPalette.dark(Colors.transparent);

const double _kTileMinWidth = 176;

const double _kTileAvatarShare = 0.5;

const double _kPanelButtonSize = 44;

const double _kPanelButtonGap = 4;
const double _kPanelPadding = 4;

const double _kPanelRadius = _kPanelButtonSize * CallButton.radiusShare + _kPanelPadding;

BoxDecoration _panelDecoration() => BoxDecoration(
      color: _kPanelFill,
      borderRadius: BorderRadius.circular(_kPanelRadius),
      border: Border.all(color: _kPanelOutline),
    );

const Color _kPanelFill = Color(0xFF0A0A0C);
const Color _kPanelOutline = Color(0xFF202024);

final GlitchPalette _stageMenuInk = callInk.copyWith(bgMenu: _kPanelFill);
const EdgeInsets _kPanelMargin = EdgeInsets.fromLTRB(12, 4, 12, 10);

const double _kTopButtonSize = 32;

const double _kTopBadgeScale = 1.4;
const EdgeInsets _kTopRowPadding = EdgeInsets.fromLTRB(16, 8, 10, 0);

const Duration _kControlsHideDelay = Duration(seconds: 4);

const Duration _kControlsFade = Duration(milliseconds: 180);

const double _kStageIconButtonSize = 36;

const double _kMiniShadeHeight = 88;

const double _kMiniTextScale = 1.5;


String callStatusText(BuildContext context, CallProvider p) {
  switch (p.state) {
    case CallState.outgoing:
      return context.s.callRinging;
    case CallState.incoming:
      return context.s.callIncoming;
    case CallState.connecting:
      return context.s.callConnecting;
    case CallState.active:
      return ElapsedTime.format(p.elapsed);
    case CallState.idle:
      return context.s.callEnded;
  }
}


/// Состав учитывает подключение к звонку с другого устройства.
List<_TileData> _buildTiles(
  BuildContext context, {
  required List<CallMember> roster,
  required List<VoiceMember> media,
  required bool isGroup,
  required bool withSelf,
  Set<int> deafened = const {},
}) {
  final me = authService.currentUser;
  final myId = me?.id;
  final myName = me?.displayName ?? '';

  VoiceMember? mediaOf(int userId) {
    for (final m in media) {
      if (m.userId == userId) return m;
    }
    return null;
  }

  String? statusOf(CallMemberState state, {required bool local, required bool live}) {
    if (live) return null;
    return switch (state) {
      CallMemberState.ringing => local ? null : context.s.callRinging,
      CallMemberState.joining => context.s.callConnecting,
      CallMemberState.reconnecting => context.s.callReconnecting,
      _ => null,
    };
  }

  _TileData person(int userId, CallMember? c, VoiceMember? m) {
    final local = userId == myId;
    final name = local ? myName : (c?.displayName ?? m?.name ?? '');
    final nickname = local ? (me?.nickname ?? '') : (c?.nickname ?? m?.nickname ?? name);
    final status = c == null ? null : statusOf(c.state, local: local, live: m != null);
    return _TileData(
      key: 'u$userId:person',
      userId: userId,
      name: name,
      status: status,
      initials: GlitchAvatar.initialsFromName(name),
      avatarUrl: local ? me?.avatar : (c?.avatar ?? m?.avatar),
      avatarSizes: local ? me?.avatarSizes : null,
      color: local ? me?.avatarColor : (parseAvatarColor(c?.avatarColor) ?? m?.avatarColor),
      colorIndex: GlitchAvatar.colorFromNickname(nickname),
      video: m?.camera,
      mirror: m?.mirror ?? false,
      muted: local && withSelf ? voiceControls.micOff : (m != null && !m.micOn),
      deafened: local && withSelf ? voiceControls.deafOff : deafened.contains(userId),
      personMuted: !local && voiceConnection.isPersonMuted(userId),
    );
  }

  final tiles = <_TileData>[];
  void add(int userId, CallMember? c) {
    final m = mediaOf(userId);
    tiles.add(person(userId, c, m));
    final screen = m?.screen;
    if (screen != null) {
      tiles.add(_TileData(
        key: 'u$userId:screen',
        userId: userId,
        name: userId == myId ? myName : (c?.displayName ?? m!.name),
        colorIndex: 0,
        video: screen,
        isScreen: true,
        stream: m!.isLocal ? null : m.identity,
        watched: m.isLocal || voiceConnection.isWatching(m.identity),
        streamSound: m.screenSound,
      ));
    }
  }

  bool shownMember(CallMember c) =>
      c.state.inCall || (c.state == CallMemberState.ringing && !isGroup) || mediaOf(c.userId) != null;
  final shown = [for (final c in roster) if (shownMember(c)) c];
  final known = {for (final c in roster) c.userId};
  for (final c in shown) {
    if (c.userId != myId) add(c.userId, c);
  }
  for (final m in media) {
    if (!m.isLocal && !known.contains(m.userId)) {
      known.add(m.userId);
      add(m.userId, null);
    }
  }
  final mine = shown.where((c) => c.userId == myId).firstOrNull;
  if (myId != null && (withSelf || mine != null)) add(myId, mine);
  return tiles;
}


enum CallStageMode {
  inCall,

  incoming,

  outside,
}

class CallStage extends StatefulWidget {
  final CallStageMode mode;

  final VoiceWhere place;

  final List<CallMember> roster;
  final bool isGroup;

  final Set<int> deafened;

  final VoidCallback? onJoin;

  final void Function(int userId, Offset position)? onMemberMenu;

  final Widget? extraTile;

  final Widget? title;

  const CallStage({
    super.key,
    required this.mode,
    required this.roster,
    required this.isGroup,
    this.place = VoiceWhere.call,
    this.deafened = const {},
    this.onJoin,
    this.onMemberMenu,
    this.extraTile,
    this.title,
  });

  @override
  State<CallStage> createState() => _CallStageState();
}

class _CallStageState extends State<CallStage> {

  final _StageChrome _chrome = _StageChrome();

  @override
  void initState() {
    super.initState();
    voiceControls.changes.addListener(_onCallChanged);
    appFullscreen.addListener(_onFullscreenChanged);
    _configureChrome();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _takePendingFocus();
    });
  }

  @override
  void didUpdateWidget(CallStage old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode) _configureChrome();
  }

  @override
  void dispose() {
    voiceControls.changes.removeListener(_onCallChanged);
    appFullscreen.removeListener(_onFullscreenChanged);
    if (_fullscreen) unawaited(appFullscreen.exit());
    _chrome.dispose();
    super.dispose();
  }


  final OverlayPortalController _portal = OverlayPortalController();

  bool _ownsFullscreen = false;

  bool get _fullscreen => _ownsFullscreen && appFullscreen.value;

  void _toggleFullscreen() {
    if (_fullscreen) {
      unawaited(appFullscreen.exit());
      return;
    }
    _ownsFullscreen = true;
    unawaited(appFullscreen.enter());
  }

  void _onFullscreenChanged() {
    if (!mounted) return;
    if (!appFullscreen.value) _ownsFullscreen = false;
    setState(() {
      if (_fullscreen) {
        _portal.show();
      } else {
        _portal.hide();
      }
    });
  }

  void _configureChrome() => _chrome.configure(
        autoHide: widget.mode == CallStageMode.inCall,
        idleHide: _focus != null,
      );

  List<VoiceMember> get _media {
    if (widget.mode != CallStageMode.inCall) return const [];
    return switch (widget.place) {
      VoiceWhere.call => callProvider.members,
      VoiceWhere.channel => voiceChannels.members,
      VoiceWhere.none => const [],
    };
  }

  List<_TileData> _tiles(BuildContext context) => _buildTiles(
        context,
        roster: widget.roster,
        media: _media,
        isGroup: widget.isGroup,
        withSelf: widget.mode != CallStageMode.outside,
        deafened: widget.deafened,
      );

  void Function(_TileData tile, Offset position)? get _tileMenu {
    final menu = widget.onMemberMenu;
    if (menu == null) return null;
    return (tile, position) {
      final id = tile.userId;
      if (id != null && !tile.isScreen) menu(id, position);
    };
  }


  void _onCallChanged() {
    if (!mounted) return;
    setState(() {
      final focus = _focus;
      if (focus != null && !_tiles(context).any((t) => t.key == focus && _focusable(t))) {
        _setFocus(null);
      }
    });
    _takePendingFocus();
  }

  void _takePendingFocus() {
    if (widget.place != VoiceWhere.channel || !voiceControls.hasPendingFocus) return;
    final tiles = _tiles(context);
    final key = voiceControls.takePendingFocus(tiles.map((t) => t.key));
    if (key == null) return;
    _openTile(tiles.firstWhere((t) => t.key == key));
  }


  String? _focus;

  /// Крупным планом — только то, что видно: чужой показ — пока его смотрим.
  /// Иначе на всё место растягивалась бы размытая заставка «Смотреть стрим»
  /// (как у Discord: «Прекратить просмотр» возвращает к сетке).
  static bool _focusable(_TileData t) => t.stream == null || t.watched;

  void _setFocus(String? key) {
    if (_focus == key) return;
    _focus = key;
    _configureChrome();
  }

  void _onTileTap(_TileData tile) => _openTile(tile);

  void _openTile(_TileData tile) {
    final stream = tile.stream;
    if (stream != null && !tile.watched) voiceConnection.watch(stream);
    setState(() => _setFocus(tile.key));
  }

  void _exitFocus() => setState(() => _setFocus(null));

  VoidCallback _keepVisible(VoidCallback action) => () {
        action();
        _chrome.poke();
      };


  @override
  Widget build(BuildContext context) {
    final tiles = _tiles(context);
    _TileData? focused;
    for (final t in tiles) {
      if (t.key == _focus && _focusable(t)) focused = t;
    }
    final fullscreen = _fullscreen;
    final stage = Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: kCallBackground,
        border: fullscreen ? null : Border(bottom: BorderSide(color: GlitchColors.border)),
      ),
      child: Listener(
        onPointerDown: _chrome.pointer,
        onPointerHover: _chrome.pointer,
        child: MouseRegion(
          onEnter: (_) => _chrome.enter(),
          onExit: (_) => _chrome.exit(),
          child: _buildLayout(context, tiles, focused),
        ),
      ),
    );
    return StageOnScreen(
      where: widget.mode == CallStageMode.inCall ? widget.place : null,
      child: PopScope(
        canPop: !fullscreen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _fullscreen) _toggleFullscreen();
        },
        child: OverlayPortal.targetsRootOverlay(
          controller: _portal,
          overlayChildBuilder: (context) => Positioned.fill(
            child: CallbackShortcuts(
              bindings: {const SingleActivator(LogicalKeyboardKey.escape): _toggleFullscreen},
              child: Focus(autofocus: true, child: stage),
            ),
          ),
          child: fullscreen ? const ColoredBox(color: kCallBackground) : stage,
        ),
      ),
    );
  }

  Widget _fade(Widget child) => _ChromeFade(chrome: _chrome, child: child);

  Widget _buildLayout(BuildContext context, List<_TileData> tiles, _TileData? focused) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fade(_buildTopRow(context, focused)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: focused != null
                ? _CallTile(
                    key: ValueKey(focused.key),
                    data: focused,
                    large: true,
                    chrome: _chrome,
                    onTap: _exitFocus,
                    onMenu: _tileMenu == null ? null : (position) => _tileMenu!(focused, position),
                  )
                : _TileGrid(
                    tiles: tiles,
                    chrome: _chrome,
                    onTap: _onTileTap,
                    onMenu: _tileMenu,
                    extra: tiles.where((t) => !t.isScreen).length <= 1 ? widget.extraTile : null,
                  ),
          ),
        ),
        _fade(_buildBottom(context)),
      ],
    );
  }


  Widget _buildTopRow(BuildContext context, _TileData? focused) {
    final p = callProvider;
    final mine = widget.mode == CallStageMode.inCall;
    final myCall = mine && widget.place == VoiceWhere.call;
    final video = focused?.video;
    return Padding(
      padding: _kTopRowPadding,
      child: SizedBox(
        height: _kTopButtonSize,
        child: Row(
          children: [
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: widget.title ?? const SizedBox.shrink()),
            ),
            if (focused != null && video != null) ...[
              const SizedBox(width: 12),
              _VideoBadge(
                key: ValueKey(focused.key),
                track: video,
                label: focused.isScreen ? context.s.voiceBadgeScreen : context.s.voiceBadgeCamera,
                hovered: _chrome.over,
                scale: _kTopBadgeScale,
              ),
            ],
            if (myCall && p.canControlAudio && p.canSwitchSpeaker) ...[
              const SizedBox(width: 8),
              CallButton(
                key: const ValueKey('speaker'),
                size: _kTopButtonSize,
                icon: p.speaker ? Icons.volume_up_rounded : Icons.hearing_rounded,
                active: p.speaker,
                onTap: _keepVisible(p.toggleSpeaker),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottom(BuildContext context) {
    final panel = _buildPanel(context);
    if (widget.mode != CallStageMode.inCall) return panel;
    final fullscreen = _fullscreen;
    return Stack(
      alignment: Alignment.center,
      children: [
        panel,
        Positioned(
          right: 12,
          child: _StageIconButton(
            key: const ValueKey('fullscreen'),
            icon: fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
            onTap: _keepVisible(_toggleFullscreen),
          ),
        ),
      ],
    );
  }

  Widget _buildPanel(BuildContext context) {
    final p = callProvider;
    if (widget.mode == CallStageMode.outside) {
      return Padding(
        padding: _kPanelMargin,
        child: Center(child: GlitchFilledButton(label: context.s.groupCallJoin, onTap: widget.onJoin)),
      );
    }
    final List<Widget> buttons;
    if (widget.mode == CallStageMode.incoming) {
      buttons = [
        CallButton(
          key: const ValueKey('decline'),
          tooltip: context.s.callDecline,
          size: _kPanelButtonSize,
          icon: Icons.call_end_rounded,
          background: GlitchColors.error,
          onTap: p.decline,
        ),
        CallButton(
          key: const ValueKey('accept'),
          tooltip: context.s.callAccept,
          size: _kPanelButtonSize,
          icon: Icons.call_rounded,
          background: GlitchColors.online,
          onTap: p.accept,
        ),
      ];
    } else {
      final c = voiceControls;
      buttons = [
        CallButton(
          key: const ValueKey('camera'),
          tooltip: c.cameraOn
              ? context.s.tipCameraOff
              : c.canUseCamera
                  ? context.s.tipCameraOn
                  : context.s.tipCameraUnavailable,
          size: _kPanelButtonSize,
          icon: c.cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
          active: c.cameraOn,
          onTap: c.cameraOn || c.canUseCamera ? _keepVisible(c.toggleCamera) : null,
        ),
        CallButton(
          key: const ValueKey('mic'),
          tooltip: c.micOff ? context.s.tipUnmute : context.s.tipMute,
          size: _kPanelButtonSize,
          icon: c.micOff ? Icons.mic_off_rounded : Icons.mic_rounded,
          active: c.micOff,
          activeColor: GlitchColors.error,
          onTap: _keepVisible(() => c.tapMic(context)),
          onMenu: voiceAudioMenuAvailable(VoiceAudioMenuKind.input)
              ? (anchor) => _chrome.holdWhile(showVoiceAudioMenu(anchor, VoiceAudioMenuKind.input, ink: _stageMenuInk))
              : null,
          menuTooltip: context.s.tipInputSettings,
        ),
        if (c.showsScreenShare)
          CallButton(
            key: const ValueKey('screen'),
            tooltip: c.sharingScreen ? context.s.tipStopShare : context.s.tipShareScreen,
            size: _kPanelButtonSize,
            icon: c.sharingScreen ? GlitchIcons.screenShareStop : GlitchIcons.screenShare,
            active: c.sharingScreen,
            onTap: c.sharingScreen || c.canShareScreen ? _keepVisible(() => c.tapScreenShare(context)) : null,
            onMenu: c.sharingScreen && c.canChangeScreenSource
                ? (anchor) => _chrome.holdWhile(_openOwnStreamMenu(anchor))
                : null,
            menuTooltip: context.s.tipStreamSettings,
          ),
        CallButton(
          key: const ValueKey('hangup'),
          tooltip: c.watchingStreams ? context.s.voiceStopWatching : context.s.tipDisconnect,
          size: _kPanelButtonSize,
          icon: c.watchingStreams ? Icons.cancel_presentation_rounded : Icons.call_end_rounded,
          background: GlitchColors.error,
          onTap: c.watchingStreams ? c.stopWatchingAll : c.leave,
        ),
      ];
    }

    final panel = Center(
      child: Container(
        margin: _kPanelMargin,
        padding: const EdgeInsets.all(_kPanelPadding),
        decoration: _panelDecoration(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < buttons.length; i++) ...[
              if (i > 0) const SizedBox(width: _kPanelButtonGap),
              buttons[i],
            ],
          ],
        ),
      ),
    );
    if (widget.mode == CallStageMode.incoming || !voiceControls.showsPushToTalk) return panel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PushToTalkButton(key: const ValueKey('ptt'), chrome: _chrome),
        panel,
      ],
    );
  }
}

class _PushToTalkButton extends StatefulWidget {
  final _StageChrome chrome;

  const _PushToTalkButton({super.key, required this.chrome});

  @override
  State<_PushToTalkButton> createState() => _PushToTalkButtonState();
}

class _PushToTalkButtonState extends State<_PushToTalkButton> {
  bool _down = false;

  void _press() {
    if (_down) return;
    _down = true;
    widget.chrome.hold(true);
    voiceControls.pressPushToTalk();
  }

  void _release() {
    if (!_down) return;
    _down = false;
    widget.chrome.hold(false);
    voiceControls.releasePushToTalk();
  }

  @override
  void dispose() {
    if (_down) {
      _down = false;
      voiceControls.releasePushToTalk();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _press(),
          onPointerUp: (_) => _release(),
          onPointerCancel: (_) => _release(),
          child: ListenableBuilder(
            listenable: voiceControls.changes,
            builder: (context, _) {
              final open = voiceControls.pushToTalkOpen;
              final color = open ? Colors.white : callInk.textPrimary;
              return Container(
                padding: const EdgeInsets.all(_kPanelPadding),
                decoration: _panelDecoration(),
                child: Container(
                  height: _kPanelButtonSize,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: open ? GlitchColors.accentBlue : Colors.transparent,
                    borderRadius: BorderRadius.circular(_kPanelButtonSize * CallButton.radiusShare),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.mic_rounded, size: _kPanelButtonSize * CallButton.iconShare, color: color),
                      const SizedBox(width: 8),
                      Text(
                        context.s.voicePushToTalkHold,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
}

class _ChromeFade extends StatelessWidget {
  final _StageChrome chrome;
  final Widget child;

  const _ChromeFade({required this.chrome, required this.child});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: chrome.visible,
        builder: (context, visible, child) => AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: _kControlsFade,
          child: IgnorePointer(ignoring: !visible, child: child),
        ),
        child: child,
      );
}

class _StageIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StageIconButton({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GlitchPressable(
        onTap: onTap,
        child: SizedBox.square(
          dimension: _kStageIconButtonSize,
          child: Icon(icon, size: 26, color: callInk.textPrimary),
        ),
      );
}


class _StageChrome {
  final ValueNotifier<bool> over = ValueNotifier(false);
  final ValueNotifier<bool> visible = ValueNotifier(true);

  bool _mouse = RendererBinding.instance.mouseTracker.mouseIsConnected;

  bool get mouse => _mouse;
  bool _autoHide = false;
  bool _idleHide = false;
  bool _idle = false;
  Timer? _idleTimer;

  int _holds = 0;

  void hold(bool held) {
    if (_disposed) return;
    _holds += held ? 1 : -1;
    _restartIdle();
    _update();
  }

  Future<void> holdWhile(Future<void> work) async {
    hold(true);
    try {
      await work;
    } finally {
      hold(false);
    }
  }

  void configure({required bool autoHide, required bool idleHide}) {
    _autoHide = autoHide;
    if (_idleHide != idleHide) {
      _idleHide = idleHide;
      _restartIdle();
    }
    _update();
  }

  void enter() {
    over.value = true;
    _update();
  }

  void exit() {
    over.value = false;
    _update();
  }

  void pointer(PointerEvent e) {
    _mouse = e.kind == PointerDeviceKind.mouse;
    _restartIdle();
    _update();
  }

  void poke() {
    _restartIdle();
    _update();
  }

  void _restartIdle() {
    _idleTimer?.cancel();
    _idle = false;
    if (!_idleHide) return;
    _idleTimer = Timer(_kControlsHideDelay, () {
      _idle = true;
      _update();
    });
  }

  bool _disposed = false;

  void _update() {
    if (_disposed) return;
    visible.value = !_autoHide || _holds > 0 || (!(_idleHide && _idle) && (!_mouse || over.value));
  }

  void dispose() {
    _disposed = true;
    _idleTimer?.cancel();
    over.dispose();
    visible.dispose();
  }
}


class CallMiniStage extends StatelessWidget {
  final VideoTrack? stream;

  const CallMiniStage({super.key, this.stream});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([voiceControls.changes, voiceConnection.speakers]),
        builder: (context, _) {
          final stream = this.stream;
          if (stream != null) {
            final tile = _buildTiles(
              context,
              roster: const [],
              media: voiceConnection.members,
              isGroup: true,
              withSelf: true,
            ).where((t) => identical(t.video, stream)).firstOrNull;
            if (tile == null) return const SizedBox.shrink();
            return _MiniStream(tile: tile);
          }
          final p = callProvider;
          final speakers = voiceConnection.speakers.value;
          final tiles = _buildTiles(
            context,
            roster: p.roster,
            media: p.members,
            isGroup: p.isGroup,
            withSelf: true,
          );
          if (tiles.isEmpty) return const SizedBox.shrink();
          final myKey = 'u${authService.currentUser?.id}:person';
          final others = [for (final t in tiles) if (t.key != myKey) t];
          final main = others.where((t) => t.video != null).firstOrNull ??
              others.where((t) => speakers.contains(t.userId)).firstOrNull ??
              others.firstOrNull ??
              tiles.first;
          return _CallTile(data: main, compact: true, onTap: null);
        },
      );
}


class _TileData {
  final String key;

  final int? userId;

  final String name;

  final bool muted;

  final bool deafened;

  final bool personMuted;

  final String? status;

  final String initials;
  final String? avatarUrl;
  final Map<String, String>? avatarSizes;

  final Color? color;

  final int colorIndex;

  final VideoTrack? video;

  final bool isScreen;

  final bool mirror;

  final String? stream;

  final bool watched;

  final bool streamSound;

  const _TileData({
    required this.key,
    required this.name,
    required this.colorIndex,
    this.userId,
    this.initials = '',
    this.avatarUrl,
    this.avatarSizes,
    this.color,
    this.video,
    this.isScreen = false,
    this.mirror = false,
    this.muted = false,
    this.deafened = false,
    this.personMuted = false,
    this.status,
    this.stream,
    this.watched = true,
    this.streamSound = false,
  });
}

class _TileGrid extends StatelessWidget {
  final List<_TileData> tiles;
  final void Function(_TileData tile) onTap;
  final void Function(_TileData tile, Offset position)? onMenu;

  final Widget? extra;

  final _StageChrome? chrome;

  const _TileGrid({required this.tiles, required this.onTap, this.onMenu, this.extra, this.chrome});

  @override
  Widget build(BuildContext context) {
    final extra = this.extra;
    return LayoutBuilder(builder: (context, constraints) {
      final count = tiles.length + (extra != null ? 1 : 0);
      final fitted = _tileSize(count, constraints.maxWidth, constraints.maxHeight);
      final scroll = fitted.width < _kTileMinWidth;
      final minWidth = math.min(_kTileMinWidth, constraints.maxWidth).floorToDouble();
      final size = scroll ? Size(minWidth, (minWidth / kCallTileAspect).floorToDouble()) : fitted;
      final grid = Wrap(
        alignment: WrapAlignment.center,
        runAlignment: WrapAlignment.center,
        spacing: _kTileGap,
        runSpacing: _kTileGap,
        children: [
          for (final t in tiles)
            SizedBox(
              key: ValueKey(t.key),
              width: size.width,
              height: size.height,
              child: _CallTile(
                data: t,
                chrome: chrome,
                onTap: () => onTap(t),
                onMenu: onMenu == null ? null : (position) => onMenu!(t, position),
              ),
            ),
          if (extra != null)
            SizedBox(
              key: const ValueKey('extra-tile'),
              width: size.width,
              height: size.height,
              child: ClipRRect(borderRadius: BorderRadius.circular(_kTileRadius), child: extra),
            ),
        ],
      );
      if (!scroll) return Center(child: grid);
      return SingleChildScrollView(
        child: SizedBox(width: constraints.maxWidth, child: grid),
      );
    });
  }

  static Size _tileSize(int count, double width, double height) {
    var best = Size.zero;
    for (var cols = 1; cols <= count; cols++) {
      final rows = (count / cols).ceil();
      final cellW = (width - _kTileGap * (cols - 1)) / cols;
      final cellH = (height - _kTileGap * (rows - 1)) / rows;
      if (cellW <= 0 || cellH <= 0) continue;
      final w = math.min(cellW, cellH * kCallTileAspect).floorToDouble();
      final h = (w / kCallTileAspect).floorToDouble();
      if (w * h > best.width * best.height) best = Size(w, h);
    }
    return best;
  }
}

class _CallTile extends StatelessWidget {
  final _TileData data;

  final VoidCallback? onTap;

  final bool compact;

  final bool large;

  final void Function(Offset position)? onMenu;

  final _StageChrome? chrome;

  const _CallTile({
    super.key,
    required this.data,
    required this.onTap,
    this.compact = false,
    this.large = false,
    this.onMenu,
    this.chrome,
  });

  static Widget _shade(Alignment begin) => IgnorePointer(
        child: Container(
          height: _kMiniShadeHeight,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: begin,
              end: -begin,
              colors: [
                kCallBackground.withOpacity(0.95),
                kCallBackground.withOpacity(0.7),
                kCallBackground.withOpacity(0),
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final video = data.video;
    final chrome = this.chrome;
    final fitVideo = large && video != null;
    final pillScale = compact && chrome != null ? _kMiniTextScale : 1.0;

    final Widget content;
    if (video != null && !data.watched) {
      content = StreamWatchPreview(
        background: _BlurredVideo(track: video),
        onWatch: onTap,
      );
    } else if (video != null) {
      content = VideoTrackRenderer(
        video,
        fit: data.isScreen || large ? VideoViewFit.contain : VideoViewFit.cover,
        mirrorMode: data.mirror ? VideoViewMirrorMode.mirror : VideoViewMirrorMode.off,
        autoCenter: !fitVideo,
      );
    } else if (data.isScreen) {
      content = const SizedBox.expand();
    } else {
      content = LayoutBuilder(builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        final avatar = math.max(side * _kTileAvatarShare, 28.0);
        return Center(
          child: Container(
            padding: EdgeInsets.all(compact ? 2 : 3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white24,
            ),
            child: GlitchAvatar(
              initials: data.initials,
              size: avatar,
              colorIndex: data.colorIndex,
              imageUrl: data.avatarUrl,
              avatarSizes: data.avatarSizes,
            ),
          ),
        );
      });
    }

    final tile = ClickableCursor(
      enabled: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onSecondaryTapUp: onMenu == null ? null : (d) => onMenu!(d.globalPosition),
        onLongPressStart: onMenu == null ? null : (d) => onMenu!(d.globalPosition),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(compact ? _kStripTileRadius : _kTileRadius),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: data.isScreen || data.status != null ? kCallBackground : data.color,
              gradient: data.isScreen || data.status != null || data.color != null
                  ? null
                  : GlitchColors.avatarGradients[
                      data.colorIndex % GlitchColors.avatarGradients.length],
            ),
            child: Stack(
              fit: fitVideo ? StackFit.loose : StackFit.expand,
              children: [
                data.status != null ? Opacity(opacity: 0.45, child: content) : content,
                if (compact && chrome != null) ...[
                  Positioned(top: 0, left: 0, right: 0, child: _ChromeFade(chrome: chrome, child: _shade(Alignment.topCenter))),
                  Positioned(bottom: 0, left: 0, right: 0, child: _ChromeFade(chrome: chrome, child: _shade(Alignment.bottomCenter))),
                ],
                Positioned(
                  left: 8,
                  right: compact ? 8 + _kStageIconButtonSize : 8,
                  bottom: compact ? 6 : 12,
                  child: Align(
                    alignment: compact ? Alignment.centerLeft : Alignment.center,
                    child: chrome == null || data.status != null
                        ? _TilePill(data: data, compact: compact, scale: pillScale)
                        : ValueListenableBuilder<bool>(
                            valueListenable: chrome.visible,
                            builder: (context, visible, pill) => AnimatedOpacity(
                              opacity: visible ? 1 : 0,
                              duration: _kControlsFade,
                              child: pill,
                            ),
                            child: _TilePill(data: data, compact: compact, scale: pillScale, backdrop: !compact),
                          ),
                  ),
                ),
                if (data.isScreen && video != null && chrome != null && !large && !compact)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IgnorePointer(
                      child: _VideoBadge(track: video, label: context.s.voiceBadgeScreen, hovered: chrome.over),
                    ),
                  ),
                if (data.isScreen && video != null && data.watched && chrome != null && !compact)
                  Positioned.fill(child: _StreamMenuButton(data: data, chrome: chrome)),
                if (data.userId case final int userId when !data.isScreen)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: SpeakingBuilder(
                        userId: userId,
                        builder: (context, speaking) => speaking
                            ? DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(color: GlitchColors.online, width: compact ? 2 : 3),
                                  borderRadius: BorderRadius.circular(
                                      compact ? _kStripTileRadius : _kTileRadius),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!fitVideo) return tile;
    final centered = Center(child: tile);
    return callVideoZoomSupported ? InteractiveViewer(maxScale: 5, child: centered) : centered;
  }
}

class _StreamMenuButton extends StatefulWidget {
  final _TileData data;
  final _StageChrome chrome;

  const _StreamMenuButton({required this.data, required this.chrome});

  @override
  State<_StreamMenuButton> createState() => _StreamMenuButtonState();
}

class _StreamMenuButtonState extends State<_StreamMenuButton> {
  bool _hovered = false;
  bool _menuOpen = false;

  void _open(BuildContext anchor, {Offset? position}) {
    final stream = widget.data.stream;
    final userId = widget.data.userId;
    final s = context.s;
    if (stream == null) {
      setState(() => _menuOpen = true);
      unawaited(widget.chrome.holdWhile(_openOwnStreamMenu(anchor, position: position)).then((_) {
        if (mounted) setState(() => _menuOpen = false);
      }));
      return;
    }
    final items = <GlitchMenuItem<String>>[
      GlitchMenuItem(value: 'stopWatching', child: glitchMenuRow(Icons.cancel_presentation_rounded, s.voiceStopWatching)),
      if (userId != null) ...[
        glitchMenuDivider<String>(),
        ...voiceStreamAudioItems<String>(userId, enabled: widget.data.streamSound),
      ],
    ];
    setState(() => _menuOpen = true);
    unawaited(widget.chrome.holdWhile(_openStageStreamMenu(
      anchor,
      items: items,
      position: position,
      onSelected: (v) {
        if (v == 'stopWatching') voiceConnection.stopWatching(stream);
      },
    )).then((_) {
      if (mounted) setState(() => _menuOpen = false);
    }));
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: (details) => _open(context, position: details.globalPosition),
        child: _hoverButton(context),
      );

  Widget _hoverButton(BuildContext context) => MouseRegion(
        opaque: false,
        hitTestBehavior: HitTestBehavior.translucent,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 12),
            child: ValueListenableBuilder<bool>(
              valueListenable: widget.chrome.visible,
              builder: (context, visible, _) {
                final show = _menuOpen || (visible && (_hovered || !widget.chrome.mouse));
                return IgnorePointer(
                  ignoring: !show,
                  child: AnimatedOpacity(
                    opacity: show ? 1 : 0,
                    duration: _kControlsFade,
                    child: Builder(
                      builder: (anchor) => DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(GlitchHoverRow.radius),
                        ),
                        child: GlitchIconButton(
                          size: 30,
                          extent: 30,
                          selected: _menuOpen,
                          onTap: () => _open(anchor),
                          icon: const Icon(Icons.more_horiz_rounded, size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
}

class _MiniStream extends StatefulWidget {
  final _TileData tile;

  const _MiniStream({required this.tile});

  @override
  State<_MiniStream> createState() => _MiniStreamState();
}

class _MiniStreamState extends State<_MiniStream> {
  final _StageChrome _chrome = _StageChrome();

  @override
  void initState() {
    super.initState();
    _chrome.configure(autoHide: true, idleHide: false);
  }

  @override
  void dispose() {
    _chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tile = widget.tile;
    final stream = tile.stream;
    final c = voiceControls;
    return Listener(
      onPointerDown: _chrome.pointer,
      onPointerHover: _chrome.pointer,
      child: MouseRegion(
        onEnter: (_) => _chrome.enter(),
        onExit: (_) => _chrome.exit(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _CallTile(data: tile, compact: true, chrome: _chrome, onTap: null),
            Positioned(
              top: 8,
              left: 10,
              right: 10,
              child: _ChromeFade(
                chrome: _chrome,
                child: Row(
                  children: [
                    Icon(
                      c.where == VoiceWhere.call ? Icons.call_rounded : Icons.volume_up_rounded,
                      size: 16 * _kMiniTextScale,
                      color: callInk.textPrimary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        c.placeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13 * _kMiniTextScale,
                          fontWeight: FontWeight.w600,
                          color: callInk.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 2,
              bottom: 0,
              child: _ChromeFade(
                chrome: _chrome,
                child: stream == null
                    ? _StageIconButton(
                        key: const ValueKey('mini-stop-share'),
                        icon: GlitchIcons.screenShareStop,
                        onTap: () => c.tapScreenShare(context),
                      )
                    : _StageIconButton(
                        key: const ValueKey('mini-stop-watching'),
                        icon: Icons.cancel_presentation_rounded,
                        onTap: () => voiceConnection.stopWatching(stream),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlurredVideo extends StatefulWidget {
  final VideoTrack track;

  const _BlurredVideo({required this.track});

  @override
  State<_BlurredVideo> createState() => _BlurredVideoState();
}

const AdaptiveStreamPixelDensity _kBlurredDensity = AdaptiveStreamPixelDensity.fixed(0.1);

const double _kBlurSigma = 18;

class _BlurredVideoState extends State<_BlurredVideo> {
  rtc.RTCVideoRenderer? _renderer;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    final renderer = rtc.RTCVideoRenderer();
    await renderer.initialize();
    if (!mounted) {
      await renderer.dispose();
      return;
    }
    renderer.addListener(_onRenderer);
    setState(() => _renderer = renderer);
  }

  void _onRenderer() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final renderer = _renderer;
    if (renderer != null) {
      renderer.removeListener(_onRenderer);
      unawaited(renderer.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final renderer = _renderer;
    if (renderer == null) return const SizedBox.expand();
    return blurredVideo(
      renderer,
      VideoTrackRenderer(
        widget.track,
        fit: VideoViewFit.cover,
        cachedRenderer: renderer,
        autoDisposeRenderer: false,
        adaptiveStreamPixelDensity: _kBlurredDensity,
      ),
      _kBlurSigma,
    );
  }
}

class _VideoBadge extends StatefulWidget {
  final VideoTrack track;
  final String label;
  final ValueListenable<bool> hovered;
  final double scale;

  const _VideoBadge({super.key, required this.track, required this.label, required this.hovered, this.scale = 1});

  @override
  State<_VideoBadge> createState() => _VideoBadgeState();
}

const Color _kVideoBadgeGray = Color(0xFF4E5058);

class _VideoBadgeState extends State<_VideoBadge> {
  Timer? _timer;
  VideoShape? _shape;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.hovered.addListener(_onHover);
    _onHover();
  }

  @override
  void didUpdateWidget(_VideoBadge old) {
    super.didUpdateWidget(old);
    if (old.hovered != widget.hovered) {
      old.hovered.removeListener(_onHover);
      widget.hovered.addListener(_onHover);
    }
    if (old.track != widget.track) _shape = null;
  }

  @override
  void dispose() {
    widget.hovered.removeListener(_onHover);
    _timer?.cancel();
    super.dispose();
  }

  void _onHover() {
    if (widget.hovered.value) {
      if (_timer != null) return;
      unawaited(_measure());
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_measure()));
    } else {
      _timer?.cancel();
      _timer = null;
      if (mounted) setState(() {});
    }
  }

  Future<void> _measure() async {
    if (_busy) return;
    _busy = true;
    try {
      final shape = await VoiceDebug.measureVideo(widget.track);
      if (!mounted || _timer == null) return;
      if (shape == null || shape.height == null || shape.fps == null) return;
      setState(() => _shape = shape);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final shape = _shape;
    final height = shape?.height;
    final fps = shape?.fps;
    final k = widget.scale;
    final details = widget.hovered.value && height != null && fps != null
        ? '${height}P ${context.s.screenShareFps(fps.round())}'.toUpperCase()
        : null;
    return DecoratedBox(
      decoration: BoxDecoration(color: _kVideoBadgeGray, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: Alignment.centerRight,
            child: details == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: EdgeInsets.fromLTRB(8 * k, 2 * k, 6 * k, 2 * k),
                    child: Text(details, maxLines: 1, style: liveBadgeTextStyleOf(k)),
                  ),
          ),
          LiveBadge(widget.label, scale: k),
        ],
      ),
    );
  }
}

class _TilePill extends StatelessWidget {
  final _TileData data;
  final bool compact;

  final double scale;

  final bool backdrop;

  const _TilePill({required this.data, required this.compact, this.scale = 1, this.backdrop = true});

  @override
  Widget build(BuildContext context) {
    final k = scale;
    final iconSize = (compact ? 12.0 : 16.0) * k;
    final icons = <IconData>[
      if (data.isScreen) GlitchIcons.screenShare,
      if (!data.isScreen && data.muted) Icons.mic_off_rounded,
      if (!data.isScreen && data.deafened) Icons.headset_off_rounded,
      if (!data.isScreen && data.personMuted) Icons.volume_off_rounded,
    ];
    // Нечего подписать (имя не пришло и значков нет) — подложки нет вовсе:
    // пустая пилюля выглядела бы сломанной.
    if (icons.isEmpty && data.name.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: (compact ? 8 : 12) * k,
        vertical: (compact ? 3 : 6) * k,
      ),
      decoration: backdrop
          ? BoxDecoration(
              color: Colors.black.withOpacity(0.45),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final icon in icons)
            Padding(
              padding: EdgeInsets.only(right: (compact ? 3 : 5) * k),
              child: Icon(icon, size: iconSize, color: Colors.white),
            ),
          if (data.name.isNotEmpty)
            Flexible(
              child: Text.rich(
                TextSpan(
                  text: data.name,
                  children: [
                    if (data.status != null)
                      TextSpan(
                        text: '  ·  ${data.status}',
                        style: TextStyle(
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withOpacity(0.75),
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: (compact ? 11 : 15) * k,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CallButton extends StatelessWidget {
  final IconData icon;
  final double size;

  /// null — кнопка на месте, но пока недоступна (приглушена, не нажимается).
  final VoidCallback? onTap;
  final Color? background;
  final bool active;
  final Color activeColor;
  final String? tooltip;

  final Future<void> Function(BuildContext anchor)? onMenu;
  final String? menuTooltip;

  static const double radiusShare = GlitchHoverRow.radius / 40;

  static const double iconShare = 0.55;

  const CallButton({
    super.key,
    required this.icon,
    required this.size,
    required this.onTap,
    this.background,
    this.active = false,
    this.activeColor = GlitchColors.online,
    this.tooltip,
    this.onMenu,
    this.menuTooltip,
  });

  static const double _arrowShare = 0.5;

  @override
  Widget build(BuildContext context) {
    final fill = background;
    final ink = fill != null ? Colors.white : (active ? activeColor : callInk.textPrimary);
    final menu = onMenu;
    if (menu != null) {
      final split = GlitchSplitButton(
        icon: icon,
        onTap: onTap,
        onMenu: menu,
        tooltip: tooltip,
        menuTooltip: menuTooltip,
        height: size,
        mainWidth: size,
        arrowWidth: size * _arrowShare,
        iconSize: size * iconShare,
        radius: size * radiusShare,
        iconColor: ink,
        fill: fill,
      );
      final dark = GlitchInk(palette: callInk, child: split);
      return onTap == null ? Opacity(opacity: 0.4, child: dark) : dark;
    }
    final button = GlitchHoverArea(
      onTap: onTap,
      builder: (context, hovered) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: fill ?? GlitchHoverRow.highlight(context, active: hovered, palette: callInk),
          borderRadius: BorderRadius.circular(size * radiusShare),
        ),
        child: Icon(
          icon,
          size: size * iconShare,
          color: ink,
        ),
      ),
    );
    return GlitchTooltip(
      message: tooltip,
      child: onTap == null ? Opacity(opacity: 0.4, child: button) : button,
    );
  }
}

Future<void> _openStageStreamMenu(
  BuildContext anchor, {
  required List<GlitchMenuItem<String>> items,
  required ValueChanged<String> onSelected,
  Offset? position,
}) {
  if (position != null) {
    return showGlitchContextMenuAt<String>(anchor, position, items, onSelected, ink: _stageMenuInk);
  }
  return openGlitchMenu<String>(anchor, items: items, onSelected: onSelected, ink: _stageMenuInk);
}

Future<void> _openOwnStreamMenu(BuildContext anchor, {Offset? position}) {
  final s = anchor.s;
  final c = voiceControls;
  return _openStageStreamMenu(
    anchor,
    position: position,
    items: [
      if (c.canChangeScreenSource)
        GlitchMenuItem(value: 'source', child: glitchMenuRow(GlitchIcons.screenShare, s.voiceChangeStreamSource)),
      GlitchMenuItem(value: 'stop', child: glitchMenuRow(GlitchIcons.screenShareStop, s.voiceStopStream, danger: true)),
    ],
    onSelected: (v) {
      if (!anchor.mounted) return;
      if (v == 'source') c.changeScreenSource(anchor);
      if (v == 'stop' && c.sharingScreen) c.tapScreenShare(anchor);
    },
  );
}
