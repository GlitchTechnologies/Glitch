import 'dart:async';

import 'package:flutter/material.dart';

import '../core/copy_actions.dart';
import '../core/l10n.dart';
import '../core/perm_texts.dart';
import '../core/permissions.dart';
import '../models/server.dart';
import '../providers/server_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/color_palette.dart';
import '../widgets/glitch_action_button.dart';
import '../widgets/glitch_dialog.dart';
import '../widgets/glitch_form_field.dart';
import '../widgets/glitch_menu.dart';
import '../widgets/glitch_pressable.dart';
import '../widgets/glitch_search_field.dart';
import '../widgets/glitch_segmented_control.dart';
import '../widgets/glitch_switch.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/role_picker.dart';
import '../widgets/settings_parts.dart';
import '../widgets/unsaved_changes_bar.dart';
import '../widgets/settings_two_pane.dart';
import '../core/text_match.dart';
import '../widgets/glitch_icon_button.dart';

/// Последнее — не украшение: сервер разрешает менять только те биты, которыми
/// владеешь сам (`may_set_perms`). Тумблер права, которого у меня нет, обязан
/// быть выключен из работы, иначе человек его двигает, жмёт «Сохранить» и
/// получает 403 — то самое расхождение «кнопка ≠ ответ ручки», от которого
/// в этом проекте заведены `canKick`/`canBan`.

const int _kNewRole = -1;

enum _RoleMenuAction { copyId }

const int _kMaxRoleName = 64;

const double _kMaxFormWidth = 560;


const double _kRolesColumnWidth = 220;

const double _kMaxWidth = 820;

class ServerRolesSection extends StatefulWidget {
  final ServerDetail server;

  final Widget? header;

  final bool wide;

  const ServerRolesSection({
    super.key,
    required this.server,
    this.header,
    this.wide = false,
  });

  @override
  State<ServerRolesSection> createState() => _ServerRolesSectionState();
}

