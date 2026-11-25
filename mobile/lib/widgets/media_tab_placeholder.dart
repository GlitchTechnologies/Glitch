import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class MediaTabPlaceholder extends StatelessWidget {
  final bool loading;
  final String emptyText;

  const MediaTabPlaceholder({super.key, required this.loading, this.emptyText = ''});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320,
      child: Center(
        child: loading
            ? CircularProgressIndicator(color: GlitchColors.accentBlue, strokeWidth: 2)
            : Text(emptyText, style: TextStyle(color: GlitchColors.textHint, fontSize: 14)),
      ),
    );
  }
}
