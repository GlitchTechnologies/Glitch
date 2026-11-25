import 'dart:ui' show ColorFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show MatrixUtils, RenderBox, RenderObject, RenderParagraph, SelectionGeometry;

class SelectionContrastText extends StatelessWidget {
  final Text text;

  const SelectionContrastText(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    if (SelectionContainer.maybeOf(context) == null) return text;
    return _SelectionContrast(text: text);
  }
}

class _SelectionContrast extends StatefulWidget {
  final Text text;

  const _SelectionContrast({required this.text});

  @override
  State<_SelectionContrast> createState() => _SelectionContrastState();
}

class _SelectionContrastState extends State<_SelectionContrast> {
  final _originalText = GlobalKey();
  late final _selection = _ContrastSelectionDelegate(_originalText);

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionContainer(
      delegate: _selection,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          KeyedSubtree(key: _originalText, child: widget.text),
          AnimatedBuilder(
            animation: _selection,
            builder: (_, child) => _selection.value.selectionRects.isEmpty
                ? const SizedBox.shrink()
                : ClipPath(clipper: _SelectedGlyphClip(_selection), child: child),
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: SelectionContainer.disabled(
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                    child: widget.text,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContrastSelectionDelegate extends StaticSelectionContainerDelegate {
  final GlobalKey originalText;

  _ContrastSelectionDelegate(this.originalText);

  @override
  SelectionGeometry getSelectionGeometry() {
    final geometry = super.getSelectionGeometry();
    if (geometry.selectionRects.isNotEmpty || !geometry.hasSelection) return geometry;

    final root = originalText.currentContext?.findRenderObject();
    if (root is! RenderBox || !root.attached || !root.hasSize || !hasSize) return geometry;
    final paragraph = _findParagraph(root);
    final registrar = paragraph?.registrar;
    if (paragraph == null || registrar is! MultiSelectableSelectionContainerDelegate) return geometry;

    final bounds = Offset.zero & containerSize;
    final rects = <Rect>[];
    for (final selectable in registrar.selectables) {
      if (!paragraph.selectableBelongsToParagraph(selectable)) continue;
      final transform = getTransformFrom(selectable);
      for (final rect in selectable.value.selectionRects) {
        final local = MatrixUtils.transformRect(transform, rect).intersect(bounds);
        if (local.isFinite && !local.isEmpty) rects.add(local);
      }
    }
    return SelectionGeometry(
      startSelectionPoint: geometry.startSelectionPoint,
      endSelectionPoint: geometry.endSelectionPoint,
      selectionRects: rects,
      status: geometry.status,
      hasContent: geometry.hasContent,
    );
  }

  RenderParagraph? _findParagraph(RenderObject object) {
    if (object is RenderParagraph) return object;
    RenderParagraph? paragraph;
    object.visitChildren((child) {
      paragraph ??= _findParagraph(child);
    });
    return paragraph;
  }
}

class _SelectedGlyphClip extends CustomClipper<Path> {
  final StaticSelectionContainerDelegate selection;

  _SelectedGlyphClip(this.selection) : super(reclip: selection);

  @override
  Path getClip(Size size) {
    final path = Path();
    for (final rect in selection.value.selectionRects) {
      path.addRect(rect);
    }
    return path;
  }

  @override
  bool shouldReclip(_SelectedGlyphClip oldClipper) => selection != oldClipper.selection;
}
