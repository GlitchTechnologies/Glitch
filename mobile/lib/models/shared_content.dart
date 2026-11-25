import 'package:cross_file/cross_file.dart';

class SharedContent {
  final List<XFile> media;

  final XFile? file;
  final String? fileName;
  final int? fileSize;
  final String? fileMime;

  final String text;

  const SharedContent({
    this.media = const [],
    this.file,
    this.fileName,
    this.fileSize,
    this.fileMime,
    this.text = '',
  });

  bool get isEmpty => media.isEmpty && file == null && text.isEmpty;
}
