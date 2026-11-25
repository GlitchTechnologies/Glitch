import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

/// Именно `IOWebSocketChannel`, а не общий `WebSocketChannel.connect`: только
/// он умеет передавать заголовки. Из-за него же этот файл и вынесен отдельно —
/// `package:web_socket_channel/io.dart` тянет `dart:io`, которого в браузере
/// нет, и один этот импорт сломал бы веб-сборку целиком.
Future<WebSocketChannel> openWsChannel({
  required String wsBase,
  required String token,
}) async {
  return IOWebSocketChannel.connect(
    Uri.parse('$wsBase/ws'),
    headers: {'Authorization': 'Bearer $token'},
  );
}
