import 'dart:async';

import 'package:flutter/material.dart';

import '../core/copy_actions.dart';
import '../core/l10n.dart';
import '../core/permissions.dart';
import '../core/personal_chat_open.dart';
import '../models/server.dart';
import '../models/voice_pass.dart';
import '../providers/call_provider.dart';
import '../providers/voice_channels.dart';
import '../screens/user_profile_screen.dart' show showUserProfile;
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/call_audio_prefs.dart';
import '../services/voice_connection.dart';
import '../theme/glitch_ink.dart';
import 'glitch_menu.dart';
import 'glitch_slider.dart';
import 'glitch_toast.dart';


void openVoiceMemberMenu(
  BuildContext context, {
  required Room room,
  required VoiceStateInfo member,
  required Offset position,
}) {
  final isMe = member.userId == authService.currentUser?.id;
  final perms = room.permissions;
  final moderation = <GlitchMenuItem<String>>[
    if (!isMe && perms.can(Perm.muteMembers))
      GlitchMenuItem.control(
        child: _ServerVoiceToggle(room: room, userId: member.userId, flag: _ServerVoiceFlag.mute),
      ),
    if (!isMe && perms.can(Perm.deafenMembers))
      GlitchMenuItem.control(
        child: _ServerVoiceToggle(room: room, userId: member.userId, flag: _ServerVoiceFlag.deafen),
      ),
    if (!isMe && perms.can(Perm.moveMembers))
      GlitchMenuItem(value: 'disconnect', child: glitchMenuTextRow(context.s.voiceDisconnectMember, danger: true)),
  ];
  final person = _PersonCard(
    nickname: member.nickname,
    displayName: member.displayName,
    avatar: member.avatar,
    serverId: room.serverId,
  );
  final items = <GlitchMenuItem<String>>[
    ..._personItems(context, person, isMe: isMe),
    if (!isMe) ...[...voicePersonAudioItems<String>(member.userId), glitchMenuDivider()],
    if (moderation.isNotEmpty) ...[...moderation, glitchMenuDivider()],
    GlitchMenuItem(value: 'copyId', child: copyIdMenuRow(context, IdKind.user)),
  ];
  showGlitchContextMenuAt<String>(context, position, items, (action) async {
    if (await _runPersonAction(context, action, person, member.userId)) return;
    try {
      if (action == 'disconnect') {
        await api.disconnectMemberVoice(room.serverId, member.userId);
      }
    } catch (e) {
      if (context.mounted) GlitchToast.show(context, errorMessage(e));
    }
  });
}

enum _ServerVoiceFlag { mute, deafen }

class _ServerVoiceToggle extends StatefulWidget {
  final Room room;
  final int userId;
  final _ServerVoiceFlag flag;

  const _ServerVoiceToggle({required this.room, required this.userId, required this.flag});

  @override
  State<_ServerVoiceToggle> createState() => _ServerVoiceToggleState();
}

class _ServerVoiceToggleState extends State<_ServerVoiceToggle> {
  bool _saving = false;

  ({VoiceStateInfo snapshot, bool value})? _confirmation;

  VoiceStateInfo? get _current => voiceChannels
      .inRoom(widget.room.serverId, widget.room.id)
      .where((member) => member.userId == widget.userId)
      .firstOrNull;

  bool _value(VoiceStateInfo member) {
    final confirmed = _confirmation;
    return confirmed != null && identical(member, confirmed.snapshot)
        ? confirmed.value
        : widget.flag == _ServerVoiceFlag.mute
            ? member.serverMute
            : member.serverDeaf;
  }

  Future<void> _toggle() async {
    final before = _current;
    if (_saving || before == null) return;
    final value = !_value(before);
    setState(() => _saving = true);
    try {
      await api.setMemberVoice(
        widget.room.serverId,
        widget.userId,
        mute: widget.flag == _ServerVoiceFlag.mute ? value : null,
        deafen: widget.flag == _ServerVoiceFlag.deafen ? value : null,
      );
      if (!mounted) return;
      if (identical(_current, before)) {
        _confirmation = (snapshot: before, value: value);
      }
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: voiceChannels,
        builder: (context, _) {
          final member = _current;
          return GlitchMenuToggle(
            label: widget.flag == _ServerVoiceFlag.mute ? context.s.voiceServerMute : context.s.voiceServerDeafen,
            value: member != null && _value(member),
            onChanged: _saving || member == null ? null : (_) => unawaited(_toggle()),
          );
        },
      );
}

void openCallMemberMenu(BuildContext context, {required int userId, required Offset position}) {
  final isMe = userId == authService.currentUser?.id;
  final m = callProvider.roster.where((m) => m.userId == userId).firstOrNull;
  final person = _PersonCard(nickname: m?.nickname, displayName: m?.displayName, avatar: m?.avatar);
  final items = <GlitchMenuItem<String>>[
    ..._personItems(context, person, isMe: isMe),
    if (!isMe) ...[...voicePersonAudioItems<String>(userId), glitchMenuDivider()],
    GlitchMenuItem(value: 'copyId', child: copyIdMenuRow(context, IdKind.user)),
  ];
  showGlitchContextMenuAt<String>(context, position, items, (action) async {
    await _runPersonAction(context, action, person, userId);
  });
}

class _PersonCard {
  final String? nickname;
  final String? displayName;
  final String? avatar;
  final int? serverId;

