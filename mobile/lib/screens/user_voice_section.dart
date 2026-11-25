import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' show VideoTrackRenderer, VideoViewFit, VideoViewMirrorMode;

import '../core/l10n.dart';
import '../core/platform_info.dart';
import '../providers/theme_provider.dart';
import '../services/call_audio_prefs.dart' show CallAudioPrefs;
import '../services/keybinds.dart';
import '../services/voice_connection.dart';
import '../theme/app_theme.dart';
import '../widgets/glitch_action_button.dart';
import '../widgets/glitch_form_field.dart' show GlitchFormLabel;
import '../widgets/glitch_select_field.dart';
import '../widgets/glitch_slider.dart';
import '../widgets/glitch_switch.dart';
import '../widgets/input_sensitivity_bar.dart';
import '../widgets/keybind_field.dart';
import '../widgets/mic_test_row.dart';
import '../widgets/settings_page_parts.dart';
import '../widgets/settings_parts.dart' show SettingsNotice;
import '../widgets/settings_two_pane.dart';
import '../widgets/settings_window.dart' show SettingsBlock, SettingsDivider;
import '../widgets/voice_audio_menu.dart' show voiceDeviceLabel;

class UserVoiceSection extends StatefulWidget {
  final Widget? header;

  const UserVoiceSection({super.key, this.header});

  @override
  State<UserVoiceSection> createState() => _UserVoiceSectionState();
}

