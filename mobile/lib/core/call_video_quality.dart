import 'package:livekit_client/livekit_client.dart'
    show DegradationPreference, VideoDimensions, VideoDimensionsPresets, VideoEncoding, VideoParameters, VideoParametersPresets;

class CallVideoQuality {
  static const VideoParameters camera = VideoParametersPresets.h720_169;

  static const VideoParameters phoneScreen = VideoParametersPresets.screenShareH720FPS15;

  static final VideoParameters computerScreen = computerScreenOf(ScreenShareQuality.standard);

  static VideoParameters computerScreenOf(ScreenShareQuality q) => VideoParameters(
        dimensions: q.resolution.size ?? const VideoDimensions(3840, 2160),
        encoding: VideoEncoding(maxBitrate: _screenKbps(q) * 1000, maxFramerate: q.fps),
      );

  static int _screenKbps(ScreenShareQuality q) {
    const at60 = {
      ScreenResolution.p720: 4500,
      ScreenResolution.p1080: 8000,
      ScreenResolution.p1440: 12000,
      ScreenResolution.source: 15000,
    };
    final kbps60 = at60[q.resolution]!;
    return switch (q.fps) {
      >= 60 => kbps60,
      >= 30 => kbps60 * 5 ~/ 8,
      _ => kbps60 * 3 ~/ 8,
    };
  }

  static VideoParameters screen({required bool phone}) => phone ? phoneScreen : computerScreen;

  static VideoEncoding screenEncoding({required bool phone}) => screen(phone: phone).encoding!;

  static const String computerScreenCodec = 'h264';

  static const DegradationPreference degradation = DegradationPreference.maintainFramerate;
}

enum ScreenResolution {
  p720('720', VideoDimensionsPresets.h720_169),
  p1080('1080', VideoDimensionsPresets.h1080_169),
  p1440('1440', VideoDimensions(2560, 1440)),
  source('source', null);

  final String wire;
  final VideoDimensions? size;

  const ScreenResolution(this.wire, this.size);
}

class ScreenShareQuality {
  final ScreenResolution resolution;
  final int fps;

  const ScreenShareQuality(this.resolution, this.fps);

  static const List<int> fpsChoices = [15, 30, 60];
  static const List<ScreenResolution> resolutions = ScreenResolution.values;

  static const standard = ScreenShareQuality(ScreenResolution.p1080, 60);

  ScreenShareQuality copyWith({ScreenResolution? resolution, int? fps}) =>
      ScreenShareQuality(resolution ?? this.resolution, fps ?? this.fps);

  String toWire() => '${resolution.wire}:$fps';

  static ScreenShareQuality fromWire(String? raw) {
    final parts = (raw ?? '').split(':');
    if (parts.length != 2) return standard;
    final resolution = ScreenResolution.values.where((r) => r.wire == parts[0]).firstOrNull;
    final fps = int.tryParse(parts[1]);
    if (resolution == null || fps == null || !fpsChoices.contains(fps)) return standard;
    return ScreenShareQuality(resolution, fps);
  }

  @override
  bool operator ==(Object other) => other is ScreenShareQuality && other.resolution == resolution && other.fps == fps;

  @override
  int get hashCode => Object.hash(resolution, fps);
}

