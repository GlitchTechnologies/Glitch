import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'glitch_dialog.dart' show GlitchCheckMark;
import 'glitch_pressable.dart';

class GlitchFormField extends StatelessWidget {
  final String? label;

  final String? hint;
  final TextEditingController controller;

  final String? placeholder;

  final int? maxLength;
  final bool showCounter;
  final int minLines;
  final int maxLines;
  final bool enabled;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  final ValueChanged<String>? onChanged;

  final String? prefixText;

  final List<TextInputFormatter>? inputFormatters;

  final FocusNode? focusNode;

  final Widget? suffix;

  const GlitchFormField({
    super.key,
    this.label,
    required this.controller,
    this.hint,
    this.placeholder,
    this.maxLength,
    this.showCounter = false,
    this.minLines = 1,
    this.maxLines = 1,
    this.enabled = true,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.prefixText,
    this.inputFormatters,
    this.focusNode,
    this.suffix,
  });

  static const double _kCounterReserve = 16;

  @override
  Widget build(BuildContext context) {
    final limit = maxLength;
    final label = this.label;
    final counter = showCounter && limit != null;
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      minLines: minLines,
      maxLines: maxLines,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      inputFormatters: [
        if (limit != null) LengthLimitingTextInputFormatter(limit),
        ...?inputFormatters,
      ],
      style: TextStyle(fontSize: 15, color: GlitchColors.textPrimary),
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: TextStyle(color: GlitchColors.textHint, fontSize: 16),
        prefixText: prefixText,
        prefixStyle: TextStyle(fontSize: 15, color: GlitchColors.textSecond),
        suffixIcon: suffix,
        filled: true,
        fillColor: GlitchColors.bgInput,
        hoverColor: Colors.transparent,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        contentPadding: EdgeInsets.fromLTRB(
            16, 16, 16, counter ? 16 + _kCounterReserve : 16),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) GlitchFormLabel(label: label, hint: hint),
        if (!counter)
          field
        else
          Stack(
            children: [
              field,
              Positioned(
                right: 12,
                bottom: 8,
                child: IgnorePointer(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (_, value, __) => Text(
                      '${value.text.characters.length}/$limit',
                      style: TextStyle(fontSize: 12, color: GlitchColors.textHint),
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class GlitchFormLabel extends StatelessWidget {
  final String label;
  final String? hint;

  const GlitchFormLabel({super.key, required this.label, this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint!, style: TextStyle(fontSize: 13, height: 1.3, color: GlitchColors.textSecond)),
          ],
        ],
      ),
    );
  }
}

class GlitchChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;

  final VoidCallback? onTap;

  const GlitchChoiceTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final accent = selected ? GlitchColors.accentBlue : GlitchColors.textSecond;
    return ClickableCursor(
      enabled: enabled,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: GlitchColors.bgInput,
            border: Border.all(
              color: selected ? GlitchColors.accentBlue : GlitchColors.borderSoft,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: GlitchColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 13, height: 1.3, color: GlitchColors.textSecond),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                GlitchCheckMark(value: selected, enabled: enabled),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
