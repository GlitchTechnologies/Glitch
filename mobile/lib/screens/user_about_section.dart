import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_version.dart';
import '../services/desktop_shell.dart';
import '../core/glitch_link.dart';
import '../core/l10n.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/glitch_logo.dart';
import '../widgets/linked_text.dart' show launchSmartUrl;
import '../widgets/settings_page_parts.dart';
import '../widgets/settings_two_pane.dart';
import '../widgets/settings_window.dart' show SettingsBlock, SettingsDivider, pushSettingsPage;
import 'privacy_policy_view.dart';


const _siteLink = glitchDomain;
const _supportEmail = 'support@glitchapp.online';

class UserAboutSection extends StatefulWidget {
  final Widget? header;

  const UserAboutSection({super.key, this.header});

  @override
  State<UserAboutSection> createState() => _UserAboutSectionState();
}

class _UserAboutSectionState extends State<UserAboutSection>
    with ThemeAwareState<UserAboutSection> {
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

          Row(
            children: [
              const GlitchLogo(size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Glitch',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text('v$appVersion', style: TextStyle(fontSize: 13.5, color: GlitchColors.textSecond)),
                    if (desktopShell != null)
                      Text(
                        s.desktopAppVersion(desktopShell!.appVersion),
                        style: TextStyle(fontSize: 13.5, color: GlitchColors.textSecond),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(s.aboutDescription,
              style: TextStyle(fontSize: 14.5, color: GlitchColors.textPrimary, height: 1.5)),
          const SizedBox(height: 24),
          const SettingsDivider(),
          const SizedBox(height: 24),

          SettingsBlock(
            title: s.aboutContactTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsBlockTitle(s.aboutContactTitle),
                SettingsLineRow(
                  label: s.aboutSite,
                  link: _siteLink,
                  onLink: () => launchSmartUrl(context, _siteLink),
                ),
                SettingsLineRow(
                  label: s.aboutSupportEmail,
                  link: _supportEmail,
                  onLink: () => launchUrl(Uri(scheme: 'mailto', path: _supportEmail)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
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

          const SizedBox(height: 28),
          Text('© 2026 Glitch', style: TextStyle(fontSize: 13, color: GlitchColors.textHint)),
        ],
      ),
    );
  }
}
