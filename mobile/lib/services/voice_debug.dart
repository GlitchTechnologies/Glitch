import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc show StatsReport;
import 'package:livekit_client/livekit_client.dart' as lk;

import '../core/app_version.dart';
import '../core/platform_info.dart';
import 'desktop_shell.dart';
import 'voice_connection.dart';
import 'voice_stats.dart';
import 'websocket_service.dart';

class VoiceDebug {
  final Map<String, _Counters> _prev = {};

  DateTime? _asked;

  static const Duration _askEvery = Duration(seconds: 2);

  Future<VoiceDebugSnapshot?> collect() async {
    final room = voiceConnection.statsRoom;
    if (room == null) return null;
    final now = DateTime.now();
    final asked = _asked;
    if (asked == null || now.difference(asked) >= _askEvery) {
      _asked = now;
      voiceDebugExchange.ask();
    }
    final names = {for (final m in voiceConnection.members) m.identity: m.name};
    final mine = await selfInfo();

    final people = <VoiceDebugAudio>[];
    final screens = <VoiceDebugVideo>[];
    final cameras = <VoiceDebugVideo>[];

    Future<void> participant(lk.Participant p, {required bool local}) async {
      final name = names[p.identity] ?? p.name;
      lk.TrackPublication? pub(lk.TrackSource source) => p.getTrackPublicationBySource(source);

      Future<StatsIndex?> statsOf(lk.TrackPublication? publication) async {
        final track = publication?.track;
        if (track == null) return null;
        final List<rtc.StatsReport> reports;
        try {
          final sender = local ? track.sender : null;
          final receiver = local ? null : track.receiver;
          if (sender != null) {
            reports = await sender.getStats();
          } else if (receiver != null) {
            reports = await receiver.getStats();
          } else {
            return null;
          }
        } catch (_) {
          return null;
        }
        return StatsIndex(reports);
      }

      final info = local ? mine : voiceDebugExchange.infoOf(p.identity);

      final mic = pub(lk.TrackSource.microphone);
      final micIndex = await statsOf(mic);
      final audio = micIndex == null
          ? null
          : (local ? _sentAudio(micIndex, p.identity) : _receivedAudio(micIndex, p.identity));
      people.add(VoiceDebugAudio(
        id: p.identity,
        name: name,
        isLocal: local,
        info: info,
        quality: _quality(p.connectionQuality),
        micOn: mic != null && !mic.muted,
        codec: audio?.codec,
        kbps: audio?.kbps,
        lossPct: audio?.lossPct,
        jitterMs: audio?.jitterMs,
        delayMs: audio?.delayMs,
        concealPct: audio?.concealPct,
      ));

      Future<void> video(lk.TrackSource source, List<VoiceDebugVideo> into, {bool? withAudio}) async {
        final publication = pub(source);
        if (publication == null || publication.muted) return;
        final index = await statsOf(publication);
        final key = '${p.identity}/${source.name}';
        final row = index == null
            ? null
            : (local ? _sentVideo(index, key) : _receivedVideo(index, key));
        final sender = source == lk.TrackSource.camera ? info?.camera : info?.screen;
        final captureSid = sender?.capture?.trackSid;
        into.add(VoiceDebugVideo(
          id: key,
          name: name,
          isLocal: local,
          receiving: index != null,
          answered: info != null,
          sender: captureSid == null || captureSid == publication.sid ? sender : null,
          withAudio: withAudio,
          width: row?.width,
          height: row?.height,
          fps: row?.fps,
          kbps: row?.kbps,
          codec: row?.codec,
          coder: row?.coder,
          hardware: row?.hardware,
          framesDropped: row?.framesDropped,
          freezes: row?.freezes,
          lossPct: row?.lossPct,
        ));
      }

      final screenAudio = pub(lk.TrackSource.screenShareAudio);
      await video(lk.TrackSource.screenShareVideo, screens, withAudio: screenAudio != null && !screenAudio.muted);
      await video(lk.TrackSource.camera, cameras);
    }

    final local = room.localParticipant;
    if (local != null) await participant(local, local: true);
    for (final p in room.remoteParticipants.values) {
      await participant(p, local: false);
    }
    final alive = {
      if (local != null) local.identity,
      for (final p in room.remoteParticipants.values) p.identity,
    };
    _prev.removeWhere((key, _) => !key.startsWith('self/') && !alive.contains(key.split('/').first));

    return VoiceDebugSnapshot(
      general: VoiceDebugGeneral(
        serverVersion: room.serverVersion,
        serverRegion: room.serverRegion,
      ),
      people: people,
      screens: screens,
      cameras: cameras,
    );
  }