class _UserVoiceSectionState extends State<UserVoiceSection>
    with ThemeAwareState<UserVoiceSection> {
  @override
  void initState() {
    super.initState();
    unawaited(voiceConnection.refreshAudioDevices());
    unawaited(voiceConnection.refreshCameras());
  }

  @override
  void dispose() {
    unawaited(voiceConnection.stopMicTest());
    unawaited(voiceConnection.stopCameraTest());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final header = widget.header;
    return ListenableBuilder(
      listenable: voiceConnection,
      builder: (context, _) {
        final v = voiceConnection;
        final devices = _devicesBlock(context, v);
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, header != null ? SettingsTwoPane.windowTopPad : 18, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (header != null) ...[
                KeyedSubtree(key: const ValueKey('header'), child: header),
                const SizedBox(key: ValueKey('header-gap'), height: 24),
              ],
              if (devices != null) ...[
                KeyedSubtree(key: const ValueKey('devices'), child: devices),
                const SizedBox(key: ValueKey('devices-gap'), height: 24),
                const SettingsDivider(key: ValueKey('devices-divider')),
                const SizedBox(key: ValueKey('devices-gap-2'), height: 24),
              ],
              _PushToTalkBlock(key: const ValueKey('ptt'), voice: v),
              const SizedBox(key: ValueKey('ptt-gap'), height: 24),
              const SettingsDivider(key: ValueKey('ptt-divider')),
              const SizedBox(key: ValueKey('ptt-gap-2'), height: 24),
              if (v.canSetSensitivity && !v.pushToTalk) ...[
                _SensitivityBlock(key: const ValueKey('sensitivity'), voice: v),
                const SizedBox(key: ValueKey('sensitivity-gap'), height: 24),
                const SettingsDivider(key: ValueKey('sensitivity-divider')),
                const SizedBox(key: ValueKey('sensitivity-gap-2'), height: 24),
              ],
              if (v.canSelectCamera) ...[
                _CameraBlock(key: const ValueKey('camera'), voice: v),
                const SizedBox(key: ValueKey('camera-gap'), height: 24),
                const SettingsDivider(key: ValueKey('camera-divider')),
                const SizedBox(key: ValueKey('camera-gap-2'), height: 24),
              ],
              KeyedSubtree(key: const ValueKey('processing'), child: _processingBlock(context, v)),
            ],
          ),
        );
      },
    );
  }

  Widget? _devicesBlock(BuildContext context, VoiceConnection v) {
    final s = context.s;
    final input = v.canSelectInput
        ? _Field(
            label: s.voiceSettingsMic,
            child: _DeviceSelect(
              devices: v.inputDevices,
              selectedId: v.inputDeviceId,
              onChanged: (id) => unawaited(v.chooseInput(id)),
            ),
          )
        : null;
    final output = v.canSelectOutput
        ? _Field(
            label: s.voiceSettingsSpeaker,
            child: _DeviceSelect(
              devices: v.outputDevices,
              selectedId: v.outputDeviceId,
              onChanged: (id) => unawaited(v.chooseOutput(id)),
            ),
          )
        : null;
    final micVolume = v.canSetMicVolume
        ? _Field(
            label: s.voiceSettingsMicVolume,
            child: GlitchSlider(
              value: v.micVolume,
              onChanged: (x) => v.setMicVolume(x),
              onChangeEnd: (x) => v.setMicVolume(x, persist: true),
              valueLabel: GlitchSlider.percentLabel,
            ),
          )
        : null;
    final outputVolume = v.canSetOutputVolume
        ? _Field(
            label: s.voiceSettingsSpeakerVolume,
            child: GlitchSlider(
              value: v.outputVolume,
              onChanged: (x) => v.setOutputVolume(x),
              onChangeEnd: (x) => v.setOutputVolume(x, persist: true),
              valueLabel: GlitchSlider.percentLabel,
            ),
          )
        : null;
    final rows = [
      if (input != null || output != null) (input, output),
      if (micVolume != null || outputVolume != null) (micVolume, outputVolume),
    ];
    if (rows.isEmpty && !v.canTestMic) return null;
    return SettingsBlock(
      title: s.voiceSettingsVoiceTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsBlockTitle(s.voiceSettingsVoiceTitle),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final paired = constraints.maxWidth >= _pairedMinWidth;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, (left, right)) in rows.indexed)
                    if (paired)
                      Padding(
                        key: ValueKey('row-$i'),
                        padding: const EdgeInsets.only(bottom: _rowGap),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: left ?? const SizedBox.shrink()),
                            const SizedBox(width: _columnGap),
                            Expanded(child: right ?? const SizedBox.shrink()),
                          ],
                        ),
                      )
                    else
                      for (final (j, cell) in [left, right].indexed)
                        if (cell != null)
                          Padding(
                            key: ValueKey('cell-$i-$j'),
                            padding: const EdgeInsets.only(bottom: _rowGap),
                            child: cell,
                          ),
                ],
              );
            },
          ),
          if (v.canTestMic) ...[
            GlitchFormLabel(key: const ValueKey('test-label'), label: s.voiceMicTestTitle),
            const MicTestRow(key: ValueKey('test')),
          ],
        ],
      ),
    );
  }

  Widget _processingBlock(BuildContext context, VoiceConnection v) {
    final s = context.s;
    return SettingsBlock(
      title: s.voiceProcessingTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsBlockTitle(s.voiceProcessingTitle),
          GlitchSwitchRow(
            label: s.voiceNoiseTitle,
            description: v.noiseAvailable ? s.voiceNoiseDescription : s.voiceNoiseUnavailable,
            value: v.noiseActive,
            onChanged: v.noiseAvailable ? (_) => unawaited(v.toggleNoiseSuppression()) : null,
            border: false,
            padding: _switchPadding,
          ),
          GlitchSwitchRow(
            label: s.voiceEchoTitle,
            description: s.voiceEchoDescription,
            value: v.echoCancellation,
            onChanged: (on) => unawaited(v.setEchoCancellation(on)),
            border: false,
            padding: _switchPadding,
          ),
          GlitchSwitchRow(
            label: s.voiceAgcTitle,
            description: s.voiceAgcDescription,
            value: v.autoGainControl,
            onChanged: (on) => unawaited(v.setAutoGainControl(on)),
            border: false,
            padding: _switchPadding,
          ),
        ],
      ),
    );
  }

  static const double _pairedMinWidth = 480;
  static const double _columnGap = 16;
  static const double _rowGap = 20;

  static const _switchPadding = EdgeInsets.symmetric(vertical: 12);
}

class _Field extends StatelessWidget {
  final String label;
  final Widget child;

