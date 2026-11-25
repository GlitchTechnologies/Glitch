import 'dart:async';
import 'dart:js_interop';

import 'package:cross_file/cross_file.dart';
import 'package:web/web.dart' as web;

import '../models/attach_result.dart' show PendingFile;
import 'file_pick.dart' show guessDocumentMime;


class DroppedAttachment {
  final List<XFile> media;

  /// Одиночный документ — тем же путём, что выбор файла через скрепку.
  /// Одновременно с [media] не бывает: сообщение может быть только ОДНОГО
  /// типа (см. главный архитектурный принцип проекта — унифицированная
  /// отправка контента), поэтому при смешанном перетаскивании побеждает
  /// медиа, а документы уходят в [skipped].
  final PendingFile? file;

  final int skipped;

  const DroppedAttachment({this.media = const [], this.file, this.skipped = 0});
}

typedef FilesDroppedHandler = void Function(DroppedAttachment attachment);

typedef DragActiveHandler = void Function(bool active);

class _Listener {
  final FilesDroppedHandler onDropped;
  final DragActiveHandler onDragActiveChanged;
  _Listener(this.onDropped, this.onDragActiveChanged);
}

/// Кто сейчас готов принять перетащенный файл. Список, а НЕ единственный
/// обработчик — та же причина, что и у вставки из буфера: плашек ввода на
/// экране может быть несколько одновременно (так было: лента каналов + открытые под ней
/// комментарии), и перетаскивание обязано попасть в ВЕРХНЮЮ, то есть в ту, что
/// подписалась последней.
final List<_Listener> _listeners = [];

int _enterDepth = 0;

JSFunction? _onDragEnter;
JSFunction? _onDragOver;
JSFunction? _onDragLeave;
JSFunction? _onDrop;

/// Подписаться на перетаскивание. Возвращает функцию отписки — звать в
/// dispose(), иначе закрытый экран продолжит получать события (и, если
/// отписка происходит посреди активного перетаскивания, сама снимает
/// подсказку, чтобы та не зависла).
void Function() listenFileDrop(
  FilesDroppedHandler onDropped,
  DragActiveHandler onDragActiveChanged,
) {
  final listener = _Listener(onDropped, onDragActiveChanged);
  _listeners.add(listener);
  _ensureDomListeners();
  return () {
    final wasActiveListener = _listeners.isNotEmpty && identical(_listeners.last, listener);
    _listeners.remove(listener);
    if (wasActiveListener && _enterDepth > 0) {
      _enterDepth = 0;
      listener.onDragActiveChanged(false);
    }
  };
}

bool _isFileDrag(web.DataTransfer? data) {
  if (data == null) return false;
  final types = data.types.toDart;
  for (final t in types) {
    if (t.toDart == 'Files') return true;
  }
  return false;
}

void _ensureDomListeners() {
  if (_onDrop != null) return;

  _onDragEnter = ((web.DragEvent event) {
    if (_listeners.isEmpty || !_isFileDrag(event.dataTransfer)) return;
    event.preventDefault();
    _enterDepth++;
    if (_enterDepth == 1) _listeners.last.onDragActiveChanged(true);
  }).toJS;

  _onDragOver = ((web.DragEvent event) {
    if (_listeners.isEmpty || !_isFileDrag(event.dataTransfer)) return;
    event.preventDefault();
  }).toJS;

  _onDragLeave = ((web.DragEvent event) {
    if (_listeners.isEmpty || _enterDepth == 0) return;
    _enterDepth--;
    if (_enterDepth == 0) _listeners.last.onDragActiveChanged(false);
  }).toJS;

  _onDrop = ((web.DragEvent event) {
    if (_listeners.isEmpty || !_isFileDrag(event.dataTransfer)) return;
    event.preventDefault();
    final listener = _listeners.last;
    _enterDepth = 0;
    listener.onDragActiveChanged(false);
    unawaited(_handleDrop(event.dataTransfer?.files, listener));
  }).toJS;

  web.document.addEventListener('dragenter', _onDragEnter);
  web.document.addEventListener('dragover', _onDragOver);
  web.document.addEventListener('dragleave', _onDragLeave);
  web.document.addEventListener('drop', _onDrop);
}

Future<void> _handleDrop(web.FileList? fileList, _Listener listener) async {
  if (fileList == null || fileList.length == 0) return;

  final mediaSrc = <web.File>[];
  final otherSrc = <web.File>[];
  for (var i = 0; i < fileList.length; i++) {
    final file = fileList.item(i);
    if (file == null) continue;
    final type = file.type.toLowerCase();
    if (type.startsWith('image/') || type.startsWith('video/')) {
      mediaSrc.add(file);
    } else {
      otherSrc.add(file);
    }
  }
  if (mediaSrc.isEmpty && otherSrc.isEmpty) return;

  if (mediaSrc.isNotEmpty) {
    final media = await _readAsXFiles(mediaSrc);
    if (media.isEmpty) return;
    listener.onDropped(DroppedAttachment(media: media, skipped: otherSrc.length));
    return;
  }

  final pending = await _readAsPendingFile(otherSrc.first);
  if (pending == null) return;
  listener.onDropped(DroppedAttachment(file: pending, skipped: otherSrc.length - 1));
}

Future<List<XFile>> _readAsXFiles(List<web.File> files) async {
  final result = <XFile>[];
  for (final file in files) {
    try {
      final buffer = await file.arrayBuffer().toDart;
      final bytes = buffer.toDart.asUint8List();
      if (bytes.isEmpty) continue;
      result.add(XFile.fromData(
        bytes,
        name: file.name,
        mimeType: file.type.isEmpty ? null : file.type,
        length: bytes.length,
      ));
    } catch (_) {
    }
  }
  return result;
}

Future<PendingFile?> _readAsPendingFile(web.File file) async {
  try {
    final buffer = await file.arrayBuffer().toDart;
    final bytes = buffer.toDart.asUint8List();
    if (bytes.isEmpty) return null;
    final mime = file.type.isEmpty ? guessDocumentMime(file.name) : file.type;
    return PendingFile(
      file: XFile.fromData(bytes, name: file.name, mimeType: mime, length: bytes.length),
      name: file.name,
      size: bytes.length,
      mimeType: mime,
    );
  } catch (_) {
    return null;
  }
}
