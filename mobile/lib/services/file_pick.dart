import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import '../core/platform_info.dart';
import '../models/attach_result.dart';

Future<List<PendingFile>> pickSystemFiles({bool multiple = false}) async {
  final result = await FilePicker.platform.pickFiles(allowMultiple: multiple, withData: !hasFileSystem);
  if (result == null) return const [];
  return [
    for (final pf in result.files)
      if (_fileOf(pf) case final file?)
        PendingFile(file: file, name: pf.name, size: pf.size, mimeType: guessDocumentMime(pf.name)),
  ];
}

XFile? _fileOf(PlatformFile pf) {
  if (hasFileSystem) {
    final path = pf.path;
    return path == null ? null : XFile(path);
  }
  final bytes = pf.bytes;
  return bytes == null ? null : XFile.fromData(bytes, name: pf.name, length: bytes.length);
}

String guessDocumentMime(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  const map = {
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'zip': 'application/zip',
    'rar': 'application/vnd.rar',
    '7z': 'application/x-7z-compressed',
    'txt': 'text/plain',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'ogg': 'audio/ogg',
    'wav': 'audio/wav',
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
    'png': 'image/png', 'webp': 'image/webp', 'gif': 'image/gif',
    'mp4': 'video/mp4', 'webm': 'video/webm', 'mov': 'video/quicktime',
  };
  return map[ext] ?? 'application/octet-stream';
}
