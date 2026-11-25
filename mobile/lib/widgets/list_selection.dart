import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'glitch_icon_button.dart';



class SelectionController extends ChangeNotifier {
  final Set<int> _selected = {};

  bool get selecting => _selected.isNotEmpty;
  int get count => _selected.length;
  Set<int> get selectedIds => Set.unmodifiable(_selected);

  bool isSelected(int id) => _selected.contains(id);

  void toggle(int id) {
    if (!_selected.remove(id)) _selected.add(id);
    notifyListeners();
  }

  void clear() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  void prune(Set<int> existingIds) {
    final before = _selected.length;
    _selected.removeWhere((id) => !existingIds.contains(id));
    if (_selected.length != before) notifyListeners();
  }
}


class SelectionAction {
  final IconData icon;
  final Color? color; // null — textPrimary
  final VoidCallback onTap;
  const SelectionAction({required this.icon, this.color, required this.onTap});
}

class SelectionTopBar extends StatelessWidget {
  final SelectionController controller;
  final List<SelectionAction> actions;
  const SelectionTopBar({super.key, required this.controller, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GlitchIconButton(
          icon: Icon(Icons.close_rounded, color: GlitchColors.textPrimary, size: 24),
          onTap: controller.clear,
        ),
        Text('${controller.count}',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
        const Spacer(),
        for (final a in actions)
          GlitchIconButton(
            icon: Icon(a.icon, color: a.color ?? GlitchColors.textPrimary, size: 23),
            onTap: a.onTap,
          ),
      ],
    );
  }
}


class SelectableRow extends StatelessWidget {
  final SelectionController controller;
  final int id;
  final Widget child;

  const SelectableRow({
    super.key,
    required this.controller,
    required this.id,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final selecting = controller.selecting;
        final selected = controller.isSelected(id);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPress: selecting ? null : () => controller.toggle(id),
          onTap: selecting ? () => controller.toggle(id) : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                width: selecting ? 34 : 0,
                child: selecting
                    ? Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected ? GlitchColors.accentBlue : Colors.transparent,
                            border: selected ? null : Border.all(color: GlitchColors.textHint, width: 1.6),
                          ),
                          child: selected
                              ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                              : null,
                        ),
                      )
                    : null,
              ),
              Expanded(child: selecting ? AbsorbPointer(child: child) : child),
            ],
          ),
        );
      },
    );
  }
}