  Future<VoicePeerInfo?> selfInfo() async {
    final room = voiceConnection.statsRoom;
    if (room == null) return null;
    final v = voiceConnection;
    StatsIndex? sendPair;
    StatsIndex? recvPair;
    final local = room.localParticipant;
    if (local != null) {
      for (final pub in local.trackPublications.values) {
        final sender = pub.track?.sender;
        if (sender == null) continue;
        final index = await _stats(sender.getStats);
        if (index?.selectedPair != null) {
          sendPair = index;
          break;
        }
      }
    }
    outer:
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.trackPublications.values) {
        final receiver = pub.track?.receiver;
        if (receiver == null) continue;
        final index = await _stats(receiver.getStats);
        if (index?.selectedPair != null) {
          recvPair = index;
          break outer;
        }
      }
    }
    final candidate = (recvPair ?? sendPair)?.localCandidate;
    Future<VoiceVideoSender?> sent(lk.TrackSource source) async {
      final publication = local?.getTrackPublicationBySource(source);
      if (publication == null || publication.muted) return null;
      final track = publication.track;
      final capture = screenCaptureDebug.detailsFor(track);
      final sender = track?.sender;
      final index = screenCaptureDebug.indexFor(track) ?? (sender == null ? null : await _stats(sender.getStats));
      if (index != null) return _senderOf(index, capture: capture);
      return capture == null ? null : VoiceVideoSender(capture: capture);
    }

    final sendReport = sendPair?.selectedPair;
    final recvReport = recvPair?.selectedPair;
    final samples = v.ping.samples.value;
    final since = v.connectedAt;
    return VoicePeerInfo(
      rttMs: samples.isEmpty ? null : samples.last,
      avgRttMs: samples.isEmpty ? null : (samples.reduce((a, b) => a + b) / samples.length).round(),
      candidateType: StatsIndex.text(candidate, 'candidateType'),
      protocol: StatsIndex.text(candidate, 'protocol'),
      relayProtocol: StatsIndex.text(candidate, 'relayProtocol'),
      reconnects: v.reconnects,
      inVoiceSeconds: since == null ? null : DateTime.now().difference(since).inSeconds,
      sendKbps: sendReport == null
          ? null
          : _counters('self/send', sendReport).kbps(StatsIndex.number(sendReport, 'bytesSent')),
      recvKbps: recvReport == null
          ? null
          : _counters('self/recv', recvReport).kbps(StatsIndex.number(recvReport, 'bytesReceived')),
      noise: !v.noiseAvailable
          ? 'unavailable'
          : v.noiseActive
              ? 'on'
              : 'off',
      mic: _deviceLabel(v.inputDevices, v.inputDeviceId),
      speaker: _deviceLabel(v.outputDevices, v.outputDeviceId),
      device: _platform(),
      app: appVersion,
      screen: await sent(lk.TrackSource.screenShareVideo),
      camera: await sent(lk.TrackSource.camera),
    );
  }

  static Future<StatsIndex?> _stats(Future<List<rtc.StatsReport>> Function() get) async {
    try {
      return StatsIndex(await get());
    } catch (_) {
      return null;
    }
  }

  /// Название выбранного устройства; null — «по умолчанию» (подпись — у
  /// показывающего, на его языке).
  static String? _deviceLabel(List<VoiceAudioDevice> devices, String? id) {
    if (id == null) return null;
    for (final d in devices) {
      if (d.id == id && d.label.isNotEmpty) return d.label;
    }
    return null;
  }

  static String _platform() {
    if (!isWebPlatform) return isAndroidPlatform ? 'Android' : '—';
    final shell = desktopShell;
    if (shell != null) return 'Glitch для Windows ${shell.appVersion} (Chrome ${shell.chromeVersion.split('.').first})';
    final name = lk.lkBrowser().name;
    final title = name.isEmpty ? name : '${name[0].toUpperCase()}${name.substring(1)}';
    return '$title ${lk.lkBrowserVersion().major}';
  }


  _AudioRow? _sentAudio(StatsIndex index, String identity) {
    final out = _rtp(index, 'outbound-rtp', 'audio').firstOrNull;
    if (out == null) return null;
    final c = _counters('$identity/mic', out);
    final remote = _remoteOf(index, out);
    final fraction = StatsIndex.number(remote, 'fractionLost');
    final jitter = StatsIndex.number(remote, 'jitter');
    final rtt = StatsIndex.number(remote, 'roundTripTime');
    return _AudioRow(
      codec: index.codecOf(out),
      kbps: c.kbps(StatsIndex.number(out, 'bytesSent')),
      lossPct: fraction == null ? null : fraction * 100,
      jitterMs: jitter == null ? null : (jitter * 1000).round(),
      delayMs: rtt == null ? null : (rtt * 1000).round(),
    );
  }

  _AudioRow? _receivedAudio(StatsIndex index, String identity) {
    final inb = _rtp(index, 'inbound-rtp', 'audio').firstOrNull;
    if (inb == null) return null;
    final c = _counters('$identity/mic', inb);
    final jitter = StatsIndex.number(inb, 'jitter');
    final delay = c.ratio(
      StatsIndex.number(inb, 'jitterBufferDelay'),
      StatsIndex.number(inb, 'jitterBufferEmittedCount'),
      'jbDelay',
      'jbEmitted',
    );
    final conceal = c.ratio(
      StatsIndex.number(inb, 'concealedSamples'),
      StatsIndex.number(inb, 'totalSamplesReceived'),
      'concealed',
      'samples',
    );
    return _AudioRow(
      codec: index.codecOf(inb),
      kbps: c.kbps(StatsIndex.number(inb, 'bytesReceived')),
      lossPct: c.loss(inb),
      jitterMs: jitter == null ? null : (jitter * 1000).round(),
      delayMs: delay == null ? null : (delay * 1000).round(),
      concealPct: conceal == null ? null : conceal * 100,
    );
  }


  static ({List<rtc.StatsReport> outs, List<rtc.StatsReport> sending, rtc.StatsReport best})? _layers(
    StatsIndex index,
  ) {
    final outs = _rtp(index, 'outbound-rtp', 'video').toList();
    if (outs.isEmpty) return null;
    final sending = [
      for (final o in outs)
        if ((StatsIndex.number(o, 'frameWidth') ?? 0) > 0) o,
    ];
    var best = outs.first;
    for (final o in sending) {
      if ((StatsIndex.number(o, 'frameWidth') ?? 0) > (StatsIndex.number(best, 'frameWidth') ?? 0)) best = o;
    }
    return (outs: outs, sending: sending, best: best);
  }

  static VideoShape _shapeOf(rtc.StatsReport r) => (
        width: StatsIndex.number(r, 'frameWidth')?.round(),
        height: StatsIndex.number(r, 'frameHeight')?.round(),
        fps: StatsIndex.number(r, 'framesPerSecond')?.toDouble(),
      );

  static Future<VideoShape?> measureVideo(lk.Track track) async {
    final List<rtc.StatsReport> reports;
    try {
      final sender = track is lk.LocalTrack ? track.sender : null;
      final receiver = track is lk.LocalTrack ? null : track.receiver;
      if (sender != null) {
        reports = await sender.getStats();
      } else if (receiver != null) {
        reports = await receiver.getStats();
      } else {
        return null;
      }
    } catch (_) {
      return null;
    }
    final index = StatsIndex(reports);
    if (track is lk.LocalTrack) {
      final layers = _layers(index);
      final sent = layers == null ? null : _shapeOf(layers.best);
      if (sent != null && sent.height != null && sent.fps != null) return sent;
      final source = index
          .ofType('media-source')
          .where((r) => StatsIndex.text(r, 'kind') == 'video')
          .firstOrNull;
      if (source == null) return sent;
      return (
        width: StatsIndex.number(source, 'width')?.round(),
        height: StatsIndex.number(source, 'height')?.round(),
        fps: StatsIndex.number(source, 'framesPerSecond')?.toDouble(),
      );
    }
    final inb = _rtp(index, 'inbound-rtp', 'video').firstOrNull;
    return inb == null ? null : _shapeOf(inb);
  }

  _VideoRow? _sentVideo(StatsIndex index, String key) {
    final layers = _layers(index);
    if (layers == null) return null;
    final best = layers.best;
    final c = _counters(key, layers.outs.first);
    num bytes = 0;
    for (final o in layers.outs) {
      bytes += StatsIndex.number(o, 'bytesSent') ?? 0;
    }
    final fraction = StatsIndex.number(_remoteOf(index, best), 'fractionLost');
    final shape = _shapeOf(best);
    return _VideoRow(
      width: shape.width,
      height: shape.height,
      kbps: c.kbps(bytes),
      codec: index.codecOf(best),
      lossPct: fraction == null ? null : fraction * 100,
    );
  }

  static VoiceVideoSender? _senderOf(StatsIndex index, {ScreenDebugDetails? capture}) {
    final layers = _layers(index);
    if (layers == null) return null;
    final best = layers.best;
    final source = _videoSource(index, best);
    final efficient = best.values['powerEfficientEncoder'];
    num? target;
    for (final o in layers.sending) {
      final t = StatsIndex.number(o, 'targetBitrate');
      if (t != null) target = (target ?? 0) + t;
    }
    final channel = index.availableOutgoingBitrate;
    return VoiceVideoSender(
      channelKbps: channel == null ? null : (channel / 1000).round(),
      targetKbps: target == null ? null : (target / 1000).round(),
      captureFps: StatsIndex.number(source, 'framesPerSecond')?.toDouble(),
      fps: _shapeOf(best).fps,
      coder: StatsIndex.text(best, 'encoderImplementation'),
      hardware: efficient is bool ? efficient : null,
      layers: layers.sending.length,
      limit: StatsIndex.text(best, 'qualityLimitationReason'),
      capture: capture,
    );
  }

  static rtc.StatsReport? _videoSource(StatsIndex index, rtc.StatsReport? outbound) {
    return index.byId(outbound?.values['mediaSourceId']) ??
        index.ofType('media-source').where((r) => StatsIndex.text(r, 'kind') == 'video').firstOrNull;
  }

  _VideoRow? _receivedVideo(StatsIndex index, String key) {
    final inb = _rtp(index, 'inbound-rtp', 'video').firstOrNull;
    if (inb == null) return null;
    final c = _counters(key, inb);
    final efficient = inb.values['powerEfficientDecoder'];
    final shape = _shapeOf(inb);
    return _VideoRow(
      width: shape.width,
      height: shape.height,
      fps: shape.fps,
      kbps: c.kbps(StatsIndex.number(inb, 'bytesReceived')),
      codec: index.codecOf(inb),
      coder: StatsIndex.text(inb, 'decoderImplementation'),
      hardware: efficient is bool ? efficient : null,
      framesDropped: StatsIndex.number(inb, 'framesDropped')?.round(),
      freezes: StatsIndex.number(inb, 'freezeCount')?.round(),
      lossPct: c.loss(inb),
    );
  }


  /// Записи дорожки нужного вида. Вид — `kind`, у старых браузеров —
  /// `mediaType`.
  static Iterable<rtc.StatsReport> _rtp(StatsIndex index, String type, String kind) => index
      .ofType(type)
      .where((r) => (StatsIndex.text(r, 'kind') ?? StatsIndex.text(r, 'mediaType')) == kind);

  static rtc.StatsReport? _remoteOf(StatsIndex index, rtc.StatsReport out) {
    final direct = index.byId(out.values['remoteId']);
    if (direct != null) return direct;
    for (final r in index.ofType('remote-inbound-rtp')) {
      if (r.values['localId'] == out.id) return r;
    }
    return null;
  }

  _Counters _counters(String key, rtc.StatsReport r) {
    final prev = _prev[key];
    final now = _Counters(r.timestamp.toDouble(), prev);
    _prev[key] = now;
    return now;
  }

  static VoiceLinkQuality _quality(lk.ConnectionQuality q) => switch (q) {
        lk.ConnectionQuality.excellent => VoiceLinkQuality.excellent,
        lk.ConnectionQuality.good => VoiceLinkQuality.good,
        lk.ConnectionQuality.poor => VoiceLinkQuality.poor,
        lk.ConnectionQuality.lost => VoiceLinkQuality.lost,
        lk.ConnectionQuality.unknown => VoiceLinkQuality.unknown,
      };
}

