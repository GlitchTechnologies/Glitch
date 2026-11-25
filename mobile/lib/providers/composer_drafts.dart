import 'package:cross_file/cross_file.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/attach_result.dart';

class AttachmentDraft {
  final List<XFile> photos;
  final Map<String, int> videoDurations;
  final PendingFile? file;
  final GeoResult? geo;

  const AttachmentDraft({
    this.photos = const [],
    this.videoDurations = const {},
    this.file,
    this.geo,
  });

  bool get isEmpty => photos.isEmpty && file == null && geo == null;
}

class ComposerDrafts {
  static const chatPrefix = 'draft_';

  static String webhookKey(int webhookId) => 'webhook_draft_$webhookId';

  static const savedPrefixes = [chatPrefix, 'webhook_draft_', 'ch_draft_text_', 'ch_draft_photo_'];

  Future<String> load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key) ?? '';
  }

  Future<void> save(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  final Map<String, AttachmentDraft> _byKey = {};

  AttachmentDraft of(String key) => _byKey[key] ?? const AttachmentDraft();

  void put(String key, AttachmentDraft draft) {
    if (draft.isEmpty) {
      _byKey.remove(key);
    } else {
      _byKey[key] = draft;
    }
  }

  void clear() => _byKey.clear();
}

final composerDrafts = ComposerDrafts();
