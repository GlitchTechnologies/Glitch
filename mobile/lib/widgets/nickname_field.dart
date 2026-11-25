import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class NicknameField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  const NicknameField({
    super.key,
    required this.controller,
    required this.hint,
    this.textInputAction,
    this.onSubmitted,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: GlitchColors.bgInput,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: GlitchColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text('@', style: TextStyle(color: GlitchColors.textHint, fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(width: 2),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: TextStyle(color: GlitchColors.textPrimary, fontSize: 16),
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                fillColor: Colors.transparent,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: textInputAction,
              onSubmitted: onSubmitted,
            ),
          ),
        ],
      ),
    );
  }
}
