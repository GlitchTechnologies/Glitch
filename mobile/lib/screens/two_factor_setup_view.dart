import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/copy_actions.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../providers/theme_provider.dart';
import '../widgets/glitch_pressable.dart';

/// Подключение двухфакторной авторизации: пароль → ключ настройки → код.
class TwoFactorSetupView extends StatefulWidget {
  const TwoFactorSetupView({super.key});

  @override
  State<TwoFactorSetupView> createState() => _TwoFactorSetupViewState();
}

class _TwoFactorSetupViewState extends State<TwoFactorSetupView>
    with ThemeAwareState<TwoFactorSetupView> {
  final _passwordCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  String? _secret;
  String? _uri;
  bool _showQr = false;

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }


  Future<void> _requestSecret() async {
    final password = _passwordCtrl.text;
    if (password.isEmpty) {
      setState(() => _error = context.s.twoFactorEnterPassword);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final data = await api.totpSetup(password: password);
      if (!mounted) return;
      setState(() {
        _secret = data['secret'] as String;
        _uri = data['uri'] as String;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  Future<void> _confirm() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = context.s.twoFactorEnterCode);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final codes = await api.totpConfirm(code: code);
      if (!mounted) return;
      Navigator.pop(context, codes);
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = errorMessage(e); _codeCtrl.clear(); });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyKey() async {
    if (_secret == null) return;
    await copyToClipboard(context, _secret!, context.s.twoFactorKeyCopied);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: _secret == null ? _passwordStep(s) : _keyStep(s),
    );
  }

  Widget _passwordStep(S s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.twoFactorAbout,
            style: TextStyle(color: GlitchColors.textSecond, fontSize: 14.5, height: 1.45)),
        const SizedBox(height: 24),
        _field(s.twoFactorPasswordHint, _passwordCtrl, obscure: true),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: const TextStyle(color: GlitchColors.error, fontSize: 14)),
        ],
        const SizedBox(height: 24),
        _primaryButton(s.twoFactorEnable, _requestSecret),
      ],
    );
  }


  Widget _keyStep(S s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.twoFactorSetupStep1,
            style: TextStyle(color: GlitchColors.textSecond, fontSize: 14.5, height: 1.45)),
        const SizedBox(height: 18),
        Text(s.twoFactorSetupStep2,
            style: TextStyle(color: GlitchColors.textSecond, fontSize: 14.5, height: 1.45)),
        const SizedBox(height: 12),
        _keyBox(s),
        const SizedBox(height: 14),
        Center(
          child: TextButton(
            onPressed: () => setState(() => _showQr = !_showQr),
            child: Text(_showQr ? s.twoFactorHideQr : s.twoFactorShowQr,
                style: TextStyle(color: GlitchColors.accentBlue, fontSize: 14.5)),
          ),
        ),
        if (_showQr && _uri != null) ...[
          const SizedBox(height: 6),
          Center(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: QrImageView(
                data: _uri!,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF111111)),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF111111)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(s.twoFactorQrHint,
              style: TextStyle(color: GlitchColors.textHint, fontSize: 13, height: 1.4)),
        ],
        const SizedBox(height: 22),
        Text(s.twoFactorSetupStep3,
            style: TextStyle(color: GlitchColors.textSecond, fontSize: 14.5, height: 1.45)),
        const SizedBox(height: 12),
        _codeField(s),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: const TextStyle(color: GlitchColors.error, fontSize: 14)),
        ],
        const SizedBox(height: 24),
        _primaryButton(s.twoFactorConfirm, _confirm),
      ],
    );
  }

  Widget _keyBox(S s) {
    final grouped = <String>[];
    for (var i = 0; i < _secret!.length; i += 4) {
      grouped.add(_secret!.substring(i, i + 4 > _secret!.length ? _secret!.length : i + 4));
    }
    return GlitchPressable(
      onTap: _copyKey,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: GlitchColors.bgInput,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: GlitchColors.border),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: SelectableText(
                grouped.join(' '),
                style: TextStyle(
                  color: GlitchColors.textPrimary,
                  fontSize: 16,
                  fontFamily: 'monospace',
                  letterSpacing: 0.5,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.copy_rounded, size: 19, color: GlitchColors.accentBlue),
          ],
        ),
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

  Widget _codeField(S s) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: GlitchColors.bgInput,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: GlitchColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _codeCtrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        textAlign: TextAlign.center,
        style: TextStyle(color: GlitchColors.textPrimary, fontSize: 16),
        decoration: InputDecoration(
          hintText: s.twoFactorCodeHint,
          border: InputBorder.none,
          fillColor: Colors.transparent,
          filled: false,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (v) {
          if (v.length == 6 && !_loading) _confirm();
        },
      ),
    );
  }

  Widget _primaryButton(String label, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: GlitchColors.gradientAccent, borderRadius: BorderRadius.circular(15)),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
          onPressed: _loading ? null : onTap,
          child: _loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(label, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
      ),
    );
  }
}