class _ServerRolesSectionState extends State<ServerRolesSection>
    with UnsavedGuard<ServerRolesSection> {
  List<ServerRole> _roles = [];
  bool _canCreate = false;
  bool _loading = true;
  String? _error;

  int? _editingId;

  GlobalKey<_RoleEditorState> _editorKey = GlobalKey<_RoleEditorState>();

  int _tab = 0;

  StreamSubscription<MemberDisplayChange>? _displaySub;

  final _searchCtrl = TextEditingController();
  String _query = '';

  final Set<int> _busy = {};

  final Map<int, _RoleDraft> _drafts = {};

  final _barKey = GlobalKey<UnsavedChangesBarState>();
  bool _saving = false;

  @override
  bool get hasUnsaved => _drafts.isNotEmpty;

  @override
  void warnUnsaved() => _barKey.currentState?.warn();

  @override
  void initState() {
    super.initState();
    _displaySub = serverRail.memberDisplay.listen((c) {
      if (mounted && c.affects(widget.server.id)) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _displaySub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ServerRole> get _ordinary => _roles.where((r) => !r.isDefault).toList();
  ServerRole? get _everyone => _roles.where((r) => r.isDefault).firstOrNull;

  int? get _firstRoleId => _ordinary.firstOrNull?.id ?? _everyone?.id;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await api.getServerRoles(widget.server.id);
      if (!mounted) return;
      setState(() {
        _roles = page.roles;
        _canCreate = page.canCreate;
        _loading = false;
        _dropStaleDrafts();
        if (widget.wide && _editingId == null) _editingId = _firstRoleId;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(e);
        _loading = false;
      });
    }
  }

  void _closeEditor() => setState(() => _editingId = null);

  void _openEditor(int id) {
    if (id == _editingId) return;
    setState(() {
      _editingId = id;
      _editorKey = GlobalKey<_RoleEditorState>();
    });
  }

  ServerRole? _roleById(int id) => _roles.where((r) => r.id == id).firstOrNull;

  bool get _canViewAs =>
      widget.server.isOwner || widget.server.myPermissions.has(Perm.administrator);

  void _startViewAs(ServerRole role) {
    if (hasUnsaved) {
      warnUnsaved();
      return;
    }
    serverRail.startViewAs(widget.server.id, _roles, role.isDefault ? <int>{} : {role.id});
  }

  bool _editableId(int id) => id == _kNewRole || (_roleById(id)?.canEdit ?? false);

  void _onDraft(int id, _RoleDraft draft) {
    if (!_editableId(id)) return;
    final changed = !draft.sameAs(_RoleDraft.of(id == _kNewRole ? null : _roleById(id)));
    setState(() {
      if (changed) {
        _drafts[id] = draft;
      } else {
        _drafts.remove(id);
      }
    });
  }

  void _dropStaleDrafts() {
    _drafts.removeWhere((id, _) => id != _kNewRole && !_editableId(id));
  }

  void _resetAll() {
    setState(() {
      _drafts.clear();
      if (_editingId == _kNewRole) _editingId = widget.wide ? _firstRoleId : null;
      _editorKey = GlobalKey<_RoleEditorState>();
    });
  }

  Future<void> _saveAll() async {
    if (_saving) return;
    for (final e in _drafts.entries) {
      if (_roleById(e.key)?.isDefault ?? false) continue;
      if (e.value.name.trim().isEmpty) {
        _openEditor(e.key);
        GlitchToast.show(context, context.s.serverRolesNameRequired);
        return;
      }
    }
    setState(() => _saving = true);
    int? failed;
    try {
      for (final id in [..._drafts.keys]) {
        failed = id;
        final draft = _drafts[id];
        final role = id == _kNewRole ? null : _roleById(id);
        if (draft == null || (id != _kNewRole && role == null)) continue;
        final form = draft.toForm(role);
        final saved = role == null
            ? await api.createServerRole(widget.server.id, form)
            : await api.updateServerRole(widget.server.id, role.id, form);
        if (!mounted) return;
        setState(() {
          _drafts.remove(id);
          _onSaved(saved, isNew: role == null);
        });
      }
      failed = null;
      if (!widget.wide && mounted) setState(() => _editingId = null);
    } catch (e) {
      if (!mounted) return;
      GlitchToast.show(context, errorMessage(e));
      if (failed != null) _openEditor(failed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _onSaved(ServerRole role, {required bool isNew}) {
    if (isNew) {
      final everyoneAt = _roles.indexWhere((r) => r.isDefault);
      _roles = [..._roles]..insert(everyoneAt >= 0 ? everyoneAt : _roles.length, role);
      if (_editingId == _kNewRole) _editingId = role.id;
    } else {
      final i = _roles.indexWhere((r) => r.id == role.id);
      if (i >= 0) _roles = [..._roles]..[i] = role;
    }
    if (_editingId == role.id) _editorKey = GlobalKey<_RoleEditorState>();
  }

  Future<void> _delete(ServerRole role) async {
    if (_busy.contains(role.id)) return;
    final ok = await glitchConfirm(
      context,
      title: context.s.serverRolesDeleteTitle(role.name),
      body: context.s.serverRolesDeleteBody,
      confirmLabel: context.s.delete,
    );
    if (!ok || !mounted) return;

    setState(() => _busy.add(role.id));
    try {
      await api.deleteServerRole(widget.server.id, role.id);
      if (!mounted) return;
      setState(() {
        _roles = _roles.where((r) => r.id != role.id).toList();
        _drafts.remove(role.id);
        _busy.remove(role.id);
        if (_editingId == role.id) {
          _editingId = widget.wide ? _firstRoleId : null;
          _editorKey = GlobalKey<_RoleEditorState>();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(role.id));
      GlitchToast.show(context, errorMessage(e));
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final ordinary = _ordinary;
    if (oldIndex >= ordinary.length) return;
    if (newIndex > ordinary.length) newIndex = ordinary.length;
    if (newIndex > oldIndex) newIndex -= 1;
    final fixed = ordinary.takeWhile((r) => !r.canEdit).length;
    if (newIndex < fixed) newIndex = fixed;
    if (oldIndex == newIndex) return;

    final before = _roles;
    final moved = [...ordinary];
    moved.insert(newIndex, moved.removeAt(oldIndex));
    setState(() {
      _roles = [...moved, ..._roles.where((r) => r.isDefault)];
    });

    try {
      final page = await api.reorderServerRoles(
        widget.server.id, [for (final r in moved) r.id],
      );
      if (!mounted) return;
      setState(() {
        _roles = page.roles;
        _canCreate = page.canCreate;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _roles = before);
      GlitchToast.show(context, errorMessage(e));
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_loading && _roles.isEmpty) {
      return Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue));
    }
    if (_error != null && _roles.isEmpty) {
      return SettingsRetry(text: _error!, onRetry: _load);
    }

    final id = _editingId;
    if (id != null && id != _kNewRole && !_roles.any((r) => r.id == id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _editingId = widget.wide ? _firstRoleId : null;
          _editorKey = GlobalKey<_RoleEditorState>();
        });
      });
    }
    return Stack(
      children: [
        Positioned.fill(child: widget.wide ? _buildWide() : _buildNarrow()),
        UnsavedChangesDock(
          visible: hasUnsaved,
          wide: widget.wide,
          maxWidth: _kMaxFormWidth,
          barKey: _barKey,
          saving: _saving,
          onReset: _resetAll,
          onSave: _saveAll,
        ),
      ],
    );
  }

  Widget? _editor({required bool page}) {
    final id = _editingId;
    if (id == null) return null;
    final role = id == _kNewRole ? null : _roles.where((r) => r.id == id).firstOrNull;
    if (id != _kNewRole && role == null) return null;
    return _RoleEditor(
      key: _editorKey,
      server: widget.server,
      role: role,
      page: page,
      tab: _tab,
      onTab: (t) => setState(() => _tab = t),
      busy: role != null && _busy.contains(role.id),
      onBack: _closeEditor,
      draft: _drafts[id],
      onDraft: (d) => _onDraft(id, d),
      onDelete: role == null ? null : () => _delete(role),
      onViewAs: role == null || !_canViewAs ? null : () => _startViewAs(role),
    );
  }

  Widget _searchRow() => Row(
        children: [
          Expanded(
            child: GlitchSearchField(
              controller: _searchCtrl,
              hint: context.s.serverRolesSearch,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (_canCreate) ...[
            const SizedBox(width: 6),
            GlitchAddButton(onTap: () => _openEditor(_kNewRole)),
          ],
        ],
      );

  List<ServerRole> get _shown {
    // Совпадение — общее правило (core/text_match.dart).
    return _ordinary.where((r) => matchesQuery(_query, [r.name])).toList();
  }

  Widget _rolesList({required bool shrink, required bool chevron}) {
    final s = context.s;
    final everyone = _everyone;
    final shown = _shown;
    final canDrag = _query.trim().isEmpty;
    // Строка создаваемой роли — пока её открыли ИЛИ у неё есть черновик (ушли
    // к другой роли, не создав): иначе набранная роль пропала бы из виду, а
    // «Сохранить» всё равно бы её создал.
    final creating = _editingId == _kNewRole || _drafts.containsKey(_kNewRole);

    Widget? emptyLine;
    if (_ordinary.isEmpty && !creating) {
      emptyLine = _EmptyLine(text: s.serverRolesEmpty);
    } else if (shown.isEmpty && !creating) {
      emptyLine = _EmptyLine(text: s.serverRolesNotFound);
    }

    final list = ReorderableListView.builder(
      shrinkWrap: shrink,
      physics: shrink ? const NeverScrollableScrollPhysics() : null,
      buildDefaultDragHandles: false,
      itemCount: shown.length + (creating ? 1 : 0),
      onReorder: _reorder,
      itemBuilder: (context, i) {
        if (i >= shown.length) {
          return _RoleListItem.creating(
            key: const ValueKey('new-role'),
            chevron: chevron,
            selected: _editingId == _kNewRole,
            onTap: () => _openEditor(_kNewRole),
          );
        }
        final r = shown[i];
        return _RoleListItem(
          key: ValueKey(r.id),
          role: r,
          selected: r.id == _editingId,
          chevron: chevron,
          dragIndex: canDrag && r.canEdit ? i : null,
          onTap: () => _openEditor(r.id),
          onMenu: (pos) => _openRoleMenu(r, pos),
        );
      },
    );

    final bottom = [
      if (emptyLine != null) emptyLine,
      if (everyone != null) ...[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: chevron ? 14 : 10, vertical: 6),
          child: Divider(height: 1, color: GlitchColors.borderSoft),
        ),
        _RoleListItem(
          role: everyone,
          selected: everyone.id == _editingId,
          chevron: chevron,
          onTap: () => _openEditor(everyone.id),
          onMenu: (pos) => _openRoleMenu(everyone, pos),
        ),
      ],
    ];

    return Column(
      mainAxisSize: shrink ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (shrink) list else Expanded(child: list),
        ...bottom,
        if (!shrink) const SizedBox(height: 16),
      ],
    );
  }

  void _openRoleMenu(ServerRole role, Offset position) {
    showGlitchContextMenuAt<_RoleMenuAction>(
      context,
      position,
      [GlitchMenuItem(value: _RoleMenuAction.copyId, child: copyIdMenuRow(context, IdKind.role))],
      (action) {
        switch (action) {
          case _RoleMenuAction.copyId:
            copyId(context, role.id);
        }
      },
    );
  }

  Widget _buildWide() {
    final editor = _editor(page: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, SettingsTwoPane.topPad, 0, 0),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.header != null) ...[widget.header!, const SizedBox(height: 20)],
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _kRolesColumnWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _searchRow(),
                          const SizedBox(height: 10),
                          Expanded(child: _rolesList(shrink: false, chevron: false)),
                        ],
                      ),
                    ),
                    Expanded(child: editor ?? const SizedBox.shrink()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNarrow() {
    final editor = _editor(page: true);
    if (editor != null) return editor;
    final s = context.s;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
      children: [
        Text(
          s.serverRolesSubtitle,
          style: TextStyle(fontSize: 13.5, height: 1.35, color: GlitchColors.textSecond),
        ),
        const SizedBox(height: 16),
        _searchRow(),
        const SizedBox(height: 10),
        Text(
          s.serverRolesHint,
          style: TextStyle(fontSize: 12.5, height: 1.35, color: GlitchColors.textSecond),
        ),
        const SizedBox(height: 14),
        SettingsCard(child: _rolesList(shrink: true, chevron: true)),
      ],
    );
  }
}

