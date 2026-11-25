import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/form_width_limit.dart';
import '../services/api_service.dart';
import '../providers/theme_provider.dart';
import '../widgets/glitch_icon_button.dart';

class EmailVerifyScreen extends StatefulWidget {
  final String email;            // уже нормализованный, как ушёл на сервер
  final String verificationId;
  final int resendAfter;         // секунд до возможности запросить письмо заново

  /// Длина кода приходит с сервера (`code_length`), а не зашита здесь — иначе
  /// при изменении длины на бэкенде клиент молча перестал бы отправлять код
  /// автоматически и ограничивал ввод неверным числом цифр.
  final int codeLength;

  final Future<Map<String, dynamic>> Function() onResend;

  const EmailVerifyScreen({
    super.key,
    required this.email,
    required this.verificationId,
    required this.resendAfter,
    required this.onResend,
    this.codeLength = 6,
  });

  @override
  State<EmailVerifyScreen> createState() => _EmailVerifyScreenState();
}

class _EmailVerifyScreenState extends State<EmailVerifyScreen> with ThemeAwareState<EmailVerifyScreen> {
  final _codeCtrl = TextEditingController();
  final _codeFocus = FocusNode();

  late String _verificationId;
  late int _resendIn;
  Timer? _resendTimer;

  bool _loading = false;   // идёт проверка кода
  bool _resending = false; // идёт повторный запрос письма
  String? _error;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendIn = widget.resendAfter;
    _startResendTimer();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    if (_resendIn <= 0) return;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _resendIn--;
        if (_resendIn <= 0) t.cancel();
      });
    });
  }


  Future<void> _confirm() async {
    final code = _codeCtrl.text.trim();
    if (code.length != widget.codeLength) {
      setState(() => _error = context.s.emailVerifyEnterCode);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final token = await api.confirmEmailCode(verificationId: _verificationId, code: code);
      if (!mounted) return;
      Navigator.pop(context, token);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; _codeCtrl.clear(); });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = context.s.errorGeneric; _loading = false; });
    }
  }


  Future<void> _resend() async {
    if (_resendIn > 0 || _resending) return;
    setState(() { _resending = true; _error = null; });
    try {
      final data = await widget.onResend();
      if (!mounted) return;
      setState(() {
        _verificationId = data['verification_id'] as String;
        _resendIn = (data['resend_after'] as num?)?.toInt() ?? 60;
        _codeCtrl.clear();
      });
      _startResendTimer();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = context.s.errorGeneric);
    } finally {
      if (mounted) setState(() => _resending = false);
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
                  Text(s.emailVerifyTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
                ],
              ),
            ),
            Divider(height: 1, color: GlitchColors.borderSoft),
            Expanded(
              child: CenteredFormBody(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.emailVerifyDescription(widget.email),
                      style: TextStyle(color: GlitchColors.textSecond, fontSize: 14.5, height: 1.45),
                    ),
                    const SizedBox(height: 10),
                    // Подсказка про «Спам» — не украшение: письмо от нового
                    // отправителя почтовики нередко кладут туда, и без этой
                    // строки человек решает, что код просто не пришёл.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: GlitchColors.textHint),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            s.emailVerifySpamHint,
                            style: TextStyle(color: GlitchColors.textHint, fontSize: 13, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _codeField(s),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: const TextStyle(color: GlitchColors.error, fontSize: 14)),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity, height: 54,
                      child: DecoratedBox(
                        decoration: BoxDecoration(gradient: GlitchColors.gradientAccent, borderRadius: BorderRadius.circular(15)),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                          onPressed: _loading ? null : _confirm,
                          child: _loading
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text(s.emailVerifySubmit, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: Colors.white)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton(
                        onPressed: (_resendIn > 0 || _resending) ? null : _resend,
                        child: _resending
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(
                                _resendIn > 0 ? s.emailVerifyResendIn(_resendIn) : s.emailVerifyResend,
                                style: TextStyle(
                                  color: _resendIn > 0 ? GlitchColors.textHint : GlitchColors.accentBlue,
                                  fontSize: 14.5,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _codeField(S s) {
    return Container(
      height: 54,
      decoration: BoxDecoration(color: GlitchColors.bgInput, borderRadius: BorderRadius.circular(15), border: Border.all(color: GlitchColors.border)),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _codeCtrl,
        focusNode: _codeFocus,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(widget.codeLength)],
        textAlign: TextAlign.center,
        style: TextStyle(color: GlitchColors.textPrimary, fontSize: 16),
        decoration: InputDecoration(hintText: s.emailVerifyCodeHint, border: InputBorder.none, fillColor: Colors.transparent, filled: false, contentPadding: EdgeInsets.zero),
        onChanged: (v) {
          if (v.length == widget.codeLength && !_loading) _confirm();
        },
      ),
    );
  }
}
