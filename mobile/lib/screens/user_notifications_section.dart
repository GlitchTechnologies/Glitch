import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../providers/notif_settings.dart';
import '../providers/theme_provider.dart';
import '../widgets/glitch_switch.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/settings_page_parts.dart';
import '../widgets/settings_two_pane.dart';
import '../widgets/settings_window.dart' show SettingsBlock, SettingsDivider;

class UserNotificationsSection extends StatefulWidget {
  final Widget? header;

  const UserNotificationsSection({super.key, this.header});

  @override
  State<UserNotificationsSection> createState() => _UserNotificationsSectionState();
}

class _UserNotificationsSectionState extends State<UserNotificationsSection>
    with ThemeAwareState<UserNotificationsSection> {
  final _settings = NotifSettings();

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
    final ready = !_settings.loading;
    final chatsOn = ready && _settings.enabled;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, header != null ? SettingsTwoPane.windowTopPad : 18, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null) ...[header, const SizedBox(height: 24)],
          SettingsBlock(
            title: s.notifGeneralTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsBlockTitle(s.notifGeneralTitle),
                GlitchSwitchRow(
                  label: s.notifications,
                  description: s.notifAllDesc,
                  value: _settings.enabled,
                  onChanged: ready ? (v) => _settings.setEnabled(v).then(_showError) : null,
                  border: false,
                  padding: _rowPadding,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const SettingsDivider(),
          const SizedBox(height: 24),
          SettingsBlock(
            title: s.notifChatsTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsBlockTitle(s.notifChatsTitle),
                GlitchSwitchRow(
                  label: s.notifPersonal,
                  description: s.notifPersonalDesc,
                  value: _settings.enabled && _settings.personal,
                  onChanged: chatsOn ? (v) => _settings.setPersonal(v).then(_showError) : null,
                  border: false,
                  padding: _rowPadding,
                ),
                GlitchSwitchRow(
                  label: s.notifGroups,
                  description: s.notifGroupsDesc,
                  value: _settings.enabled && _settings.groups,
                  onChanged: chatsOn ? (v) => _settings.setGroups(v).then(_showError) : null,
                  border: false,
                  padding: _rowPadding,
                ),
                GlitchSwitchRow(
                  label: s.notifServers,
                  description: s.notifServersDesc,
                  value: _settings.enabled && _settings.servers,
                  onChanged: chatsOn ? (v) => _settings.setServers(v).then(_showError) : null,
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