class _EmptyLine extends StatelessWidget {
  final String text;

  const _EmptyLine({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, color: GlitchColors.textPrimary),
        ),
      );
}

class _RoleListItem extends StatelessWidget {
  final ServerRole? role;
  final bool selected;

  final bool chevron;

  final int? dragIndex;
  final VoidCallback? onTap;

  final ValueChanged<Offset>? onMenu;

  const _RoleListItem({
    super.key,
    required ServerRole this.role,
    required this.selected,
    required this.chevron,
    required this.onTap,
    this.dragIndex,
    this.onMenu,
  });

  const _RoleListItem.creating({
    super.key,
    required this.chevron,
    required this.selected,
    required this.onTap,
  })  : role = null,
        dragIndex = null,
        onMenu = null;

  @override
  Widget build(BuildContext context) {
    final r = role;
    return ClickableCursor(
      enabled: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        onSecondaryTapUp: onMenu == null ? null : (d) => onMenu!(d.globalPosition),
        onLongPressStart: onMenu == null ? null : (d) => onMenu!(d.globalPosition),
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: chevron ? EdgeInsets.zero : const EdgeInsets.only(bottom: 2),
          padding: EdgeInsets.symmetric(
            horizontal: chevron ? 14 : 10,
            vertical: chevron ? 13 : 8,
          ),
          decoration: BoxDecoration(
            color: selected && !chevron ? GlitchColors.bgInput : null,
            borderRadius: chevron ? null : BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              if (dragIndex != null)
                ReorderableDragStartListener(
                  index: dragIndex!,
                  child: ClickableCursor(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.drag_indicator_rounded,
                          size: 18, color: GlitchColors.textPrimary),
                    ),
                  ),
                ),
              RoleIcon(color: r?.color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  r?.name ?? context.s.serverRolesNew,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: GlitchColors.textPrimary,
                  ),
                ),
              ),
              if (chevron && onTap != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 20, color: GlitchColors.textPrimary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}


