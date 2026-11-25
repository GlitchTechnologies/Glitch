import 'package:camera/camera.dart' show CameraLensDirection;
import 'package:shared_preferences/shared_preferences.dart';

class VideoNoteCameraService {
  static const _prefsKey = 'video_note_lens_v1';
  static const _fallback = CameraLensDirection.front;

  CameraLensDirection _current = _fallback;

  CameraLensDirection get current => _current;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved == null) return;
    for (final dir in CameraLensDirection.values) {
      if (dir.name == saved) {
        _current = dir;
        return;
      }
    }
  }

  Future<void> remember(CameraLensDirection? dir) async {
    if (dir == null || dir == _current) return;
    _current = dir;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, dir.name);
  }
}

final videoNoteCamera = VideoNoteCameraService();
