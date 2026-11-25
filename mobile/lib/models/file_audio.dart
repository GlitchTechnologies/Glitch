class FileAudio {
  final String format;
  final double duration;
  const FileAudio({required this.format, required this.duration});

  static FileAudio? fromJson(dynamic value) {
    if (value is! Map) return null;
    final duration = value['duration'];
    final format = value['format'];
    if (duration is! num || !duration.isFinite || duration <= 0 || duration > 2147483647 ||
        !const {'mp3', 'm4a', 'wav', 'flac', 'ogg'}.contains(format)) return null;
    return FileAudio(format: format as String, duration: duration.toDouble());
  }

  Map<String, dynamic> toJson() => {'format': format, 'duration': duration};

  static bool canTry(String name, FileAudio? info) => info != null ||
      const {'mp3', 'm4a', 'wav', 'flac', 'ogg', 'oga', 'opus'}.contains(name.split('.').last.toLowerCase());
}
