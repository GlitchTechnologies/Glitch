import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../providers/theme_provider.dart';
import '../widgets/appearance_options.dart';
import '../widgets/settings_page_parts.dart';
import '../widgets/settings_two_pane.dart';
import '../widgets/settings_window.dart' show SettingsBlock, SettingsDivider;

class UserAppearanceSection extends StatefulWidget {
  final Widget? header;

  const UserAppearanceSection({super.key, this.header});

  @override
  State<UserAppearanceSection> createState() => _UserAppearanceSectionState();
}

class _UserAppearanceSectionState extends State<UserAppearanceSection>
    with ThemeAwareState<UserAppearanceSection> {
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final header = widget.header;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, header != null ? SettingsTwoPane.windowTopPad : 18, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null) ...[header, const SizedBox(height: 24)],
          SettingsBlock(
            title: s.appearanceThemeSection,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsBlockTitle(s.appearanceThemeSection),
                const AppearanceThemeOptions(),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SettingsDivider(),
          const SizedBox(height: 24),
          SettingsBlock(
            title: s.appearanceAccentColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsBlockTitle(s.appearanceAccentColor),
                const AccentColorOptions(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
