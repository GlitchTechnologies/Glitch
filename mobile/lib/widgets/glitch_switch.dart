import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glitch_pressable.dart';

class GlitchSwitch extends StatefulWidget {
  final bool value;

  final ValueChanged<bool>? onChanged;

  const GlitchSwitch({super.key, required this.value, required this.onChanged});

  @override
  State<GlitchSwitch> createState() => _GlitchSwitchState();
}

class _GlitchSwitchState extends State<GlitchSwitch> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 260);

  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: _duration, value: 1);

  late double _from = widget.value ? 1 : 0;

  int _seed = 0;

  @override
  void didUpdateWidget(covariant GlitchSwitch old) {
    super.didUpdateWidget(old);
    if (old.value == widget.value) return;
    _from = _GlitchSwitchPainter.positionAt(_from, old.value, _ctrl.value);
    _seed++;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _ctrl.value = 1;
    } else {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    return ClickableCursor(
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => widget.onChanged!(!widget.value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: RepaintBoundary(
            child: CustomPaint(
              size: const Size(44, 26),
              painter: _GlitchSwitchPainter(
                progress: _ctrl,
                from: _from,
                target: widget.value,
                seed: _seed,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlitchSwitchPainter extends CustomPainter {
  final Animation<double> progress;
  final double from;
  final bool target;
  final int seed;

  _GlitchSwitchPainter({
    required this.progress,
    required this.from,
    required this.target,
    required this.seed,
  }) : super(repaint: progress);

  static double positionAt(double from, bool target, double t) =>
      from + ((target ? 1.0 : 0.0) - from) * Curves.easeOutCubic.transform(t);

  static double _rand(int n) {
    final x = math.sin(n * 12.9898 + 78.233) * 43758.5453;
    return x - x.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final pos = positionAt(from, target, t);
    canvas.clipRect(Offset.zero & size);
    final g = t >= 1 ? 0.0 : math.sin(math.pi * t);
    final step = seed * 31 + (t * 12).floor();
    double r(int k) => _rand(step * 7 + k) - 0.5; // −0.5..0.5

    final track = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2));
    var color = Color.lerp(GlitchColors.switchOff, GlitchColors.switchOn, pos)!;
    if (g > 0.35 && _rand(step) > 0.55) color = Color.lerp(color, Colors.white, 0.18)!;
    canvas.drawRRect(track, Paint()..color = color);

    if (g > 0.2) {
      final y = 4 + (r(1) + 0.5) * (size.height - 10);
      canvas.save();
      canvas.clipRRect(track);
      canvas.drawRect(
        Rect.fromLTWH(r(2) * 14 * g, y, size.width, 3),
        Paint()..color = Color.lerp(color, Colors.white, 0.25)!,
      );
      canvas.restore();
    }

    const knobR = 11.0;
    final cx = 2 + knobR + pos * (size.width - 4 - knobR * 2);
    final cy = size.height / 2;
    final jitter = r(3) * 5 * g;

    if (g > 0.05) {
      final spread = 3.5 * g;
      canvas.drawCircle(Offset(cx - spread + jitter, cy + r(4) * 2 * g), knobR,
          Paint()..color = GlitchColors.glitchRed.withOpacity(0.75 * g));
      canvas.drawCircle(Offset(cx + spread - jitter, cy + r(5) * 2 * g), knobR,
          Paint()..color = GlitchColors.glitchCyan.withOpacity(0.75 * g));
    }

    final white = Paint()..color = Colors.white;
    final center = Offset(cx + jitter * 0.4, cy);
    if (g > 0.3 && _rand(step + 3) > 0.45) {
      final cut = cy + r(6) * 8;
      final slice = r(7) * 7 * g;
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, 0, size.width, cut));
      canvas.drawCircle(center.translate(slice, 0), knobR, white);
      canvas.restore();
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, cut, size.width, size.height));
      canvas.drawCircle(center.translate(-slice, 0), knobR, white);
      canvas.restore();
    } else {
      canvas.drawCircle(center, knobR, white);
    }
  }

  @override
  bool shouldRepaint(_GlitchSwitchPainter old) =>
      old.seed != seed || old.from != from || old.target != target;
}

