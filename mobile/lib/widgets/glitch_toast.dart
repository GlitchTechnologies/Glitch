import 'package:flutter/material.dart';
import '../main.dart' show navigatorKey;
import '../theme/app_theme.dart';

enum ToastType { error, info, success }

class GlitchToast {
  static OverlayEntry? _current;

  static void show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.error,
    Duration duration = const Duration(seconds: 3),
  }) {
    // Если контекст принадлежит самому Navigator, его Overlay находится ниже в дереве.
    final overlay = Overlay.maybeOf(context) ?? navigatorKey.currentState?.overlay;
    if (overlay == null) return; // показывать некуда — молчим, но не падаем

    _current?.remove();
    _current = null;

    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => _ToastWidget(
        message: message,
        type: type,
        duration: duration,
        onDone: () {
          entry.remove();
          if (_current == entry) _current = null;
        },
      ),
    );

    _current = entry;
    overlay.insert(entry);
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final ToastType type;
  final Duration duration;
  final VoidCallback onDone;

  const _ToastWidget({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDone,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _ctrl.forward();

    Future.delayed(widget.duration, _dismiss);
  }

  void _dismiss() async {
    if (!mounted || _dismissing) return;
    _dismissing = true;
    await _ctrl.reverse();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _accentColor => switch (widget.type) {
        ToastType.error   => GlitchColors.error,
        ToastType.success => const Color(0xFF4CAF50),
        ToastType.info    => GlitchColors.accentBlue,
      };

  IconData get _icon => switch (widget.type) {
        ToastType.error   => Icons.error_outline_rounded,
        ToastType.success => Icons.check_circle_outline_rounded,
        ToastType.info    => Icons.info_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 80,
      left: 16,
      right: 16,
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _slide,
          child: Center(
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: GlitchColors.bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border(
                    left: BorderSide(color: _accentColor, width: 3),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_icon, color: _accentColor, size: 20),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          color: GlitchColors.textPrimary,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
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