class _Counters {
  final double timestampMs;
  final _Counters? prev;
  final Map<String, num> values = {};

  _Counters(this.timestampMs, this.prev);

  num? _delta(String key, num? value) {
    if (value == null) return null;
    values[key] = value;
    final before = prev?.values[key];
    if (before == null) return null;
    final d = value - before;
    return d < 0 ? null : d; // счётчик начался заново (переподключение)
  }

  int? kbps(num? bytes) {
    final d = _delta('bytes', bytes);
    final p = prev;
    if (d == null || p == null) return null;
    final seconds = (timestampMs - p.timestampMs) / 1000;
    if (seconds <= 0) return null;
    return (d * 8 / 1000 / seconds).round();
  }

  double? loss(rtc.StatsReport inbound) {
    final lost = _delta('lost', StatsIndex.number(inbound, 'packetsLost'));
    final got = _delta('received', StatsIndex.number(inbound, 'packetsReceived'));
    if (lost == null || got == null || lost + got == 0) return null;
    return lost / (lost + got) * 100;
  }

  double? ratio(num? top, num? bottom, String topKey, String bottomKey) {
    final t = _delta(topKey, top);
    final b = _delta(bottomKey, bottom);
    if (t == null || b == null || b == 0) return null;
    return t / b;
  }
}