class GlitchSwitchRow extends StatelessWidget {
  final String label;

  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  final Widget? labelAction;

  final bool border;

  final EdgeInsets padding;

  const GlitchSwitchRow({
    super.key,
    required this.label,
    this.description,
    required this.value,
    required this.onChanged,
    this.labelAction,
    this.border = true,
    this.padding = _kControlRowPadding,
  });

  @override
  Widget build(BuildContext context) => GlitchControlRow(
        label: label,
        labelAction: labelAction,
        description: description,
        enabled: onChanged != null,
        border: border,
        padding: padding,
        control: GlitchSwitch(value: value, onChanged: onChanged),
      );
}

const EdgeInsets _kControlRowPadding = EdgeInsets.fromLTRB(14, 12, 14, 12);

class GlitchControlRow extends StatelessWidget {
  final String label;
  final Widget? labelAction;
  final String? description;
  final bool enabled;
  final bool border;

  final Widget? control;

  final Widget? below;
  final EdgeInsets padding;

  const GlitchControlRow({
    super.key,
    required this.label,
    this.labelAction,
    required this.description,
    required this.enabled,
    required this.border,
    this.control,
    this.below,
    this.padding = _kControlRowPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: border
          ? BoxDecoration(border: Border(bottom: BorderSide(color: GlitchColors.borderSoft)))
          : null,
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label(),
                if (description != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    description!,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.3,
                      color: enabled ? GlitchColors.textSecond : GlitchColors.textHint,
                    ),
                  ),
                ],
                if (below != null) ...[
                  const SizedBox(height: 10),
                  below!,
                ],
              ],
            ),
          ),
          if (control != null) ...[
            const SizedBox(width: 12),
            Padding(padding: const EdgeInsets.only(top: 2), child: control!),
          ],
        ],
      ),
    );
  }

  Widget _label() {
    final text = Text(
      label,
      style: TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
        color: enabled ? GlitchColors.textPrimary : GlitchColors.textHint,
      ),
    );
    final action = labelAction;
    if (action == null) return text;
    return Row(
      children: [
        Flexible(child: text),
        const SizedBox(width: 6),
        action,
      ],
    );
  }
}


enum GlitchTriState { deny, inherit, allow }

class GlitchTriSwitch extends StatelessWidget {
  final GlitchTriState value;

  final ValueChanged<GlitchTriState>? onChanged;

  const GlitchTriSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  static const Color _allowColor = GlitchColors.switchOn;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    Widget cell(GlitchTriState state, IconData icon, Color active, {required bool left, required bool right}) {
      final selected = value == state;
      return ClickableCursor(
        enabled: enabled,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled && !selected ? () => onChanged!(state) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 30,
            height: 26,
            decoration: BoxDecoration(
              color: selected ? active : Colors.transparent,
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(left ? 7 : 0),
                right: Radius.circular(right ? 7 : 0),
              ),
            ),
            child: Icon(
              icon,
              size: 16,
              color: selected
                  ? (state == GlitchTriState.inherit ? GlitchColors.textPrimary : Colors.white)
                  : GlitchColors.textSecond,
            ),
          ),
        ),
      );
    }

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: GlitchColors.border),
        ),
        padding: const EdgeInsets.all(1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            cell(GlitchTriState.deny, Icons.close_rounded, GlitchColors.error, left: true, right: false),
            cell(GlitchTriState.inherit, Icons.horizontal_rule_rounded, GlitchColors.bgChip,
                left: false, right: false),
            cell(GlitchTriState.allow, Icons.check_rounded, _allowColor, left: false, right: true),
          ],
        ),
      ),
    );
  }
}

class GlitchTriSwitchRow extends StatelessWidget {
  final String label;
  final String? description;
  final GlitchTriState value;
  final ValueChanged<GlitchTriState>? onChanged;

  final bool border;

  const GlitchTriSwitchRow({
    super.key,
    required this.label,
    this.description,
    required this.value,
    required this.onChanged,
    this.border = true,
  });

  @override
  Widget build(BuildContext context) => GlitchControlRow(
        label: label,
        description: description,
        enabled: onChanged != null,
        border: border,
        control: GlitchTriSwitch(value: value, onChanged: onChanged),
      );
}
