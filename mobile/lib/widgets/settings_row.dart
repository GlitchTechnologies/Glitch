import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'glitch_pressable.dart';

/// Заведена 2026-09-21 вместе с настройками сервера. До этого строка была
/// скопирована руками в ДЕВЯТИ экранах (`_settingRow` / `_row`: настройки,
/// безопасность, приватность, уведомления, аккаунт, папки, разрешения,
/// заблокированные, мои стикеры) — и копии уже разъехались: у главных
/// настроек отступ 14, иконка 34, шрифт 16; у «Безопасности» 13, 30 и 15.5,
/// а вдобавок там потерялся `ClickableCursor`, и на вебе над её строками
/// стрелка вместо руки.
class SettingsRow extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String label;

  final String? value;

  final bool border;

  final Color? labelColor;

  final VoidCallback? onTap;
  final Widget? trailing;

  const SettingsRow({
    super.key,
    this.icon,
    this.leading,
    required this.label,
    this.value,
    this.border = true,
    this.labelColor,
    this.onTap,
    this.trailing,
  }) : assert(icon != null || leading != null);

  @override
  Widget build(BuildContext context) {
    return ClickableCursor(
      enabled: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: border
              ? BoxDecoration(border: Border(bottom: BorderSide(color: GlitchColors.borderSoft)))
              : null,
          child: Row(
            children: [
              leading ??
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(icon, color: labelColor ?? GlitchColors.textPrimary, size: 22),
                  ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    color: labelColor ?? GlitchColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (value != null && value!.isNotEmpty) ...[
                Text(value!, style: TextStyle(fontSize: 14.5, color: GlitchColors.textSecond)),
                const SizedBox(width: 4),
              ],
              trailing ?? Icon(Icons.chevron_right_rounded, color: GlitchColors.textHint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsSection extends StatelessWidget {
  final List<Widget> children;

  const SettingsSection({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: GlitchColors.bgCard,
        border: Border.all(color: GlitchColors.borderCard),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(children: children),
    );
  }
}
