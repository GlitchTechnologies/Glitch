import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CallAudioPrefs {
  static const _inputKey = 'call_audio_input_v1';
  static const _outputKey = 'call_audio_output_v1';
  static const _cameraKey = 'call_video_camera_v1';
  static const _volumeKey = 'call_audio_volume_v1';
  static const _noiseKey = 'call_audio_noise_v1';
  static const _micVolumeKey = 'call_audio_mic_volume_v1';
  static const _echoKey = 'call_audio_echo_v1';
  static const _agcKey = 'call_audio_agc_v1';
  static const _pttKey = 'call_audio_ptt_v1';
  static const _pttDelayKey = 'call_audio_ptt_delay_ms_v1';
  static const _autoSensitivityKey = 'call_audio_auto_sensitivity_v1';
  static const _sensitivityKey = 'call_audio_sensitivity_db_v1';

  static const int minSensitivityDb = -100;
  static const int defaultSensitivityDb = -60;

  static const int maxPushToTalkDelayMs = 2000;
  static const int defaultPushToTalkDelayMs = 20;

  static const double maxPersonVolume = 2;

  String? inputId;
  String? outputId;

  String? cameraId;

  double volume = 1.0;

  bool noiseSuppression = true;

  double micVolume = 1.0;

  bool echoCancellation = true;
  bool autoGainControl = true;

  bool pushToTalk = false;

  int pushToTalkDelayMs = defaultPushToTalkDelayMs;

  bool autoSensitivity = true;
  int sensitivityDb = defaultSensitivityDb;

  final PeopleAudio voice = PeopleAudio._('call_audio_people_volume_v1', 'call_audio_people_muted_v1');

  final PeopleAudio stream = PeopleAudio._('call_audio_stream_volume_v1', 'call_audio_stream_muted_v1');

  Future<void>? _loading;

  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    final prefs = await SharedPreferences.getInstance();
    inputId = prefs.getString(_inputKey);
    outputId = prefs.getString(_outputKey);
    cameraId = prefs.getString(_cameraKey);
    volume = (prefs.getDouble(_volumeKey) ?? 1.0).clamp(0.0, 1.0).toDouble();
    noiseSuppression = prefs.getBool(_noiseKey) ?? true;
    micVolume = (prefs.getDouble(_micVolumeKey) ?? 1.0).clamp(0.0, 1.0).toDouble();
    echoCancellation = prefs.getBool(_echoKey) ?? true;
    autoGainControl = prefs.getBool(_agcKey) ?? true;
    pushToTalk = prefs.getBool(_pttKey) ?? false;
    pushToTalkDelayMs =
        (prefs.getInt(_pttDelayKey) ?? defaultPushToTalkDelayMs).clamp(0, maxPushToTalkDelayMs).toInt();
    autoSensitivity = prefs.getBool(_autoSensitivityKey) ?? true;
    sensitivityDb =
        (prefs.getInt(_sensitivityKey) ?? defaultSensitivityDb).clamp(minSensitivityDb, 0).toInt();
    voice._read(prefs);
    stream._read(prefs);
  }

  Future<void> saveInput(String deviceId) async {
    inputId = deviceId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_inputKey, deviceId);
  }

  Future<void> saveCamera(String deviceId) async {
    cameraId = deviceId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cameraKey, deviceId);
  }

  Future<void> saveOutput(String deviceId) async {
    outputId = deviceId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_outputKey, deviceId);
  }

  void setVolume(double value) => volume = value.clamp(0.0, 1.0).toDouble();

  Future<void> saveVolume() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_volumeKey, volume);
  }

  void setMicVolume(double value) => micVolume = value.clamp(0.0, 1.0).toDouble();

  Future<void> saveMicVolume() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_micVolumeKey, micVolume);
  }

  Future<void> clearPeople() async {
    await load();
    final prefs = await SharedPreferences.getInstance();
    await voice._clear(prefs);
    await stream._clear(prefs);
  }

  Future<void> saveNoiseSuppression(bool on) async {
    noiseSuppression = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_noiseKey, on);
  }

  Future<void> saveEchoCancellation(bool on) async {
    echoCancellation = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_echoKey, on);
  }

  Future<void> saveAutoGainControl(bool on) async {
    autoGainControl = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_agcKey, on);
  }

  Future<void> savePushToTalk(bool on) async {
    pushToTalk = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pttKey, on);
  }

  void setPushToTalkDelay(int ms) => pushToTalkDelayMs = ms.clamp(0, maxPushToTalkDelayMs).toInt();

  Future<void> savePushToTalkDelay() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pttDelayKey, pushToTalkDelayMs);
  }

  Future<void> saveAutoSensitivity(bool on) async {
    autoSensitivity = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSensitivityKey, on);
  }

  void setSensitivity(int db) => sensitivityDb = db.clamp(minSensitivityDb, 0).toInt();

  Future<void> saveSensitivity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sensitivityKey, sensitivityDb);
  }
}

final callAudioPrefs = CallAudioPrefs();

class PeopleAudio {
  PeopleAudio._(this._volumeKey, this._mutedKey);

  final String _volumeKey;
  final String _mutedKey;

  final Map<int, double> _volume = {};
  final Set<int> _muted = {};

  double volumeOf(int userId) => _volume[userId] ?? 1.0;
  bool isMuted(int userId) => _muted.contains(userId);

  void _read(SharedPreferences prefs) {
    _volume.clear();
    _muted.clear();
    try {
      final volumes = jsonDecode(prefs.getString(_volumeKey) ?? '{}') as Map<String, dynamic>;
      for (final e in volumes.entries) {
        final id = int.tryParse(e.key);
        final v = e.value;
        if (id != null && v is num) _volume[id] = v.toDouble().clamp(0.0, CallAudioPrefs.maxPersonVolume).toDouble();
      }
    } catch (_) {
    }
    for (final raw in prefs.getStringList(_mutedKey) ?? const <String>[]) {
      final id = int.tryParse(raw);
      if (id != null) _muted.add(id);
    }
  }

  void setVolume(int userId, double volume) {
    final v = volume.clamp(0.0, CallAudioPrefs.maxPersonVolume).toDouble();
    if (v == 1.0) {
      _volume.remove(userId);
    } else {
      _volume[userId] = v;
    }
  }

  Future<void> saveVolumes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_volumeKey, jsonEncode({for (final e in _volume.entries) '${e.key}': e.value}));
  }

  Future<void> saveMuted(int userId, bool muted) async {
    muted ? _muted.add(userId) : _muted.remove(userId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_mutedKey, [for (final id in _muted) '$id']);
  }

  Future<void> _clear(SharedPreferences prefs) async {
    _volume.clear();
    _muted.clear();
    await prefs.remove(_volumeKey);
    await prefs.remove(_mutedKey);
  }
}
