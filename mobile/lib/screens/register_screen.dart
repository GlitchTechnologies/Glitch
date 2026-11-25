import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/form_width_limit.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/user.dart';
import '../widgets/adaptive_shell.dart';
import '../widgets/nickname_field.dart';
import 'email_verify_screen.dart';
import 'privacy_policy_view.dart';
import '../widgets/settings_window.dart' show SettingsSubpageFrame;
import '../providers/theme_provider.dart';
import '../widgets/glitch_icon_button.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with ThemeAwareState<RegisterScreen> {
  final _nicknameCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  late final TapGestureRecognizer _privacyRecognizer;
  bool _showPw = false;
  bool _loading = false;
  String? _error;

  String? _emailToken;
  String? _verifiedEmail;
  DateTime? _verifiedAt;

  bool _hasFreshToken(String email) =>
      _emailToken != null &&
      _verifiedEmail == email &&
      _verifiedAt != null &&
      DateTime.now().difference(_verifiedAt!) < const Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SettingsSubpageFrame(
                title: context.s.privacyTitle,
                child: const PrivacyPolicyView(),
              ),
            ),
          );
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    _emailCtrl.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final nick = _nicknameCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final pass = _passwordCtrl.text;
    final email = _emailCtrl.text.trim().toLowerCase();
    if (nick.isEmpty || name.isEmpty || pass.isEmpty) {
      setState(() => _error = context.s.registerFillRequired);
      return;
    }
    if (email.isEmpty) {
      setState(() => _error = context.s.registerEmailRequired);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final String emailToken;

      if (_hasFreshToken(email)) {
        emailToken = _emailToken!;
      } else {
        final req = await api.requestEmailCode(nickname: nick, email: email);
        if (!mounted) return;

        final token = await Navigator.push<String>(
          context,
          MaterialPageRoute(builder: (_) => EmailVerifyScreen(
            email: email,
            verificationId: req['verification_id'] as String,
            resendAfter: (req['resend_after'] as num?)?.toInt() ?? 60,
            codeLength: (req['code_length'] as num?)?.toInt() ?? 6,
            onResend: () => api.requestEmailCode(nickname: nick, email: email),
          )),
        );
        if (!mounted) return;
        if (token == null) {
          setState(() => _loading = false);
          return;
        }
        emailToken = token;
        _emailToken = token;
        _verifiedEmail = email;
        _verifiedAt = DateTime.now();
      }

      final data = await api.register(
        nickname: nick, displayName: name, password: pass,
        email: email, emailToken: emailToken,
      );
      final user = User.fromJson(data['user']);
      await authService.saveSession(data['access_token'], user);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AdaptiveShell()), (_) => false);
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
                  Text(s.registerTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
                ],
              ),
            ),
            Divider(height: 1, color: GlitchColors.borderSoft),
            Expanded(child: _buildBody(s)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(S s) {
    return CenteredFormBody(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            NicknameField(
              controller: _nicknameCtrl,
              hint: s.registerNicknameHint,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            _field(s.registerDisplayName, _nameCtrl, hint: s.registerDisplayNameHint),
            const SizedBox(height: 12),
            _pwField(s),
            const SizedBox(height: 12),
            _field(s.registerEmail, _emailCtrl, hint: 'you@example.com', keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 6),
            Text(s.registerEmailHint, style: TextStyle(color: GlitchColors.textHint, fontSize: 12.5)),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: GlitchColors.error, fontSize: 14)),
            ],
            const SizedBox(height: 20),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(fontSize: 12.5, color: GlitchColors.textHint, height: 1.5),
                children: [
                  TextSpan(text: s.registerAgreement),
                  TextSpan(
                    text: s.registerPrivacyLink,
                    style: TextStyle(color: GlitchColors.accentBlue, decoration: TextDecoration.underline),
                    recognizer: _privacyRecognizer,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity, height: 54,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: GlitchColors.gradientAccent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                  onPressed: _loading ? null : _register,
                  child: _loading
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(s.registerSubmit, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      );
  }

  Widget _field(String label, TextEditingController ctrl, {String? hint, TextInputType? keyboardType, List<TextInputFormatter>? inputFormatters}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: GlitchColors.textSecond, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Container(
          height: 54,
          decoration: BoxDecoration(color: GlitchColors.bgInput, borderRadius: BorderRadius.circular(15), border: Border.all(color: GlitchColors.border)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: ctrl,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            style: TextStyle(color: GlitchColors.textPrimary, fontSize: 16),
            decoration: InputDecoration(hintText: hint, border: InputBorder.none, fillColor: Colors.transparent, filled: false, contentPadding: EdgeInsets.zero),
          ),
        ),
      ],
    );
  }

  Widget _pwField(S s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.loginPassword, style: TextStyle(color: GlitchColors.textSecond, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Container(
          height: 54,
          decoration: BoxDecoration(color: GlitchColors.bgInput, borderRadius: BorderRadius.circular(15), border: Border.all(color: GlitchColors.border)),
          padding: const EdgeInsets.only(left: 16, right: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _passwordCtrl,
                  obscureText: !_showPw,
                  style: TextStyle(color: GlitchColors.textPrimary, fontSize: 16),
                  decoration: InputDecoration(hintText: s.registerPasswordHint, border: InputBorder.none, fillColor: Colors.transparent, filled: false, contentPadding: EdgeInsets.zero),
                ),
              ),
              GlitchIconButton(
                icon: Icon(_showPw ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 22),
                onTap: () => setState(() => _showPw = !_showPw),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
