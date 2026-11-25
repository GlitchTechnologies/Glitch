import 'dart:async';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../providers/theme_provider.dart';
import '../services/app_sounds.dart';
import '../services/voice_connection.dart';
import '../services/voice_cue.dart';
import '../theme/app_theme.dart';
import '../widgets/glitch_icon_button.dart';
import '../widgets/settings_parts.dart' show SettingsNavTile;
import '../widgets/glitch_switch.dart';
import '../widgets/settings_page_parts.dart';
import '../widgets/settings_two_pane.dart';
import '../widgets/settings_window.dart' show SettingsBlock, SettingsDivider;

class UserSoundsSection extends StatefulWidget {
  final Widget? header;

  const UserSoundsSection({super.key, this.header});

  @override
  State<UserSoundsSection> createState() => _UserSoundsSectionState();
}

class _UserSoundsSectionState extends State<UserSoundsSection> with ThemeAwareState<UserSoundsSection> {
  final Set<_SoundGroup> _open = {};

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final header = widget.header;
    return ListenableBuilder(
      listenable: appSounds,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, header != null ? SettingsTwoPane.windowTopPad : 18, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (header != null) ...[header, const SizedBox(height: 24)],
              SettingsBlock(
                title: s.userSettingsSounds,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SettingsBlockTitle(s.userSettingsSounds),
                    for (final (i, group) in _SoundGroup.values.indexed) ...[
                      if (i > 0) const SettingsDivider(),
                      _GroupBlock(
                        group: group,
                        open: _open.contains(group),
                        onToggle: () => setState(() {
                          if (!_open.remove(group)) _open.add(group);
                        }),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _SoundGroup {
  messages(Icons.chat_bubble_outline_rounded, [VoiceCue.message]),
  calls(Icons.call_rounded, [VoiceCue.ringtone, VoiceCue.ringback]),
  micAndSound(Icons.mic_rounded, [
    VoiceCue.deafen,
    VoiceCue.undeafen,
    VoiceCue.micOff,
    VoiceCue.micOn,
    VoiceCue.pttOn,
    VoiceCue.pttOff,
  ]),
  voiceAndVideo(Icons.headset_rounded, [
    VoiceCue.connected,
    VoiceCue.disconnected,
    VoiceCue.moved,
    VoiceCue.streamOn,
    VoiceCue.streamOff,
  ]);

  final IconData icon;
  final List<VoiceCue> cues;

  const _SoundGroup(this.icon, this.cues);

  String title(BuildContext context) {
    final s = context.s;
    return switch (this) {
      messages => s.soundsGroupMessages,
      calls => s.soundsGroupCalls,
      micAndSound => s.soundsGroupMicAndSound,
      voiceAndVideo => s.soundsGroupVoiceAndVideo,
    };
  }

  String summary(BuildContext context) {
    final s = context.s;
    final list = [for (final cue in cues.take(3)) s.soundsQuoted(soundLabel(context, cue))].join(', ');
    return cues.length > 3 ? s.soundsAndOthers(list) : list;
  }
}

class _GroupBlock extends StatelessWidget {
  final _SoundGroup group;
  final bool open;
  final VoidCallback onToggle;

  const _GroupBlock({required this.group, required this.open, required this.onToggle});

  static const double _indent = SettingsNavTile.tileSize + SettingsNavTile.tileGap;

  @override
  Widget build(BuildContext context) {
    final head = SettingsNavTile(
      icon: group.icon,
      title: group.title(context),
      subtitle: group.summary(context),
      onTap: onToggle,
      trailing: AnimatedRotation(
        turns: open ? 0.25 : 0,
        duration: const Duration(milliseconds: 150),
        child: Icon(Icons.chevron_right_rounded, size: 24, color: GlitchColors.textSecond),
      ),
    );
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          head,
          if (open)
            for (final cue in group.cues)
              Padding(
                padding: const EdgeInsets.only(left: _indent),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SettingsDivider(),
                    GlitchSwitchRow(
                      label: soundLabel(context, cue),
                      labelAction: _PreviewButton(cue: cue),
                      value: appSounds.isOn(cue),
                      onChanged: (on) => unawaited(appSounds.setOn(cue, on)),
                      border: false,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _PreviewButton extends StatelessWidget {
  final VoiceCue cue;

  const _PreviewButton({required this.cue});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: context.s.soundPreview,
        child: GlitchIconButton(
          onTap: () => voiceConnection.previewCue(cue),
          size: 28,
          extent: 28,
          icon: const Icon(Icons.volume_up_rounded, size: 18),
        ),
      );
}

String soundLabel(BuildContext context, VoiceCue cue) {
  final s = context.s;
  return switch (cue) {
    VoiceCue.message => s.soundMessage,
    VoiceCue.deafen => s.soundDeafen,
    VoiceCue.undeafen => s.soundUndeafen,
    VoiceCue.micOff => s.soundMicOff,
    VoiceCue.micOn => s.soundMicOn,
    VoiceCue.connected => s.soundConnected,
    VoiceCue.disconnected => s.soundDisconnected,
    VoiceCue.moved => s.soundMoved,
    VoiceCue.pttOn => s.soundPttOn,
    VoiceCue.pttOff => s.soundPttOff,
    VoiceCue.streamOn => s.soundStreamOn,
    VoiceCue.streamOff => s.soundStreamOff,
    VoiceCue.ringtone => s.soundRingtone,
    VoiceCue.ringback => s.soundRingback,
  };
}