class _AudioRow {
  final String? codec;
  final int? kbps;
  final double? lossPct;
  final int? jitterMs;
  final int? delayMs;
  final double? concealPct;

  const _AudioRow({this.codec, this.kbps, this.lossPct, this.jitterMs, this.delayMs, this.concealPct});
}

class _VideoRow {
  final int? width;
  final int? height;
  final double? fps;
  final int? kbps;
  final String? codec;
  final String? coder;
  final bool? hardware;
  final int? framesDropped;
  final int? freezes;
  final double? lossPct;

  const _VideoRow({
    this.width,
    this.height,
    this.fps,
    this.kbps,
    this.codec,
    this.coder,
    this.hardware,
    this.framesDropped,
    this.freezes,
    this.lossPct,
  });
}

typedef VideoShape = ({int? width, int? height, double? fps});


enum VoiceLinkQuality { excellent, good, poor, lost, unknown }

class VoiceDebugSnapshot {
  final VoiceDebugGeneral general;

  final List<VoiceDebugAudio> people;
  final List<VoiceDebugVideo> screens;
  final List<VoiceDebugVideo> cameras;

  const VoiceDebugSnapshot({
    required this.general,
    required this.people,
    required this.screens,
    required this.cameras,
  });

  Map<String, Object?> toJson() => {
        'general': general.toJson(),
        'people': [for (final p in people) p.toJson()],
        'screens': [for (final v in screens) v.toJson()],
        'cameras': [for (final v in cameras) v.toJson()],
      };

