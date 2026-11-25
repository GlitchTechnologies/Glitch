import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../theme/app_theme.dart';
import 'glitch_bar_buttons.dart';

class UnsavedChangesBar extends StatefulWidget {
  final bool saving;
  final VoidCallback onReset;
  final VoidCallback onSave;

  const UnsavedChangesBar({
    super.key,
    required this.saving,
    required this.onReset,
    required this.onSave,
  });

  @override
  State<UnsavedChangesBar> createState() => UnsavedChangesBarState();
}

class UnsavedChangesBarState extends State<UnsavedChangesBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  bool _alert = false;
  Timer? _alertTimer;

  @override
  void dispose() {
    _alertTimer?.cancel();
    _shake.dispose();
    super.dispose();
  }

  void warn() {
    _alertTimer?.cancel();
    setState(() => _alert = true);
    _shake.forward(from: 0);
    _alertTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _alert = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final bg = _alert ? GlitchColors.error : GlitchColors.bgMenu;
    final fg = _alert ? Colors.white : GlitchColors.textPrimary;

    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final t = _shake.value;
        final dx = math.sin(t * math.pi * 6) * 10 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _alert ? GlitchColors.error : GlitchColors.border),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 16, offset: Offset(0, 6))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                s.unsavedChangesTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: fg),
              ),
            ),
            const SizedBox(width: 8),
            GlitchPlainButton(
              label: s.unsavedChangesReset,
              color: fg,
              onTap: widget.saving ? null : widget.onReset,
            ),
            const SizedBox(width: 4),
            GlitchFilledButton(label: s.save, loading: widget.saving, onTap: widget.onSave),
          ],
        ),
      ),
    );
  }
}

class UnsavedChangesDock extends StatelessWidget {
  final bool visible;
  final bool wide;
  final double maxWidth;
  final GlobalKey<UnsavedChangesBarState> barKey;
  final bool saving;
  final VoidCallback onReset;
  final VoidCallback onSave;

  const UnsavedChangesDock({
    super.key,
    required this.visible,
    required this.wide,
    required this.maxWidth,
    required this.barKey,
    required this.saving,
    required this.onReset,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: SafeArea(
        top: false,
        child: Align(
          alignment: wide ? Alignment.bottomLeft : Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: IgnorePointer(
              ignoring: !visible,
              child: AnimatedSlide(
                offset: visible ? Offset.zero : const Offset(0, 1.6),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: AnimatedOpacity(
                  opacity: visible ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: UnsavedChangesBar(
                    key: barKey,
                    saving: saving,
                    onReset: onReset,
                    onSave: onSave,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

mixin UnsavedGuard<T extends StatefulWidget> on State<T> {
  bool get hasUnsaved;

  void warnUnsaved();

  final List<Set<UnsavedGuard>> _scopes = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scopes.isNotEmpty) return;
    context.visitAncestorElements((e) {
      final w = e.widget;
      if (w is UnsavedGuardScope) _scopes.add(w.guards);
      return true;
    });
    for (final set in _scopes) {
      set.add(this);
    }
  }

  @override
  void dispose() {
    for (final set in _scopes) {
      set.remove(this);
    }
    super.dispose();
  }
}

class UnsavedGuardScope extends InheritedWidget {
  final Set<UnsavedGuard> guards;

  const UnsavedGuardScope({super.key, required this.guards, required super.child});

  @override
  bool updateShouldNotify(UnsavedGuardScope oldWidget) => false;
}

bool unsavedBlocksLeaving(Set<UnsavedGuard> guards) {
  for (final g in guards) {
    if (g.mounted && g.hasUnsaved) {
      g.warnUnsaved();
      return true;
    }
  }
  return false;
}
