import 'dart:async';
import 'dart:js_interop';

import 'package:cross_file/cross_file.dart';
import 'package:web/web.dart' as web;

typedef PastedMediaHandler = void Function(List<XFile> files);

/// Кто сейчас готов принять вставленное. Список, а НЕ единственный обработчик:
/// плашек ввода на экране может быть несколько одновременно (так было в ленте каналов
/// открыли комментарии, и обе плашки (поста и комментария) живы, просто одна
/// под другой. Вставка обязана попасть в ВЕРХНЮЮ, то есть в ту, что подписалась
/// последней; без этого одна картинка прикрепилась бы сразу к обеим.
final List<PastedMediaHandler> _handlers = [];

JSFunction? _domListener;

/// Подписаться на вставку. Возвращает функцию отписки — её обязательно звать в
/// dispose(), иначе закрытый экран продолжит получать вставки.
void Function() listenPastedMedia(PastedMediaHandler onMedia) {
  _handlers.add(onMedia);
  _ensureDomListener();
  return () => _handlers.remove(onMedia);
}

void _ensureDomListener() {
  if (_domListener != null) return;
  _domListener = ((web.ClipboardEvent event) {
    final data = event.clipboardData;
    if (data == null) return;

    final files = data.files;
    final picked = <web.File>[];
    for (var i = 0; i < files.length; i++) {
      final file = files.item(i);
      if (file == null) continue;
      final type = file.type.toLowerCase();
      if (type.startsWith('image/') || type.startsWith('video/')) picked.add(file);
    }
    if (picked.isEmpty) return;
    if (_handlers.isEmpty) return;

    event.preventDefault();

    final handler = _handlers.last;
    unawaited(_deliver(picked, handler));
  }).toJS;
  web.document.addEventListener('paste', _domListener);
}

Future<void> _deliver(List<web.File> files, PastedMediaHandler handler) async {
  final result = <XFile>[];
  for (final file in files) {
    try {
      final buffer = await file.arrayBuffer().toDart;
      final bytes = buffer.toDart.asUint8List();
      if (bytes.isEmpty) continue;
      result.add(XFile.fromData(
        bytes,
        name: _safeName(file),
        mimeType: file.type.isEmpty ? null : file.type,
        length: bytes.length,
      ));
    } catch (_) {
    }
  }
  if (result.isNotEmpty) handler(result);
}

String _safeName(web.File file) {
  final name = file.name;
  if (name.isNotEmpty && name.contains('.') && !name.endsWith('.')) return name;

  const map = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
    'image/gif': 'gif',
    'video/mp4': 'mp4',
    'video/quicktime': 'mov',
    'video/webm': 'webm',
  };
  final ext = map[file.type.toLowerCase()] ?? 'png';
  final base = name.isEmpty ? 'pasted' : name.replaceAll('.', '');
  return '$base.$ext';
}
