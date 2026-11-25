import 'package:flutter/material.dart';

import '../screens/profile_editor.dart';
import '../screens/user_settings_window.dart';
import '../services/auth_service.dart';
import '../widgets/glitch_dialog.dart' show glitchConfirm;
import 'l10n.dart';


Future<void> openMySettings(BuildContext context, {UserSettingsSection? section}) =>
    showUserSettings(context, section: section);

Future<void> editMyProfile(BuildContext context, {int? serverId, bool achievements = false}) =>
    showProfileEditor(context, serverId: serverId, achievements: achievements);

Future<void> confirmLogout(BuildContext context) async {
  final confirm = await glitchConfirm(context,
      title: context.s.logoutTitle, confirmLabel: context.s.logout);
  if (!confirm) return;
  await authService.logout();
}
