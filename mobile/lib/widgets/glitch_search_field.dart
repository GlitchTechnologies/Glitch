import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GlitchSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool loading;
  final double height;

  final bool brightIcon;

  const GlitchSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.loading = false,
    this.height = 46,
    this.brightIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: GlitchColors.bgInput,
        border: Border.all(color: GlitchColors.border),
        borderRadius: BorderRadius.circular(13),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        Icon(Icons.search_rounded, color: brightIcon ? GlitchColors.textPrimary : GlitchColors.textHint, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(color: GlitchColors.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: GlitchColors.textHint, fontSize: 15),
              border: InputBorder.none,
              fillColor: Colors.transparent,
              filled: false,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
        if (loading)
          SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.accentBlue),
          ),
      ]),
    );
  }
}
