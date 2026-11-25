import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/form_width_limit.dart';
import '../services/api_service.dart';
import '../providers/theme_provider.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/glitch_icon_button.dart';

class TwoFactorLoginScreen extends StatefulWidget {
  final String loginTicket;

  const TwoFactorLoginScreen({super.key, required this.loginTicket});

  @override
  State<TwoFactorLoginScreen> createState() => _TwoFactorLoginScreenState();
}

class _TwoFactorLoginScreenState extends State<TwoFactorLoginScreen>
    with ThemeAwareState<TwoFactorLoginScreen> {
  final _codeCtrl = TextEditingController();
  final _codeFocus = FocusNode();

  bool _backupMode = false;

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = context.s.twoFactorEnterCode);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final data = await api.loginTotp(loginTicket: widget.loginTicket, code: code);
      if (!mounted) return;
      Navigator.pop(context, data);
    } on ApiException catch (e) {
      if (!mounted) return;
      // 410 (Gone) от сервера означает, что билета больше нет: истёк по времени
      // или сгорел после пяти неверных попыток. Вводить код больше некуда, и
      // экран закрывается — человек возвращается к паролю. Признак именно код
      // ответа, а НЕ текст сообщения: подстрочный поиск по фразе сломался бы
      // молча при первой же правке формулировки на сервере.
      if (e.statusCode == 410) {
        GlitchToast.show(context, e.message);
        Navigator.pop(context, null);
        return;
      }
      setState(() { _error = e.message; _loading = false; _codeCtrl.clear(); });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = errorMessage(e); _loading = false; });
    }
  }

  void _toggleMode() {
    setState(() {
      _backupMode = !_backupMode;
      _codeCtrl.clear();
      _error = null;
    });
    _codeFocus.requestFocus();
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
                    onTap: () => Navigator.pop(context, null),
                  ),
                  Text(s.twoFactorLoginTitle,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
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
                    Text(s.twoFactorLoginDescription,
                        style: TextStyle(color: GlitchColors.textSecond, fontSize: 14.5, height: 1.45)),
                    const SizedBox(height: 24),
                    _codeField(s),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: const TextStyle(color: GlitchColors.error, fontSize: 14)),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
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
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text(s.twoFactorConfirm,
                                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: Colors.white)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton(
                        onPressed: _loading ? null : _toggleMode,
                        child: Text(
                          _backupMode ? s.twoFactorUseAppCode : s.twoFactorUseBackupCode,
                          style: TextStyle(color: GlitchColors.accentBlue, fontSize: 14.5),
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
      decoration: BoxDecoration(
        color: GlitchColors.bgInput,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: GlitchColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _codeCtrl,
        focusNode: _codeFocus,
        autofocus: true,
        keyboardType: _backupMode ? TextInputType.text : TextInputType.number,
        inputFormatters: _backupMode
            ? null
            : [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        textAlign: TextAlign.center,
        style: TextStyle(color: GlitchColors.textPrimary, fontSize: 16),
        decoration: InputDecoration(
          hintText: _backupMode ? s.twoFactorBackupCodeHint : s.twoFactorCodeHint,
          border: InputBorder.none,
          fillColor: Colors.transparent,
          filled: false,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (v) {
          if (!_backupMode && v.length == 6 && !_loading) _submit();
        },
      ),
    );
  }
}
