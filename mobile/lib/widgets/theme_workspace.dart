import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../providers/theme_provider.dart';
import '../theme/custom_theme.dart';
import '../theme/glitch_ink.dart';

class ThemeWorkspace extends StatelessWidget {
  static const barTint = 0.16;
  static const _frameTint = 0.04;

  final Widget child;

  const ThemeWorkspace({super.key, required this.child});

  static bool _hasGradient(BuildContext context) =>
      InheritedModel.inheritFrom<_WorkspaceScope>(context, aspect: _WorkspaceAspect.active)?.gradient != null;

  static Color surface(BuildContext context, Color solid, {double tint = 0}) =>
      _hasGradient(context) ? solid.withOpacity(tint) : solid;

  static Color outline(BuildContext context, Color solid) =>
      _hasGradient(context) ? const Color(0x1FFFFFFF) : solid;

  static Color dividerColor(BuildContext context) => outline(context, GlitchInk.of(context).border);

  static Color frameSurface(BuildContext context, Color solid) {
    if (!_hasGradient(context)) return solid;
    final light = GlitchInk.of(context).brightness == Brightness.light;
    return (light ? Colors.black : Colors.white).withOpacity(_frameTint);
  }

  static LinearGradient? bottomLeftSurface(BuildContext context, {required Offset inset}) {
    final scope = InheritedModel.inheritFrom<_WorkspaceScope>(context, aspect: _WorkspaceAspect.gradient);
    final gradient = scope?.gradient;
    if (scope == null || gradient == null) return null;
    return _BottomLeftGradient(gradient, scope.viewport, inset);
  }

  static Widget backdrop(BuildContext context, Color solid, {required double opacity, required double tint}) {
    if (opacity == 0) return const SizedBox.shrink();
    final scope = InheritedModel.inheritFrom<_WorkspaceScope>(context, aspect: _WorkspaceAspect.gradient);
    final gradient = scope?.gradient;
    if (scope == null || gradient == null) return ColoredBox(color: solid.withOpacity(opacity));
    final wash = solid.withOpacity(tint);
    return Builder(
      builder: (paintContext) => CustomPaint(
        painter: _WorkspaceBackdropPainter(
          surface: paintContext,
          workspace: scope.workspace,
          gradient: LinearGradient(
            begin: gradient.begin,
            end: gradient.end,
            colors: [for (final color in gradient.colors) Color.alphaBlend(wash, color).withOpacity(opacity)],
            stops: gradient.stops,
          ),
          viewport: scope.viewport,
        ),
      ),
    );
  }

  static BorderSide frameEdge(BuildContext context) =>
      BorderSide(color: outline(context, GlitchInk.of(context).borderWindow));

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<CustomTheme?>(
        valueListenable: themeProvider.custom,
        child: child,
        builder: (context, custom, child) => LayoutBuilder(
          builder: (context, constraints) {
            final viewport = constraints.biggest;
            final gradient = custom?.background(themeProvider.palette, viewport);
            return _WorkspaceScope(
              gradient: gradient,
              viewport: viewport,
              workspace: context,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(child: DecoratedBox(decoration: BoxDecoration(gradient: gradient))),
                  ),
                  child!,
                ],
              ),
            );
          },
        ),
      );
}

enum _WorkspaceAspect { active, gradient }

class _WorkspaceScope extends InheritedModel<_WorkspaceAspect> {
  final LinearGradient? gradient;
  final Size viewport;
  final BuildContext workspace;

  const _WorkspaceScope({required this.gradient, required this.viewport, required this.workspace, required super.child});

  @override
  bool updateShouldNotify(_WorkspaceScope old) =>
      old.gradient != gradient || (gradient != null && old.viewport != viewport);

  @override
  bool updateShouldNotifyDependent(_WorkspaceScope old, Set<_WorkspaceAspect> dependencies) =>
      dependencies.contains(_WorkspaceAspect.gradient) || (old.gradient == null) != (gradient == null);
}

class _WorkspaceBackdropPainter extends CustomPainter {
  final BuildContext surface;
  final BuildContext workspace;
  final LinearGradient gradient;
  final Size viewport;

  const _WorkspaceBackdropPainter({
    required this.surface,
    required this.workspace,
    required this.gradient,
    required this.viewport,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final origin = (surface.findRenderObject() as RenderBox).localToGlobal(
      Offset.zero,
      ancestor: workspace.findRenderObject(),
    );
    final shader = gradient.createShader(-origin & viewport);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_WorkspaceBackdropPainter old) =>
      gradient != old.gradient || viewport != old.viewport || workspace != old.workspace;
}

class _BottomLeftGradient extends LinearGradient {
  final Size viewport;
  final Offset inset;

  _BottomLeftGradient(LinearGradient gradient, this.viewport, this.inset)
      : super(
          begin: gradient.begin,
          end: gradient.end,
          colors: [
            for (final color in gradient.colors)
              Color.alphaBlend(Colors.white.withOpacity(ThemeWorkspace._frameTint), color),
          ],
          stops: gradient.stops,
        );

  @override
  ui.Shader createShader(Rect rect, {TextDirection? textDirection}) => super.createShader(
        Rect.fromLTWH(rect.left - inset.dx, rect.bottom + inset.dy - viewport.height, viewport.width, viewport.height),
        textDirection: textDirection,
      );

  @override
  bool operator ==(Object other) =>
      other is _BottomLeftGradient && other.viewport == viewport && other.inset == inset && super == other;

  @override
  int get hashCode => Object.hash(super.hashCode, viewport, inset);
}
