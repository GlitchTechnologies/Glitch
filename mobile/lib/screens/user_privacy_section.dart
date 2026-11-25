import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../providers/privacy_settings.dart';
import '../providers/theme_provider.dart';
import '../widgets/blocked_users_list.dart';
import '../widgets/glitch_switch.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/settings_page_parts.dart';
import '../widgets/settings_two_pane.dart';
import '../widgets/settings_window.dart' show SettingsBlock, SettingsDivider, pushSettingsPage;
import 'privacy_policy_view.dart';

/// Раздел «КОНФИДЕНЦИАЛЬНОСТЬ» окна личных настроек — по образцу Discord
/// «Данные и конфиденциальность» (2026-09-25). Три блока (список под пунктом
/// меню собирается со страницы — `SettingsBlock`):
///   • «Видимость» — «Публичный профиль» и «Показывать активность», с
///     пояснением, что каждый делает;
///   • «Чёрный список» — заблокированные прямо на странице (раньше —
///     отдельный экран из «Безопасности»);
///   • «Документы» — политика конфиденциальности подстраницей окна.
class UserPrivacySection extends StatefulWidget {
  final Widget? header;

  const UserPrivacySection({super.key, this.header});

  @override
  State<UserPrivacySection> createState() => _UserPrivacySectionState();
}

class _UserPrivacySectionState extends State<UserPrivacySection>
    with ThemeAwareState<UserPrivacySection> {
  final _settings = PrivacySettings();

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
            title: s.privacyVisibilityTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsBlockTitle(s.privacyVisibilityTitle),
                GlitchSwitchRow(
                  label: s.privacyPublicProfile,
                  description: s.privacyPublicProfileDesc,
                  value: _settings.isPublic,
                  onChanged: _settings.loading ? null : (v) => _settings.setPublic(v).then(_showError),
                  border: false,
                  padding: _rowPadding,
                ),
                GlitchSwitchRow(
                  label: s.privacyShowActivity,
                  description: s.privacyShowActivityDesc,
                  value: _settings.showActivity,
                  onChanged: _settings.loading ? null : (v) => _settings.setShowActivity(v).then(_showError),
                  border: false,
                  padding: _rowPadding,
                ),
                GlitchSwitchRow(
                  label: s.privacyShowPlaying,
                  description: s.privacyShowPlayingDesc,
                  value: _settings.showPlaying,
                  onChanged: _settings.loading ? null : (v) => _settings.setShowPlaying(v).then(_showError),
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
            title: s.privacyFriendRequestsTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsBlockTitle(s.privacyFriendRequestsTitle),
                for (final (label, desc, value, change) in [
                  (s.privacyFriendReqEveryone, s.privacyFriendReqEveryoneDesc, _settings.friendReqEveryone,
                      (bool v) => _settings.setFriendRequests(everyone: v)),
                  (s.privacyFriendReqFriends, s.privacyFriendReqFriendsDesc, _settings.friendReqFriends,
                      (bool v) => _settings.setFriendRequests(friends: v)),
                  (s.privacyFriendReqServers, s.privacyFriendReqServersDesc, _settings.friendReqServers,
                      (bool v) => _settings.setFriendRequests(servers: v)),
                ])
                  GlitchSwitchRow(
                    label: label,
                    description: desc,
                    value: value,
                    onChanged: _settings.loading ? null : (v) => change(v).then(_showError),
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
            title: s.securityBlacklist,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsBlockTitle(s.securityBlacklist),
                const SizedBox(height: 4),
                const BlockedUsersList(),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SettingsDivider(),
          const SizedBox(height: 24),
          SettingsBlock(
            title: s.privacyDocsTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsBlockTitle(s.privacyDocsTitle),
                SettingsLineRow(
                  label: s.privacyPolicyRow,
                  onTap: () => pushSettingsPage<void>(
                    context,
                    title: s.privacyPolicyRow,
                    builder: (_) => const PrivacyPolicyView(),
                  ),
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
