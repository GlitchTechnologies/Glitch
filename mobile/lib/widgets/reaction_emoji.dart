import 'package:flutter/material.dart';

class ReactionEmoji extends StatelessWidget {
  final String emoji;
  final double size;

  const ReactionEmoji(this.emoji, {super.key, required this.size});

  @override
  Widget build(BuildContext context) =>
      Text(emoji, style: TextStyle(fontSize: size, fontFamily: 'Noto Color Emoji'));
}