  const _PersonCard({this.nickname, this.displayName, this.avatar, this.serverId});
}

List<GlitchMenuItem<String>> _personItems(BuildContext context, _PersonCard p, {required bool isMe}) {
  if (p.nickname == null) return const [];
  final s = context.s;
  return [
    GlitchMenuItem(value: 'profile', child: glitchMenuTextRow(s.voiceMemberProfile)),
    if (!isMe) GlitchMenuItem(value: 'write', child: glitchMenuTextRow(s.voiceMemberWrite)),
    glitchMenuDivider(),
  ];
}

Future<bool> _runPersonAction(BuildContext context, String action, _PersonCard p, int userId) async {
  final nickname = p.nickname;
  switch (action) {
    case 'copyId':
      await copyId(context, userId);
      return true;
    case 'profile' when nickname != null:
      await showUserProfile(context, nickname: nickname, serverId: p.serverId);
      return true;
    case 'write' when nickname != null:
      await openPersonalChat(context, nickname: nickname, displayName: p.displayName ?? nickname, avatar: p.avatar);
      return true;
  }
  return false;
}

List<GlitchMenuItem<T>> voicePersonAudioItems<T>(int userId) => [
      GlitchMenuItem<T>.control(child: _PeopleAudioMute(userId: userId, of: _AudioOf.voice)),
      GlitchMenuItem<T>.control(child: _PeopleAudioVolume(userId: userId, of: _AudioOf.voice)),
    ];

List<GlitchMenuItem<T>> voiceStreamAudioItems<T>(int userId, {bool enabled = true}) => [
      GlitchMenuItem<T>.control(child: _PeopleAudioMute(userId: userId, of: _AudioOf.stream, enabled: enabled)),
      GlitchMenuItem<T>.control(child: _PeopleAudioVolume(userId: userId, of: _AudioOf.stream, enabled: enabled)),
    ];

enum _AudioOf { voice, stream }

class _PeopleAudioVolume extends StatelessWidget {
  final int userId;
  final _AudioOf of;
  final bool enabled;

  const _PeopleAudioVolume({required this.userId, required this.of, this.enabled = true});

  static const double _minWidth = 220;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: voiceConnection.personAudio,
        builder: (context, _) {
          final stream = of == _AudioOf.stream;
          final volume = stream ? voiceConnection.streamVolume(userId) : voiceConnection.personVolume(userId);
          void set(double v, {bool persist = false}) => stream
              ? voiceConnection.setStreamVolume(userId, v, persist: persist)
              : voiceConnection.setPersonVolume(userId, v, persist: persist);
          return ConstrainedBox(
            constraints: const BoxConstraints(minWidth: _minWidth),
            child: Padding(
              padding: kMenuItemPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    stream ? context.s.voiceStreamVolume : context.s.voiceUserVolume,
                    style: TextStyle(
                      color: enabled ? GlitchInk.of(context).textPrimary : GlitchInk.of(context).textHint,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GlitchSlider(
                    value: volume,
                    max: CallAudioPrefs.maxPersonVolume,
                    onChanged: enabled ? (v) => set(v) : null,
                    onChangeEnd: enabled ? (v) => set(v, persist: true) : null,
                    valueLabel: GlitchSlider.percentLabel,
                  ),
                ],
              ),
            ),
          );
        },
      );
}

class _PeopleAudioMute extends StatelessWidget {
  final int userId;
  final _AudioOf of;
  final bool enabled;

  const _PeopleAudioMute({required this.userId, required this.of, this.enabled = true});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: voiceConnection.personAudio,
        builder: (context, _) {
          final stream = of == _AudioOf.stream;
          return GlitchMenuToggle(
            label: stream ? context.s.voiceStreamMute : context.s.voiceUserMute,
            value: stream ? voiceConnection.isStreamMuted(userId) : voiceConnection.isPersonMuted(userId),
            onChanged: !enabled
                ? null
                : (_) => unawaited(stream
                    ? voiceConnection.toggleStreamMuted(userId)
                    : voiceConnection.togglePersonMuted(userId)),
          );
        },
      );
}
