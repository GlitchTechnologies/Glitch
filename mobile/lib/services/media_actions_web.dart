import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:web/web.dart' as web;

import 'desktop_shell.dart';


bool get canSaveToGallery => false;

bool get saveShowsDialog => desktopShell != null;

Future<bool> saveMediaToGallery({
  required String url,
  required bool isVideo,
  Map<String, String> headers = const {},
}) async {
  final shell = desktopShell;
  if (shell != null) {
    final result = await shell.download(url, _fileNameFromUrl(url));
    if (result == DesktopDownloadResult.failed) throw Exception('desktop download failed');
    return result == DesktopDownloadResult.saved;
  }

  final res = await http.get(Uri.parse(url), headers: headers);
  if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');

  final blob = web.Blob(
    [res.bodyBytes.toJS].toJS,
    web.BlobPropertyBag(
      type: res.headers['content-type'] ?? 'application/octet-stream',
    ),
  );
  final objectUrl = web.URL.createObjectURL(blob);
  try {
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = objectUrl
      ..download = _fileNameFromUrl(url);
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
  } finally {
    web.URL.revokeObjectURL(objectUrl);
  }
  return true;
}

String _fileNameFromUrl(String url) {
  final name = url.split('?').first.split('/').last;
  return name.isEmpty ? 'glitch-media' : name;
}

/// Это File System Access API — он есть в Chrome и Edge, но НЕ в Firefox и
/// Safari. Поэтому пункт меню показывается по этому флагу, а не всегда: пункт,
/// который у половины людей молча ничего не делает, хуже отсутствующего.
bool get canSaveMediaAs =>
    desktopShell == null && (web.window as JSObject).has('showSaveFilePicker');

Future<bool> saveMediaAs({
  required String url,
  required bool isVideo,
  Map<String, String> headers = const {},
}) async {
  if (!canSaveMediaAs) return false;

  final options = JSObject()
    ..setProperty('suggestedName'.toJS, _fileNameFromUrl(url).toJS);

  JSAny? handleAny;
  try {
    handleAny = await (web.window as JSObject)
        .callMethod<JSPromise<JSAny?>>('showSaveFilePicker'.toJS, options)
        .toDart;
  } catch (_) {
    return false;
  }
  if (handleAny == null) return false;

  final res = await http.get(Uri.parse(url), headers: headers);
  if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');

  final handle = handleAny as web.FileSystemFileHandle;
  final writable = await handle.createWritable().toDart;
  final blob = web.Blob(
    [res.bodyBytes.toJS].toJS,
    web.BlobPropertyBag(
      type: res.headers['content-type'] ?? 'application/octet-stream',
    ),
  );
  await writable.write(blob).toDart;
  await writable.close().toDart;
  return true;
}

bool get canCopyImage => true;

Future<void> copyImageToClipboard({
  required String url,
  Map<String, String> headers = const {},
}) async {
  final res = await http.get(Uri.parse(url), headers: headers);
  if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');

  final png = await _reencodeToPng(
    res.bodyBytes,
    res.headers['content-type'] ?? 'image/jpeg',
  );

  final blob = web.Blob([png.toJS].toJS, web.BlobPropertyBag(type: 'image/png'));
  final items = JSObject()..setProperty('image/png'.toJS, blob);
  await web.window.navigator.clipboard
      .write(<web.ClipboardItem>[web.ClipboardItem(items)].toJS)
      .toDart;
}

Future<Uint8List> _reencodeToPng(Uint8List bytes, String mimeType) async {
  final srcBlob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final objectUrl = web.URL.createObjectURL(srcBlob);
  web.HTMLImageElement? img;
  try {
    img = (web.document.createElement('img') as web.HTMLImageElement)..src = objectUrl;

    final ready = Completer<void>();
    late final JSFunction onLoad;
    late final JSFunction onError;
    onLoad = ((web.Event _) {
      if (!ready.isCompleted) ready.complete();
    }).toJS;
    onError = ((web.Event _) {
      if (!ready.isCompleted) ready.completeError(Exception('image decode failed'));
    }).toJS;
    img.addEventListener('load', onLoad);
    img.addEventListener('error', onError);
    try {
      await ready.future.timeout(const Duration(seconds: 8));
    } finally {
      img.removeEventListener('load', onLoad);
      img.removeEventListener('error', onError);
    }

    final w = img.naturalWidth;
    final h = img.naturalHeight;
    if (w == 0 || h == 0) throw Exception('image has no size');

    final canvas = (web.document.createElement('canvas') as web.HTMLCanvasElement)
      ..width = w
      ..height = h;
    (canvas.getContext('2d') as web.CanvasRenderingContext2D).drawImage(img, 0, 0);

    final dataUrl = canvas.toDataURL('image/png');
    return base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1));
  } finally {
    // Отпускаем и элемент, и ссылку: иначе браузер держит всю картинку в
    // памяти вкладки до сборки мусора.
    img?.removeAttribute('src');
    web.URL.revokeObjectURL(objectUrl);
  }
}

Future<void> shareMedia({
  required String url,
  required bool isVideo,
  XFile? localFile,
  Map<String, String> headers = const {},
}) async {
  await Share.share(url);
}
