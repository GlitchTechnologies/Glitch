import 'package:flutter/material.dart';
import '../core/platform_info.dart';

/// ## Почему это отдельный виджет, а не `SelectionArea` на всё приложение
///
/// ## Что это меняет по умолчанию
///
/// ## Как устроено выделение в ленте
///
/// ## Только там, где есть мышь
class SelectableContent extends StatelessWidget {
  final Widget child;

  final bool fillWidth;

  const SelectableContent({super.key, required this.child, this.fillWidth = false});

  @override
  Widget build(BuildContext context) {
    if (!hasPointerInput) return child;
    if (SelectionContainer.maybeOf(context) != null) return child;
    return SelectionArea(
      contextMenuBuilder: (_, __) => const SizedBox.shrink(),
      child: fillWidth
          ? SizedBox(width: double.infinity, child: Align(alignment: Alignment.centerLeft, child: child))
          : child,
    );
  }
}