  const _Field({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [GlitchFormLabel(label: label), child],
      );
}

class _DeviceSelect extends StatelessWidget {
  final List<VoiceAudioDevice> devices;
  final String? selectedId;
  final ValueChanged<String> onChanged;
  final String? emptyLabel;

  const _DeviceSelect({required this.devices, required this.selectedId, required this.onChanged, this.emptyLabel});

  @override
  Widget build(BuildContext context) {
    final current = devices.where((d) => d.id == selectedId).firstOrNull;
    return GlitchSelectField<VoiceAudioDevice?>(
      value: current,
      options: devices.isEmpty ? const <VoiceAudioDevice?>[null] : devices,
      label: (d) => d == null && emptyLabel != null ? emptyLabel! : voiceDeviceLabel(context, d),
      onChanged: (d) {
        if (d != null) onChanged(d.id);
      },
      expand: true,
    );
  }
}

class _PushToTalkBlock extends StatelessWidget {
  final VoiceConnection voice;

  const _PushToTalkBlock({super.key, required this.voice});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final v = voice;
    final on = v.pushToTalk;
    return SettingsBlock(
      title: s.voicePttTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlitchSwitchRow(
            key: const ValueKey('switch'),
            label: s.voicePttTitle,
            description: hasPointerInput ? s.voicePttDescKey : s.voicePttDescButton,
            value: on,
            onChanged: (value) => unawaited(v.setPushToTalk(value)),
            border: false,
            padding: _UserVoiceSectionState._switchPadding,
          ),
          if (on && hasPointerInput)
            ListenableBuilder(
              key: const ValueKey('key'),
              listenable: keybinds,
              builder: (context, _) => _keyRow(context),
            ),
          if (on && hasBrowserTabs) ...[
            const SizedBox(key: ValueKey('browser-gap'), height: 12),
            SettingsNotice(key: const ValueKey('browser'), icon: Icons.info_outline_rounded, text: s.voicePttBrowser),
          ],
          if (on) ...[
            const SizedBox(key: ValueKey('delay-gap'), height: 20),
            GlitchFormLabel(key: const ValueKey('delay-label'), label: s.voicePttDelay),
            GlitchSlider(
              key: const ValueKey('delay'),
              value: v.pushToTalkDelay.inMilliseconds.toDouble(),
              max: CallAudioPrefs.maxPushToTalkDelayMs.toDouble(),
              onChanged: (x) => v.setPushToTalkDelay(Duration(milliseconds: x.round())),
              onChangeEnd: (x) => v.setPushToTalkDelay(Duration(milliseconds: x.round()), persist: true),
              valueLabel: (x) => s.voicePttDelayMs(x.round()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _keyRow(BuildContext context) {
    final s = context.s;
    final combo = keybinds.combosOf(KeybindAction.pushToTalk).firstOrNull;
    final field = KeybindField(
      combo: combo,
      onRecorded: (recorded) async {
        final problem = await keybinds.assign(KeybindAction.pushToTalk, recorded);
        if (problem != null && context.mounted) showKeybindProblem(context, problem);
      },
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final label = Text(
                s.voicePttKey,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary),
              );
              if (constraints.maxWidth < _UserVoiceSectionState._pairedMinWidth) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [label, const SizedBox(height: 10), field],
                );
              }
              return Row(
                children: [
                  Expanded(child: label),
                  const SizedBox(width: _UserVoiceSectionState._columnGap),
                  Expanded(child: field),
                ],
              );
            },
          ),
          if (combo == null) ...[
            const SizedBox(key: ValueKey('none-gap'), height: 12),
            SettingsNotice(key: const ValueKey('none'), icon: Icons.warning_amber_rounded, text: s.voicePttNoKey),
          ],
        ],
      ),
    );
  }
}

/// «Чувствительность ввода» — как у Discord: «Автоматически определять
/// чувствительность ввода»; выключено — ползунок порога в децибелах. Под ним
/// (или одна, если автоматически) — полоса с громкостью своего голоса сейчас.
/// Сам порог и отсекание — voiceConnection (`setSensitivity`, mic_options.dart).
class _SensitivityBlock extends StatefulWidget {
  final VoiceConnection voice;

