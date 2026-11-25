import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// [soft] и [destructive] взаимоисключающие. Одновременно не бывает.
class GlitchActionButton extends StatelessWidget {
  final String? label;
  final VoidCallback? onTap;
  final bool soft;
  final bool destructive;

  final bool brandAccent;

  final IconData? icon;

  final bool loading;

  final bool compact;

  final Color? softInk;

  final double? height;

  const GlitchActionButton({
    super.key,
    this.label,
    required this.onTap,
    this.soft = false,
    this.destructive = false,
    this.brandAccent = false,
    this.icon,
    this.loading = false,
    this.compact = false,
    this.softInk,
    this.height,
  }) : assert(!(soft && destructive), 'soft и destructive взаимоисключающие — см. doc-комментарий класса'),
       assert(label != null || icon != null, 'нужна надпись или значок');

  static const double _softFill = 0.08;
  static const double _softFillActive = 0.14;

  static const double _iconOnlySize = 20;

  @override
  Widget build(BuildContext context) {
    final enabled = !loading && onTap != null;

    final width = compact ? null : double.infinity;
    final padding = compact ? const EdgeInsets.symmetric(horizontal: 16) : null;

    if (soft) {
      final ink = softInk ?? GlitchColors.textPrimary;
      return SizedBox(
        width: width,
        height: compact ? 36 : 40,
        child: TextButton(
          onPressed: enabled ? onTap : null,
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) => ink.withOpacity(
                states.contains(WidgetState.hovered) || states.contains(WidgetState.pressed)
                    ? _softFillActive
                    : _softFill)),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? 10 : 8))),
            // Только значок — без полей и без минимальной ширины кнопки
            // Material (64): иначе в узком квадрате (шестерёнка окна выбора
            // экрана, 40×40) кнопка вылезала за край, и значок сидел правее
            // середины. Значок встаёт по центру того места, что дали.
            padding: WidgetStatePropertyAll(
                label == null ? EdgeInsets.zero : (padding ?? const EdgeInsets.symmetric(horizontal: 16))),
            minimumSize: label == null ? const WidgetStatePropertyAll(Size.zero) : null,
          ),
          child: loading
              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.textSecond))
              : _label(TextStyle(
                  fontSize: compact ? 14 : 14.5,
                  fontWeight: FontWeight.w600,
                  color: enabled ? ink : GlitchColors.textHint,
                )),
        ),
      );
    }

    final gradient = brandAccent ? GlitchColors.brandActionGradient : GlitchColors.gradientAccent;
    const radius = BorderRadius.all(Radius.circular(12));
    return SizedBox(
      width: width,
      height: compact ? 36 : (height ?? 54),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: destructive ? null : gradient,
          color: destructive ? GlitchColors.error : null,
          borderRadius: radius,
        ),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: const RoundedRectangleBorder(borderRadius: radius),
            padding: padding,
          ),
          onPressed: enabled ? onTap : null,
          child: loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4))
              : _label(TextStyle(fontSize: compact ? 14 : 16.5, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
      ),
    );
  }

  Widget _label(TextStyle style) {
    final label = this.label;
    if (label == null) return Icon(icon, size: _iconOnlySize, color: style.color);
    final text = Text(label, maxLines: 1, softWrap: false, textAlign: TextAlign.center, style: style);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: icon == null
          ? text
          : Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: (style.fontSize ?? 15) + 3, color: style.color),
              const SizedBox(width: 8),
              text,
            ]),
    );
  }
}
