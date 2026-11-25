import 'package:cross_file/cross_file.dart';
import '../models/attach_result.dart' show PendingFile;


class DroppedAttachment {
  final List<XFile> media;
  final PendingFile? file;
  final int skipped;
  const DroppedAttachment({this.media = const [], this.file, this.skipped = 0});
}

typedef FilesDroppedHandler = void Function(DroppedAttachment attachment);
typedef DragActiveHandler = void Function(bool active);

void Function() listenFileDrop(
  FilesDroppedHandler onDropped,
  DragActiveHandler onDragActiveChanged,
) =>
    () {};
