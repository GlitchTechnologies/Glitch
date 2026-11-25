import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../models/notification_settings.dart';
import '../models/server.dart';
import '../providers/server_provider.dart';
import '../services/api_service.dart';
import '../widgets/glitch_form_field.dart';
import '../widgets/glitch_select_field.dart';
import '../widgets/glitch_switch.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/room_name_line.dart';
import '../widgets/settings_two_pane.dart';
import '../widgets/unsaved_changes_bar.dart';

class ServerSystemSection extends StatefulWidget {
  final ServerDetail server;

  final Widget? header;

  const ServerSystemSection({super.key, required this.server, this.header});

  @override
  State<ServerSystemSection> createState() => ServerSystemSectionState();
}

class ServerSystemSectionState extends State<ServerSystemSection>
    with UnsavedGuard<ServerSystemSection> {
  final _barKey = GlobalKey<UnsavedChangesBarState>();

  late ServerDetail _saved;
  late ServerSystemSettings _system;
  late NotifLevel _defaultNotifications;
  bool _saving = false;

  static const double _maxFormWidth = 560;
  static const _rowPadding = EdgeInsets.symmetric(vertical: 12);

  @override
  void initState() {
    super.initState();
    _saved = widget.server;
    _system = _saved.system;
    _defaultNotifications = _saved.defaultNotifications;
  }

  @override
  void didUpdateWidget(ServerSystemSection old) {
    super.didUpdateWidget(old);
    if (!identical(old.server, widget.server) && !hasUnsaved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !hasUnsaved) _resetTo(widget.server);
      });
    }
  }

  @override
  bool get hasUnsaved => _system != _saved.system || _defaultNotifications != _saved.defaultNotifications;

  @override
  void warnUnsaved() => _barKey.currentState?.warn();

  void _set({ServerSystemSettings? system, NotifLevel? level}) {
    setState(() {
      if (system != null) _system = system;
      if (level != null) _defaultNotifications = level;
    });
  }

  void _resetTo(ServerDetail saved) => setState(() {
        _saved = saved;
        _system = saved.system;
        _defaultNotifications = saved.defaultNotifications;
      });

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final updated = await api.updateServerSystem(
        _saved.id,
        defaultNotifications: _defaultNotifications,
        system: _system,
      );
      serverRail.applyProfile(updated.profile);
      if (!mounted) return;
      _resetTo(updated);
      GlitchToast.show(context, context.s.roomSaved, type: ToastType.success);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<int?> _roomOptions(List<Room> texts) {
    final current = _system.roomId;
    return [
      null,
      for (final r in texts) r.id,
      if (current != null && !texts.any((r) => r.id == current)) current,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final texts = [for (final r in widget.server.allRooms) if (r.kind == RoomKind.text) r];
    final names = {for (final r in texts) r.id: r.name};
    final categories = {for (final c in widget.server.categories) c.id: c.name};
    final enabled = !_saving;
    return Stack(
      children: [
        SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, widget.header != null ? SettingsTwoPane.topPad : 18, 16, 110),
          child: Align(
            alignment: widget.header != null ? Alignment.topLeft : Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxFormWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.header != null) ...[
                    widget.header!,
                    const SizedBox(height: 22),
                  ],
                  GlitchFormLabel(label: s.serverSystemMessagesTitle, hint: s.serverSystemMessagesHint),
                  GlitchSwitchRow(
                    label: s.serverSystemJoin,
                    description: s.serverSystemJoinHint,
                    value: _system.joinMessages,
                    onChanged: enabled
                        ? (v) => _set(system: ServerSystemSettings(
                            roomId: _system.roomId, joinMessages: v, leaveMessages: _system.leaveMessages))
                        : null,
                    border: false,
                    padding: _rowPadding,
                  ),
                  GlitchSwitchRow(
                    label: s.serverSystemLeave,
                    description: s.serverSystemLeaveHint,
                    value: _system.leaveMessages,
                    onChanged: enabled
                        ? (v) => _set(system: ServerSystemSettings(
                            roomId: _system.roomId, joinMessages: _system.joinMessages, leaveMessages: v))
                        : null,
                    border: false,
                    padding: _rowPadding,
                  ),
                  GlitchSelectRow<int?>(
                    label: s.serverSystemChannel,
                    description: s.serverSystemChannelHint,
                    value: _system.roomId,
                    options: _roomOptions(texts),
                    optionLabel: (id) => id == null
                        ? s.serverSystemNone
                        : (names[id] != null ? '#${names[id]}' : s.serverSystemHiddenRoom),
                    optionView: (id, style) {
                      final room = id == null ? null : texts.where((r) => r.id == id).firstOrNull;
                      if (room == null) {
                        return Text(
                          id == null ? s.serverSystemNone : s.serverSystemHiddenRoom,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: style,
                        );
                      }
                      return RoomNameLine(
                        name: room.name,
                        category: categories[room.categoryId],
                        style: style,
                      );
                    },
                    onChanged: enabled
                        ? (id) => _set(system: ServerSystemSettings(
                            roomId: id, joinMessages: _system.joinMessages, leaveMessages: _system.leaveMessages))
                        : null,
                    padding: _rowPadding,
                  ),
                  const SizedBox(height: 28),
                  GlitchFormLabel(label: s.notifDefaultTitle, hint: s.notifDefaultHint),
                  GlitchChoiceTile(
                    icon: Icons.notifications_active_outlined,
                    title: s.notifLevelAll,
                    subtitle: s.notifDefaultAllHint,
                    selected: _defaultNotifications == NotifLevel.all,
                    onTap: enabled ? () => _set(level: NotifLevel.all) : null,
                  ),
                  const SizedBox(height: 10),
                  GlitchChoiceTile(
                    icon: Icons.alternate_email_rounded,
                    title: s.notifLevelMentions,
                    subtitle: s.notifDefaultMentionsHint,
                    selected: _defaultNotifications == NotifLevel.mentions,
                    onTap: enabled ? () => _set(level: NotifLevel.mentions) : null,
                  ),
                ],
              ),
            ),
          ),
        ),
        UnsavedChangesDock(
          visible: hasUnsaved,
          wide: widget.header != null,
          maxWidth: _maxFormWidth,
          barKey: _barKey,
          saving: _saving,
          onReset: () => _resetTo(_saved),
          onSave: _save,
        ),
      ],
    );
  }
}
