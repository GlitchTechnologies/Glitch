import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'glitch_pressable.dart' show ClickableCursor;

class GlitchSegmentedControl extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  final double height;

  const GlitchSegmentedControl({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.height = 54,
  });

  @override
  Widget build(BuildContext context) {
    const gap = 4.0;
    const padding = 4.0;
    return Container(
      height: height,
      padding: const EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: GlitchColors.bgTabBar,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: GlitchColors.borderTabBar),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalGap = gap * (labels.length - 1);
          final tabWidth = (constraints.maxWidth - totalGap) / labels.length;

          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                left: selected * (tabWidth + gap),
                top: 0,
                bottom: 0,
                width: tabWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: GlitchColors.bgTabActive,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: GlitchColors.borderTabActive),
                  ),
                ),
              ),

              Row(
                children: [
                  for (int i = 0; i < labels.length; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    Expanded(
                      child: ClickableCursor(
                        child: GestureDetector(
                        onTap: () => onChanged(i),
                        behavior: HitTestBehavior.opaque,
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 180),
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                              color: selected == i ? GlitchColors.textPrimary : GlitchColors.textSecond,
                            ),
                            // Одна строка с многоточием: длинная подпись
                            // (вкладки полного профиля в узком окне) иначе
                            // вылезала бы за вкладку.
                            child: Text(labels[i], maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
