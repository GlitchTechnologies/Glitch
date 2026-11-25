import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'file_open_result.dart';

/// Именно скачать НА УСТРОЙСТВО: у телефона есть файловая система, и открыть
/// документ можно только тем приложением, которому дали путь к файлу.
Future<FileOpenResult> downloadAndOpenFile({
  required String url,
  required String fileName,
  Map<String, String> headers = const {},
}) async {
  try {
    final res = await http.get(Uri.parse(url), headers: headers);
    if (res.statusCode != 200) return FileOpenResult.failed;

    // Внешнее хранилище, если есть, иначе временная папка — как было.
    final dir = await getExternalStorageDirectory() ?? await getTemporaryDirectory();
    final path = '${dir.path}/$fileName';
    await File(path).writeAsBytes(res.bodyBytes);

    final result = await OpenFilex.open(path);
    return result.type == ResultType.done
        ? FileOpenResult.opened
        : FileOpenResult.noApp;
  } catch (_) {
    return FileOpenResult.failed;
  }
}
