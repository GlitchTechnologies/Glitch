library;

import 'package:glitch_noise_filter/glitch_noise_filter.dart' show GlitchNoiseFilter;
import 'package:livekit_client/livekit_client.dart' as lk;

import '../core/platform_info.dart';
import 'error_reporter.dart';
import 'mic_options.dart';

bool get noiseFilterSupported => isAndroidPlatform;

const bool micVolumeSupported = false;

bool get micGateSupported => isAndroidPlatform;

Future<void> syncMicChain(lk.Room room, MicProcessing processing, {required double attenuationDb}) async {
  if (!noiseFilterSupported) return;
  final gate = processing.gate;
  try {
    if (gate != null) {
      await GlitchNoiseFilter.setGate(auto: gate.auto, thresholdDb: gate.thresholdDb);
    } else {
      await GlitchNoiseFilter.clearGate();
    }
  } catch (e, s) {
    errorReporter.report(e, stack: s, screen: 'voice:micGate');
  }
  if (processing.noise) {
    await GlitchNoiseFilter.start(attenuationDb: attenuationDb);
  } else {
    await GlitchNoiseFilter.stop();
  }
}

Future<void> releaseMicChain() async {
  if (!noiseFilterSupported) return;
  try {
    await GlitchNoiseFilter.stop();
  } finally {
    await GlitchNoiseFilter.clearGate();
  }
}

Future<double?> micChainLevel() async {
  if (!noiseFilterSupported) return null;
  return GlitchNoiseFilter.level();
}
