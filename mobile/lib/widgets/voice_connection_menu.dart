import 'dart:async';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../services/voice_connection.dart';
import '../services/voice_ping.dart';
import '../theme/app_theme.dart';
import 'glitch_action_button.dart';
import 'glitch_menu.dart';
import 'voice_debug_window.dart';
import 'voice_graph.dart';


const double _kWidth = 300;

const int kVoicePingBad = 250;

Future<void> showVoiceConnectionMenu(BuildContext anchorContext) => openGlitchPopup(
      anchorContext,
      width: _kWidth,
      builder: (close, maxHeight) =>
          _VoiceConnectionMenu(anchorContext: anchorContext, close: close, maxHeight: maxHeight),
    );

class _VoiceConnectionMenu extends StatefulWidget {
  final BuildContext anchorContext;
  final Future<void> Function() close;
  final double maxHeight;

  const _VoiceConnectionMenu({required this.anchorContext, required this.close, required this.maxHeight});

  @override
  State<_VoiceConnectionMenu> createState() => _VoiceConnectionMenuState();
}

class _VoiceConnectionMenuState extends State<_VoiceConnectionMenu> {
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
    if (mounted && voiceConnection.state == VoiceLinkState.idle) unawaited(widget.close());
  }

  Future<void> _openDebug() async {
    final anchor = widget.anchorContext;
    await widget.close();
    if (!anchor.mounted) return;
    await openVoiceDebugWindow(anchor);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return GlitchPopupCard(
      maxHeight: widget.maxHeight,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: ValueListenableBuilder<List<int>>(
          valueListenable: voiceConnection.ping.samples,
          builder: (context, samples, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 96,
                child: VoiceGraph(samples: samples, keep: VoicePing.keep, step: 100, badFrom: kVoicePingBad),
              ),
              const SizedBox(height: 14),
              if (samples.isEmpty)
                Text(s.voicePingMeasuring, style: TextStyle(fontSize: 14, color: GlitchColors.textSecond))
              else ...[
                _PingLine(label: s.voicePingAverage, ms: (samples.reduce((a, b) => a + b) / samples.length).round()),
                const SizedBox(height: 2),
                _PingLine(label: s.voicePingLast, ms: samples.last),
              ],
              const SizedBox(height: 10),
              Text(s.voicePingHint, style: TextStyle(fontSize: 13, height: 1.35, color: GlitchColors.textSecond)),
              const SizedBox(height: 14),
              GlitchActionButton(label: s.voiceDebug, soft: true, compact: true, onTap: () => unawaited(_openDebug())),
            ],
          ),
        ),
      ),
    );
  }
}

class _PingLine extends StatelessWidget {
  final String label;
  final int ms;

  const _PingLine({required this.label, required this.ms});

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(
          style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary),
          children: [
            TextSpan(text: '$label '),
            TextSpan(text: context.s.voicePingMs(ms), style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
