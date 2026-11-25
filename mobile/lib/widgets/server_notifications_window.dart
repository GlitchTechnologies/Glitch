import 'dart:async';

import 'package:flutter/material.dart';

import '../core/date_text.dart';
import '../core/l10n.dart';
import '../models/notification_settings.dart';
import '../providers/server_notifications.dart';
import '../services/api_service.dart';
import 'adaptive_sheet.dart';
import 'glitch_form_field.dart';
import 'glitch_menu.dart';
import 'glitch_switch.dart';
import 'glitch_toast.dart';

Future<void> openServerNotifications(BuildContext context, {required int serverId, required String serverName}) =>
    showAdaptiveSheet<void>(
      context,
      title: context.s.notifServerTitle,
      bodyBuilder: (ctx, _) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
        child: _ServerNotificationsForm(serverId: serverId, serverName: serverName),
      ),
    );

class _MuteChoice {
  final int? minutes;
  const _MuteChoice(this.minutes);
}

String _muteLabel(BuildContext context, int? minutes) {
  final s = context.s;
  return switch (minutes) {
    15 => s.notifMuteFor15m,
    60 => s.notifMuteFor1h,
    180 => s.notifMuteFor3h,
    480 => s.notifMuteFor8h,
    1440 => s.notifMuteFor24h,
    _ => s.notifMuteForever,
  };
}

class _ServerNotificationsForm extends StatefulWidget {
  final int serverId;
  final String serverName;

  const _ServerNotificationsForm({required this.serverId, required this.serverName});

  @override
  State<_ServerNotificationsForm> createState() => _ServerNotificationsFormState();
}

class _ServerNotificationsFormState extends State<_ServerNotificationsForm> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    serverNotifications.addListener(_onChange);
    unawaited(serverNotifications.refresh(widget.serverId).catchError((_) => serverNotifications.of(widget.serverId)));
  }

  @override
  void dispose() {
    serverNotifications.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _apply(Future<ServerNotifSettings> Function() send) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await send();
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setLevel(NotifLevel level) => _apply(() => serverNotifications.update(widget.serverId, level: level));

  void _askMute(BuildContext anchor) {
    openGlitchMenu<_MuteChoice>(
      anchor,
      items: [
        for (final m in [...kMuteMinutes, null])
          GlitchMenuItem(
            value: _MuteChoice(m),
            child: glitchMenuRow(
              m == null ? Icons.notifications_off_outlined : Icons.schedule_rounded,
              _muteLabel(context, m),
            ),
          ),
      ],
      onSelected: (choice) => _apply(() => serverNotifications.update(
            widget.serverId,
            muted: true,
            muteMinutes: choice.minutes,
          )),
    );
  }

  void _unmute() => _apply(() => serverNotifications.update(widget.serverId, muted: false));

  String _mutedText(BuildContext context, ServerNotifSettings settings) {
    final s = context.s;
    final until = settings.mutedUntil;
    if (until == null) return s.notifMutedForever;
    final now = DateTime.now();
    final sameDay = until.year == now.year && until.month == now.month && until.day == now.day;
    return s.notifMutedUntil(sameDay ? formatTime(until) : '${formatDay(until)} ${formatTime(until)}');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final settings = serverNotifications.of(widget.serverId);
    final muted = settings.mutedAt(DateTime.now());
    final enabled = !_busy;

    Widget level(NotifLevel value, IconData icon, String title, String subtitle) => GlitchChoiceTile(
          icon: icon,
          title: title,
          subtitle: subtitle,
          selected: settings.level == value,
          onTap: enabled
              ? () {
                  if (settings.level != value) _setLevel(value);
                }
              : null,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Builder(
          builder: (anchor) => GlitchSwitchRow(
            label: s.notifMuteServer(widget.serverName),
            description: muted ? _mutedText(context, settings) : s.notifMuteDesc,
            value: muted,
            onChanged: enabled
                ? (on) {
                    if (on) {
                      _askMute(anchor);
                    } else {
                      _unmute();
                    }
                  }
                : null,
            border: false,
            padding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
        const SizedBox(height: 16),
        GlitchFormLabel(label: s.notifServerLevel),
        level(NotifLevel.all, Icons.notifications_active_outlined, s.notifLevelAll, s.notifLevelAllHint),
        const SizedBox(height: 10),
        level(NotifLevel.mentions, Icons.alternate_email_rounded, s.notifLevelMentions, s.notifLevelMentionsHint),
        const SizedBox(height: 10),
        level(NotifLevel.none, Icons.notifications_off_outlined, s.notifLevelNone, s.notifLevelNoneHint),
        const SizedBox(height: 16),
        GlitchSwitchRow(
          label: s.notifSuppressEveryone,
          description: s.notifSuppressHint,
          value: settings.suppressEveryone,
          onChanged: enabled
              ? (v) => _apply(() => serverNotifications.update(widget.serverId, suppressEveryone: v))
              : null,
          border: false,
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
        GlitchSwitchRow(
          label: s.notifSuppressRoles,
          description: s.notifSuppressHint,
          value: settings.suppressRoles,
          onChanged: enabled
              ? (v) => _apply(() => serverNotifications.update(widget.serverId, suppressRoles: v))
              : null,
          border: false,
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ],
    );
  }
}
