import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../providers/theme_provider.dart';
import '../widgets/appearance_options.dart';
import '../widgets/settings_page_parts.dart';
import '../widgets/settings_two_pane.dart';
import '../widgets/settings_window.dart' show SettingsBlock;

class UserLanguageSection extends StatefulWidget {
  final Widget? header;

  const UserLanguageSection({super.key, this.header});

  @override
  State<UserLanguageSection> createState() => _UserLanguageSectionState();
}

// ThemeAwareState: смена темы перекрашивает карточку. Смену языка страница
// получает сама (context.s), галочку перерисовывает LanguageOptions.
class _UserLanguageSectionState extends State<UserLanguageSection>
    with ThemeAwareState<UserLanguageSection> {
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
            title: s.languageSelectTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsBlockTitle(s.languageSelectTitle),
                LanguageOptions(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
