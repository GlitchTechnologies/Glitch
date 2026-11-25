import 'package:cross_file/cross_file.dart';

import 'poll.dart' show PollDraft;

sealed class AttachResult {}

class PhotosResult extends AttachResult {
  final List<XFile> files;

  /// Длительность видео в секундах, ключ — путь файла. Заполняется только там,
  /// где источник её знает (галерея, камера).
  final Map<String, int> durations;

  PhotosResult(this.files, {this.durations = const {}});
}

class FileResult extends AttachResult {
  final PendingFile file;
  FileResult(this.file);
}

class GeoResult extends AttachResult {
  final double lat;
  final double lon;
  GeoResult(this.lat, this.lon);
}

class PollResult extends AttachResult {
  final PollDraft draft;
  PollResult(this.draft);
}

class PendingFile {
  final XFile file;
  final String name;
  final int size;
  final String mimeType;
  PendingFile({required this.file, required this.name, required this.size, required this.mimeType});
}
