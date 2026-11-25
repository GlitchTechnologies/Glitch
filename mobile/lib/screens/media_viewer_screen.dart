import 'user_profile_screen.dart';
import 'dart:async';
import 'package:cross_file/cross_file.dart';
import '../services/media_actions_web.dart' if (dart.library.io) '../services/media_actions_native.dart';
import '../widgets/local_image_web.dart' if (dart.library.io) '../widgets/local_image_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import '../core/media_content.dart';
import '../core/platform_info.dart';
import '../providers/mini_player_provider.dart';
import '../widgets/animated_network_image.dart';
import '../widgets/glitch_avatar.dart';
import '../widgets/glitch_pressable.dart' show ClickableCursor;
import '../widgets/glitch_menu.dart';
import '../widgets/media_context_menu.dart';
import '../widgets/glitch_toast.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../providers/theme_provider.dart';
import '../widgets/glitch_bar_buttons.dart';
import '../widgets/glitch_dialog.dart';

class MediaItem {
  final String? url;
  final XFile? localFile;
  final bool isVideo;
  final double? aspectRatio;
  const MediaItem({this.url, this.localFile, required this.isVideo, this.aspectRatio})
      : assert(url != null || localFile != null);
}

enum ViewerShell {
  fullscreenRoute,

  overlay,
}

ViewerShell get viewerShell =>
    hasSystemBack ? ViewerShell.fullscreenRoute : ViewerShell.overlay;

const double _kOverlayScrimOpacity = 0.82;

// ЗАЧЕМ ОБЩИЙ ХЕЛПЕР, А НЕ Navigator.push НА МЕСТЕ (баг найден 2026-07-25):
// перед push обязательно снимается фокус с поля ввода. Flutter держит у
// FocusScopeNode каждого маршрута его focusedChild и на pop возвращает туда
// primary focus. Из-за этого после выхода из просмотрщика системным "назад" в
// чате сама собой всплывала клавиатура: фокус в поле ввода при открытии фото
// не сбрасывался, а запоминался, и восстанавливался на закрытии маршрута.
// Всплывала ДЁРГАНО, потому что её анимация стартовала уже посреди анимации
// закрытия маршрута — одновременно с ресайзом Scaffold по
// resizeToAvoidBottomInset и перелейаутом ленты сообщений (плюс в тот же кадр
// dispose() разбирает media_kit-плеер). Тот же механизм Flutter, что обойдён в
// widgets/message_action_menu.dart для диалога удаления (flutter#145155).
void openMediaViewer(
  BuildContext context, {
  required List<MediaItem> items,
  int initialIndex = 0,
  bool isLocalPreview = false,
  String senderName = '',
  String senderNickname = '',
  String? senderAvatarUrl,
  Map<String, String>? senderAvatarSizes,
  String time = '',
  int colorIndex = 0,
  void Function(BuildContext)? onTitleTap,
  Duration initialPosition = Duration.zero,
  Player? adoptedPlayer,
  VideoController? adoptedVideoController,
  NavigatorState? navigator,
}) {
  final focus = FocusManager.instance.primaryFocus;
  if (focus != null && focus is! FocusScopeNode) focus.unfocus();

  final nav = navigator ?? Navigator.maybeOf(context, rootNavigator: true);
  if (nav == null) return;

  final screen = MediaViewerScreen(
    items: items,
    initialIndex: initialIndex,
    isLocalPreview: isLocalPreview,
    senderName: senderName,
    senderNickname: senderNickname,
    senderAvatarUrl: senderAvatarUrl,
    senderAvatarSizes: senderAvatarSizes,
    time: time,
    colorIndex: colorIndex,
    onTitleTap: onTitleTap,
    initialPosition: initialPosition,
    adoptedPlayer: adoptedPlayer,
    adoptedVideoController: adoptedVideoController,
  );

  final route = viewerShell == ViewerShell.overlay
      // Браузер/десктоп: слой ПОВЕРХ приложения. opaque: false обязателен —
      // иначе Flutter перестаёт рисовать маршрут под нами, и затемнять было бы
      // нечего (сквозь полупрозрачный фон виднелась бы пустота). Переход —
      // проявление, как у Telegram Web и Discord: выезд снизу тут читался бы
      // как «другой экран», а это слой над тем же самым.
      ? PageRouteBuilder(
          opaque: false,
          barrierDismissible: false,
          transitionDuration: const Duration(milliseconds: 180),
          reverseTransitionDuration: const Duration(milliseconds: 140),
          pageBuilder: (_, __, ___) => screen,
          transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
        )
      : MaterialPageRoute(builder: (_) => screen, fullscreenDialog: true);

  withDimmedStatusBar(() => nav.push(route));
}

