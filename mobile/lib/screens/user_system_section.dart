import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../providers/system_settings.dart';
import '../providers/theme_provider.dart';
import '../services/desktop_shell.dart';
import '../widgets/glitch_switch.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/settings_page_parts.dart';
import '../widgets/settings_two_pane.dart';
import '../widgets/settings_window.dart' show SettingsBlock;

bool get hasSystemSection => desktopShell?.hasSystemSettings ?? false;

class UserSystemSection extends StatefulWidget {
  final Widget? header;

  const UserSystemSection({super.key, this.header});

  @override
  State<UserSystemSection> createState() => _UserSystemSectionState();
}

class _UserSystemSectionState extends State<UserSystemSection>
    with ThemeAwareState<UserSystemSection> {
  final _settings = SystemSettings();

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onChange);
    _settings.load().then(_showError);
  }

  @override
  void dispose() {
    _settings.removeListener(_onChange);
    _settings.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _showError(String? error) {
    if (error != null && mounted) GlitchToast.show(context, error);
  }

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
            title: s.systemBehaviorTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsBlockTitle(s.systemBehaviorTitle),
                GlitchSwitchRow(
                  label: s.systemOpenAtLogin,
                  description: s.systemOpenAtLoginDesc,
                  value: _settings.openAtLogin,
                  onChanged: _settings.loading ? null : (v) => _settings.setOpenAtLogin(v).then(_showError),
                  border: false,
                  padding: _rowPadding,
                ),
                GlitchSwitchRow(
                  label: s.systemCloseToTray,
                  description: s.systemCloseToTrayDesc,
                  value: _settings.closeToTray,
                  onChanged: _settings.loading ? null : (v) => _settings.setCloseToTray(v).then(_showError),
                  border: false,
                  padding: _rowPadding,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _rowPadding = EdgeInsets.symmetric(vertical: 12);
}
