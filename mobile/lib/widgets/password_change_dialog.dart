import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'glitch_bar_buttons.dart';
import 'glitch_dialog.dart';
import 'glitch_toast.dart';

Future<void> changePassword(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _repeatCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _repeatCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final s = context.s;
    final oldPass = _oldCtrl.text;
    final newPass = _newCtrl.text;
    final repeat = _repeatCtrl.text;

    if (oldPass.isEmpty || newPass.isEmpty || repeat.isEmpty) {
      setState(() => _error = s.changePasswordFillFields);
      return;
    }
    // Совпадение повтора проверяем на клиенте: серверу второе поле не
    // отправляется вообще, это защита от опечатки, а не правило безопасности.
    if (newPass != repeat) {
      setState(() => _error = s.changePasswordMismatch);
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      await api.changePassword(oldPassword: oldPass, newPassword: newPass);
      if (!mounted) return;
      GlitchToast.show(context, s.changePasswordSuccess, type: ToastType.success);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return GlitchDialog(
      title: s.changePasswordTitle,
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.changePasswordDescription, style: GlitchDialog.bodyStyle),
            const SizedBox(height: 16),
            GlitchDialogField(controller: _oldCtrl, hint: s.changePasswordCurrent, obscure: true, autofocus: true),
            const SizedBox(height: 10),
            GlitchDialogField(controller: _newCtrl, hint: s.changePasswordNew, obscure: true),
            const SizedBox(height: 10),
            GlitchDialogField(
              controller: _repeatCtrl,
              hint: s.changePasswordRepeat,
              obscure: true,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(s.changePasswordHint, style: TextStyle(color: GlitchColors.textHint, fontSize: 13)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: GlitchColors.error, fontSize: 14)),
            ],
          ],
        ),
      ),
      actions: [
        GlitchPlainButton(label: s.cancel, onTap: () => Navigator.pop(context)),
        GlitchFilledButton(label: s.save, loading: _loading, onTap: _submit),
      ],
    );
  }
}