void openLocalMediaGallery(
  BuildContext context,
  List<XFile> files, {
  required int initialIndex,
  required bool Function(XFile) isVideo,
}) {
  openMediaViewer(
    context,
    items: [for (final f in files) MediaItem(localFile: f, isVideo: isVideo(f))],
    initialIndex: initialIndex,
    isLocalPreview: true,
  );
}

class MediaViewerScreen extends StatefulWidget {
  final List<MediaItem> items;
  final int initialIndex;
  final bool isLocalPreview;
  final String senderName;
  final String senderNickname;
  final String? senderAvatarUrl;
  final Map<String, String>? senderAvatarSizes;
  final String time;
  final int colorIndex;
  final void Function(BuildContext)? onTitleTap;
  final Duration initialPosition;
  final Player? adoptedPlayer;
  final VideoController? adoptedVideoController;

  const MediaViewerScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.isLocalPreview = false,
    this.senderName = '',
    this.senderNickname = '',
    this.senderAvatarUrl,
    this.senderAvatarSizes,
    this.time = '',
    this.colorIndex = 0,
    this.onTitleTap,
    this.initialPosition = Duration.zero,
    this.adoptedPlayer,
    this.adoptedVideoController,
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> with ThemeAwareState<MediaViewerScreen> {
  late final PageController _pageCtrl;
  late int _currentIndex;
  bool _uiVisible = true;
  bool _saving = false;
  bool _sharing = false;
  bool _isFullscreen = false;
  Timer? _autoHideTimer;

  late final Player _player;
  late final VideoController _videoCtrl;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _muted = false;
  double _speed = 1.0;
  late final StreamSubscription _subPlaying;
  late final StreamSubscription _subPosition;
  late final StreamSubscription _subDuration;
  final _seekKey = GlobalKey();
  double? _dragFrac;
  Duration? _pendingSeekTarget;
  Timer? _pendingSeekTimeout;
  bool _ownershipTransferred = false;

  final Map<int, TransformationController> _transforms = {};

  TransformationController _transformFor(int i) =>
      _transforms.putIfAbsent(i, () => TransformationController());

  final Map<int, GlobalKey> _mediaKeys = {};

  GlobalKey _mediaKeyFor(int i) => _mediaKeys.putIfAbsent(i, () => GlobalKey());

  final FocusNode? _keyboardFocus =
      viewerShell == ViewerShell.overlay ? FocusNode(debugLabel: 'MediaViewerKeys') : null;

  bool get _isOverlayShell => viewerShell == ViewerShell.overlay;

  bool get _isZoomed {
    final ctrl = _transforms[_currentIndex];
    return ctrl != null && ctrl.value.getMaxScaleOnAxis() > 1.01;
  }

  bool get _currentIsVideo => widget.items[_currentIndex].isVideo;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);

    final adopted = widget.adoptedPlayer;
    final adoptedCtrl = widget.adoptedVideoController;
    final isAdopted = adopted != null && adoptedCtrl != null;
    if (isAdopted) {
      _player = adopted;
      _videoCtrl = adoptedCtrl;
      final st = _player.state;
      _playing = st.playing;
      _position = st.position;
      _duration = st.duration;
    } else {
      _player = Player();
      _videoCtrl = VideoController(_player);
    }

