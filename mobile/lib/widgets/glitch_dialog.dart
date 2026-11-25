import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../theme/glitch_ink.dart';
import 'glitch_bar_buttons.dart';
import 'glitch_pressable.dart';
import 'glitch_tooltip.dart' show kTooltipScale;


const double kDialogRadius = 16;
const double kDialogCheckRadius = 7;

const double kDialogMaxWidth = 440;

ShapeBorder glitchWindowShape({double radius = kDialogRadius, Color? outline, GlitchWindowArrow? arrow}) {
  final side = BorderSide(color: outline ?? GlitchColors.borderWindow);
  if (arrow != null) return _ArrowWindowBorder(radius: radius, side: side, arrow: arrow);
  return RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: side);
}

class GlitchWindowArrow {
  final AxisDirection edge;
  final double at;
  const GlitchWindowArrow({required this.edge, required this.at});

  static const double width = 11 * kTooltipScale;
  static const double height = 5.5 * kTooltipScale;
}

class _ArrowWindowBorder extends ShapeBorder {
  final double radius;
  final BorderSide side;
  final GlitchWindowArrow arrow;
  const _ArrowWindowBorder({required this.radius, required this.side, required this.arrow});

  @override
  EdgeInsetsGeometry get dimensions => switch (arrow.edge) {
        AxisDirection.up => const EdgeInsets.only(top: GlitchWindowArrow.height),
        AxisDirection.down => const EdgeInsets.only(bottom: GlitchWindowArrow.height),
        AxisDirection.left => const EdgeInsets.only(left: GlitchWindowArrow.height),
        AxisDirection.right => const EdgeInsets.only(right: GlitchWindowArrow.height),
      };

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final body = dimensions.resolve(textDirection).deflateRect(rect);
    const w = GlitchWindowArrow.width / 2, h = GlitchWindowArrow.height;
    final tri = Path();
    switch (arrow.edge) {
      case AxisDirection.up:
        final x = body.left + arrow.at;
        tri..moveTo(x - w, body.top + 1)..lineTo(x, body.top - h)..lineTo(x + w, body.top + 1);
      case AxisDirection.down:
        final x = body.left + arrow.at;
        tri..moveTo(x - w, body.bottom - 1)..lineTo(x, body.bottom + h)..lineTo(x + w, body.bottom - 1);
      case AxisDirection.left:
        final y = body.top + arrow.at;
        tri..moveTo(body.left + 1, y - w)..lineTo(body.left - h, y)..lineTo(body.left + 1, y + w);
      case AxisDirection.right:
        final y = body.top + arrow.at;
        tri..moveTo(body.right - 1, y - w)..lineTo(body.right + h, y)..lineTo(body.right - 1, y + w);
    }
    tri.close();
    return Path.combine(
      PathOperation.union,
      Path()..addRRect(RRect.fromRectAndRadius(body, Radius.circular(radius))),
      tri,
    );
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(getOuterPath(rect, textDirection: textDirection), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) => this;
}

class GlitchDialog extends StatelessWidget {
  final String title;
  final Widget? leading;
  final Widget? content;
  final List<Widget> actions;
  final Color? backgroundColor;
  final Color? titleColor;

  const GlitchDialog({
    super.key,
    required this.title,
    this.leading,
    this.content,
    this.actions = const [],
    this.backgroundColor,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: backgroundColor ?? GlitchColors.bgCard,
      surfaceTintColor: Colors.transparent,
      shape: glitchWindowShape(),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      title: _capped(leading == null
          ? Text(title, style: _titleStyleOf(titleColor))
          : Row(
              children: [
                leading!,
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: _titleStyleOf(titleColor))),
              ],
            )),
      content: content == null ? null : _capped(content!),
      actions: actions,
    );
  }

  static Widget _capped(Widget child) =>
      ConstrainedBox(constraints: const BoxConstraints(maxWidth: kDialogMaxWidth), child: child);

  static TextStyle _titleStyleOf(Color? color) => TextStyle(
    color: color ?? GlitchColors.textPrimary,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static TextStyle get bodyStyle => TextStyle(
    color: GlitchColors.textSecond,
    fontSize: 15,
    height: 1.45,
  );
}

