import 'package:flutter/material.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../providers/theme_provider.dart';
import '../widgets/glitch_action_button.dart';

enum TwoFactorAction { disable, regenerateCodes }

class TwoFactorConfirmView extends StatefulWidget {
  final TwoFactorAction action;

  const TwoFactorConfirmView({super.key, required this.action});

  @override
  State<TwoFactorConfirmView> createState() => _TwoFactorConfirmViewState();
}

class _TwoFactorConfirmViewState extends State<TwoFactorConfirmView>
    with ThemeAwareState<TwoFactorConfirmView> {
  final _passwordCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = context.s;
    final password = _passwordCtrl.text;
    final code = _codeCtrl.text.trim();

    if (password.isEmpty) {
      setState(() => _error = s.twoFactorEnterPassword);
      return;
    }
    if (code.isEmpty) {
      setState(() => _error = s.twoFactorEnterCode);
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      if (widget.action == TwoFactorAction.disable) {
        await api.totpDisable(password: password, code: code);
        if (!mounted) return;
        Navigator.pop(context, true);
      } else {
        final codes = await api.totpRegenerateBackupCodes(password: password, code: code);
        if (!mounted) return;
        Navigator.pop(context, codes);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = errorMessage(e); _codeCtrl.clear(); });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final isDisable = widget.action == TwoFactorAction.disable;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isDisable ? s.twoFactorDisableWarning : s.twoFactorRegenerateWarning,
              style: TextStyle(color: GlitchColors.textSecond, fontSize: 14.5, height: 1.45)),
          const SizedBox(height: 24),
          _field(s.twoFactorPasswordHint, _passwordCtrl, obscure: true),
          const SizedBox(height: 12),
          _field(s.twoFactorCodeHint, _codeCtrl),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: GlitchColors.error, fontSize: 14)),
          ],
          const SizedBox(height: 24),
          GlitchActionButton(
            label: isDisable ? s.twoFactorDisable : s.twoFactorConfirm,
            onTap: _submit,
            destructive: isDisable,
            loading: _loading,
          ),
        ],
      ),
    );
  }

  Widget _field(String hint, TextEditingController ctrl, {bool obscure = false}) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: GlitchColors.bgInput,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: GlitchColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        style: TextStyle(color: GlitchColors.textPrimary, fontSize: 16),
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          fillColor: Colors.transparent,
          filled: false,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