    _subPlaying  = _player.stream.playing.listen((v) => setState(() => _playing = v));
    _subPosition = _player.stream.position.listen((v) => setState(() {
      _position = v;
      final target = _pendingSeekTarget;
      if (target != null && (v - target).inMilliseconds.abs() < 400) {
        _dragFrac = null;
        _pendingSeekTarget = null;
        _pendingSeekTimeout?.cancel();
      }
    }));
    _subDuration = _player.stream.duration.listen((v) => setState(() => _duration = v));

    if (isAdopted) {
      _scheduleAutoHide();
    } else {
      final current = widget.items[_currentIndex];
      if (current.isVideo) {
        _playVideo(current, seekTo: widget.initialPosition);
        _scheduleAutoHide();
      }
    }
  }

  @override
  void dispose() {
    // Если закрываем экран в развёрнутом (landscape) режиме — обязательно
    // возвращаем portrait, иначе всё остальное приложение (не рассчитанное
    // на альбомную ориентацию) останется повёрнутым.
    if (_isFullscreen) SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _autoHideTimer?.cancel();
    _pendingSeekTimeout?.cancel();
    _pageCtrl.dispose();
    _subPlaying.cancel();
    _subPosition.cancel();
    _subDuration.cancel();
    if (!_ownershipTransferred) _player.dispose();
    for (final c in _transforms.values) c.dispose();
    _keyboardFocus?.dispose();
    super.dispose();
  }


  bool _hitsMedia(Offset globalPos) {
    final ctx = _mediaKeys[_currentIndex]?.currentContext;
    if (ctx == null) return true;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return true;
    return (box.localToGlobal(Offset.zero) & box.size).contains(globalPos);
  }

  void _handleTapAt(Offset globalPos) {
    if (_isOverlayShell && !_hitsMedia(globalPos)) {
      Navigator.pop(context);
      return;
    }
    _toggleUi();
  }

  void _pageBy(int delta) {
    final next = _currentIndex + delta;
    if (next < 0 || next >= widget.items.length) return;
    _pageCtrl.animateToPage(next,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _pageBy(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _pageBy(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space && _currentIsVideo) {
      _player.playOrPause();
      _scheduleAutoHide();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _playVideo(MediaItem item, {Duration seekTo = Duration.zero}) async {
    try {
      setState(() { _position = seekTo; _duration = Duration.zero; });
      final local = item.localFile;
      await _player.open(local != null
          ? Media(local.path)
          : Media(item.url!, httpHeaders: api.headersFor(item.url!)));
      if (seekTo > Duration.zero) await _player.seek(seekTo);
    } catch (_) {}
  }

  void _onPageChanged(int i) {
    _transforms[_currentIndex]?.value = Matrix4.identity();
    setState(() {
      _currentIndex = i;
      _speed = 1.0;
      _muted = false;
      _uiVisible = true;
    });
    _player.setRate(1.0);
    _player.setVolume(100);
    _autoHideTimer?.cancel();

    final item = widget.items[i];
    if (item.isVideo) {
      _playVideo(item);
      _scheduleAutoHide();
    } else {
      _player.pause();
    }
  }

  void _scheduleAutoHide() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing) setState(() => _uiVisible = false);
    });
  }

  void _toggleUi() {
    setState(() => _uiVisible = !_uiVisible);
    if (_uiVisible && _currentIsVideo && _playing) _scheduleAutoHide();
  }

  void _skipBack() => _player.seek(Duration(
      seconds: (_position.inSeconds - 10).clamp(0, _duration.inSeconds)));

  void _skipFwd() => _player.seek(Duration(
      seconds: (_position.inSeconds + 10).clamp(0, _duration.inSeconds)));

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _player.setVolume(_muted ? 0 : 100);
  }

  void _cycleSpeed() {
    const speeds = [1.0, 1.5, 2.0, 0.5];
    final next = speeds[(speeds.indexOf(_speed) + 1) % speeds.length];
    setState(() => _speed = next);
    _player.setRate(next);
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    SystemChrome.setPreferredOrientations(_isFullscreen
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : [DeviceOrientation.portraitUp]);
  }

  void _minimize() {
    if (!_currentIsVideo) return;
    final item = widget.items[_currentIndex];
    _ownershipTransferred = true; // плеер уходит в мини-окно — сам не диспоузим
    miniPlayer.adopt(
      player: _player,
      controller: _videoCtrl,
      url: item.url!,
      aspectRatio: item.aspectRatio,
      senderName: widget.senderName,
      senderNickname: widget.senderNickname,
      senderAvatarUrl: widget.senderAvatarUrl,
      senderAvatarSizes: widget.senderAvatarSizes,
      time: widget.time,
      colorIndex: widget.colorIndex,
    );
    Navigator.pop(context);
  }

  double? _fracAt(Offset localOffset) {
    final ctx = _seekKey.currentContext;
    if (ctx == null || _duration == Duration.zero) return null;
    final box = ctx.findRenderObject() as RenderBox;
    return (localOffset.dx / box.size.width).clamp(0.0, 1.0);
  }

  void _seekAt(Offset localOffset) {
    final frac = _fracAt(localOffset);
    if (frac == null) return;
    _beginPendingSeek(frac);
  }

  void _dragSeek(Offset localOffset) {
    final frac = _fracAt(localOffset);
    if (frac == null) return;
    _pendingSeekTimeout?.cancel();
    _pendingSeekTarget = null;
    setState(() => _dragFrac = frac);
    _player.seek(Duration(milliseconds: (frac * _duration.inMilliseconds).round()));
  }

  void _beginPendingSeek(double frac) {
    _pendingSeekTimeout?.cancel();
    final target = Duration(milliseconds: (frac * _duration.inMilliseconds).round());
    _pendingSeekTarget = target;
    setState(() => _dragFrac = frac);
    _player.seek(target);
    _pendingSeekTimeout = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() { _dragFrac = null; _pendingSeekTarget = null; });
    });
  }

  void _endDrag() {
    if (_dragFrac == null) return;
    _beginPendingSeek(_dragFrac!);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _speedLabel {
    if (_speed == 1.0) return '1×';
    if (_speed == 0.5) return '½×';
    return '${_speed.toStringAsFixed(1).replaceAll('.0', '')}×';
  }

  Future<bool> _saveOne(MediaItem item) async {
    return saveMediaToGallery(
      url: item.url!,
      isVideo: item.isVideo,
      headers: api.headersFor(item.url!),
    );
  }

  Future<void> _saveMedia() async {
    if (_saving) return;

    if (widget.items.length > 1) {
      final total = widget.items.length;
      final choice = await showDialog<String>(
        context: context,
        builder: (_) => GlitchDialog(
          backgroundColor: const Color(0xFF1e1e1e),
          titleColor: Colors.white,
          title: context.s.save,
          content: Text(context.s.gallerySaveChoice, style: const TextStyle(color: Colors.white70)),
          actions: [
            GlitchPlainButton(
              label: context.s.gallerySaveOnlyCurrent,
              color: Colors.white,
              onTap: () => Navigator.pop(context, 'one'),
            ),
            GlitchFilledButton(
              label: context.s.gallerySaveAll(total),
              onTap: () => Navigator.pop(context, 'all'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      setState(() => _saving = true);
      try {
        if (choice == 'one') {
          final saved = await _saveOne(widget.items[_currentIndex]);
          if (saved && !saveShowsDialog && mounted) {
            GlitchToast.show(context, context.s.savedToGallery, type: ToastType.success);
          }
        } else {
          for (final item in widget.items) await _saveOne(item);
          if (!saveShowsDialog && mounted) {
            GlitchToast.show(context, context.s.gallerySavedCount(total), type: ToastType.success);
          }
        }
      } catch (_) {
        if (mounted) GlitchToast.show(context, context.s.saveFailed);
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }

    setState(() => _saving = true);
    try {
      final saved = await _saveOne(widget.items[_currentIndex]);
      if (saved && !saveShowsDialog && mounted) {
        GlitchToast.show(context, context.s.savedToGallery, type: ToastType.success);
      }
    } catch (_) {
      if (mounted) GlitchToast.show(context, context.s.saveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showViewerMenu(Offset position) {
    if (widget.isLocalPreview) return;
    final item = widget.items[_currentIndex];
    final url = item.url;
    if (url == null) return;
    showMediaContextMenu(
      context,
      position: position,
      url: url,
      isVideo: item.isVideo,
      headers: api.headersFor(url),
      onSaveToDownloads: () { if (!_saving) _saveMedia(); },
    );
  }

  Future<void> _shareCurrent() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final item = widget.items[_currentIndex];
      await shareMedia(
        url: item.url ?? '',
        isVideo: item.isVideo,
        localFile: item.localFile,
        headers: item.url != null ? api.headersFor(item.url!) : const {},
      );
    } catch (_) {
      if (mounted) GlitchToast.show(context, context.s.shareFailed);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total   = widget.items.length;
    final isVideo = _currentIsVideo;
    final top     = MediaQuery.of(context).padding.top;
    final bottom  = MediaQuery.of(context).padding.bottom;
    final dur     = _duration.inMilliseconds;
    final pos     = _position.inMilliseconds;
    final played  = _dragFrac ?? (dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0);
    final displayPosition = _dragFrac != null
        ? Duration(milliseconds: (_dragFrac! * dur).round())
        : _position;

    final content = AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
      backgroundColor: _isOverlayShell ? Colors.transparent : Colors.black,
      body: Stack(
        children: [
          if (_isOverlayShell)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Colors.black.withOpacity(_kOverlayScrimOpacity)),
              ),
            ),
          GestureDetector(
            onSecondaryTapUp: (d) => _showViewerMenu(d.globalPosition),
            // ── PageView ──────────────────────────────────────────────────
            child: PageView.builder(
            controller: _pageCtrl,
            physics: _isZoomed
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            itemCount: total,
            onPageChanged: _onPageChanged,
            itemBuilder: (_, i) {
              final item = widget.items[i];
              if (item.isVideo) {
                return GestureDetector(
                  onTapUp: (d) => _handleTapAt(d.globalPosition),
                  child: SizedBox.expand(
                    child: InteractiveViewer(
                      transformationController: _transformFor(i),
                      minScale: 0.8,
                      maxScale: 5.0,
                      onInteractionUpdate: (_) => setState(() {}),
                      child: Center(
                        child: i == _currentIndex
                            ? KeyedSubtree(
                                key: _mediaKeyFor(i),
                                child: Video(controller: _videoCtrl, controls: NoVideoControls))
                            : const Center(child: Icon(Icons.videocam_rounded, color: Colors.white24, size: 64)),
                      ),
                    ),
                  ),
                );
              } else {
                return GestureDetector(
                  onTapUp: (d) => _handleTapAt(d.globalPosition),
                  child: SizedBox.expand(
                    child: InteractiveViewer(
                      transformationController: _transformFor(i),
                      minScale: 0.8,
                      maxScale: 5.0,
                      onInteractionUpdate: (_) => setState(() {}),
                      child: Center(
                        child: KeyedSubtree(
                        key: _mediaKeyFor(i),
                        child: item.localFile != null
                            ? localImage(item.localFile!.path, fit: BoxFit.contain)
                            : isGifUrl(item.url!)
                                ? AnimatedNetworkImage(
                                    url: item.url!,
                                    headers: api.headersFor(item.url!),
                                    fit: BoxFit.contain,
                                    placeholder: (_) => const Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
                                  )
                                : CachedNetworkImage(
                                    imageUrl: item.url!,
                                    cacheManager: mediaCacheManager,
                                    fit: BoxFit.contain,
                                    placeholder: (_, __) => const Center(
                                      child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
                                    errorWidget: (_, __, ___) => const Center(
                                      child: Icon(Icons.broken_image, color: Colors.white54, size: 48)),
                                  ),
                        ),
                      ),
                    ),
                  ),
                );
              }
            },
          ),
          ),

          // ── Controls overlay ────────────────────────────────────────────
          AnimatedOpacity(
            opacity: _uiVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_uiVisible,
              child: Stack(
                children: [

                  Positioned(
                    top: 0, left: 0, right: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [Color(0x9E000000), Colors.transparent],
                        ),
                      ),
                      padding: EdgeInsets.only(top: top + 10, bottom: 26, left: 10, right: 10),
                      child: Row(
                        children: [
                          if (!_isOverlayShell) ...[
                            _iconBtn(
                              onTap: () => Navigator.pop(context),
                              child: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 30),
                            ),
                            const SizedBox(width: 4),
                          ],
                          if (widget.isLocalPreview)
                            const Expanded(child: SizedBox())
                          else
                            Expanded(
                              child: ClickableCursor(
                                enabled: widget.onTitleTap != null || widget.senderNickname.isNotEmpty,
                                child: GestureDetector(
                                onTap: widget.onTitleTap != null
                                    ? () => widget.onTitleTap!(context)
                                    : (widget.senderNickname.isEmpty ? null : () => _openSenderProfile(context)),
                                child: Row(children: [
                                  GlitchAvatar(
                                    initials: GlitchAvatar.initialsFromName(widget.senderName),
                                    size: 38,
                                    colorIndex: widget.colorIndex,
                                    imageUrl: widget.senderAvatarUrl,
                                    avatarSizes: widget.senderAvatarSizes,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(widget.senderName,
                                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                                          overflow: TextOverflow.ellipsis),
                                        if (widget.time.isNotEmpty)
                                          Text(widget.time,
                                            style: const TextStyle(color: Colors.white60, fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                ]),
                              ),
                              ),
                            ),
                          if (total > 1)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text('${_currentIndex + 1}/$total',
                                style: const TextStyle(color: Colors.white70, fontSize: 14)),
                            ),
                          if (!widget.isLocalPreview) ...[
                            _iconBtn(
                              onTap: _saving ? null : _saveMedia,
                              child: _saving
                                  ? const SizedBox(width: 20, height: 20,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.download_rounded, color: Colors.white, size: 22),
                            ),
                            if (isVideo)
                              _iconBtn(
                                onTap: _minimize,
                                child: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white, size: 22),
                              ),
                            GlitchMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 22),
                              onSelected: (v) {
                                if (v == 'share') _shareCurrent();
                              },
                              itemBuilder: (_) => [
                                GlitchMenuItem(
                                  value: 'share',
                                  child: Row(children: [
                                    Icon(Icons.share_rounded, color: GlitchColors.textPrimary, size: 18),
                                    const SizedBox(width: 10),
                                    Text(context.s.share, style: TextStyle(color: GlitchColors.textPrimary, fontSize: 15)),
                                  ]),
                                ),
                              ],
                            ),
                          ],
                          if (_isOverlayShell)
                            _iconBtn(
                              onTap: () => Navigator.pop(context),
                              child: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                            ),
                        ],
                      ),
                    ),
                  ),

                  if (isVideo)
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClickableCursor(child: GestureDetector(
                            onTap: _skipBack,
                            child: const SizedBox(width: 52, height: 52,
                              child: Icon(Icons.replay_10_rounded, color: Colors.white, size: 42)),
                          )),
                          const SizedBox(width: 34),
                          ClickableCursor(child: GestureDetector(
                            onTap: () { _player.playOrPause(); _scheduleAutoHide(); },
                            child: Container(
                              width: 74, height: 74,
                              decoration: BoxDecoration(
                                color: const Color(0x80141418),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                              ),
                              child: Icon(
                                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white, size: 34,
                              ),
                            ),
                          )),
                          const SizedBox(width: 34),
                          ClickableCursor(child: GestureDetector(
                            onTap: _skipFwd,
                            child: const SizedBox(width: 52, height: 52,
                              child: Icon(Icons.forward_10_rounded, color: Colors.white, size: 42)),
                          )),
                        ],
                      ),
                    ),

                  if (isVideo)
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter, end: Alignment.topCenter,
                            colors: [Color(0xA8000000), Colors.transparent],
                          ),
                        ),
                        padding: EdgeInsets.fromLTRB(16, 34, 16, 22 + bottom),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Text(_fmt(displayPosition),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                    color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: GestureDetector(
                                    key: _seekKey,
                                    behavior: HitTestBehavior.opaque,
                                    onTapDown: (d) => _seekAt(d.localPosition),
                                    onHorizontalDragStart: (d) => _dragSeek(d.localPosition),
                                    onHorizontalDragUpdate: (d) => _dragSeek(d.localPosition),
                                    onHorizontalDragEnd: (_) => _endDrag(),
                                    onHorizontalDragCancel: _endDrag,
                                    child: SizedBox(
                                      height: 40,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Container(height: 4, decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.22),
                                            borderRadius: BorderRadius.circular(3),
                                          )),
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: FractionallySizedBox(
                                              widthFactor: played,
                                              child: Container(height: 4, decoration: BoxDecoration(
                                                color: GlitchColors.accentBlue,
                                                borderRadius: BorderRadius.circular(3),
                                              )),
                                            ),
                                          ),
                                          Align(
                                            alignment: Alignment(played * 2 - 1, 0),
                                            child: Container(
                                              width: 15, height: 15,
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                shape: BoxShape.circle,
                                                boxShadow: [BoxShadow(
                                                  color: Colors.black.withOpacity(0.5), blurRadius: 4)],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 11),
                                Text(_fmt(_duration),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                    color: Colors.white60, fontFeatures: [FontFeature.tabularFigures()])),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _iconBtn(
                                  onTap: () { _player.playOrPause(); _scheduleAutoHide(); },
                                  child: Icon(
                                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: Colors.white, size: 26),
                                ),
                                _iconBtn(
                                  onTap: _toggleMute,
                                  child: Icon(
                                    _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                    color: Colors.white, size: 23),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: _cycleSpeed,
                                  child: _pill(Text(_speedLabel,
                                    style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700))),
                                ),
                                if (!_isOverlayShell) ...[
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: _toggleFullscreen,
                                    child: _pill(
                                      Icon(_isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                        color: Colors.white, size: 20),
                                      width: 40,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_isOverlayShell && total > 1) ...[
                    Positioned(
                      left: 8, top: 0, bottom: 0,
                      child: Center(child: _sideArrow(
                        icon: Icons.chevron_left_rounded,
                        onTap: _currentIndex > 0 ? () => _pageBy(-1) : null,
                      )),
                    ),
                    Positioned(
                      right: 8, top: 0, bottom: 0,
                      child: Center(child: _sideArrow(
                        icon: Icons.chevron_right_rounded,
                        onTap: _currentIndex < total - 1 ? () => _pageBy(1) : null,
                      )),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    );

    final focus = _keyboardFocus;
    if (focus == null) return content;
    return Focus(
      focusNode: focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: content,
    );
  }

  Widget _sideArrow({required IconData icon, VoidCallback? onTap}) => ClickableCursor(
    enabled: onTap != null,
    child: GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap != null ? 1 : 0.25,
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.38),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 30),
        ),
      ),
    ),
  );

  Widget _iconBtn({VoidCallback? onTap, required Widget child}) => ClickableCursor(
    enabled: onTap != null,
    child: GestureDetector(
      onTap: onTap,
      child: SizedBox(width: 40, height: 40, child: Center(child: child)),
    ),
  );

  void _openSenderProfile(BuildContext context) {
    showUserProfile(context, nickname: widget.senderNickname);
  }

  Widget _pill(Widget child, {double? width}) => ClickableCursor(
    child: Container(
      height: 34,
      width: width,
      padding: width != null ? null : const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.13),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Center(child: child),
    ),
  );
}
