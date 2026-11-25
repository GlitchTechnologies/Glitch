import 'dart:async';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../services/voice_connection.dart';
import '../theme/app_theme.dart';
import 'glitch_menu.dart';
import 'glitch_switch.dart';
import 'mic_test_row.dart';


const double _kWidth = 300;

Future<void> showNoiseSuppressionMenu(BuildContext anchorContext) async {
  await openGlitchPopup(
    anchorContext,
    width: _kWidth,
    centered: true,
    builder: (close, maxHeight) => _NoiseSuppressionMenu(close: close, maxHeight: maxHeight),
  );
  await voiceConnection.stopMicTest();
}

class _NoiseSuppressionMenu extends StatefulWidget {
  final Future<void> Function() close;
  final double maxHeight;

  const _NoiseSuppressionMenu({required this.close, required this.maxHeight});

  @override
  State<_NoiseSuppressionMenu> createState() => _NoiseSuppressionMenuState();
}

class _NoiseSuppressionMenuState extends State<_NoiseSuppressionMenu> {
  @override
  void initState() {
    super.initState();
    voiceConnection.addListener(_onVoice);
  }

  @override
  void dispose() {
    voiceConnection.removeListener(_onVoice);
    super.dispose();
  }

  void _onVoice() {
    if (!mounted) return;
    if (voiceConnection.state == VoiceLinkState.idle) {
      unawaited(widget.close());
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = voiceConnection;
    final s = context.s;
    return GlitchPopupCard(
      maxHeight: widget.maxHeight,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.voiceNoiseTitle,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
                  ),
                ),
                const SizedBox(width: 12),
                GlitchSwitch(
                  value: v.noiseActive,
                  onChanged: v.noiseAvailable ? (_) => unawaited(v.toggleNoiseSuppression()) : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              v.noiseAvailable ? s.voiceNoiseDescription : s.voiceNoiseUnavailable,
              style: TextStyle(fontSize: 13, height: 1.35, color: GlitchColors.textSecond),
            ),
            if (v.canTestMic) ...[
              const SizedBox(height: 16),
              Text(
                s.voiceMicTestTitle,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
              ),
              const SizedBox(height: 10),
              const MicTestRow(),
            ],
          ],
        ),
      ),
    );
  }
}
