import 'package:shared_preferences/shared_preferences.dart';

const _key = 'glitch_voice_place_v1';
const _atKey = 'glitch_voice_place_at_v1';

Future<({String value, int at})?> readVoicePlace() async {
  final prefs = await SharedPreferences.getInstance();
  final value = prefs.getString(_key);
  final at = prefs.getInt(_atKey);
  if (value == null || at == null) return null;
  return (value: value, at: at);
}

Future<void> writeVoicePlace(String value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_key, value);
  await prefs.setInt(_atKey, DateTime.now().millisecondsSinceEpoch);
}

Future<void> clearVoicePlace() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_key);
  await prefs.remove(_atKey);
}

void markVoiceAlive() {}

void clearVoiceAlive() {}

bool otherTabHoldsVoice(Duration within) => false;
