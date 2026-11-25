import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/perm_texts.dart';
import '../core/permissions.dart';
import '../models/server.dart';
import '../providers/server_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glitch_dialog.dart';
import '../widgets/glitch_pressable.dart';
import '../widgets/glitch_switch.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/glitch_menu.dart';
import '../widgets/overwrite_target_picker.dart';
import '../widgets/role_picker.dart';
import '../widgets/server_user_avatar.dart';
import '../widgets/settings_parts.dart';
import '../widgets/unsaved_changes_bar.dart';
import '../widgets/settings_two_pane.dart';
import '../widgets/glitch_icon_button.dart';


const double _kRolesColumnWidth = 220;

const double _kMaxWidth = 760;

class PlacePermissionsSection extends StatefulWidget {
  final int serverId;
  final int placeId;
  final bool isCategory;

  final RoomKind? roomKind;

  final Widget? header;

  final bool twoPane;

  final VoidCallback onLostAccess;

  const PlacePermissionsSection({
    super.key,
    required this.serverId,
    required this.placeId,
    required this.isCategory,
    this.roomKind,
    required this.twoPane,
    required this.onLostAccess,
    this.header,
  });

  @override
  State<PlacePermissionsSection> createState() => _PlacePermissionsSectionState();
}


@immutable
class _Target {
  final int? roleId;
  final int? userId;

  const _Target.role(int this.roleId) : userId = null;
  const _Target.user(int this.userId) : roleId = null;

  @override
  bool operator ==(Object other) =>
      other is _Target && other.roleId == roleId && other.userId == userId;

  @override
  int get hashCode => Object.hash(roleId, userId);
}

