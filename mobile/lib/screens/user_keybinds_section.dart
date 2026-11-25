import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/platform_info.dart';
import '../providers/theme_provider.dart';
import '../services/keybinds.dart';
import '../theme/app_theme.dart';
import '../widgets/keybind_field.dart';
import '../widgets/settings_page_parts.dart';
import '../widgets/settings_parts.dart' show SettingsCard, SettingsNotice;
import '../widgets/settings_two_pane.dart';
import '../widgets/settings_window.dart' show SettingsBlock;

bool get hasKeybindsSection => hasPointerInput;

class UserKeybindsSection extends StatefulWidget {
  final Widget? header;

  const UserKeybindsSection({super.key, this.header});

  @override
  State<UserKeybindsSection> createState() => _UserKeybindsSectionState();
}

class _UserKeybindsSectionState extends State<UserKeybindsSection>
    with ThemeAwareState<UserKeybindsSection> {
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final header = widget.header;
    return ListenableBuilder(
      listenable: keybinds,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, header != null ? SettingsTwoPane.windowTopPad : 18, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (header != null) ...[header, const SizedBox(height: 24)],
              SettingsBlock(
                title: s.userSettingsKeybinds,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SettingsBlockTitle(s.userSettingsKeybinds),
                    Text(
                      s.keybindsDescription,
                      style: TextStyle(fontSize: 13, height: 1.35, color: GlitchColors.textSecond),
                    ),
                    const SizedBox(height: 16),
                    SettingsCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, action) in KeybindAction.values.indexed) ...[
                            if (i > 0) Divider(height: 1, color: GlitchColors.border),
                            _KeybindRow(action: action),
                          ],
                        ],
                      ),
                    ),
                    if (!keybinds.programEditable && hasBrowserTabs) ...[
                      const SizedBox(height: 12),
                      SettingsNotice(icon: Icons.info_outline_rounded, text: s.keybindsBrowserFixed),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KeybindRow extends StatelessWidget {
  final KeybindAction action;

  const _KeybindRow({required this.action});

  static const double _pairedMinWidth = 480;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      keybindActionLabel(context, action),
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary),
    );
    final field = KeybindField(
      combo: keybinds.combosOf(action).firstOrNull,
      onRecorded: keybinds.isEditable(action)
          ? (combo) async {
              final problem = await keybinds.assign(action, combo);
              if (problem != null && context.mounted) showKeybindProblem(context, problem);
            }
          : null,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < _pairedMinWidth) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [label, const SizedBox(height: 8), field],
            );
          }
          return Row(
            children: [
              Expanded(flex: 5, child: label),
              const SizedBox(width: 16),
              Expanded(flex: 7, child: field),
            ],
          );
        },
      ),
    );
  }
}

String keybindActionLabel(BuildContext context, KeybindAction action) {
  final s = context.s;
  return switch (action) {
    KeybindAction.pushToTalk => s.keybindActionPushToTalk,
    KeybindAction.toggleMute => s.keybindActionToggleMute,
    KeybindAction.toggleDeafen => s.keybindActionToggleDeafen,
    KeybindAction.editLastMessage => s.keybindActionEditLastMessage,
    KeybindAction.reload => s.keybindActionReload,
    KeybindAction.zoomIn => s.keybindActionZoomIn,
    KeybindAction.zoomOut => s.keybindActionZoomOut,
    KeybindAction.zoomReset => s.keybindActionZoomReset,
  };
}