class GlitchDialogField extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final bool obscure;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  final int? maxLength;

  const GlitchDialogField({
    super.key,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.obscure = false,
    this.autofocus = false,
    this.onSubmitted,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      decoration: BoxDecoration(
        color: GlitchColors.bgInput,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: GlitchColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      alignment: Alignment.centerLeft,
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        obscureText: obscure,
        keyboardType: keyboardType,
        onSubmitted: onSubmitted,
        inputFormatters: maxLength != null ? [LengthLimitingTextInputFormatter(maxLength)] : null,
        style: TextStyle(color: GlitchColors.textPrimary, fontSize: 16),
        decoration: InputDecoration(
          border: InputBorder.none,
          fillColor: Colors.transparent,
          filled: false,
          hintText: hint,
          hintStyle: TextStyle(color: GlitchColors.textHint),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

Future<void> glitchInfo(
  BuildContext context, {
  required String title,
  String? body,
  Widget? content,
  Widget? leading,
  String? buttonLabel,
}) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => ModalStatusBarDim(
        child: GlitchDialog(
          title: title,
          leading: leading,
          content: content ?? (body == null ? null : Text(body, style: GlitchDialog.bodyStyle)),
          actions: [
            GlitchFilledButton(label: buttonLabel ?? context.s.ok, onTap: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    );

Future<T?> showGlitchCardDialog<T>(
  BuildContext context, {
  required Widget Function(BuildContext ctx) builder,
}) =>
    showDialog<T>(
      context: context,
      builder: (ctx) => ModalStatusBarDim(
        child: Dialog(
          backgroundColor: GlitchColors.bgCard,
          surfaceTintColor: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: glitchWindowShape(),
          insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(child: builder(ctx)),
          ),
        ),
      ),
    );

Future<bool> glitchConfirm(
  BuildContext context, {
  required String title,
  String? body,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = true,
  Widget? leading,
}) async =>
    (await glitchConfirmWithOption(
      context,
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      leading: leading,
    )).$1;

Future<(bool, bool)> glitchConfirmWithOption(
  BuildContext context, {
  required String title,
  String? body,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = true,
  Widget? leading,
  String? optionLabel,
}) async {
  bool checked = false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => ModalStatusBarDim(
      child: StatefulBuilder(
      builder: (ctx, setLocal) => GlitchDialog(
        title: title,
        leading: leading,
        content: (body == null && optionLabel == null)
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (body != null) Text(body, style: GlitchDialog.bodyStyle),
                  if (optionLabel != null)
                    Padding(
                      padding: EdgeInsets.only(top: body != null ? 16 : 0),
                      child: _DialogCheckbox(
                        label: optionLabel,
                        value: checked,
                        onChanged: (v) => setLocal(() => checked = v),
                      ),
                    ),
                ],
              ),
        actions: [
          GlitchPlainButton(label: cancelLabel ?? context.s.cancel, onTap: () => Navigator.pop(ctx, false)),
          GlitchFilledButton(
            label: confirmLabel,
            destructive: destructive,
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
      ),
    ),
  );
  return (confirmed == true, checked);
}

Future<bool> glitchConfirmByTyping(
  BuildContext context, {
  required String title,
  String? body,
  required String fieldLabel,
  required String expected,
  required String mismatch,
  required String confirmLabel,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => ModalStatusBarDim(
        child: _TypedConfirmDialog(
          title: title,
          body: body,
          fieldLabel: fieldLabel,
          expected: expected,
          mismatch: mismatch,
          confirmLabel: confirmLabel,
        ),
      ),
    ) ==
    true;

class _TypedConfirmDialog extends StatefulWidget {
  final String title;
  final String? body;
  final String fieldLabel;
  final String expected;
  final String mismatch;
  final String confirmLabel;

  const _TypedConfirmDialog({
    required this.title,
    required this.body,
    required this.fieldLabel,
    required this.expected,
    required this.mismatch,
    required this.confirmLabel,
  });

  @override
  State<_TypedConfirmDialog> createState() => _TypedConfirmDialogState();
}

class _TypedConfirmDialogState extends State<_TypedConfirmDialog> {
  final _ctrl = TextEditingController();
  bool _wrong = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_ctrl.text.trim() == widget.expected.trim()) {
      Navigator.pop(context, true);
    } else {
      setState(() => _wrong = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlitchDialog(
      title: widget.title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.body != null) ...[
            Text(widget.body!, style: GlitchDialog.bodyStyle),
            const SizedBox(height: 16),
          ],
          Text(widget.fieldLabel,
              style: TextStyle(color: GlitchColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          GlitchDialogField(controller: _ctrl, autofocus: true, onSubmitted: (_) => _confirm()),
          if (_wrong) ...[
            const SizedBox(height: 6),
            Text(widget.mismatch, style: TextStyle(color: GlitchColors.error, fontSize: 13)),
          ],
        ],
      ),
      actions: [
        GlitchPlainButton(label: context.s.cancel, onTap: () => Navigator.pop(context, false)),
        GlitchFilledButton(label: widget.confirmLabel, destructive: true, onTap: _confirm),
      ],
    );
  }
}

class _DialogCheckbox extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _DialogCheckbox({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GlitchPressable(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            GlitchCheckMark(value: value),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(color: GlitchColors.textPrimary, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }
}

class GlitchCheckMark extends StatelessWidget {
  final bool value;
  final bool enabled;

  const GlitchCheckMark({super.key, required this.value, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 140),
      opacity: enabled ? 1 : 0.35,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: value ? GlitchColors.accentBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(kDialogCheckRadius),
          border: value ? null : Border.all(color: GlitchInk.of(context).textHint, width: 1.6),
        ),
        child: value ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
      ),
    );
  }
}
