import 'shared_content.dart';

class ChatArrival {
  final SharedContent? shared;
  final String? text;

  // Без const: одинаковые постоянные слились бы в один объект, а новый вход
  // узнаётся по тождеству.
  ChatArrival({this.shared, this.text});
}
