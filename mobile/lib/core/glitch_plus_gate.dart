import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../screens/user_settings_window.dart' show UserSettingsSection;
import '../services/auth_service.dart';
import '../widgets/glitch_dialog.dart';
import 'l10n.dart';
import 'own_account_open.dart' show openMySettings;

Future<bool> ensureGlitchPlus(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  if (authService.currentUser?.isGlitchPlus == true) return true;

  final wantsSubscribe = await glitchConfirm(
    context,
    title: title,
    body: body,
    confirmLabel: context.s.glitchPlusPromoConfirm,
    destructive: false,
  );
  if (wantsSubscribe && context.mounted) {
    unawaited(openMySettings(context, section: UserSettingsSection.glitchPlus));
  }
  return false;
}
