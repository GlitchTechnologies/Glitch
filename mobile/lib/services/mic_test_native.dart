library;

import 'package:livekit_client/livekit_client.dart' as lk;

import 'mic_options.dart';
import 'mic_test.dart';

const bool micTestSupported = false;

Future<MicTest> openMicTest({
  required lk.AudioCaptureOptions capture,
  required MicProcessing processing,
  required double attenuationDb,
  String? outputDeviceId,
  required double volume,
  bool hear = true,
}) =>
    throw UnsupportedError('mic test is web-only');
