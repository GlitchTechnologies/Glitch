import 'package:flutter/material.dart';
import '../widgets/settings_window.dart' show pushSettingsPage;
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../providers/theme_provider.dart';
import '../widgets/glitch_action_button.dart';
import '../widgets/glitch_toast.dart';
import 'two_factor_setup_view.dart';
import 'two_factor_codes_screen.dart';
import 'two_factor_confirm_view.dart';

/// Двухфакторная авторизация — раздел «Настройки → Безопасность».
class TwoFactorView extends StatefulWidget {
  const TwoFactorView({super.key});

  @override
  State<TwoFactorView> createState() => _TwoFactorViewState();
}

class _TwoFactorViewState extends State<TwoFactorView> with ThemeAwareState<TwoFactorView> {
  bool _loading = true;
  bool _enabled = false;
  int _codesLeft = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await api.getTotpStatus();
      if (!mounted) return;
      setState(() {
        _enabled = data['enabled'] == true;
        _codesLeft = (data['backup_codes_left'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showCodes(List<String> codes) async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => TwoFactorCodesScreen(codes: codes)),
    );
    if (!mounted) return;
    await _load();
  }

  Future<void> _enable() async {
    final codes = await pushSettingsPage<List<String>>(
      context,
      title: context.s.twoFactorSetupTitle,
      builder: (_) => const TwoFactorSetupView(),
    );
    if (!mounted || codes == null) return;
    GlitchToast.show(context, context.s.twoFactorEnabledToast, type: ToastType.success);
    await _showCodes(codes);
  }

  Future<void> _disable() async {
    final done = await pushSettingsPage<bool>(
      context,
      title: context.s.twoFactorDisableTitle,
      builder: (_) => const TwoFactorConfirmView(action: TwoFactorAction.disable),
    );
    if (!mounted || done != true) return;
    GlitchToast.show(context, context.s.twoFactorDisabledToast, type: ToastType.success);
    await _load();
  }

  Future<void> _regenerate() async {
    final codes = await pushSettingsPage<List<String>>(
      context,
      title: context.s.twoFactorNewBackupCodes,
      builder: (_) => const TwoFactorConfirmView(action: TwoFactorAction.regenerateCodes),
    );
    if (!mounted || codes == null) return;
    await _showCodes(codes);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: GlitchColors.error, fontSize: 14)),
          const SizedBox(height: 16),
        ],
        Container(
          decoration: BoxDecoration(
            color: GlitchColors.bgCard,
            border: Border.all(color: GlitchColors.borderCard),
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: _enabled ? const Color(0xFF2fa84f) : GlitchColors.textHint,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(_enabled ? Icons.verified_user_rounded : Icons.shield_outlined,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(_enabled ? s.twoFactorOn : s.twoFactorOff,
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(s.twoFactorAbout,
              style: TextStyle(color: GlitchColors.textSecond, fontSize: 14, height: 1.45)),
        ),
        const SizedBox(height: 20),

        if (!_enabled)
          GlitchActionButton(label: s.twoFactorEnable, onTap: _enable)
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(s.twoFactorBackupCodesLeft(_codesLeft),
                style: TextStyle(color: GlitchColors.textSecond, fontSize: 14.5)),
          ),
          const SizedBox(height: 14),
          GlitchActionButton(label: s.twoFactorNewBackupCodes, onTap: _regenerate, soft: true),
          const SizedBox(height: 12),
          GlitchActionButton(label: s.twoFactorDisable, onTap: _disable, destructive: true),
        ],
      ],
    );
  }
}
