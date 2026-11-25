import 'package:livekit_client/livekit_client.dart' as lk;

import '../core/platform_info.dart';


typedef MicProcessing = ({bool noise, double volume, MicGate? gate});

typedef MicGate = ({bool auto, double thresholdDb});

const double kMicSilenceDb = -100;

const int kMicGateHoldMs = 300;

const double kMicGateAutoMarginDb = 15;

const double kMicGateAutoMinDb = -70;
const double kMicGateAutoMaxDb = -30;

const int kMicGateFloorWindowMs = 4000;

lk.AudioCaptureOptions micCaptureOptions({
  String? deviceId,
  required bool echoCancellation,
  required bool autoGainControl,
}) =>
    _MicCaptureOptions(
      deviceId: deviceId,
      echoCancellation: echoCancellation,
      autoGainControl: autoGainControl,
    );

class _MicCaptureOptions extends lk.AudioCaptureOptions {
  const _MicCaptureOptions({
    super.deviceId,
    required super.echoCancellation,
    required super.autoGainControl,
  });

  @override
  Map<String, dynamic> toMediaConstraintsMap() {
    final constraints = super.toMediaConstraintsMap();
    if (isWebPlatform && !constraints.containsKey('optional')) {
      constraints.addAll(<String, dynamic>{
        'echoCancellation': echoCancellation,
        'autoGainControl': autoGainControl,
        'noiseSuppression': noiseSuppression,
        'voiceIsolation': noiseSuppression,
      });
    }
    return constraints;
  }
}