class _PlacePermissionsSectionState extends State<PlacePermissionsSection>
    with UnsavedGuard<PlacePermissionsSection> {
  final _barKey = GlobalKey<UnsavedChangesBarState>();

  PlaceOverwrites? _data;

  Map<int, RoleOverwrite> _edits = {};
  Map<int, RoleOverwrite> _memberEdits = {};

  Map<int, ServerUser> _people = {};

  final Set<int> _addedRoles = {};
  final Set<int> _addedPeople = {};

  _Target? _selected;

  bool _loading = true;
  String? _error;
  bool _saving = false;
  bool _syncing = false;
  StreamSubscription<int>? _rolesSub;

  @override
  void initState() {
    super.initState();
    _rolesSub = serverRail.roleChanges.listen((id) {
      if (id == widget.serverId && mounted && !hasUnsaved && !_saving) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _rolesSub?.cancel();
    super.dispose();
  }

  static Map<int, RoleOverwrite> _nonEmpty(Map<int, RoleOverwrite> m) =>
      {for (final e in m.entries) if (!e.value.isEmpty) e.key: e.value};

  static Map<int, RoleOverwrite> _membersOf(PlaceOverwrites data) =>
      {for (final m in data.members) m.user.id: m.overwrite};

  @override
  bool get hasUnsaved {
    final data = _data;
    if (data == null) return false;
    return !mapEquals(_nonEmpty(_edits), _nonEmpty(data.overwrites)) ||
        !mapEquals(_nonEmpty(_memberEdits), _nonEmpty(_membersOf(data)));
  }

  @override
  void warnUnsaved() => _barKey.currentState?.warn();

  OverwriteRole? get _everyone => _data?.roles.where((r) => r.isDefault).firstOrNull;

  bool _customized(RoleOverwrite? o) =>
      o != null &&
      kRoomOverwritePerms.any((p) =>
          placeShowsPerm(widget.roomKind, p) && (o.allow.has(p) || o.deny.has(p)));

  List<OverwriteRole> get _shownRoles => [
        for (final r in _data?.roles ?? const <OverwriteRole>[])
          if (r.isDefault || _addedRoles.contains(r.id) || _customized(_edits[r.id])) r,
      ];

  List<ServerUser> get _shownPeople {
    final ids = {
      for (final e in _memberEdits.entries) if (_customized(e.value)) e.key,
      ..._addedPeople,
    };
    final people = [for (final id in ids) if (_people[id] != null) _people[id]!];
    people.sort((a, b) => _nameOf(a).toLowerCase().compareTo(_nameOf(b).toLowerCase()));
    return people;
  }

  static String _nameOf(ServerUser u) => u.displayName.isNotEmpty ? u.displayName : u.nickname;

  bool _isShown(_Target t) => t.roleId != null
      ? _shownRoles.any((r) => r.id == t.roleId)
      : _shownPeople.any((u) => u.id == t.userId);

  void _fixSelection() {
    final sel = _selected;
    if (sel != null && _isShown(sel)) return;
    final everyone = _everyone;
    _selected = widget.twoPane && everyone != null ? _Target.role(everyone.id) : null;
  }

  void _apply(PlaceOverwrites data) {
    _data = data;
    _edits = Map.of(data.overwrites);
    _memberEdits = _membersOf(data);
    _people = {for (final m in data.members) m.user.id: m.user};
    _addedRoles.clear();
    _addedPeople.clear();
    _fixSelection();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await api.getOverwrites(widget.serverId, widget.placeId,
          isCategory: widget.isCategory);
      if (!mounted) return;
      setState(() {
        _apply(data);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.statusCode == 403) {
        widget.onLostAccess();
        return;
      }
      setState(() {
        _error = errorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final data = await api.setOverwrites(widget.serverId, widget.placeId, _edits, _memberEdits,
          isCategory: widget.isCategory);
      if (!mounted) return;
      if (data == null) {
        widget.onLostAccess();
        return;
      }
      setState(() => _apply(data));
      GlitchToast.show(context, context.s.placePermsSaved, type: ToastType.success);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reset() {
    final data = _data;
    if (data == null) return;
    setState(() => _apply(data));
  }

  Future<void> _sync() async {
    if (_syncing || _saving) return;
    if (hasUnsaved) {
      warnUnsaved();
      return;
    }
    final s = context.s;
    final ok = await glitchConfirm(
      context,
      title: s.placePermsSyncTitle,
      body: s.placePermsSyncBody(_data?.categoryName ?? ''),
      confirmLabel: s.placePermsSync,
    );
    if (!ok || !mounted) return;
    setState(() => _syncing = true);
    try {
      final data = await api.syncRoomWithCategory(widget.serverId, widget.placeId);
      if (!mounted) return;
      if (data == null) {
        widget.onLostAccess();
        return;
      }
      setState(() => _apply(data));
      GlitchToast.show(context, s.placePermsSaved, type: ToastType.success);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }


  Map<int, RoleOverwrite> _formOf(_Target t) => t.roleId != null ? _edits : _memberEdits;
  int _idOf(_Target t) => t.roleId ?? t.userId!;

  GlitchTriState _stateOf(_Target t, Perm p) {
    final o = _formOf(t)[_idOf(t)] ?? RoleOverwrite.empty;
    if (o.allow.has(p)) return GlitchTriState.allow;
    if (o.deny.has(p)) return GlitchTriState.deny;
    return GlitchTriState.inherit;
  }

  void _setPerm(_Target t, Perm p, GlitchTriState state) {
    final id = _idOf(t);
    final o = _formOf(t)[id] ?? RoleOverwrite.empty;
    var allow = o.allow.withoutPerm(p);
    var deny = o.deny.withoutPerm(p);
    if (state == GlitchTriState.allow) allow = allow.withPerm(p);
    if (state == GlitchTriState.deny) deny = deny.withPerm(p);
    final next = RoleOverwrite(allow, deny);
    setState(() {
      if (t.roleId != null) {
        _edits = {..._edits, id: next};
        _addedRoles.add(id);
      } else {
        _memberEdits = {..._memberEdits, id: next};
        _addedPeople.add(id);
      }
    });
  }

  void _openAdd(
    BuildContext anchor, {
    required Set<int> excludeRoles,
    required Set<int> excludeUsers,
    required void Function(_Target target) then,
  }) {
    final data = _data;
    if (data == null) return;
    openGlitchPopup(
      anchor,
      growRight: true,
      width: kOverwriteTargetPopupWidth,
      builder: (close, maxHeight) => OverwriteTargetPopup(
        roles: [for (final r in data.roles) if (!r.isDefault && !excludeRoles.contains(r.id)) r],
        excludeUsers: excludeUsers,
        withMembers: data.canEditMembers,
        searchMembers: (q) => api.searchOverwriteMembers(widget.serverId, widget.placeId,
            isCategory: widget.isCategory, query: q),
        maxHeight: maxHeight,
        onPick: (t) {
          close();
          if (!mounted) return;
          final role = t.role;
          final user = t.user;
          if (role != null) {
            setState(() => _addedRoles.add(role.id));
            then(_Target.role(role.id));
          } else if (user != null) {
            setState(() {
              _people[user.id] = user;
              _addedPeople.add(user.id);
            });
            then(_Target.user(user.id));
          }
        },
      ),
    );
  }

  void _openAddAdvanced(BuildContext anchor) => _openAdd(
        anchor,
        excludeRoles: {for (final r in _shownRoles) r.id},
        excludeUsers: {for (final u in _shownPeople) u.id},
        then: (t) => setState(() => _selected = t),
      );


  bool get _isPrivate {
    final everyone = _everyone;
    if (everyone == null) return false;
    return (_edits[everyone.id] ?? RoleOverwrite.empty).deny.has(Perm.viewRoom);
  }

  bool _allowsView(Map<int, RoleOverwrite> form, int id) =>
      (form[id] ?? RoleOverwrite.empty).allow.has(Perm.viewRoom);

  List<OverwriteRole> get _viewRoles => [
        for (final r in _data?.roles ?? const <OverwriteRole>[])
          if (!r.isDefault && _allowsView(_edits, r.id)) r,
      ];

  List<ServerUser> get _viewPeople =>
      [for (final u in _shownPeople) if (_allowsView(_memberEdits, u.id)) u];

  bool get _viewGrantable => _data?.grantable.has(Perm.viewRoom) ?? false;

  void _setPrivate(bool on) {
    final everyone = _everyone;
    if (everyone == null) return;
    _setPerm(_Target.role(everyone.id), Perm.viewRoom,
        on ? GlitchTriState.deny : GlitchTriState.inherit);
  }

  void _openAddViewer(BuildContext anchor) => _openAdd(
        anchor,
        excludeRoles: {for (final r in _viewRoles) r.id},
        excludeUsers: {for (final u in _viewPeople) u.id},
        then: (t) => _setPerm(t, Perm.viewRoom, GlitchTriState.allow),
      );

  void _remove(_Target t) {
    setState(() {
      if (t.roleId != null) {
        _edits = {..._edits}..remove(t.roleId);
        _addedRoles.remove(t.roleId);
      } else {
        _memberEdits = {..._memberEdits}..remove(t.userId);
        _addedPeople.remove(t.userId);
      }
      _selected = null;
      _fixSelection();
    });
  }

  bool get _canAdd {
    final data = _data;
    if (data == null) return false;
    return data.canEditMembers || data.roles.any((r) => !r.isDefault && r.canEdit);
  }


  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      if (_loading) {
        return Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue));
      }
      return SettingsRetry(text: _error ?? '', onRetry: _load);
    }
    return Stack(
      children: [
        Positioned.fill(child: widget.twoPane ? _buildWide(data) : _buildNarrow(data)),
        UnsavedChangesDock(
          visible: hasUnsaved,
          wide: widget.twoPane,
          maxWidth: _kMaxWidth,
          barKey: _barKey,
          saving: _saving,
          onReset: _reset,
          onSave: _save,
        ),
      ],
    );
  }

  Widget? _notice(PlaceOverwrites data) {
    final s = context.s;
    if (widget.isCategory) {
      return SettingsNotice(icon: Icons.info_outline_rounded, text: s.categoryPermsHint);
    }
    final synced = data.synced;
    if (synced == null) return null;
    final name = data.categoryName ?? '';
    if (synced) {
      return SettingsNotice(icon: Icons.link_rounded, text: s.placePermsSynced(name));
    }
    return SettingsNotice(
      icon: Icons.link_off_rounded,
      text: s.placePermsNotSynced(name),
      trailing: GlitchPressable(
        onTap: _syncing ? null : _sync,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: GlitchColors.accentBlue,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            s.placePermsSync,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _listHeader({required bool chevron}) {
    final s = context.s;
    return Padding(
      padding: EdgeInsets.fromLTRB(chevron ? 14 : 10, chevron ? 10 : 0, chevron ? 6 : 0, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              s.placePermsTargets.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: GlitchColors.textHint,
              ),
            ),
          ),
          if (_canAdd)
            Builder(
              builder: (btn) => GlitchAddButton(onTap: () => _openAddAdvanced(btn), size: 28),
            ),
        ],
      ),
    );
  }

  bool _removable(_Target t) {
    final data = _data;
    if (data == null || _saving || _syncing) return false;
    if (t.userId != null) return data.canEditMembers;
    final role = data.roles.where((r) => r.id == t.roleId).firstOrNull;
    return role != null && !role.isDefault && role.canEdit;
  }

  void _openItemMenu(_Target t, Offset position) {
    if (!_removable(t)) return;
    final s = context.s;
    showGlitchContextMenuAt<_Target>(
      context,
      position,
      [
        GlitchMenuItem(
          value: t,
          child: glitchMenuRow(
            Icons.delete_outline_rounded,
            t.roleId != null ? s.placePermsRemoveRole : s.placePermsRemoveMember,
            danger: true,
          ),
        ),
      ],
      _remove,
    );
  }

  List<Widget> _items({required bool chevron}) => [
        for (final r in _shownRoles)
          _TargetItem(
            leading: RoleIcon(color: r.color),
            name: r.name,
            selected: !chevron && _selected == _Target.role(r.id),
            customized: _customized(_edits[r.id]),
            chevron: chevron,
            onTap: () => setState(() => _selected = _Target.role(r.id)),
            onMenu: (pos) => _openItemMenu(_Target.role(r.id), pos),
          ),
        for (final u in _shownPeople)
          _TargetItem(
            leading: ServerUserAvatar(user: u, name: _nameOf(u), size: 20),
            name: _nameOf(u),
            selected: !chevron && _selected == _Target.user(u.id),
            customized: _customized(_memberEdits[u.id]),
            chevron: chevron,
            onTap: () => setState(() => _selected = _Target.user(u.id)),
            onMenu: (pos) => _openItemMenu(_Target.user(u.id), pos),
          ),
      ];

  bool _advancedCollapsed = false;

  Widget _advancedHeader() {
    final s = context.s;
    return ClickableCursor(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _advancedCollapsed = !_advancedCollapsed),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Text(
                s.placePermsAdvanced,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
              ),
              const SizedBox(width: 6),
              Icon(
                _advancedCollapsed ? Icons.chevron_right_rounded : Icons.expand_more_rounded,
                size: 22,
                color: GlitchColors.textPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _privateCard(PlaceOverwrites data) {
    final s = context.s;
    final everyone = _everyone;
    final busy = _saving || _syncing;
    final canToggle = !busy && everyone != null && everyone.canEdit && _viewGrantable;
    final private = _isPrivate;
    final roles = _viewRoles;
    final people = _viewPeople;
    final canAdd = !busy && _viewGrantable && _canAdd;

    Widget sub(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Text(
            text,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
          ),
        );
    Widget none(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
          child: Text(text, style: TextStyle(fontSize: 13.5, color: GlitchColors.textSecond)),
        );
    Widget divider() => Divider(height: 1, color: GlitchColors.border);
    Widget revoke(_Target t, bool can) => can && !busy
        ? GlitchIconButton(
            onTap: () => _setPerm(t, Perm.viewRoom, GlitchTriState.inherit),
            size: 26,
            extent: 26,
            icon: const Icon(Icons.close_rounded, size: 16),
          )
        : const SizedBox.shrink();

    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 18, color: GlitchColors.textPrimary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.isCategory ? s.placePrivateCategory : s.placePrivateRoom,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
                  ),
                ),
                GlitchSwitch(value: private, onChanged: canToggle ? _setPrivate : null),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Text(
              widget.isCategory ? s.placePrivateCategoryDesc : s.placePrivateRoomDesc,
              style: TextStyle(fontSize: 12.5, height: 1.35, color: GlitchColors.textSecond),
            ),
          ),
          if (private) ...[
            divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.isCategory ? s.placePrivateWhoCategory : s.placePrivateWhoRoom,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary),
                    ),
                  ),
                  if (canAdd)
                    Builder(
                      builder: (btn) => GlitchPressable(
                        onTap: () => _openAddViewer(btn),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: GlitchColors.accentBlue,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            s.placePrivateAdd,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            divider(),
            sub(s.placePrivateRoles),
            if (roles.isEmpty) none(s.placePrivateNoRoles),
            for (final r in roles)
              _accessRow(
                leading: RoleIcon(color: r.color),
                name: r.name,
                trailing: revoke(_Target.role(r.id), r.canEdit),
              ),
            const SizedBox(height: 6),
            divider(),
            sub(s.placePrivateMembers),
            if (people.isEmpty) none(s.placePrivateNoMembers),
            for (final u in people)
              _accessRow(
                leading: ServerUserAvatar(user: u, name: _nameOf(u), size: 22),
                name: _nameOf(u),
                subtitle: u.nickname.isNotEmpty ? '@${u.nickname}' : null,
                trailing: revoke(_Target.user(u.id), data.canEditMembers),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: Text(
                s.placePrivateAlways,
                style: TextStyle(fontSize: 12.5, height: 1.35, color: GlitchColors.textSecond),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _accessRow({required Widget leading, required String name, String? subtitle, required Widget trailing}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 5, 8, 5),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: name, style: TextStyle(fontSize: 14.5, color: GlitchColors.textPrimary)),
                  if (subtitle != null)
                    TextSpan(text: '  $subtitle', style: TextStyle(fontSize: 12.5, color: GlitchColors.textSecond)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            trailing,
          ],
        ),
      );

  Widget _buildWide(PlaceOverwrites data) {
    final notice = _notice(data);
    final selected = _selected;
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kMaxWidth + 32),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, SettingsTwoPane.topPad, 16, 96),
          children: [
            if (widget.header != null) ...[widget.header!, const SizedBox(height: 20)],
            if (notice != null) ...[notice, const SizedBox(height: 16)],
            _privateCard(data),
            const SizedBox(height: 24),
            _advancedHeader(),
            if (!_advancedCollapsed) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _kRolesColumnWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [_listHeader(chevron: false), ..._items(chevron: false)],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: selected == null || !_isShown(selected)
                        ? const SizedBox.shrink()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _permsOf(data, selected),
                          ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNarrow(PlaceOverwrites data) {
    final s = context.s;
    final selected = _selected;
    if (selected != null && _isShown(selected)) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          SettingsBackLine(
            label: s.roomSettingsPermissions,
            onTap: () => setState(() => _selected = null),
          ),
          const SizedBox(height: 14),
          ..._permsOf(data, selected),
        ],
      );
    }
    final notice = _notice(data);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        if (notice != null) ...[notice, const SizedBox(height: 16)],
        _privateCard(data),
        const SizedBox(height: 22),
        _advancedHeader(),
        if (!_advancedCollapsed) ...[
          const SizedBox(height: 10),
          SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_listHeader(chevron: true), ..._items(chevron: true)],
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _permsOf(PlaceOverwrites data, _Target target) {
    final s = context.s;
    final role = target.roleId == null
        ? null
        : data.roles.where((r) => r.id == target.roleId).firstOrNull;
    final user = target.userId == null ? null : _people[target.userId];
    if (role == null && user == null) return const [];
    final canEdit = role?.canEdit ?? data.canEditMembers;
    final editable = canEdit && !_saving && !_syncing;
    bool shown(Perm p) => placeShowsPerm(widget.roomKind, p);
    return [
      Row(
        children: [
          if (role != null)
            RoleIcon(color: role.color)
          else
            ServerUserAvatar(user: user!, name: _nameOf(user), size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role?.name ?? _nameOf(user!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: GlitchColors.textPrimary,
                  ),
                ),
                if (user != null && user.nickname.isNotEmpty)
                  Text(
                    '@${user.nickname}',
                    style: TextStyle(fontSize: 13, color: GlitchColors.textSecond),
                  ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      if (!canEdit) ...[
        SettingsNotice(text: s.placePermsRoleLocked),
        const SizedBox(height: 14),
      ],
      for (final group in kPermGroups)
        if (group.$2.any(shown)) ...[
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              group.$1(context),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: GlitchColors.textHint,
              ),
            ),
          ),
          SettingsCard(
            child: Column(
              children: [
                for (final p in group.$2.where(shown))
                  GlitchTriSwitchRow(
                    label: permLabel(context, p, inRoom: true),
                    description: permDesc(context, p, inRoom: true),
                    value: _stateOf(target, p),
                    onChanged: editable && data.grantable.has(p)
                        ? (v) => _setPerm(target, p, v)
                        : null,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
    ];
  }
}

class _TargetItem extends StatelessWidget {
  final Widget leading;
  final String name;
  final bool selected;

  final bool customized;

  final bool chevron;
  final VoidCallback onTap;

  final ValueChanged<Offset> onMenu;

  const _TargetItem({
    required this.leading,
    required this.name,
    required this.selected,
    required this.customized,
    required this.onTap,
    required this.onMenu,
    this.chevron = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClickableCursor(
      child: GestureDetector(
        onTap: onTap,
        onSecondaryTapUp: (d) => onMenu(d.globalPosition),
        onLongPressStart: (d) => onMenu(d.globalPosition),
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: chevron ? EdgeInsets.zero : const EdgeInsets.only(bottom: 2),
          padding: EdgeInsets.symmetric(horizontal: chevron ? 14 : 10, vertical: chevron ? 13 : 8),
          decoration: BoxDecoration(
            color: selected ? GlitchColors.bgInput : null,
            borderRadius: chevron ? null : BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: GlitchColors.textPrimary,
                  ),
                ),
              ),
              if (customized)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.tune_rounded, size: 15, color: GlitchColors.textSecond),
                ),
              if (chevron)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.chevron_right_rounded, size: 20, color: GlitchColors.textPrimary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
