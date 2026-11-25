import 'dart:async';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../services/keybinds.dart';
import '../theme/app_theme.dart';
import 'glitch_action_button.dart';
import 'glitch_toast.dart';

class KeybindField extends StatefulWidget {
  final KeyCombo? combo;

  final Future<void> Function(KeyCombo combo)? onRecorded;

  const KeybindField({super.key, required this.combo, required this.onRecorded});

  @override
  State<KeybindField> createState() => _KeybindFieldState();
}

class _KeybindFieldState extends State<KeybindField> {
  bool _recording = false;

  @override
  void dispose() {
    if (_recording) keybinds.cancelRecording();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_recording) {
      keybinds.cancelRecording();
      return;
    }
    setState(() => _recording = true);
    final combo = await keybinds.record();
    if (!mounted) return;
    setState(() => _recording = false);
    final onRecorded = widget.onRecorded;
    if (combo != null && onRecorded != null) await onRecorded(combo);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final enabled = widget.onRecorded != null;
    return ValueListenableBuilder<KeyCombo?>(
      valueListenable: keybinds.recording,
      builder: (context, recorded, _) {
        final shown = _recording ? recorded : null;
        final recordingNow = shown != null;
        final String text;
        final bool hint;
        if (shown != null) {
          text = shown.isEmpty ? s.keybindRecording : shown.label;
          hint = shown.isEmpty;
        } else {
          text = widget.combo?.label ?? s.keybindNone;
          hint = widget.combo == null;
        }
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          decoration: BoxDecoration(
            color: GlitchColors.bgInput,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: recordingNow ? GlitchColors.accentBlue : GlitchColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: hint || !enabled ? GlitchColors.textHint : GlitchColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GlitchActionButton(
                label: _recording ? s.keybindStop : s.keybindChange,
                soft: true,
                compact: true,
                onTap: enabled ? () => unawaited(_toggle()) : null,
              ),
            ],
          ),
        );
      },
    );
  }
}

void showKeybindProblem(BuildContext context, KeybindProblem problem) {
  final s = context.s;
  GlitchToast.show(
    context,
    switch (problem) {
      KeybindProblem.reserved => s.keybindReserved,
      KeybindProblem.taken => s.keybindTaken,
      KeybindProblem.unsupported => s.keybindUnsupported,
    },
    type: ToastType.info,
  );
}
