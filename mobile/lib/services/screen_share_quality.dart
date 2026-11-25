import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/call_video_quality.dart';

class ScreenShareQualityStore extends ValueNotifier<ScreenShareQuality> {
  ScreenShareQualityStore() : super(ScreenShareQuality.standard);

  static const _prefsKey = 'screen_share_quality_v1';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = ScreenShareQuality.fromWire(prefs.getString(_prefsKey));
    } catch (e) {
      debugPrint('screenShareQuality.load: $e');
    }
  }

  Future<void> choose(ScreenShareQuality quality) async {
    if (value == quality) return;
    value = quality;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, quality.toWire());
    } catch (e) {
      debugPrint('screenShareQuality.choose: $e');
    }
  }
}

final screenShareQuality = ScreenShareQualityStore();

class ScreenShareSoundStore extends ValueNotifier<bool> {
  ScreenShareSoundStore() : super(true);

  static const _prefsKey = 'screen_share_sound_v1';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = prefs.getBool(_prefsKey) ?? true;
    } catch (e) {
      debugPrint('screenShareSound.load: $e');
    }
  }

  Future<void> choose(bool on) async {
    if (value == on) return;
    value = on;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, on);
    } catch (e) {
      debugPrint('screenShareSound.choose: $e');
    }
  }
}

final screenShareSound = ScreenShareSoundStore();
