import 'dart:async';

import 'package:flutter/material.dart';

import '../core/adaptive_open.dart' show openAdaptiveFullscreen;
import '../core/l10n.dart';
import '../core/permissions.dart';
import '../models/server.dart';
import '../providers/server_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glitch_dialog.dart';
import '../widgets/glitch_form_field.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/glitch_slider.dart';
import '../widgets/settings_window.dart';
import '../widgets/unsaved_changes_bar.dart';
import '../widgets/settings_two_pane.dart';
import 'place_permissions_section.dart';
import 'room_webhooks_section.dart';


enum RoomSettingsSection { general, permissions, integrations }

String _label(BuildContext context, RoomSettingsSection section) => switch (section) {
      RoomSettingsSection.general => context.s.roomSettingsGeneral,
      RoomSettingsSection.permissions => context.s.roomSettingsPermissions,
      RoomSettingsSection.integrations => context.s.roomSettingsIntegrations,
    };

IconData _icon(RoomSettingsSection section) => switch (section) {
      RoomSettingsSection.general => Icons.edit_outlined,
      RoomSettingsSection.permissions => Icons.shield_outlined,
      RoomSettingsSection.integrations => Icons.webhook_rounded,
    };

bool roomSettingsAvailable(Room room) => _visibleSections(room).isNotEmpty;

bool roomSettingsAllowed(Perms perms) =>
    perms.can(Perm.manageRooms) || perms.can(Perm.manageRoles) || perms.can(Perm.manageWebhooks);

void openRoomSettings(BuildContext context, Room room) {
  openAdaptiveFullscreen(
    context,
    narrowBuilder: (_) => RoomSettingsScreen(room: room),
    wideBuilder: (_) => RoomSettingsWideScreen(room: room),
  );
}

List<RoomSettingsSection> _visibleSections(Room room) => [
      if (room.permissions.can(Perm.manageRooms)) RoomSettingsSection.general,
      if (room.permissions.can(Perm.manageRoles)) RoomSettingsSection.permissions,
      if (room.kind == RoomKind.text && room.permissions.can(Perm.manageWebhooks)) RoomSettingsSection.integrations,
    ];

SettingsWindowSpec<RoomSettingsSection> _spec(
  BuildContext context,
  Room room, {
  required VoidCallback onDelete,
  required VoidCallback onLostAccess,
}) {
  final s = context.s;
  return SettingsWindowSpec<RoomSettingsSection>(
    title: s.roomSettings,
    objectName: room.name,
    narrowHeader: Row(
      children: [
        Icon(Icons.tag_rounded, size: 26, color: GlitchColors.textSecond),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            room.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
          ),
        ),
      ],
    ),
    groups: [(null, _visibleSections(room))],
    label: (section) => _label(context, section),
    icon: _icon,
    content: (section, {header, sectionKey, wide = false}) => switch (section) {
      RoomSettingsSection.general =>
        RoomGeneralSection(key: sectionKey, room: room, header: header),
      RoomSettingsSection.permissions => PlacePermissionsSection(
          key: sectionKey,
          serverId: room.serverId,
          placeId: room.id,
          isCategory: false,
          roomKind: room.kind,
          header: header,
          twoPane: wide,
          onLostAccess: onLostAccess,
        ),
      RoomSettingsSection.integrations => RoomWebhooksSection(key: sectionKey, room: room, header: header),
    },
    danger: room.permissions.can(Perm.manageRooms)
        ? SettingsDangerAction(label: s.roomSettingsDelete, onTap: onDelete)
        : null,
  );
}

mixin _FreshRoom<T extends StatefulWidget> on State<T> {
  late Room room;
  StreamSubscription<ServerRoomEvent>? _roomSub;
  StreamSubscription<ServerGone>? _goneSub;
  StreamSubscription<int>? _rolesSub;

  Room get initialRoom;

  @override
  void initState() {
    super.initState();
    room = initialRoom;
    _roomSub = serverRail.roomEvents.listen((e) {
      if (e.chatId != room.id || !mounted) return;
      if (e.deleted) {
        _closeWindow();
        return;
      }
      setState(() => room = room.withProfile(name: e.name, description: e.description, userLimit: e.userLimit));
    });
    _goneSub = serverRail.serverGone.listen((g) {
      if (g.id == room.serverId && mounted) _closeWindow();
    });
    _rolesSub = serverRail.roleChanges.listen((id) {
      if (id == room.serverId && mounted) _refreshRoom();
    });
  }

  Future<void> _refreshRoom() async {
    try {
      final fresh = await api.getRoom(room.serverId, room.id);
      if (!mounted) return;
      if (!roomSettingsAvailable(fresh)) {
        lostAccess();
        return;
      }
      setState(() => room = fresh);
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.statusCode == 403) lostAccess();
    }
  }

  void lostAccess() {
    if (!mounted) return;
    GlitchToast.show(context, context.s.placeSettingsLost);
    _closeWindow();
  }

  void _closeWindow() {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final nav = Navigator.of(context);
    nav.popUntil((r) => r == route);
    nav.pop();
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _goneSub?.cancel();
    _rolesSub?.cancel();
    super.dispose();
  }

  Future<void> deleteRoom() async {
    final s = context.s;
    final confirmed = await glitchConfirm(
      context,
      title: s.roomDeleteTitle,
      body: s.roomDeleteBody(room.name),
      confirmLabel: s.delete,
    );
    if (!confirmed || !mounted) return;
    try {
      await api.deleteRoom(room.serverId, room.id);
      if (!mounted) return;
      GlitchToast.show(context, s.roomDeleted, type: ToastType.success);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    }
  }
}


class RoomSettingsScreen extends StatefulWidget {
  final Room room;