  static VoiceDebugSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    List<T> list<T>(Object? v, T? Function(Object?) parse) =>
        v is List ? v.map(parse).whereType<T>().toList() : <T>[];
    return VoiceDebugSnapshot(
      general: VoiceDebugGeneral.fromJson(raw['general']),
      people: list(raw['people'], VoiceDebugAudio.fromJson),
      screens: list(raw['screens'], VoiceDebugVideo.fromJson),
      cameras: list(raw['cameras'], VoiceDebugVideo.fromJson),
    );
  }
}

class VoiceDebugGeneral {
  final String? serverVersion;

  final String? serverRegion;

  const VoiceDebugGeneral({required this.serverVersion, required this.serverRegion});

  Map<String, Object?> toJson() => {'version': serverVersion, 'region': serverRegion};

  static VoiceDebugGeneral fromJson(Object? raw) {
    final m = raw is Map ? raw : const {};
    return VoiceDebugGeneral(
      serverVersion: m['version'] is String ? m['version'] as String : null,
      serverRegion: m['region'] is String ? m['region'] as String : null,
    );
  }
}

class VoicePeerInfo {
  final int? rttMs;
  final int? avgRttMs;

  final String? candidateType;
  final String? protocol;
  final String? relayProtocol;
  final int reconnects;
  final int? inVoiceSeconds;
  final int? sendKbps;
  final int? recvKbps;

  /// on / off / unavailable.
  final String noise;

  /// Названия выбранных устройств; null — «по умолчанию».
  final String? mic;
  final String? speaker;

  final String device;
  final String app;

  final VoiceVideoSender? screen;
  final VoiceVideoSender? camera;

  const VoicePeerInfo({
    this.rttMs,
    this.avgRttMs,
    this.candidateType,
    this.protocol,
    this.relayProtocol,
    this.reconnects = 0,
    this.inVoiceSeconds,
    this.sendKbps,
    this.recvKbps,
    required this.noise,
    this.mic,
    this.speaker,
    required this.device,
    required this.app,
    this.screen,
    this.camera,
  });

  Map<String, Object?> toJson() => {
        'rtt': rttMs,
        'avg_rtt': avgRttMs,
        'cand': candidateType,
        'proto': protocol,
        'relay': relayProtocol,
        'reconnects': reconnects,
        'in_voice': inVoiceSeconds,
        'send': sendKbps,
        'recv': recvKbps,
        'noise': noise,
        'mic': mic,
        'speaker': speaker,
        'device': device,
        'app': app,
        ...?screen?.toJson('scr_'),
        ...?camera?.toJson('cam_'),
      };

