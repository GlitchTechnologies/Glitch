import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../widgets/floating_window.dart' show FloatingCorner;

class MiniPlayerProvider extends ChangeNotifier {
  Player? _player;
  VideoController? _videoCtrl;
  StreamSubscription? _subPlaying;
  StreamSubscription? _subPosition;

  String? _url;
  bool _playing = false;
  Duration _position = Duration.zero;
  FloatingCorner _windowCorner = FloatingCorner.bottomRight;
  double? _aspectRatio;
  double _sizeScale = 1.0;

  String _senderName = '';
  String _senderNickname = '';
  String? _senderAvatarUrl;
  Map<String, String>? _senderAvatarSizes;
  String _time = '';
  int _colorIndex = 0;

  bool get isVisible => _url != null;
  String? get url => _url;
  bool get playing => _playing;
  Duration get position => _position;
  FloatingCorner get windowCorner => _windowCorner;
  VideoController? get videoController => _videoCtrl;
  double? get aspectRatio => _aspectRatio;
  double get sizeScale => _sizeScale;

  String get senderName => _senderName;
  String get senderNickname => _senderNickname;
  String? get senderAvatarUrl => _senderAvatarUrl;
  Map<String, String>? get senderAvatarSizes => _senderAvatarSizes;
  String get time => _time;
  int get colorIndex => _colorIndex;

  Future<void> adopt({
    required Player player,
    required VideoController controller,
    required String url,
    double? aspectRatio,
    required String senderName,
    required String senderNickname,
    String? senderAvatarUrl,
    Map<String, String>? senderAvatarSizes,
    required String time,
    required int colorIndex,
  }) async {
    await _disposePlayer(); // на случай если в окошке уже играло другое видео

    _senderName = senderName;
    _senderNickname = senderNickname;
    _senderAvatarUrl = senderAvatarUrl;
    _senderAvatarSizes = senderAvatarSizes;
    _time = time;
    _colorIndex = colorIndex;
    _aspectRatio = aspectRatio;

    _player = player;
    _videoCtrl = controller;
    final st = player.state;
    _position = st.position;
    _playing = st.playing;

    _subPlaying = player.stream.playing.listen((v) {
      _playing = v;
      notifyListeners();
    });
    _subPosition = player.stream.position.listen((v) {
      _position = v;
      notifyListeners();
    });

    _url = url;
    notifyListeners();
  }

  void setWindowCorner(FloatingCorner corner) {
    _windowCorner = corner;
    notifyListeners();
  }

  void setSizeScale(double scale) {
    _sizeScale = scale;
    notifyListeners();
  }

  void togglePlay() => _player?.playOrPause();

  /// Отдаёт Player/VideoController наружу (полноэкранному плееру) БЕЗ
  /// диспоуза — используется при разворачивании обратно. Тот, кто вызвал,
  /// становится новым владельцем плеера и отвечает за его dispose().
  ({Player player, VideoController controller, Duration position})? releaseForExpand() {
    final player = _player;
    final controller = _videoCtrl;
    if (player == null || controller == null) return null;
    final pos = _position;

    _subPlaying?.cancel();
    _subPosition?.cancel();
    _subPlaying = null;
    _subPosition = null;
    _player = null;
    _videoCtrl = null;
    _url = null;
    _aspectRatio = null;
    notifyListeners();

    return (player: player, controller: controller, position: pos);
  }

  Future<void> close() async {
    _url = null;
    _aspectRatio = null;
    notifyListeners();
    await _disposePlayer();
  }

  Future<void> _disposePlayer() async {
    await _subPlaying?.cancel();
    await _subPosition?.cancel();
    _subPlaying = null;
    _subPosition = null;
    final p = _player;
    _player = null;
    _videoCtrl = null;
    await p?.dispose();
  }

  @override
  void dispose() {
    _disposePlayer();
    super.dispose();
  }
}

final miniPlayer = MiniPlayerProvider();
