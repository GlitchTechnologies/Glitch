import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../models/user.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/email_change_flow.dart';
import '../widgets/glitch_action_button.dart';
import '../widgets/password_change_dialog.dart';
import '../widgets/settings_page_parts.dart';
import '../widgets/settings_two_pane.dart';
import '../widgets/settings_window.dart' show SettingsBlock, SettingsDivider, pushSettingsPage;
import 'active_sessions_view.dart';
import 'two_factor_view.dart';

/// Две части:
///   • «Информация об учётной записи» — ник (не меняется) и почта (скрыта
///     звёздочками, «Показать», «Изменить» — общая `changeEmail`);
///   • «Пароль и безопасность» — пароль, двухфакторка, активные сеансы.
///     Раньше это жило в «Безопасности» и «Устройствах» прежних настроек.
class UserAccountSection extends StatefulWidget {
  final Widget? header;

  const UserAccountSection({super.key, this.header});

  @override
  State<UserAccountSection> createState() => _UserAccountSectionState();
}

class _UserAccountSectionState extends State<UserAccountSection>
    with ThemeAwareState<UserAccountSection> {
  bool _emailShown = false;

  bool? _totpEnabled;
  int? _sessions;

  @override
  void initState() {
    super.initState();
    _loadTotp();
    _loadSessions();
  }

  Future<void> _loadTotp() async {
    try {
      final data = await api.getTotpStatus();
      if (mounted) setState(() => _totpEnabled = data['enabled'] == true);
    } catch (_) {}
  }

  Future<void> _loadSessions() async {
    try {
      final sessions = await api.getSessions();
      if (mounted) setState(() => _sessions = sessions.length);
    } catch (_) {}
  }

  Future<void> _openPage(String title, Widget page, {VoidCallback? then}) async {
    await pushSettingsPage<void>(context, title: title, builder: (_) => page);
    if (mounted) then?.call();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final header = widget.header;
    return ValueListenableBuilder<User?>(
      valueListenable: authService.currentUserListenable,
      builder: (context, me, _) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, header != null ? SettingsTwoPane.windowTopPad : 18, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null) ...[header, const SizedBox(height: 24)],
            SettingsBlock(
              title: s.accountInfoTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsBlockTitle(s.accountInfoTitle),
                  SettingsLineRow(label: s.accountUsername, value: me?.nickname ?? ''),
                  SettingsLineRow(
                    label: s.email,
                    value: _emailShown ? (me?.email ?? '') : _maskEmail(me?.email ?? ''),
                    link: (me?.email ?? '').isEmpty ? null : (_emailShown ? s.accountHide : s.accountShow),
                    onLink: () => setState(() => _emailShown = !_emailShown),
                    action: GlitchActionButton(
                      label: s.edit,
                      soft: true,
                      compact: true,
                      onTap: () => changeEmail(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const SettingsDivider(),
            const SizedBox(height: 24),
            SettingsBlock(
              title: s.accountSecurityTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsBlockTitle(s.accountSecurityTitle),
                  SettingsLineRow(
                    label: s.accountPassword,
                    action: GlitchActionButton(
                      label: s.edit,
                      soft: true,
                      compact: true,
                      onTap: () => changePassword(context),
                    ),
                  ),
                  SettingsLineRow(
                    label: s.twoFactor,
                    value: _totpEnabled == null ? '' : (_totpEnabled! ? s.twoFactorOn : s.twoFactorOff),
                    onTap: () => _openPage(s.twoFactor, const TwoFactorView(), then: _loadTotp),
                  ),
                  SettingsLineRow(
                    label: s.accountSessions,
                    value: _sessions == null ? '' : s.accountSessionsCount(_sessions!),
                    onTap: () => _openPage(s.accountSessions, const ActiveSessionsView(), then: _loadSessions),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// «**********@gmail.com», как у Discord: скрыто имя ящика, домен виден —
  /// по нему человек узнаёт, какая почта привязана, не показывая её целиком
  /// тому, кто смотрит через плечо.
  static String _maskEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 0) return email;
    return '${'*' * at.clamp(1, 12)}${email.substring(at)}';
  }
}
