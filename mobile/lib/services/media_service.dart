import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cross_file/cross_file.dart';
import '../core/platform_info.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
// Всё, что умеет только платформа с настоящим диском (перекодирование видео,
// кадр-превью, временная папка), заперто за условным импортом: dart:io,
// video_compress и path_provider — каждого из них достаточно, чтобы сломать
// веб-сборку одним лишь импортом.
import 'media_platform_web.dart' if (dart.library.io) 'media_platform_native.dart';



class _PhotoConfig {
  static const int quality   = 85;   // % качества JPEG (85 — глаз не видит разницы)
  static const int maxWidth  = 2560; // px — как в Telegram
  static const int maxHeight = 2560;
}



class MediaService {
  MediaService._();
  static final MediaService instance = MediaService._();

  String ext(XFile file) {
    final name = file.name;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  bool isVideo(XFile file) =>
      ['mp4', 'mov', 'avi', 'webm'].contains(ext(file));

  bool isImage(XFile file) =>
      ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext(file));

  String mimeType(XFile file) {
    const map = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
      'png': 'image/png',  'webp': 'image/webp', 'gif': 'image/gif',
      'mp4': 'video/mp4',  'mov': 'video/quicktime',
      'avi': 'video/x-msvideo', 'webm': 'video/webm',
    };
    return map[ext(file)] ?? 'application/octet-stream';
  }

  Future<XFile> compressPhoto(XFile file) async {
    try {
      final sz = await imageSize(file);
      final targetW = sz != null ? sz.w.clamp(1, _PhotoConfig.maxWidth) : _PhotoConfig.maxWidth;
      final targetH = sz != null ? sz.h.clamp(1, _PhotoConfig.maxHeight) : _PhotoConfig.maxHeight;

      if (!hasFileSystem) {
        final bytes = await file.readAsBytes();
        final out = await FlutterImageCompress.compressWithList(
          bytes,
          quality:   _PhotoConfig.quality,
          minWidth:  targetW,
          minHeight: targetH,
          format:    CompressFormat.jpeg,
        );
        if (out.isNotEmpty) {
          return XFile.fromData(
            Uint8List.fromList(out),
            name: _asJpegName(file.name),
            mimeType: 'image/jpeg',
            length: out.length,
          );
        }
        return file;
      }

      final dir = await tempDirPath();
      if (dir == null) return file;
      final out = '$dir/photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final result = await FlutterImageCompress.compressAndGetFile(
        file.path, out,
        quality:   _PhotoConfig.quality,
        minWidth:  targetW,
        minHeight: targetH,
        format:    CompressFormat.jpeg,
      );
      if (result != null) return result;
    } catch (_) {}
    return file;
  }

  Future<XFile> compressVideo(XFile file) =>
      compressVideoFile(file, lowQuality: false);

  Future<XFile> compressVideoNote(XFile file) =>
      compressVideoFile(file, lowQuality: true);

  String _asJpegName(String name) {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    return '$base.jpg';
  }

  Future<XFile> compressAvatar(XFile file) async {
    if (isGif(file)) return file;
    try {
      final isPng   = ext(file) == 'png';
      final format  = isPng ? CompressFormat.png : CompressFormat.jpeg;
      final suffix  = isPng ? 'png' : 'jpg';

      if (!hasFileSystem) {
        final bytes = await file.readAsBytes();
        final out = await FlutterImageCompress.compressWithList(
          bytes,
          quality:   90,
          minWidth:  512,
          minHeight: 512,
          format:    format,
        );
        if (out.isNotEmpty) {
          final base = file.name.contains('.')
              ? file.name.substring(0, file.name.lastIndexOf('.'))
              : file.name;
          return XFile.fromData(
            Uint8List.fromList(out),
            name: '$base.$suffix',
            mimeType: isPng ? 'image/png' : 'image/jpeg',
            length: out.length,
          );
        }
        return file;
      }

      final dir = await tempDirPath();
      if (dir == null) return file;
      final out = '$dir/avatar_${DateTime.now().millisecondsSinceEpoch}.$suffix';
      final result = await FlutterImageCompress.compressAndGetFile(
        file.path, out,
        quality:   90,
        minWidth:  512,
        minHeight: 512,
        format:    format,
      );
      if (result != null) return result;
    } catch (_) {}
    return file;
  }

  bool isGif(XFile file) => ext(file) == 'gif';

  Future<XFile> compress(XFile file) async {
    if (isGif(file)) return file;
    if (isImage(file)) return compressPhoto(file);
    if (isVideo(file)) return compressVideo(file);
    return file;
  }

  Future<({int w, int h})?> imageSize(XFile file) async {
    ui.Codec? codec;
    try {
      final bytes = await file.readAsBytes();
      codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      frame.image.dispose();
      return (w: w, h: h);
    } catch (_) {
      return null;
    } finally {
      codec?.dispose();
    }
  }

  Future<XFile?> videoThumb(XFile file) => videoThumbFile(file);

  Future<({int w, int h})?> videoSize(XFile file) async {
    try {
      final thumb = await videoThumbBytes(file, quality: 50);
      if (thumb == null) return null;
      final codec = await ui.instantiateImageCodec(thumb);
      try {
        final frame = await codec.getNextFrame();
        final w = frame.image.width;
        final h = frame.image.height;
        frame.image.dispose();
        return (h > 0) ? (w: w, h: h) : null;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }
}

final mediaService = MediaService.instance;
