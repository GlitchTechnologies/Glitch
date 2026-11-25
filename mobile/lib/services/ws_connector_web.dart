import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';

Future<WebSocketChannel> openWsChannel({
  required String wsBase,
  required String token,
}) async {
  final ticket = await api.wsTicket();
  return WebSocketChannel.connect(
    Uri.parse('$wsBase/ws?ticket=${Uri.encodeComponent(ticket)}'),
  );
}
