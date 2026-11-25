import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../models/user.dart';
import '../screens/email_verify_screen.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'glitch_bar_buttons.dart';
import 'glitch_dialog.dart';
import 'glitch_toast.dart';

Future<void> changeEmail(BuildContext context) async {
  final emailCtrl = TextEditingController(text: authService.currentUser?.email ?? '');
  final passCtrl = TextEditingController();
  try {
    await showDialog(
      context: context,
      builder: (dialogCtx) => GlitchDialog(
        title: context.s.accountEditEmail,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlitchDialogField(
                controller: emailCtrl,
                hint: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
                autofocus: true),
            const SizedBox(height: 10),
            GlitchDialogField(
                controller: passCtrl, hint: context.s.accountEmailPasswordHint, obscure: true),
            const SizedBox(height: 10),
            Text(
              context.s.accountEmailPasswordWhy,
              style: TextStyle(color: GlitchColors.textHint, fontSize: 12.5, height: 1.35),
            ),
          ],
        ),
        actions: [
          GlitchPlainButton(label: context.s.cancel, onTap: () => Navigator.pop(dialogCtx)),
          GlitchFilledButton(
            label: context.s.save,
            onTap: () async {
              final email = emailCtrl.text.trim().toLowerCase();
              final password = passCtrl.text;
              Navigator.pop(dialogCtx);
              if (email.isEmpty || password.isEmpty) return;
              try {
                final updated = await _confirmAndSave(context, email, password);
                if (updated == null) return; // отказались подтверждать
                authService.currentUser = updated;
              } catch (e) {
                if (context.mounted) GlitchToast.show(context, errorMessage(e));
              }
            },
          ),
        ],
      ),
    );
  } finally {
    emailCtrl.dispose();
    passCtrl.dispose();
  }
}

Future<User?> _confirmAndSave(BuildContext context, String email, String password) async {
  final req = await api.requestEmailChangeCode(email: email, password: password);
  if (!context.mounted) return null;

  final token = await Navigator.push<String>(
    context,
    MaterialPageRoute(builder: (_) => EmailVerifyScreen(
      email: email,
      verificationId: req['verification_id'] as String,
      resendAfter: (req['resend_after'] as num?)?.toInt() ?? 60,
      codeLength: (req['code_length'] as num?)?.toInt() ?? 6,
      onResend: () => api.requestEmailChangeCode(email: email, password: password),
    )),
  );
  if (token == null) return null;

  return await api.updateMe(email: email, emailToken: token, password: password);
}
