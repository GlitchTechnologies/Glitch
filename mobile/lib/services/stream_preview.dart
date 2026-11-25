import 'dart:async';

import '../providers/voice_channels.dart';
import 'api_service.dart';
import 'call_screen_capture_web.dart' if (dart.library.io) 'call_screen_capture_native.dart';
import 'error_reporter.dart';
import 'voice_connection.dart';

class StreamPreviewUploader {
  StreamPreviewUploader._();

  static const _kFirstDelay = Duration(seconds: 3);
  static const _kInterval = Duration(minutes: 1);

  Timer? _timer;

  String? _key;
  bool _attached = false;

  bool _reported = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    voiceConnection.addListener(_sync);
    voiceChannels.addListener(_sync);
    _sync();
  }

  ({int serverId, int roomId, VoiceMember me, bool screen})? _target() {
    final place = voiceChannels.connectedChannel;
    if (place == null) return null;
    final me = voiceChannels.members.where((m) => m.isLocal).firstOrNull;
    if (me == null || (me.screen == null && me.camera == null)) return null;
    return (serverId: place.serverId, roomId: place.roomId, me: me, screen: me.screen != null);
  }

  void _sync() {
    final t = _target();
    final track = t == null ? null : (t.screen ? t.me.screen : t.me.camera);
    final key = t == null || track == null ? null : '${t.serverId}:${t.roomId}:${track.sid}';
    if (key == _key) return;
    _key = key;
    _reported = false;
    _timer?.cancel();
    _timer = key == null ? null : Timer(_kFirstDelay, () => _shoot(key));
  }

  Future<void> _shoot(String key) async {
    try {
      final t = _target();
      final track = t == null ? null : (t.screen ? t.me.screen : t.me.camera);
      if (t == null || track == null || key != _key) return;
      final jpeg = await grabPreviewFrame(track.mediaStreamTrack);
      if (jpeg == null || key != _key) return;
      await api.putStreamPreview(t.serverId, t.roomId, jpeg);
    } on ApiException {
    } catch (e, s) {
      if (!_reported) {
        _reported = true;
        errorReporter.report(e, stack: s, screen: 'voice:streamPreview');
      }
    } finally {
      if (key == _key) _timer = Timer(_kInterval, () => _shoot(key));
    }
  }
}

final streamPreviewUploader = StreamPreviewUploader._();
