import 'package:url_launcher/url_launcher.dart';
import 'desktop_shell.dart';
import 'file_open_result.dart';

/// Поэтому просто отдаём ему адрес. Это работает, потому что медиа Glitch
/// лежит в S3 с публичным доступом на чтение и авторизации не требует —
/// та же причина, по которой `api.headersFor` для таких адресов возвращает
/// пустые заголовки. Заголовки в этой версии не используются вовсе; параметр
/// оставлен, чтобы сигнатуры обеих версий совпадали.
Future<FileOpenResult> downloadAndOpenFile({
  required String url,
  required String fileName,
  Map<String, String> headers = const {},
}) async {
  final shell = desktopShell;
  if (shell != null) {
    try {
      final result = await shell.download(url, fileName);
      return result == DesktopDownloadResult.failed ? FileOpenResult.failed : FileOpenResult.opened;
    } catch (_) {
      return FileOpenResult.failed;
    }
  }
  try {
    final ok = await launchUrl(
      Uri.parse(url),
      webOnlyWindowName: '_blank',
    );
    return ok ? FileOpenResult.opened : FileOpenResult.failed;
  } catch (_) {
    return FileOpenResult.failed;
  }
}
