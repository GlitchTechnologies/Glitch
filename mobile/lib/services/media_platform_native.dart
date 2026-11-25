import 'dart:io';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Зачем вынесено отдельно: здесь заперты три вещи, каждой из которых
/// достаточно, чтобы сломать сборку под браузер одним лишь импортом —
/// `dart:io`, `video_compress` (веб-версии пакета не существует вовсе) и
/// `path_provider` (возвращает `Directory`, а это тип из dart:io).

Future<void> deleteTempFile(XFile file) async {
  try {
    final f = File(file.path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

Future<String?> tempDirPath() async {
  try {
    final dir = await getTemporaryDirectory();
    return dir.path;
  } catch (_) {
    return null;
  }
}

Future<String?> tempFilePath(String name) async {
  final dir = await tempDirPath();
  return dir == null ? null : '$dir/$name';
}

/// Убирает временный файл, известный только по пути (а не по XFile).
/// Отдельная форма нужна там, где файла как объекта ещё/уже нет — например при
/// откате прерванной записи или уборке в dispose.
Future<void> deleteTempPath(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

/// Черновик поста хранит ПУТИ к выбранным фото, а не сами фото. К моменту
/// возврата на экран файла могло уже не быть (человек удалил его из галереи,
/// система вычистила кэш) — такие пути молча отбрасываются, иначе на отправке
/// вылезла бы ошибка про несуществующий файл.
Future<List<XFile>> restoreLocalFiles(List<String> paths) async {
  final out = <XFile>[];
  for (final p in paths) {
    try {
      if (await File(p).exists()) out.add(XFile(p));
    } catch (_) {}
  }
  return out;
}

Future<XFile?> saveTempBytes(Uint8List bytes, String name) async {
  try {
    final path = await tempFilePath(name);
    if (path == null) return null;
    final f = File(path);
    await f.writeAsBytes(bytes);
    return XFile(path);
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> videoFrameBytes(
  XFile video, {
  required int maxWidth,
  required int quality,
}) async {
  try {
    return await VideoThumbnail.thumbnailData(
      video: video.path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: maxWidth,
      quality: quality,
    );
  } catch (_) {
    return null;
  }
}

Future<XFile> compressVideoFile(XFile file, {required bool lowQuality}) async {
  try {
    final info = await VideoCompress.compressVideo(
      file.path,
      // HighestQuality = 1080p
      quality: lowQuality ? VideoQuality.LowQuality : VideoQuality.HighestQuality,
      deleteOrigin: false,
      includeAudio: true,
    );
    final out = info?.file;
    if (out != null) return XFile(out.path);
  } catch (_) {}
  return file;
}

Future<Uint8List?> videoThumbBytes(XFile file, {required int quality}) async {
  try {
    return await VideoCompress.getByteThumbnail(file.path, quality: quality);
  } catch (_) {
    return null;
  }
}

Future<XFile?> videoThumbFile(XFile file) async {
  try {
    final bytes = await videoThumbBytes(file, quality: 70);
    if (bytes == null) return null;
    final dir = await tempDirPath();
    if (dir == null) return null;
    final out = File('$dir/vthumb_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await out.writeAsBytes(bytes);
    return XFile(out.path);
  } catch (_) {
    return null;
  }
}

/// Отдельно от videoFrameBytes: там локальный файл, здесь адрес плюс заголовки
/// авторизации. Используется в лентах и вкладках «Медиа», где надо показать
/// превью, не выкачивая ролик.
Future<Uint8List?> videoFrameFromUrl(
  String url, {
  Map<String, String> headers = const {},
  required int maxWidth,
  required int quality,
}) async {
  try {
    return await VideoThumbnail.thumbnailData(
      video: url,
      headers: headers,
      imageFormat: ImageFormat.JPEG,
      maxWidth: maxWidth,
      quality: quality,
    );
  } catch (_) {
    return null;
  }
}
