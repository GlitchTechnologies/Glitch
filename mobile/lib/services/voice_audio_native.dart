library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier, Listenable;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc show Helper;
import 'package:glitch_ringtone/glitch_ringtone.dart' show GlitchRingtone;
import 'package:livekit_client/livekit_client.dart' as lk;

import 'error_reporter.dart';
import 'voice_cue.dart';

const bool outputDeviceSelectionSupported = false;

const bool outputVolumeSupported = false;

void applyOutputVolume(double volume) {}

void prepareVoicePlayback() {}

final Listenable voicePlaybackChanges = ChangeNotifier();

final Map<String, lk.Track> _voices = {};

void playRemoteAudio(String key, lk.Track track, double level) {
  _voices[key] = track;
  _setLevel(track, level);
}

void setRemoteAudioLevel(String key, double level) {
  final track = _voices[key];
  if (track != null) _setLevel(track, level);
}

void stopRemoteAudio(String key) => _voices.remove(key);

void stopAllRemoteAudio() => _voices.clear();

void _setLevel(lk.Track track, double level) {
  unawaited(rtc.Helper.setVolume(level, track.mediaStreamTrack).catchError((Object e, StackTrace s) {
    errorReporter.report(e, stack: s, screen: 'voice:setRemoteVolume');
  }));
}

Future<void> setVoiceOutputDevice(String deviceId) async {}

bool voicePlaybackAllowed() => true;

Future<void> resumeVoicePlayback() async {}

Future<void> playVoiceCue(VoiceCue cue, {required double volume, String? outputDeviceId}) =>
    GlitchRingtone.playCue(cue.androidRes);
