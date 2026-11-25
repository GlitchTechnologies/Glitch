import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../theme/app_theme.dart';
import 'glitch_pressable.dart';
import 'glitch_select_field.dart';

class PageNavBar extends StatelessWidget {
  final int page;
  final int pageCount;
  final int pageSize;

  final List<int> pageSizes;

  final String totalLabel;

  final ValueChanged<int> onPage;
  final ValueChanged<int> onPageSize;

  const PageNavBar({
    super.key,
    required this.page,
    required this.pageCount,
    required this.pageSize,
    required this.pageSizes,
    required this.totalLabel,
    required this.onPage,
    required this.onPageSize,
  });

  static const double _compactBelow = 560;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < _compactBelow;
      final size = _SizeLine(
        pageSize: pageSize,
        pageSizes: pageSizes,
        totalLabel: totalLabel,
        onPageSize: onPageSize,
      );
      final pages = _PageButtons(
        page: page,
        pageCount: pageCount,
        compact: compact,
        onPage: onPage,
      );
      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            size,
            const SizedBox(height: 12),
            Center(child: pages),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: size),
          const SizedBox(width: 12),
          pages,
        ],
      );
    });
  }
}

List<int?> pageWindow(int current, int count, int around) {
  if (count <= 2 * around + 5) return [for (var i = 1; i <= count; i++) i];
  final keep = <int>{1, count};
  for (var i = current - around; i <= current + around; i++) {
    if (i >= 1 && i <= count) keep.add(i);
  }
  final sorted = keep.toList()..sort();
  final out = <int?>[];
  for (final p in sorted) {
    if (out.isNotEmpty && p - out.last! > 1) out.add(null);
    out.add(p);
  }
  return out;
}

class _SizeLine extends StatelessWidget {
  final int pageSize;
  final List<int> pageSizes;
  final String totalLabel;
  final ValueChanged<int> onPageSize;

  const _SizeLine({
    required this.pageSize,
    required this.pageSizes,
    required this.totalLabel,
    required this.onPageSize,
  });

  @override
  Widget build(BuildContext context) {
    final label = TextStyle(fontSize: 13.5, color: GlitchColors.textSecond);
    return Row(
      children: [
        Text(context.s.pageShowing, style: label),
        const SizedBox(width: 8),
        GlitchSelectField<int>(
          value: pageSize,
          options: pageSizes,
          label: (n) => '$n',
          onChanged: onPageSize,
          menuLabelWidth: 40,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(totalLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: label),
        ),
      ],
    );
  }
}

class _PageButtons extends StatelessWidget {
  final int page;
  final int pageCount;
  final bool compact;
  final ValueChanged<int> onPage;

  const _PageButtons({
    required this.page,
    required this.pageCount,
    required this.compact,
    required this.onPage,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          icon: Icons.chevron_left_rounded,
          label: compact ? null : s.pageBack,
          iconFirst: true,
          onTap: page > 1 ? () => onPage(page - 1) : null,
        ),
        const SizedBox(width: 6),
        for (final p in pageWindow(page, pageCount, compact ? 1 : 2))
          p == null
              ? SizedBox(
                  width: 24,
                  child: Center(child: Text('…', style: TextStyle(fontSize: 14, color: GlitchColors.textHint))),
                )
              : _NumberButton(number: p, selected: p == page, onTap: () => onPage(p)),
        const SizedBox(width: 6),
        _StepButton(
          icon: Icons.chevron_right_rounded,
          label: compact ? null : s.pageNext,
          iconFirst: false,
          onTap: page < pageCount ? () => onPage(page + 1) : null,
        ),
      ],
    );
  }
}

class _NumberButton extends StatelessWidget {
  final int number;
  final bool selected;
  final VoidCallback onTap;

  const _NumberButton({required this.number, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlitchPressable(
      onTap: selected ? null : onTap,
      child: Container(
        width: 30,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        alignment: Alignment.center,
        decoration: selected
            ? BoxDecoration(color: GlitchColors.accentBlue, shape: BoxShape.circle)
            : null,
        child: Text(
          '$number',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : GlitchColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final bool iconFirst;
  final VoidCallback? onTap;

  const _StepButton({required this.icon, required this.label, required this.iconFirst, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? GlitchColors.textHint : GlitchColors.textPrimary;
    final text = label == null
        ? null
        : Text(label!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color));
    final ic = Icon(icon, size: 20, color: color);
    return GlitchPressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iconFirst) ic,
            if (text != null) text,
            if (!iconFirst) ic,
          ],
        ),
      ),
    );
  }
}
