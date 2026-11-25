import 'package:flutter/material.dart';
import '../core/l10n.dart';
import '../core/platform_info.dart';
import '../theme/app_theme.dart';
import '../widgets/form_width_limit.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/user.dart';
import '../widgets/glitch_logo.dart';
import '../widgets/adaptive_shell.dart';
import '../widgets/glitch_pressable.dart';
import '../widgets/nickname_field.dart';
import 'register_screen.dart';
import 'restore_screen.dart';
import 'qr_login_screen.dart';
import 'two_factor_login_screen.dart';
import '../providers/theme_provider.dart';
import '../widgets/glitch_icon_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with ThemeAwareState<LoginScreen> {
  final _nicknameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _showPw = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final nick = _nicknameCtrl.text.trim();
    final pass = _passwordCtrl.text;
    if (nick.isEmpty || pass.isEmpty) {
      setState(() => _error = context.s.loginFillFields);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      var data = await api.login(nickname: nick, password: pass);

      // ВТОРОЙ ФАКТОР. При включённой двухфакторке сервер отдаёт не токен, а
      // короткоживущий билет: пароль принят, но вход ещё не состоялся. Ответ
      // различаем по наличию токена, а не по флагу — так старый формат ответа
      // продолжает работать без всяких условий, а новый распознаётся однозначно.
      if (data['access_token'] == null && data['login_ticket'] != null) {
        if (!mounted) return;
        setState(() => _loading = false);
        final result = await Navigator.push<Map<String, dynamic>>(
          context,
          MaterialPageRoute(
            builder: (_) => TwoFactorLoginScreen(loginTicket: data['login_ticket'] as String),
          ),
        );
        if (!mounted) return;
        if (result == null) return;
        setState(() => _loading = true);
        data = result;
      }

      final user = User.fromJson(data['user']);
      await authService.saveSession(data['access_token'], user);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdaptiveShell()));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Произошла ошибка. Попробуйте снова.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Container(
        color: GlitchColors.bg,
        child: SafeArea(
          child: CenteredFormBody(
            padding: EdgeInsets.only(left: 30, right: 30, top: 24, bottom: bottomInset + 24),
            child: Column(
              children: [
                Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!isWebPlatform) ...[
                    const GlitchLogo(size: 88),
                    const SizedBox(height: 18),
                  ],
                  Text('Glitch', style: TextStyle(fontFamily: 'Inter Tight', fontSize: 34, fontWeight: FontWeight.w800, color: GlitchColors.textPrimary, letterSpacing: -1)),
                  const SizedBox(height: 5),
                  Text(s.loginTitle, style: TextStyle(fontSize: 14.5, color: GlitchColors.textSecond)),
                  const SizedBox(height: 42),

                  NicknameField(
                    controller: _nicknameCtrl,
                    hint: 'nickname',
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),

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
                            decoration: InputDecoration(hintText: s.loginPassword, border: InputBorder.none, fillColor: Colors.transparent, filled: false, contentPadding: EdgeInsets.zero),
                            onSubmitted: (_) => _login(),
                          ),
                        ),
                        GlitchIconButton(
                          icon: Icon(_showPw ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 22),
                          onTap: () => setState(() => _showPw = !_showPw),
                        ),
                      ],
                    ),
                  ),

                  Align(
                    alignment: Alignment.centerRight,
                    child: ClickableCursor(
                      child: GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RestoreScreen())),
                        child: Text(s.loginForgotPassword, style: TextStyle(color: GlitchColors.textSecond, fontSize: 13.5)),
                      ),
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 4),
                    Text(_error!, style: const TextStyle(color: GlitchColors.error, fontSize: 14), textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 8),

                  SizedBox(
                    width: double.infinity, height: 54,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: GlitchColors.gradientAccent,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                        onPressed: _loading ? null : _login,
                        child: _loading
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text(s.loginSubmit, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${s.loginNoAccount} ', style: TextStyle(color: GlitchColors.textSecond, fontSize: 14.5)),
                      ClickableCursor(
                        child: GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                          child: Text(s.loginRegister, style: TextStyle(color: GlitchColors.accentBlue, fontWeight: FontWeight.w600, fontSize: 14.5)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  ClickableCursor(
                    child: GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QrLoginScreen())),
                      child: Text(s.qrLoginEntryLink, style: TextStyle(color: GlitchColors.accentBlue, fontWeight: FontWeight.w600, fontSize: 14.5)),
                    ),
                  ),
                ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