  const RoomSettingsScreen({super.key, required this.room});

  @override
  State<RoomSettingsScreen> createState() => _RoomSettingsScreenState();
}

class _RoomSettingsScreenState extends State<RoomSettingsScreen>
    with ThemeAwareState<RoomSettingsScreen>, _FreshRoom<RoomSettingsScreen> {
  @override
  Room get initialRoom => widget.room;

  @override
  Widget build(BuildContext context) => SettingsWindowNarrow<RoomSettingsSection>(
        spec: _spec(context, room, onDelete: deleteRoom, onLostAccess: lostAccess),
      );
}

class RoomSettingsWideScreen extends StatefulWidget {
  final Room room;

  const RoomSettingsWideScreen({super.key, required this.room});

  @override
  State<RoomSettingsWideScreen> createState() => _RoomSettingsWideScreenState();
}

class _RoomSettingsWideScreenState extends State<RoomSettingsWideScreen>
    with ThemeAwareState<RoomSettingsWideScreen>, _FreshRoom<RoomSettingsWideScreen> {
  @override
  Room get initialRoom => widget.room;

  @override
  Widget build(BuildContext context) => SettingsWindowWide<RoomSettingsSection>(
        spec: _spec(context, room, onDelete: deleteRoom, onLostAccess: lostAccess),
      );
}


const int _kMaxTopic = 500;

const double _kMaxFormWidth = 560;

class RoomGeneralSection extends StatefulWidget {
  final Room room;

  final Widget? header;

  const RoomGeneralSection({super.key, required this.room, this.header});

  @override
  State<RoomGeneralSection> createState() => RoomGeneralSectionState();
}

class RoomGeneralSectionState extends State<RoomGeneralSection>
    with UnsavedGuard<RoomGeneralSection> {
  final _barKey = GlobalKey<UnsavedChangesBarState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _topicCtrl;

  late Room _saved;
  bool _saving = false;

  int _limit = 0;

  bool get _isVoice => _saved.kind == RoomKind.voice;

  @override
  void initState() {
    super.initState();
    _saved = widget.room;
    _nameCtrl = TextEditingController(text: _saved.name)..addListener(_changed);
    _topicCtrl = TextEditingController(text: _saved.description ?? '')..addListener(_changed);
    _limit = _saved.userLimit ?? 0;
  }

  @override
  void didUpdateWidget(RoomGeneralSection old) {
    super.didUpdateWidget(old);
    if (!identical(old.room, widget.room) && !hasUnsaved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !hasUnsaved) _resetTo(widget.room);
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _topicCtrl.dispose();
    super.dispose();
  }

  @override
  bool get hasUnsaved =>
      _nameCtrl.text.trim() != _saved.name ||
      (!_isVoice && _topicCtrl.text.trim() != (_saved.description ?? '')) ||
      (_isVoice && _limit != (_saved.userLimit ?? 0));

  @override
  void warnUnsaved() => _barKey.currentState?.warn();

  void _changed() {
    if (mounted) setState(() {});
  }

  void _resetTo(Room saved) {
    _saved = saved;
    if (_nameCtrl.text != saved.name) _nameCtrl.text = saved.name;
    final topic = saved.description ?? '';
    if (_topicCtrl.text != topic) _topicCtrl.text = topic;
    _limit = saved.userLimit ?? 0;
    _changed();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      GlitchToast.show(context, context.s.roomCreateNameEmpty);
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await api.updateRoom(
        _saved.serverId,
        _saved.id,
        name: name,
        description: _isVoice ? null : _topicCtrl.text.trim(),
        userLimit: _isVoice ? _limit : null,
      );
      if (!mounted) return;
      _resetTo(updated);
      GlitchToast.show(context, context.s.roomSaved, type: ToastType.success);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildLimit(BuildContext context) {
    final s = context.s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlitchFormLabel(label: s.roomUserLimit, hint: s.roomUserLimitNote),
        Row(
          children: [
            Expanded(
              child: GlitchSlider(
                value: _limit.toDouble(),
                max: 99,
                divisions: 99,
                onChanged: _saving ? null : (v) => setState(() => _limit = v.round()),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 96,
              child: Text(
                _limit == 0 ? s.roomUserLimitNone : '$_limit',
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final unsaved = hasUnsaved;
    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, widget.header != null ? SettingsTwoPane.topPad : 16, 16, 96),
            child: Align(
              alignment: widget.header != null ? Alignment.topLeft : Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kMaxFormWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.header != null) ...[
                      widget.header!,
                      const SizedBox(height: 20),
                    ],
                    GlitchFormField(
                      label: s.roomGeneralName,
                      controller: _nameCtrl,
                      placeholder: s.roomCreateNameHint,
                      maxLength: kMaxRoomName,
                      enabled: !_saving,
                    ),
                    if (!_isVoice) ...[
                      const SizedBox(height: 18),
                      GlitchFormField(
                        label: s.roomGeneralTopic,
                        controller: _topicCtrl,
                        placeholder: s.roomGeneralTopicHint,
                        maxLength: _kMaxTopic,
                        showCounter: true,
                        minLines: 3,
                        maxLines: 5,
                        enabled: !_saving,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        s.roomGeneralTopicNote,
                        style: TextStyle(fontSize: 13, height: 1.35, color: GlitchColors.textSecond),
                      ),
                    ],
                    if (_isVoice) ...[
                      const SizedBox(height: 24),
                      _buildLimit(context),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        UnsavedChangesDock(
          visible: unsaved,
          wide: widget.header != null,
          maxWidth: _kMaxFormWidth,
          barKey: _barKey,
          saving: _saving,
          onReset: () => _resetTo(_saved),
          onSave: _save,
        ),
      ],
    );
  }
}