  static VoicePeerInfo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    int? n(String k) => raw[k] is num ? (raw[k] as num).round() : null;
    String? t(String k) => raw[k] is String ? raw[k] as String : null;
    return VoicePeerInfo(
      rttMs: n('rtt'),
      avgRttMs: n('avg_rtt'),
      candidateType: t('cand'),
      protocol: t('proto'),
      relayProtocol: t('relay'),
      reconnects: n('reconnects') ?? 0,
      inVoiceSeconds: n('in_voice'),
      sendKbps: n('send'),
      recvKbps: n('recv'),
      noise: t('noise') ?? 'unavailable',
      mic: t('mic'),
      speaker: t('speaker'),
      device: t('device') ?? '—',
      app: t('app') ?? '—',
      screen: VoiceVideoSender.fromJson(raw, 'scr_'),
      camera: VoiceVideoSender.fromJson(raw, 'cam_'),
    );
  }
}

class VoiceVideoSender {
  final double? captureFps;

  final double? fps;

  final String? coder;
  final bool? hardware;

  final int? layers;

  final String? limit;

  final int? channelKbps;
  final int? targetKbps;
  final ScreenDebugDetails? capture;

  const VoiceVideoSender({
    this.captureFps,
    this.fps,
    this.coder,
    this.hardware,
    this.layers,
    this.limit,
    this.channelKbps,
    this.targetKbps,
    this.capture,
  });

  double? get shownFps => layers == 0 || fps == null ? captureFps ?? fps : fps;

  Map<String, Object?> toJson(String prefix) => {
        '${prefix}on': true,
        '${prefix}cap': captureFps,
        '${prefix}fps': fps,
        '${prefix}coder': coder,
        '${prefix}hw': hardware,
        '${prefix}layers': layers,
        '${prefix}limit': limit,
        '${prefix}chan': channelKbps,
        '${prefix}tgt': targetKbps,
        ...?capture?.toJson(prefix),
      };

  static VoiceVideoSender? fromJson(Map raw, String prefix) {
    if (raw['${prefix}on'] != true) return null;
    double? d(String k) => raw['$prefix$k'] is num ? (raw['$prefix$k'] as num).toDouble() : null;
    String? t(String k) => raw['$prefix$k'] is String ? raw['$prefix$k'] as String : null;
    int? n(String k) => raw['$prefix$k'] is num ? (raw['$prefix$k'] as num).round() : null;
    final hw = raw['${prefix}hw'];
    return VoiceVideoSender(
      captureFps: d('cap'),
      fps: d('fps'),
      coder: t('coder'),
      hardware: hw is bool ? hw : null,
      layers: n('layers'),
      limit: t('limit'),
      channelKbps: n('chan'),
      targetKbps: n('tgt'),
      capture: ScreenDebugDetails.fromJson(raw, prefix),
    );
  }
}

class ScreenDebugDetails {
  final String trackSid;
  final int? configuredFps;
  final int? lowestFps;
  final DesktopCaptureTimings? timings;
  final double? encodeMs;

  const ScreenDebugDetails({
    required this.trackSid,
    this.configuredFps,
    this.lowestFps,
    this.timings,
    this.encodeMs,
  });

  Map<String, Object?> toJson(String prefix) => {
        '${prefix}cap_sid': trackSid,
        '${prefix}cap_cfg': configuredFps,
        '${prefix}cap_low': lowestFps,
        '${prefix}cap_attempts': timings?.attemptsPerSecond,
        '${prefix}cap_acquire': timings?.acquireMs,
        '${prefix}cap_prepare': timings?.prepareMs,
        '${prefix}cap_interval': timings?.intervalMs,
        '${prefix}enc_ms': encodeMs,
        ...?timings?.source?.toJson('${prefix}cap_'),
      };

  static ScreenDebugDetails? fromJson(Map raw, String prefix) {
    final sid = raw['${prefix}cap_sid'];
    if (sid is! String || sid.isEmpty) return null;
    int? n(String k) => raw['$prefix$k'] is int ? raw['$prefix$k'] as int : null;
    final encode = raw['${prefix}enc_ms'];
    return ScreenDebugDetails(
      trackSid: sid,
      configuredFps: n('cap_cfg'),
      lowestFps: n('cap_low'),
      timings: (
        attemptsPerSecond: n('cap_attempts'),
        acquireMs: n('cap_acquire'),
        prepareMs: n('cap_prepare'),
        intervalMs: n('cap_interval'),
        configuredFps: null,
        source: DesktopCaptureSource.fromJson(raw, '${prefix}cap_'),
      ),
      encodeMs: encode is num && encode.isFinite ? encode.toDouble() : null,
    );
  }
}

class ScreenCaptureDebug {
  static const _every = Duration(seconds: 1);
  static const _history = Duration(minutes: 1);
  final _clock = Stopwatch();
  final _samples = <({Duration at, int fps})>[];
  lk.Track? _track;
  String? _trackSid;
  Timer? _timer;
  ({Duration at, StatsIndex index})? _latest;
  int? _configuredFps;
  DesktopCaptureTimings? _timings;
  ({String id, num frames, num seconds})? _lastEncoded;
  double? _encodeMs;
  bool _busy = false;
  int _generation = 0;