class _RoleDraft {
  final String name;
  final String? color;
  final bool hoist;
  final bool mentionable;
  final Perms perms;

  const _RoleDraft({
    required this.name,
    required this.color,
    required this.hoist,
    required this.mentionable,
    required this.perms,
  });

  factory _RoleDraft.of(ServerRole? r) => _RoleDraft(
        name: r?.name ?? '',
        color: r?.color,
        hoist: r?.hoist ?? false,
        mentionable: r?.mentionable ?? false,
        perms: r?.permissions ?? Perms.none,
      );

  bool sameAs(_RoleDraft o) =>
      name.trim() == o.name.trim() &&
      color == o.color &&
      hoist == o.hoist &&
      mentionable == o.mentionable &&
      perms == o.perms;

  ServerRoleForm toForm(ServerRole? role) {
    final everyone = role?.isDefault ?? false;
    return ServerRoleForm(
      name: everyone ? role!.name : name.trim(),
      color: everyone ? role!.color : color,
      permissions: perms,
      hoist: everyone ? role!.hoist : hoist,
      mentionable: everyone ? role!.mentionable : mentionable,
    );
  }
}


class _RoleEditor extends StatefulWidget {
  final ServerDetail server;

  final ServerRole? role;

  final bool page;

  final int tab;
  final ValueChanged<int> onTab;

