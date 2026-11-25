import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;


Future<void> deleteTempFile(XFile file) async {}

Future<String?> tempDirPath() async => null;

/// Пути к файлу в браузере тоже не бывает. Возврат null здесь означает «запись
/// в файл невозможна» — и запись голоса на вебе по этой же причине пока
/// выключена (см. MessageComposer.canRecord).
Future<String?> tempFilePath(String name) async => null;

Future<void> deleteTempPath(String path) async {}

Future<List<XFile>> restoreLocalFiles(List<String> paths) async => const [];

Future<XFile?> saveTempBytes(Uint8List bytes, String name) async =>
    XFile.fromData(bytes, name: name, length: bytes.length);

Future<Uint8List?> videoFrameBytes(
  XFile video, {
  required int maxWidth,
  required int quality,
}) async {
  try {
    final bytes = await video.readAsBytes();
    return await _captureFrame(bytes, quality: quality, maxWidth: maxWidth);
  } catch (_) {
    return null;
  }
}

Future<XFile> compressVideoFile(XFile file, {required bool lowQuality}) async => file;

Future<Uint8List?> videoThumbBytes(XFile file, {required int quality}) async {
  try {
    final bytes = await file.readAsBytes();
    return await _captureFrame(bytes, quality: quality);
  } catch (_) {
    return null;
  }
}

Future<XFile?> videoThumbFile(XFile file) async {
  final bytes = await videoThumbBytes(file, quality: 70);
  if (bytes == null) return null;
  return saveTempBytes(bytes, 'vthumb_${DateTime.now().millisecondsSinceEpoch}.jpg');
}

Future<Uint8List?> videoFrameFromUrl(
  String url, {
  Map<String, String> headers = const {},
  required int maxWidth,
  required int quality,
}) async {
  try {
    final res = await http.get(Uri.parse(url), headers: headers);
    if (res.statusCode != 200) return null;
    return await _captureFrame(res.bodyBytes, quality: quality, maxWidth: maxWidth);
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> _captureFrame(
  Uint8List videoBytes, {
  required int quality,
  int? maxWidth,
}) async {
  String? objectUrl;
  web.HTMLVideoElement? video;
  try {
    final blob = web.Blob([videoBytes.toJS].toJS);
    objectUrl = web.URL.createObjectURL(blob);

    // document.createElement + приведение типа — тот же проверенный приём,
    // что уже собрался и заработал в media_actions_web.dart для скачивания
    // файла. Прямой конструктор HTMLVideoElement() здесь намеренно не
    // используется — в отличие от старого dart:html, для package:web это не
    // подтверждённый способ, а его цена ошибки — сломанная сборка.
    video = (web.document.createElement('video') as web.HTMLVideoElement)
      ..muted = true
      ..preload = 'auto'
      ..src = objectUrl;

    final ready = Completer<void>();
    late final JSFunction onLoadedData;
    onLoadedData = (web.Event _) {
      if (!ready.isCompleted) ready.complete();
    }.toJS;
    video.addEventListener('loadeddata', onLoadedData);
    try {
      await ready.future.timeout(const Duration(seconds: 8));
    } finally {
      video.removeEventListener('loadeddata', onLoadedData);
    }

    final nativeW = video.videoWidth;
    final nativeH = video.videoHeight;
    if (nativeW == 0 || nativeH == 0) return null;

    var outW = nativeW;
    var outH = nativeH;
    if (maxWidth != null && nativeW > maxWidth) {
      outW = maxWidth;
      outH = (nativeH * maxWidth / nativeW).round();
    }

    final canvas = (web.document.createElement('canvas') as web.HTMLCanvasElement)
      ..width = outW
      ..height = outH;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    ctx.drawImage(video, 0, 0, outW.toDouble(), outH.toDouble());

    final dataUrl = canvas.toDataURL('image/jpeg', (quality / 100).toJS);
    final base64Part = dataUrl.substring(dataUrl.indexOf(',') + 1);
    return base64Decode(base64Part);
  } catch (_) {
    return null;
  } finally {
    // Сначала снимаем источник у видео-элемента, потом освобождаем ссылку —
    // иначе на части браузеров ссылка остаётся занятой ещё какое-то время.
    try {
      video?.removeAttribute('src');
      video?.load();
    } catch (_) {}
    if (objectUrl != null) {
      try {
        web.URL.revokeObjectURL(objectUrl);
      } catch (_) {}
    }
  }
}
