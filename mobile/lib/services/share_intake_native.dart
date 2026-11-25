import 'dart:async';
import 'package:cross_file/cross_file.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../models/shared_content.dart';


Future<SharedContent?> initialSharedContent() async {
  final files = await ReceiveSharingIntent.instance.getInitialMedia();
  ReceiveSharingIntent.instance.reset();
  if (files.isEmpty) return null;
  return _build(files);
}

StreamSubscription<SharedContent>? listenSharedContent(
  void Function(SharedContent) onContent,
) {
  return ReceiveSharingIntent.instance
      .getMediaStream()
      .asyncMap(_build)
      .listen(onContent);
}

Future<SharedContent> _build(List<SharedMediaFile> files) async {
  final media = <XFile>[];
  SharedMediaFile? doc;
  String text = '';
  String caption = '';
  for (final f in files) {
    if (f.type == SharedMediaType.url) {
      continue; // не шер, а открытая ссылка — ею занимается app_links
    }
    if (f.type == SharedMediaType.image || f.type == SharedMediaType.video) {
      media.add(XFile(f.path));
    } else if (f.type == SharedMediaType.text) {
      text = text.isEmpty ? f.path : '$text\n${f.path}';
    } else {
      doc ??= f;
    }
    final m = f.message;
    if (m != null && m.isNotEmpty && caption.isEmpty) caption = m;
  }
  final captionOrText = text.isNotEmpty ? text : caption;
  if (media.isNotEmpty) {
    return SharedContent(media: media, text: captionOrText);
  }
  if (doc != null) {
    final file = XFile(doc.path);
    int size = 0;
    try {
      size = await file.length();
    } catch (_) {}
    return SharedContent(
      file: file,
      fileName: doc.path.split('/').last,
      fileSize: size,
      fileMime: doc.mimeType ?? 'application/octet-stream',
      text: captionOrText,
    );
  }
  return SharedContent(text: captionOrText);
}
