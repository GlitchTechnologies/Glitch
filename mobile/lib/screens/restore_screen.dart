import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/glitch_action_button.dart';
import '../widgets/form_width_limit.dart';
import '../widgets/nickname_field.dart';
import '../services/api_service.dart';
import '../providers/theme_provider.dart';
import 'email_verify_screen.dart';
import '../widgets/glitch_icon_button.dart';

class RestoreScreen extends StatefulWidget {
  const RestoreScreen({super.key});
  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> with ThemeAwareState<RestoreScreen> {
  final _nicknameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final nick = _nicknameCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    final pass = _passwordCtrl.text;
    if (nick.isEmpty || email.isEmpty || pass.isEmpty) {
      setState(() => _error = context.s.restoreFillFields);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final req = await api.requestRestoreCode(nickname: nick, email: email);
      if (!mounted) return;

      final emailToken = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => EmailVerifyScreen(
          email: email,
          verificationId: req['verification_id'] as String,
          resendAfter: (req['resend_after'] as num?)?.toInt() ?? 60,
          codeLength: (req['code_length'] as num?)?.toInt() ?? 6,
          onResend: () => api.requestRestoreCode(nickname: nick, email: email),
        )),
      );
      if (!mounted) return;
      if (emailToken == null) {
        setState(() => _loading = false);
        return;
      }

      await api.restorePassword(nickname: nick, email: email, newPassword: pass, emailToken: emailToken);
      if (!mounted) return;
      setState(() { _done = true; _loading = false; });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = context.s.errorGeneric; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 14, 14),
              child: Row(
                children: [
                  GlitchIconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded, color: GlitchColors.accentBlue),
                    onTap: () => Navigator.pop(context),
                  ),
                  Text(s.restoreTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
                ],
              ),
            ),
            Divider(height: 1, color: GlitchColors.borderSoft),
            Expanded(
              child: CenteredFormBody(
                padding: const EdgeInsets.all(24),
                child: _done ? _buildDone() : _buildForm(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDone() {
    final s = context.s;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle_outline_rounded, color: GlitchColors.online, size: 72),
        const SizedBox(height: 20),
        Text(s.restoreSuccess, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
        const SizedBox(height: 8),
        Text(s.restoreSuccessHint, style: TextStyle(color: GlitchColors.textSecond)),
        const SizedBox(height: 32),
        GlitchActionButton(label: s.restoreBackToLogin, soft: true, onTap: () => Navigator.pop(context)),
      ],
    );
  }

  Widget _buildForm() {
    final s = context.s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.restoreDescription, style: TextStyle(color: GlitchColors.textSecond, fontSize: 14.5, height: 1.4)),
        const SizedBox(height: 24),
        NicknameField(
          controller: _nicknameCtrl,
          hint: s.restoreNicknameHint,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _field(s.restoreEmailHint, _emailCtrl, keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 12),
        _field(s.restoreNewPasswordHint, _passwordCtrl, obscure: true),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: GlitchColors.error, fontSize: 14)),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity, height: 54,
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: GlitchColors.gradientAccent, borderRadius: BorderRadius.circular(15)),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              onPressed: _loading ? null : _restore,
              child: _loading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(s.restoreSubmit, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl, {TextInputType? keyboardType, bool obscure = false, List<TextInputFormatter>? inputFormatters}) {
    return Container(
      height: 54,
      decoration: BoxDecoration(color: GlitchColors.bgInput, borderRadius: BorderRadius.circular(15), border: Border.all(color: GlitchColors.border)),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        obscureText: obscure,
        style: TextStyle(color: GlitchColors.textPrimary, fontSize: 16),
        decoration: InputDecoration(hintText: label, border: InputBorder.none, fillColor: Colors.transparent, filled: false, contentPadding: EdgeInsets.zero),
      ),
    );
  }
}
