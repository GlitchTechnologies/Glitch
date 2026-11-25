import 'package:flutter/material.dart';
import '../core/copy_actions.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/glitch_action_button.dart';
import '../providers/theme_provider.dart';

class TwoFactorCodesScreen extends StatelessWidget {
  final List<String> codes;

  const TwoFactorCodesScreen({super.key, required this.codes});

  Future<void> _copyAll(BuildContext context) async {
    await copyToClipboard(context, codes.join('\n'), context.s.twoFactorCodesCopied);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    // ListenableBuilder на themeProvider — как в privacy_policy_view: так в проекте
    // реагируют на смену темы экраны БЕЗ состояния (миксин ThemeAwareState
    // подключается только к StatefulWidget). Без него экран остался бы в старых
    // цветах, если переключить тему, пока он открыт.
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async => false,
      child: ListenableBuilder(
        listenable: themeProvider,
        builder: (context, _) => Scaffold(
          backgroundColor: GlitchColors.bg,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
                  child: Row(
                    children: [
                      Icon(Icons.vpn_key_rounded, color: GlitchColors.accentBlue, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        s.twoFactorCodesTitle,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: GlitchColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: GlitchColors.borderSoft),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.twoFactorCodesWarning,
                          style: TextStyle(
                            color: GlitchColors.textSecond,
                            fontSize: 14.5,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _codesBox(),
                        const SizedBox(height: 16),
                        _copyButton(context, s),
                        const SizedBox(height: 24),
                        _doneButton(context, s),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _codesBox() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: GlitchColors.bgCard,
        border: Border.all(color: GlitchColors.borderCard),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: SelectableText(
        codes.join('\n'),
        style: TextStyle(
          color: GlitchColors.textPrimary,
          fontSize: 16,
          fontFamily: 'monospace',
          height: 1.9,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _copyButton(BuildContext context, S s) => GlitchActionButton(
        label: s.twoFactorCodesCopy,
        icon: Icons.copy_rounded,
        soft: true,
        onTap: () => _copyAll(context),
      );

  Widget _doneButton(BuildContext context, S s) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: GlitchColors.gradientAccent,
          borderRadius: BorderRadius.circular(15),
        ),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
          onPressed: () => Navigator.pop(context),
          child: Text(
            s.twoFactorCodesSaved,
            style: const TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
