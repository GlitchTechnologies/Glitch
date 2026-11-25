import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/own_account_open.dart' show confirmLogout, editMyProfile;
import '../models/user.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_sheet.dart';
import '../widgets/glitch_avatar.dart';
import '../widgets/glitch_plus_badge.dart';
import '../widgets/glitch_plus_panel.dart';
import '../widgets/glitch_hover_row.dart';
import '../widgets/settings_window.dart';
import 'permissions_section_web.dart' if (dart.library.io) 'permissions_section_native.dart';
import 'user_about_section.dart';
import 'user_account_section.dart';
import 'user_appearance_section.dart';
import 'user_folders_section.dart';
import 'user_language_section.dart';
import 'user_notifications_section.dart';
import 'user_privacy_section.dart';
import 'user_system_section.dart';
import 'user_keybinds_section.dart';
import 'user_sounds_section.dart';
import 'user_voice_section.dart';

enum UserSettingsSection {
  account, privacy, notifications, sounds, glitchPlus, appearance, voice, keybinds, folders, language, system, permissions, about,
}

Future<void> showUserSettings(BuildContext context, {UserSettingsSection? section}) =>
    openAdaptiveWindow<void>(
      context,
      narrowBuilder: (_) => UserSettingsWindow(wide: false, initialSection: section),
      wideBuilder: (_) => UserSettingsWindow(wide: true, initialSection: section),
      wideSize: const Size(1400, 1000),
    );

class UserSettingsWindow extends StatefulWidget {
  final bool wide;

  final UserSettingsSection? initialSection;

  const UserSettingsWindow({super.key, required this.wide, this.initialSection});

  @override
  State<UserSettingsWindow> createState() => _UserSettingsWindowState();
}

class _UserSettingsWindowState extends State<UserSettingsWindow>
    with ThemeAwareState<UserSettingsWindow> {
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final spec = SettingsWindowSpec<UserSettingsSection>(
      title: s.settingsTitle,
      objectName: authService.currentUser?.displayName ?? '',
      initialSection: widget.initialSection,
      narrowHeader: const _Identity(padding: EdgeInsets.symmetric(vertical: 8)),
      wideMenuHeader: const Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: _Identity(padding: EdgeInsets.fromLTRB(10, 8, 10, 8)),
      ),
      groups: [
        (s.userSettingsGroup, [
          UserSettingsSection.account,
          UserSettingsSection.privacy,
          UserSettingsSection.notifications,
          UserSettingsSection.sounds,
        ]),
        (s.userSettingsBillingGroup, [UserSettingsSection.glitchPlus]),
        (s.userSettingsAppGroup, [
          UserSettingsSection.appearance,
          UserSettingsSection.voice,
          if (hasKeybindsSection) UserSettingsSection.keybinds,
          UserSettingsSection.folders,
          UserSettingsSection.language,
          if (hasSystemSection) UserSettingsSection.system,
          if (hasPermissionsSection) UserSettingsSection.permissions,
        ]),
        (null, [UserSettingsSection.about]),
      ],
      label: (section) => switch (section) {
        UserSettingsSection.account => s.userSettingsAccount,
        UserSettingsSection.privacy => s.privacy,
        UserSettingsSection.notifications => s.notifications,
        UserSettingsSection.sounds => s.userSettingsSounds,
        UserSettingsSection.glitchPlus => 'Glitch+',
        UserSettingsSection.appearance => s.appearance,
        UserSettingsSection.voice => s.userSettingsVoice,
        UserSettingsSection.keybinds => s.userSettingsKeybinds,
        UserSettingsSection.folders => s.userSettingsFolders,
        UserSettingsSection.language => s.language,
        UserSettingsSection.system => s.systemSettingsSection,
        UserSettingsSection.permissions => s.permissionsTitle,
        UserSettingsSection.about => s.about,
      },
      icon: (section) => switch (section) {
        UserSettingsSection.account => Icons.person_outline_rounded,
        UserSettingsSection.privacy => Icons.lock_outline_rounded,
        UserSettingsSection.notifications => Icons.notifications_outlined,
        UserSettingsSection.sounds => Icons.volume_up_outlined,
        UserSettingsSection.glitchPlus => Icons.bolt_rounded,
        UserSettingsSection.appearance => Icons.palette_outlined,
        UserSettingsSection.voice => Icons.mic_none_rounded,
        UserSettingsSection.keybinds => Icons.keyboard_outlined,
        UserSettingsSection.folders => Icons.folder_outlined,
        UserSettingsSection.language => Icons.language_rounded,
        UserSettingsSection.system => Icons.desktop_windows_outlined,
        UserSettingsSection.permissions => Icons.verified_user_outlined,
        UserSettingsSection.about => Icons.info_outline_rounded,
      },
      content: (section, {header, sectionKey, wide = false}) => switch (section) {
        UserSettingsSection.account => UserAccountSection(key: sectionKey, header: header),
        UserSettingsSection.privacy => UserPrivacySection(key: sectionKey, header: header),
        UserSettingsSection.notifications => UserNotificationsSection(key: sectionKey, header: header),
        UserSettingsSection.sounds => UserSoundsSection(key: sectionKey, header: header),
        UserSettingsSection.glitchPlus =>
          GlitchPlusPanel(key: sectionKey, padding: const EdgeInsets.fromLTRB(16, 18, 16, 40)),
        UserSettingsSection.appearance => UserAppearanceSection(key: sectionKey, header: header),
        UserSettingsSection.voice => UserVoiceSection(key: sectionKey, header: header),
        UserSettingsSection.keybinds => UserKeybindsSection(key: sectionKey, header: header),
        UserSettingsSection.folders => UserFoldersSection(key: sectionKey, header: header),
        UserSettingsSection.language => UserLanguageSection(key: sectionKey, header: header),
        UserSettingsSection.system => UserSystemSection(key: sectionKey, header: header),
        UserSettingsSection.permissions => permissionsSection(key: sectionKey),
        UserSettingsSection.about => UserAboutSection(key: sectionKey, header: header),
      },
      danger: SettingsDangerAction(
        label: s.logout,
        icon: Icons.logout_rounded,
        onTap: () => confirmLogout(context),
      ),
    );
    return widget.wide
        ? SettingsWindowWide<UserSettingsSection>(spec: spec, windowed: true)
        : SettingsWindowNarrow<UserSettingsSection>(spec: spec);
  }
}

class _Identity extends StatelessWidget {
  final EdgeInsets padding;

  const _Identity({required this.padding});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<User?>(
        valueListenable: authService.currentUserListenable,
        builder: (context, me, _) {
          final name = me?.displayName ?? '';
          return GlitchHoverRow(
            onTap: () => editMyProfile(context),
            highlightInset: EdgeInsets.zero,
            padding: padding,
            child: _row(context, me, name),
          );
        },
      );

  Widget _row(BuildContext context, User? me, String name) => Row(
        children: [
          GlitchAvatar(
            initials: GlitchAvatar.initialsFromName(name),
            size: 44,
            colorIndex: GlitchAvatar.colorFromNickname(me?.nickname ?? ''),
            imageUrl: me?.avatar != null ? api.mediaUrl(me!.avatar!) : null,
            avatarSizes: me?.avatarSizes,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserDisplayName(
                  displayName: name,
                  isGlitchPlus: me?.isGlitchPlus ?? false,
                  ellipsis: true,
                  badgeSize: 15,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
                ),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        context.s.profileEdit,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: GlitchColors.textSecond),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.edit_rounded, size: 13, color: GlitchColors.textSecond),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
}
