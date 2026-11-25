import 'package:flutter/widgets.dart';

import '../services/voice_connection.dart';

class SpeakingBuilder extends StatelessWidget {
  final int userId;
  final Widget Function(BuildContext context, bool speaking) builder;

  const SpeakingBuilder({super.key, required this.userId, required this.builder});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Set<int>>(
        valueListenable: voiceConnection.speakers,
        builder: (context, speakers, _) => builder(context, speakers.contains(userId)),
      );
}
