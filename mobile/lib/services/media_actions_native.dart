import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/platform_info.dart';
import 'api_service.dart' show mediaCacheManager;


bool get canSaveToGallery => isAndroidPlatform;

bool get saveShowsDialog => false;

Future<bool> saveMediaToGallery({
  required String url,
  required bool isVideo,
  Map<String, String> headers = const {},
}) async {
  if (!await Gal.hasAccess(toAlbum: false)) {
    await Gal.requestAccess(toAlbum: false);
  }
  if (!isVideo) {
    final res = await http.get(Uri.parse(url), headers: headers);
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    await Gal.putImageBytes(res.bodyBytes, album: 'Glitch');
    return true;
  }

  final client = http.Client();
  File? tmpFile;
  try {
    final request = http.Request('GET', Uri.parse(url));
    request.headers.addAll(headers);
    final streamed = await client.send(request);
    if (streamed.statusCode != 200) throw Exception('HTTP ${streamed.statusCode}');
    final tmp = await getTemporaryDirectory();
    tmpFile = File('${tmp.path}/${url.split('/').last}');
    final sink = tmpFile.openWrite();
    await streamed.stream.pipe(sink);
    await sink.close();
    await Gal.putVideo(tmpFile.path);
    return true;
  } finally {
    client.close();
    try { await tmpFile?.delete(); } catch (_) {}
  }
}

bool get canSaveMediaAs => false;

Future<bool> saveMediaAs({
  required String url,
  required bool isVideo,
  Map<String, String> headers = const {},
}) async => false;

bool get canCopyImage => false;

Future<void> copyImageToClipboard({
  required String url,
  Map<String, String> headers = const {},
}) async {
  throw UnsupportedError('Копирование картинки в буфер есть только в браузере');
}

Future<void> shareMedia({
  required String url,
  required bool isVideo,
  XFile? localFile,
  Map<String, String> headers = const {},
}) async {
  if (localFile != null) {
    await Share.shareXFiles([localFile]);
    return;
  }

  final name = url.split('?').first.split('/').last;
  final tmp = await getTemporaryDirectory();
  final dest = File('${tmp.path}/$name');

  if (isVideo) {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll(headers);
      final streamed = await client.send(request);
      if (streamed.statusCode != 200) throw Exception('HTTP ${streamed.statusCode}');
      final sink = dest.openWrite();
      await streamed.stream.pipe(sink);
      await sink.close();
    } finally {
      client.close();
    }
  } else {
    final cached = await mediaCacheManager.getSingleFile(url, headers: headers);
    await cached.copy(dest.path);
  }

  await Share.shareXFiles([XFile(dest.path)]);
}