  void sync(lk.Track? track, String? sid) {
    if (!isDesktopApp || (identical(_track, track) && _trackSid == sid)) return;
    final generation = ++_generation;
    _timer?.cancel();
    _timer = null;
    _track = track;
    _trackSid = sid;
    _samples.clear();
    _latest = null;
    _configuredFps = null;
    _timings = null;
    _lastEncoded = null;
    _encodeMs = null;
    _clock
      ..stop()
      ..reset();
    if (track == null || sid == null) return;
    _clock.start();
    try {
      final fps = track.mediaStreamTrack.getSettings()['frameRate'];
      if (fps is num && fps.isFinite) _configuredFps = fps.round();
    } catch (_) {}
    _timer = Timer.periodic(_every, (_) => unawaited(_sample(track, sid, generation)));
    unawaited(_sample(track, sid, generation));
  }

  Future<void> _sample(lk.Track track, String sid, int generation) async {
    if (_busy || generation != _generation) return;
    _busy = true;
    try {
      final native = desktopShell?.screenCaptureTimings(sid, trackId: track.mediaStreamTrack.id);
      final sender = track is lk.LocalTrack ? track.sender : null;
      final index = sender == null ? null : await VoiceDebug._stats(sender.getStats);
      final timings = await native;
      if (generation != _generation) return;
      _timings = timings;
      _configuredFps = timings?.configuredFps ?? _configuredFps;
      if (index == null) return;
      final now = _clock.elapsed;
      _latest = (at: now, index: index);
      final outbound = VoiceDebug._layers(index)?.best;
      final fps = StatsIndex.number(VoiceDebug._videoSource(index, outbound), 'framesPerSecond');
      _samples.removeWhere((s) => now - s.at >= _history);
      if (now >= _every && fps != null && fps.isFinite && fps >= 0) {
        _samples.add((at: now, fps: fps.round()));
      }

      final frames = StatsIndex.number(outbound, 'framesEncoded');
      final seconds = StatsIndex.number(outbound, 'totalEncodeTime');
      final previous = _lastEncoded;
      _lastEncoded = null;
      _encodeMs = null;
      if (outbound != null && frames != null && seconds != null && frames.isFinite && seconds.isFinite) {
        _lastEncoded = (id: outbound.id, frames: frames, seconds: seconds);
        if (previous != null && previous.id == outbound.id && frames > previous.frames && seconds >= previous.seconds) {
          _encodeMs = (seconds - previous.seconds) * 1000 / (frames - previous.frames);
        }
      }
    } finally {
      _busy = false;
    }
  }

  StatsIndex? indexFor(lk.Track? track) {
    final latest = _latest;
    if (!identical(track, _track) || latest == null || _clock.elapsed - latest.at >= _every * 2) return null;
    return latest.index;
  }

  ScreenDebugDetails? detailsFor(lk.Track? track) {
    final sid = _trackSid;
    if (track == null || sid == null || !identical(track, _track)) return null;
    final now = _clock.elapsed;
    _samples.removeWhere((s) => now - s.at >= _history);
    int? lowest;
    for (final entry in _samples) {
      if (lowest == null || entry.fps < lowest) lowest = entry.fps;
    }
    return ScreenDebugDetails(
      trackSid: sid,
      configuredFps: _configuredFps,
      lowestFps: lowest,
      timings: _timings,
      encodeMs: _encodeMs,
    );
  }
}

final screenCaptureDebug = ScreenCaptureDebug();


class VoiceDebugExchange {
  VoiceDebugExchange._();

  /// Старше этого ответ не показываем: человек мог уйти или его приложение
  /// перестало отвечать (старая версия не отвечает вовсе).
  static const Duration _fresh = Duration(seconds: 6);

  final Map<String, ({VoicePeerInfo info, DateTime at})> _reports = {};

  final VoiceDebug _responder = VoiceDebug();

  void ask() => wsService.send({'type': 'voice.debug.request'});

  VoicePeerInfo? infoOf(String identity) {
    final r = _reports[identity];
    if (r == null || DateTime.now().difference(r.at) > _fresh) return null;
    return r.info;
  }

