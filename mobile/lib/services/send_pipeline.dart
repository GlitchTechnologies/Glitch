import 'package:cross_file/cross_file.dart';
import 'media_service.dart';
import 'media_platform_web.dart' if (dart.library.io) 'media_platform_native.dart';
import 'api_service.dart' show MediaUploadResult;
import 'upload_limits.dart';
import '../models/attach_result.dart' show PendingFile;
import '../models/file_audio.dart';

typedef MediaFileUploader = Future<MediaUploadResult> Function(XFile file, String mime, int? w, int? h, XFile? thumb);

class FileUploadResult {
  final String url;
  final String name;
  final int size;
  final FileAudio? audio;
  const FileUploadResult({required this.url, required this.name, required this.size, this.audio});
}

typedef FileUploader   = Future<FileUploadResult> Function(XFile file, String mime, String name);

class CompressedMedia {
  final XFile file;
  final String originalPath;
  final bool isVideo;
  final int size;
  const CompressedMedia({required this.file, required this.originalPath, required this.isVideo, required this.size});
}

class SendPipeline {
  Future<CompressedMedia> compressForUpload(XFile file) async {
    final isVid = mediaService.isVideo(file);
    final compressed = isVid
        ? await mediaService.compressVideo(file)
        : await mediaService.compress(file);
    final size = await compressed.length();
    try {
      await uploadLimits.ensureFits(isVid ? UploadKind.video : UploadKind.photo, size);
    } catch (_) {
      if (compressed.path != file.path) await deleteTempFile(compressed);
      rethrow;
    }
    return CompressedMedia(file: compressed, originalPath: file.path, isVideo: isVid, size: size);
  }

  Future<List<CompressedMedia>> compressAllForUpload(List<XFile> files) async {
    final done = <CompressedMedia>[];
    try {
      for (final f in files) {
        done.add(await compressForUpload(f));
      }
      return done;
    } catch (_) {
      await discardCompressed(done);
      rethrow;
    }
  }

  Future<void> discardCompressed(Iterable<CompressedMedia> items) async {
    for (final m in items) {
      if (m.file.path != m.originalPath) await deleteTempFile(m.file);
    }
  }

  Future<MediaUploadResult> uploadCompressed(CompressedMedia media, MediaFileUploader doUpload) async {
    XFile? thumb;
    try {
      final mime = mediaService.mimeType(media.file);
      int? w, h;
      if (!media.isVideo) {
        final sz = await mediaService.imageSize(media.file);
        w = sz?.w;
        h = sz?.h;
      } else {
        final sz = await mediaService.videoSize(media.file);
        w = sz?.w;
        h = sz?.h;
        thumb = await mediaService.videoThumb(media.file);
      }
      return await doUpload(media.file, mime, w, h, thumb);
    } finally {
      if (media.file.path != media.originalPath) {
        await deleteTempFile(media.file);
      }
      final t = thumb;
      if (t != null) await deleteTempFile(t);
    }
  }

  Future<MediaUploadResult> uploadWithDims(XFile file, MediaFileUploader doUpload) async {
    final media = await compressForUpload(file);
    return uploadCompressed(media, doUpload);
  }

  Future<FileUploadResult> uploadFile(PendingFile pf, FileUploader doUpload) =>
      doUpload(pf.file, pf.mimeType, pf.name);

  Future<XFile> prepareVideoNote(XFile raw) async {
    final compressed = await mediaService.compressVideoNote(raw);
    if (compressed.path != raw.path) {
      await deleteTempFile(raw);
    }
    return compressed;
  }
}

final sendPipeline = SendPipeline();
