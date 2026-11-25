import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../providers/theme_provider.dart';
import '../widgets/settings_page_parts.dart';
import '../widgets/settings_two_pane.dart';
import '../widgets/settings_window.dart' show SettingsBlock;
import 'folders_screen.dart' show FolderListBody;

class UserFoldersSection extends StatefulWidget {
  final Widget? header;

  const UserFoldersSection({super.key, this.header});

  @override
  State<UserFoldersSection> createState() => _UserFoldersSectionState();
}

class _UserFoldersSectionState extends State<UserFoldersSection>
    with ThemeAwareState<UserFoldersSection> {
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
            title: s.foldersMineTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsBlockTitle(s.foldersMineTitle),
                const SizedBox(height: 4),
                // Без const: список перекрашивается при смене темы вместе
                // со страницей.
                FolderListBody(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