  void onWsEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'voice.debug.request':
        final from = event['from'];
        if (from is String) unawaited(_answer(from));
      case 'voice.debug.report':
        final identity = event['identity'];
        final info = VoicePeerInfo.fromJson(event['report']);
        if (identity is String && info != null) _reports[identity] = (info: info, at: DateTime.now());
    }
  }

  Future<void> _answer(String to) async {
    final info = await _responder.selfInfo();
    if (info == null) return;
    wsService.send({'type': 'voice.debug.report', 'to': to, 'report': info.toJson()});
  }

  void reset() {
    _reports.clear();
    _responder._prev.clear();
  }
}

final voiceDebugExchange = VoiceDebugExchange._();

class VoiceDebugAudio {
  final String id;
  final String name;
  final bool isLocal;

  /// Что его устройство сообщило о себе; null — ответа нет (ещё не пришёл
  /// или старая версия Glitch, которая не отвечает).
  final VoicePeerInfo? info;
  final VoiceLinkQuality quality;
  final bool micOn;
  final String? codec;
  final int? kbps;
  final double? lossPct;
  final int? jitterMs;

  final int? delayMs;

  final double? concealPct;

  const VoiceDebugAudio({
    required this.id,
    required this.name,
    required this.isLocal,
    required this.info,
    required this.quality,
    required this.micOn,
    this.codec,
    this.kbps,
    this.lossPct,
    this.jitterMs,
    this.delayMs,
    this.concealPct,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'local': isLocal,
        'info': info?.toJson(),
        'quality': quality.name,
        'mic': micOn,
        'codec': codec,
        'kbps': kbps,
        'loss': lossPct,
        'jitter': jitterMs,
        'delay': delayMs,
        'conceal': concealPct,
      };

  static VoiceDebugAudio? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String || raw['name'] is! String) return null;
    return VoiceDebugAudio(
      id: raw['id'] as String,
      name: raw['name'] as String,
      isLocal: raw['local'] == true,
      info: VoicePeerInfo.fromJson(raw['info']),
      quality: VoiceLinkQuality.values.asNameMap()[raw['quality']] ?? VoiceLinkQuality.unknown,
      micOn: raw['mic'] == true,
      codec: _str(raw['codec']),
      kbps: _int(raw['kbps']),
      lossPct: _dbl(raw['loss']),
      jitterMs: _int(raw['jitter']),
      delayMs: _int(raw['delay']),
      concealPct: _dbl(raw['conceal']),
    );
  }
}

String? _str(Object? v) => v is String ? v : null;
int? _int(Object? v) => v is num ? v.round() : null;
double? _dbl(Object? v) => v is num ? v.toDouble() : null;
bool? _bool(Object? v) => v is bool ? v : null;

class VoiceDebugVideo {
  final String id;
  final String name;
  final bool isLocal;
  final bool receiving;

  /// Ответило ли приложение показывающего (своё — всегда); старая версия
  /// Glitch не отвечает.
  final bool answered;
  final VoiceVideoSender? sender;

  final bool? withAudio;
  final int? width;
  final int? height;
  final double? fps;
  final int? kbps;
  final String? codec;

  final String? coder;
  final bool? hardware;

  final int? framesDropped;
  final int? freezes;
  final double? lossPct;

  const VoiceDebugVideo({
    required this.id,
    required this.name,
    required this.isLocal,
    required this.receiving,
    required this.answered,
    this.sender,
    this.withAudio,
    this.width,
    this.height,
    this.fps,
    this.kbps,
    this.codec,
    this.coder,
    this.hardware,
    this.framesDropped,
    this.freezes,
    this.lossPct,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'local': isLocal,
        'receiving': receiving,
        'answered': answered,
        'sender': sender?.toJson(''),
        'audio': withAudio,
        'w': width,
        'h': height,
        'fps': fps,
        'kbps': kbps,
        'codec': codec,
        'coder': coder,
        'hw': hardware,
        'dropped': framesDropped,
        'freezes': freezes,
        'loss': lossPct,
      };

  static VoiceDebugVideo? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String || raw['name'] is! String) return null;
    final sender = raw['sender'];
    return VoiceDebugVideo(
      id: raw['id'] as String,
      name: raw['name'] as String,
      isLocal: raw['local'] == true,
      receiving: raw['receiving'] == true,
      answered: raw['answered'] == true,
      sender: sender is Map ? VoiceVideoSender.fromJson(sender, '') : null,
      withAudio: _bool(raw['audio']),
      width: _int(raw['w']),
      height: _int(raw['h']),
      fps: _dbl(raw['fps']),
      kbps: _int(raw['kbps']),
      codec: _str(raw['codec']),
      coder: _str(raw['coder']),
      hardware: _bool(raw['hw']),
      framesDropped: _int(raw['dropped']),
      freezes: _int(raw['freezes']),
      lossPct: _dbl(raw['loss']),
    );
  }
}
