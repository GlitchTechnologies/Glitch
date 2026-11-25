import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc show StatsReport;

class StatsIndex {
  final List<rtc.StatsReport> reports;
  final Map<String, rtc.StatsReport> _byId;

  StatsIndex(this.reports) : _byId = {for (final r in reports) r.id: r};

  rtc.StatsReport? byId(Object? id) => id is String ? _byId[id] : null;

  Iterable<rtc.StatsReport> ofType(String type) => reports.where((r) => r.type == type);

  static num? number(rtc.StatsReport? r, String key) {
    if (r == null) return null;
    final v = r.values[key];
    if (v is num) return v;
    return v == null ? null : num.tryParse('$v');
  }

  static String? text(rtc.StatsReport? r, String key) {
    final v = r?.values[key];
    return v == null ? null : '$v';
  }

  rtc.StatsReport? get selectedPair {
    for (final t in ofType('transport')) {
      final pair = byId(t.values['selectedCandidatePairId']);
      if (pair != null) return pair;
    }
    for (final p in ofType('candidate-pair')) {
      if (p.values['selected'] == true) return p;
    }
    for (final p in ofType('candidate-pair')) {
      if (p.values['nominated'] == true && p.values['state'] == 'succeeded') return p;
    }
    return null;
  }

  int? get roundTripMs {
    final seconds = number(selectedPair, 'currentRoundTripTime');
    return seconds == null ? null : (seconds * 1000).round();
  }

  rtc.StatsReport? get localCandidate => byId(selectedPair?.values['localCandidateId']);

  num? get availableOutgoingBitrate => number(selectedPair, 'availableOutgoingBitrate');

  String? codecOf(rtc.StatsReport rtp) {
    final mime = text(byId(rtp.values['codecId']), 'mimeType');
    if (mime == null) return null;
    final slash = mime.indexOf('/');
    return slash < 0 ? mime : mime.substring(slash + 1);
  }
}