  const _SensitivityBlock({super.key, required this.voice});

  @override
  State<_SensitivityBlock> createState() => _SensitivityBlockState();
}

class _SensitivityBlockState extends State<_SensitivityBlock> {
  @override
  void initState() {
    super.initState();
    widget.voice.watchInputLevel();
  }

  @override
  void dispose() {
    widget.voice.unwatchInputLevel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final v = widget.voice;
    final auto = v.autoSensitivity;
    return SettingsBlock(
      title: s.voiceSensitivityTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsBlockTitle(s.voiceSensitivityTitle, key: const ValueKey('title')),
          GlitchSwitchRow(
            key: const ValueKey('auto'),
            label: s.voiceSensitivityAuto,
            description: s.voiceSensitivityAutoDesc,
            value: auto,
            onChanged: (on) => unawaited(v.setAutoSensitivity(on)),
            border: false,
            padding: _UserVoiceSectionState._switchPadding,
          ),
          const SizedBox(key: ValueKey('bar-gap'), height: 8),
          if (auto)
            InputSensitivityBar(key: const ValueKey('bar'), levelDb: v.inputLevelDb)
          else ...[
            GlitchSlider(
              key: const ValueKey('slider'),
              value: v.sensitivityDb,
              min: CallAudioPrefs.minSensitivityDb.toDouble(),
              max: 0,
              onChanged: (x) => v.setSensitivity(x),
              onChangeEnd: (x) => v.setSensitivity(x, persist: true),
              valueLabel: (x) => s.voiceSensitivityDb(x.round()),
              track: InputSensitivityBar(levelDb: v.inputLevelDb, thresholdDb: v.sensitivityDb),
            ),
            const SizedBox(key: ValueKey('hint-gap'), height: 8),
            Text(
              s.voiceSensitivityManualDesc,
              key: const ValueKey('hint'),
              style: TextStyle(fontSize: 12.5, height: 1.3, color: GlitchColors.textSecond),
            ),
          ],
        ],
      ),
    );
  }
}

class _CameraBlock extends StatefulWidget {
  final VoiceConnection voice;

  const _CameraBlock({super.key, required this.voice});

  @override
  State<_CameraBlock> createState() => _CameraBlockState();
}

class _CameraBlockState extends State<_CameraBlock> {
  bool _failed = false;
  bool _starting = false;

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _failed = false;
    });
    final ok = await widget.voice.startCameraTest();
    if (!mounted) return;
    setState(() {
      _starting = false;
      _failed = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final v = widget.voice;
    final track = v.cameraTest;
    return SettingsBlock(
      title: s.voiceCameraTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsBlockTitle(s.voiceCameraTitle, key: const ValueKey('title')),
          const SizedBox(key: ValueKey('title-gap'), height: 8),
          AspectRatio(
            key: const ValueKey('preview'),
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: GlitchColors.bgInput,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (track != null)
                      VideoTrackRenderer(track, fit: VideoViewFit.cover, mirrorMode: VideoViewMirrorMode.mirror),
                    Align(
                      alignment: track == null ? Alignment.center : const Alignment(0, 0.85),
                      child: GlitchActionButton(
                        label: track == null ? s.voiceCameraTest : s.voiceCameraTestStop,
                        compact: true,
                        soft: track != null,
                        loading: _starting,
                        onTap: track == null ? _start : () => unawaited(v.stopCameraTest()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_failed) ...[
            const SizedBox(key: ValueKey('failed-gap'), height: 12),
            SettingsNotice(key: const ValueKey('failed'), icon: Icons.warning_amber_rounded, text: s.voiceCameraFailed),
          ],
          const SizedBox(key: ValueKey('field-gap'), height: 20),
          _Field(
            key: const ValueKey('field'),
            label: s.voiceCameraTitle,
            child: _DeviceSelect(
              devices: v.cameraDevices,
              selectedId: v.cameraDeviceId,
              onChanged: (id) => unawaited(v.chooseCamera(id)),
              emptyLabel: s.voiceCameraNone,
            ),
          ),
        ],
      ),
    );
  }
}
