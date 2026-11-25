import 'package:flutter/material.dart';


const IconData kEditIcon = Icons.edit_rounded;

const IconData kDeleteIcon = Icons.delete_outline_rounded;

const IconData kForwardIcon = Icons.shortcut_rounded;

class ReplyIcon extends StatelessWidget {
  final double? size;
  final Color? color;

  const ReplyIcon({super.key, this.size, this.color});

  @override
  Widget build(BuildContext context) => Transform.flip(
        flipX: true,
        child: Icon(kForwardIcon, size: size, color: color),
      );
}