  final bool busy;
  final VoidCallback onBack;

  final _RoleDraft? draft;

  final ValueChanged<_RoleDraft> onDraft;

  final VoidCallback? onDelete;

  final VoidCallback? onViewAs;

  const _RoleEditor({
    super.key,
    required this.server,
    required this.role,
    required this.page,
    required this.tab,
    required this.onTab,
    required this.busy,
    required this.onBack,
    required this.draft,
    required this.onDraft,
    required this.onDelete,
    required this.onViewAs,
  });

  @override
  State<_RoleEditor> createState() => _RoleEditorState();
}

class _RoleEditorState extends State<_RoleEditor> {
  late final TextEditingController _nameCtrl;

  late String? _color;
  late bool _hoist;
  late bool _mentionable;
  late Perms _perms;

  late String _savedName;


  bool get _isNew => widget.role == null;

  String get _liveName {
    final typed = _nameCtrl.text.trim();
    return typed.isEmpty ? _savedName : typed;
  }

  bool get _editable => _isNew || widget.role!.canEdit;

  bool get _isEveryone => widget.role?.isDefault ?? false;

  @override
  void initState() {
    super.initState();
    _savedName = widget.role?.name ?? '';
    final d = widget.draft ?? _RoleDraft.of(widget.role);
    _nameCtrl = TextEditingController(text: d.name)..addListener(_emit);
    _color = d.color;
    _hoist = d.hoist;
    _mentionable = d.mentionable;
    _perms = d.perms;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _update(VoidCallback change) {
    change();
    _emit();
  }

  void _emit() {
    if (!mounted) return;
    setState(() {}); // имя в шапке — живое
    widget.onDraft(_RoleDraft(
      name: _nameCtrl.text,
      color: _color,
      hoist: _hoist,
      mentionable: _mentionable,
      perms: _perms,
    ));
  }

  void _toggle(Perm p, bool on) {
    _update(() => _perms = on ? _perms.withPerm(p) : _perms.withoutPerm(p));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final mine = widget.server.myPermissions;
    final tabbed = !_isEveryone;
    final tab = tabbed ? widget.tab : 1;
    final role = widget.role;

    return ListView(
      padding: widget.page
          ? const EdgeInsets.fromLTRB(16, 18, 16, 110)
          : const EdgeInsets.fromLTRB(16, 0, 16, 110),
      children: [
        if (widget.page) ...[
          SettingsBackLine(label: s.serverSettingsRoles, onTap: widget.onBack),
          const SizedBox(height: 14),
        ],

        _EditorHeader(
          color: _color,
          title: _isNew
              ? s.serverRolesNew
              : (_isEveryone ? s.serverRolesEveryoneTitle : _liveName),
          subtitle: role == null ? null : s.membersCount(role.memberCount),
        ),
        const SizedBox(height: 16),

        if (!_editable) ...[
          SettingsNotice(text: s.serverRolesReadOnly),
          const SizedBox(height: 14),
        ],

        if (tabbed) ...[
          GlitchSegmentedControl(
            labels: [s.serverRolesTabDisplay, s.serverRolesPermissions],
            selected: widget.tab,
            onChanged: widget.onTab,
          ),
          const SizedBox(height: 18),
        ],

        if (tab == 0) ...[
          GlitchFormField(
            label: s.serverRolesName,
            controller: _nameCtrl,
            placeholder: s.serverRolesNameHint,
            maxLength: _kMaxRoleName,
            enabled: _editable,
          ),
          const SizedBox(height: 18),
          GlitchFormLabel(label: s.serverRolesColor, hint: s.serverRolesColorHint),
          const SizedBox(height: 8),
          GlitchColorChoice(
            value: _color,
            enabled: _editable,
            onPick: (c) => _update(() => _color = c),
          ),
          const SizedBox(height: 18),
          SettingsCard(
            child: Column(
              children: [
                GlitchSwitchRow(
                  label: s.serverRolesHoist,
                  description: s.serverRolesHoistDesc,
                  value: _hoist,
                  onChanged: _editable ? (v) => _update(() => _hoist = v) : null,
                ),
                GlitchSwitchRow(
                  label: s.serverRolesMentionable,
                  description: s.serverRolesMentionableDesc,
                  value: _mentionable,
                  onChanged:
                      _editable ? (v) => _update(() => _mentionable = v) : null,
                  border: false,
                ),
              ],
            ),
          ),
          if (widget.onDelete != null && !_isEveryone && _editable) ...[
            const SizedBox(height: 28),
            GlitchActionButton(
              label: s.serverRolesDeleteButton,
              onTap: widget.onDelete,
              destructive: true,
              loading: widget.busy,
            ),
          ],
          if (widget.onViewAs != null) ...[
            const SizedBox(height: 28),
            Divider(height: 1, color: GlitchColors.border),
            const SizedBox(height: 20),
            Text(
              s.viewAsTitle,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              s.viewAsDesc,
              style: TextStyle(fontSize: 12.5, height: 1.35, color: GlitchColors.textSecond),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: GlitchActionButton(
                label: s.viewAsButton,
                soft: true,
                compact: true,
                onTap: widget.onViewAs,
              ),
            ),
          ],
        ] else ...[
          Text(
            s.serverRolesPermissionsHint,
            style: TextStyle(fontSize: 12.5, height: 1.35, color: GlitchColors.textSecond),
          ),
          const SizedBox(height: 14),
          for (final group in kPermGroups) ...[
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
                  for (final p in group.$2)
                    // Выключенная роль не выдаёт право. Его может дать другая роль.
                    GlitchSwitchRow(
                      label: permLabel(context, p),
                      description: permDesc(context, p),
                      value: _perms.has(p),
                      onChanged: _editable && mine.can(p)
                          ? (v) => _toggle(p, v)
                          : null,
                      border: p != group.$2.last,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
        ],
      ],
    );
  }
}

class _EditorHeader extends StatelessWidget {
  final String? color;
  final String title;

  final String? subtitle;

  const _EditorHeader({required this.color, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        RoleIcon(color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: GlitchColors.textPrimary,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 13, color: GlitchColors.textSecond),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
