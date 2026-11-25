import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc show StatsReport;
import 'package:livekit_client/livekit_client.dart' as lk;

import 'voice_stats.dart';

class VoicePing {
  static const Duration interval = Duration(seconds: 2);

  static const int keep = 60;

  final ValueNotifier<List<int>> samples = ValueNotifier(const []);

  Timer? _timer;
  lk.Room? _room;
  bool _busy = false;

  void start(lk.Room room) {
    stop();
    _room = room;
    _timer = Timer.periodic(interval, (_) => unawaited(_measure()));
    unawaited(_measure());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _room = null;
    samples.value = const [];
  }

  Future<void> _measure() async {
    final room = _room;
    if (room == null || _busy) return;
    _busy = true;
    try {
      final ms = await _roundTrip(room);
      if (ms == null || !identical(_room, room)) return;
      final next = [...samples.value, ms];
      if (next.length > keep) next.removeRange(0, next.length - keep);
      samples.value = List.unmodifiable(next);
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  static Future<int?> _roundTrip(lk.Room room) async {
    for (final source in _sources(room)) {
      final ms = StatsIndex(await source()).roundTripMs;
      if (ms != null) return ms;
    }
    return null;
  }

  static Iterable<Future<List<rtc.StatsReport>> Function()> _sources(lk.Room room) sync* {
    final local = room.localParticipant;
    if (local != null) {
      for (final pub in local.trackPublications.values) {
        final sender = pub.track?.sender;
        if (sender != null) yield sender.getStats;
      }
    }
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.trackPublications.values) {
        final receiver = pub.track?.receiver;
        if (receiver != null) yield receiver.getStats;
      }
    }
  }
}
