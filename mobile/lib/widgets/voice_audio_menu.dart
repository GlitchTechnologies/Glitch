import 'dart:async';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../services/voice_connection.dart';
import '../theme/glitch_ink.dart';
import '../theme/glitch_palette.dart';
import 'glitch_cascade_menu.dart';
import 'glitch_hover_row.dart';
import 'glitch_menu.dart';
import 'glitch_slider.dart';
import 'glitch_split_button.dart';
import 'glitch_icon_button.dart';


enum VoiceAudioMenuKind { input, output }

bool voiceAudioMenuAvailable(VoiceAudioMenuKind kind) {
  final v = voiceConnection;
  return switch (kind) {
    VoiceAudioMenuKind.input => v.canSelectInput,
    VoiceAudioMenuKind.output => v.canSelectOutput || v.canSetOutputVolume,
  };
}

Future<void> showVoiceAudioMenu(BuildContext anchorContext, VoiceAudioMenuKind kind, {GlitchPalette? ink}) {
  unawaited(voiceConnection.refreshAudioDevices());
  return openGlitchPopup(
    anchorContext,
    width: GlitchCascadeMenu.popupWidth(),
    growRight: true,
    ink: ink,
    builder: (close, maxHeight) => _VoiceAudioMenu(kind: kind, close: close, maxHeight: maxHeight),
  );
}

class _VoiceAudioMenu extends StatelessWidget {
  final VoiceAudioMenuKind kind;
  final Future<void> Function() close;
  final double maxHeight;

  const _VoiceAudioMenu({required this.kind, required this.close, required this.maxHeight});

  bool get _input => kind == VoiceAudioMenuKind.input;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: voiceConnection,
        builder: (context, _) {
          final v = voiceConnection;
          final canPick = _input ? v.canSelectInput : v.canSelectOutput;
          final showVolume = !_input && v.canSetOutputVolume;
          final devices = _input ? v.inputDevices : v.outputDevices;
          final selected = _input ? v.inputDeviceId : v.outputDeviceId;
          final current = devices.where((d) => d.id == selected).firstOrNull;
          return GlitchCascadeMenu(
            close: close,
            maxHeight: maxHeight,
            opensUp: true,
            entries: [
              if (canPick)
                GlitchCascadeEntry(
                  title: _input ? context.s.callAudioInput : context.s.callAudioOutput,
                  value: voiceDeviceLabel(context, current),
                  options: [
                    for (final d in devices)
                      GlitchCascadeOption(
                        label: voiceDeviceLabel(context, d),
                        icon: _input ? Icons.mic_rounded : Icons.desktop_windows_rounded,
                        selected: d.id == selected,
                        onSelect: () => unawaited(_input ? v.chooseInput(d.id) : v.chooseOutput(d.id)),
                      ),
                  ],
                ),
            ],
            footer: [if (showVolume) _volume(context, v)],
          );
        },
      );

  Widget _volume(BuildContext context, VoiceConnection v) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.s.callAudioVolume,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GlitchInk.of(context).textPrimary),
          ),
          const SizedBox(height: 4),
          GlitchSlider(
            value: v.outputVolume,
            onChanged: (x) => v.setOutputVolume(x),
            onChangeEnd: (x) => v.setOutputVolume(x, persist: true),
            valueLabel: GlitchSlider.percentLabel,
          ),
        ],
      ),
    );
  }

}

/// Подпись устройства звука — одна на меню у стрелок и раздел «Голос»
/// личных настроек. Без названия (браузер не дал его до разрешения на
/// микрофон) или устройства нет — «По умолчанию».
String voiceDeviceLabel(BuildContext context, VoiceAudioDevice? device) {
  final label = device?.label ?? '';
  return label.isEmpty ? context.s.callAudioDeviceDefault : label;
}

class VoiceAudioSplitButton extends StatelessWidget {
  final VoiceAudioMenuKind kind;
  final IconData icon;

  final Color? color;
  final VoidCallback onTap;

  final String? tooltip;

  const VoiceAudioSplitButton({
    super.key,
    required this.kind,
    required this.icon,
    required this.onTap,
    this.color,
    this.tooltip,
  });

  static const double height = GlitchIconButton.panelSize;
  static const double _mainWidth = GlitchIconButton.panelSize;
  static const double _arrowWidth = 18;
  static const double _iconSize = GlitchIconButton.panelIconSize;

  @override
  Widget build(BuildContext context) {
    return GlitchSplitButton(
      icon: icon,
      iconColor: color,
      onTap: onTap,
      tooltip: tooltip,
      menuTooltip: kind == VoiceAudioMenuKind.input ? context.s.tipInputSettings : context.s.tipOutputSettings,
      onMenu: voiceAudioMenuAvailable(kind) ? (anchor) => showVoiceAudioMenu(anchor, kind) : null,
      height: VoiceAudioSplitButton.height,
      mainWidth: _mainWidth,
      arrowWidth: _arrowWidth,
      iconSize: _iconSize,
      radius: GlitchHoverRow.radius,
    );
  }
}
