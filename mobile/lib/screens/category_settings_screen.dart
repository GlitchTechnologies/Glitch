import 'dart:async';

import 'package:flutter/material.dart';

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
import '../widgets/settings_window.dart';
import '../widgets/unsaved_changes_bar.dart';
import '../widgets/settings_two_pane.dart';
import 'place_permissions_section.dart';


enum CategorySettingsSection { general, permissions }

String _label(BuildContext context, CategorySettingsSection section) => switch (section) {
      CategorySettingsSection.general => context.s.roomSettingsGeneral,
      CategorySettingsSection.permissions => context.s.roomSettingsPermissions,
    };

IconData _icon(CategorySettingsSection section) => switch (section) {
      CategorySettingsSection.general => Icons.edit_outlined,
      CategorySettingsSection.permissions => Icons.shield_outlined,
    };

bool categorySettingsAvailable(RoomCategory c) =>
    c.permissions.can(Perm.manageRooms) || c.permissions.can(Perm.manageRoles);

bool categoryDeleteAvailable(RoomCategory c) => c.permissions.can(Perm.manageRooms);

List<CategorySettingsSection> _visibleSections(RoomCategory c) => [
      if (c.permissions.can(Perm.manageRooms)) CategorySettingsSection.general,
      if (c.permissions.can(Perm.manageRoles)) CategorySettingsSection.permissions,
    ];

Future<void> confirmDeleteCategory(BuildContext context, RoomCategory category) async {
  final s = context.s;
  final ok = await glitchConfirm(
    context,
    title: s.categoryDeleteTitle,
    body: s.categoryDeleteBody(category.name),
    confirmLabel: s.delete,
  );
  if (!ok || !context.mounted) return;
  try {
    await api.deleteCategory(category.serverId, category.id);
    if (context.mounted) GlitchToast.show(context, s.categoryDeleted, type: ToastType.success);
  } catch (e) {
    if (context.mounted) GlitchToast.show(context, errorMessage(e));
  }
}

SettingsWindowSpec<CategorySettingsSection> _spec(
  BuildContext context,
  RoomCategory category, {
  required VoidCallback onDelete,
  required VoidCallback onLostAccess,
}) {
  final s = context.s;
  return SettingsWindowSpec<CategorySettingsSection>(
    title: s.categorySettings,
    objectName: category.name,
    narrowHeader: Row(
      children: [
        Icon(Icons.folder_outlined, size: 26, color: GlitchColors.textSecond),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            category.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
          ),
        ),
      ],
    ),
    groups: [(null, _visibleSections(category))],
    label: (section) => _label(context, section),
    icon: _icon,
    content: (section, {header, sectionKey, wide = false}) => switch (section) {
      CategorySettingsSection.general =>
        CategoryGeneralSection(key: sectionKey, category: category, header: header),
      CategorySettingsSection.permissions => PlacePermissionsSection(
          key: sectionKey,
          serverId: category.serverId,
          placeId: category.id,
          isCategory: true,
          header: header,
          twoPane: wide,
          onLostAccess: onLostAccess,
        ),
    },
    danger: categoryDeleteAvailable(category)
        ? SettingsDangerAction(label: s.categorySettingsDelete, onTap: onDelete)
        : null,
  );
}

mixin _FreshCategory<T extends StatefulWidget> on State<T> {
  late RoomCategory category;
  StreamSubscription<ServerRoomEvent>? _eventSub;
  StreamSubscription<ServerGone>? _goneSub;
  StreamSubscription<int>? _rolesSub;

  RoomCategory get initialCategory;

  @override
  void initState() {
    super.initState();
    category = initialCategory;
    _eventSub = serverRail.roomEvents.listen((e) {
      if (e.chatId != category.id || !mounted) return;
      if (e.deleted) {
        _closeWindow();
        return;
      }
      final name = e.name;
      if (name != null) setState(() => category = category.withName(name));
    });
    _goneSub = serverRail.serverGone.listen((g) {
      if (g.id == category.serverId && mounted) _closeWindow();
    });
    _rolesSub = serverRail.roleChanges.listen((id) {
      if (id == category.serverId && mounted) _refresh();
    });
  }

  Future<void> _refresh() async {
    try {
      final fresh = await api.getCategory(category.serverId, category.id);
      if (!mounted) return;
      if (!categorySettingsAvailable(fresh)) {
        lostAccess();
        return;
      }
      setState(() => category = fresh);
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
    _eventSub?.cancel();
    _goneSub?.cancel();
    _rolesSub?.cancel();
    super.dispose();
  }

  Future<void> deleteCategory() => confirmDeleteCategory(context, category);
}

class CategorySettingsScreen extends StatefulWidget {
  final RoomCategory category;

  const CategorySettingsScreen({super.key, required this.category});

  @override
  State<CategorySettingsScreen> createState() => _CategorySettingsScreenState();
}

class _CategorySettingsScreenState extends State<CategorySettingsScreen>
    with ThemeAwareState<CategorySettingsScreen>, _FreshCategory<CategorySettingsScreen> {
  @override
  RoomCategory get initialCategory => widget.category;

  @override
  Widget build(BuildContext context) => SettingsWindowNarrow<CategorySettingsSection>(
        spec: _spec(context, category, onDelete: deleteCategory, onLostAccess: lostAccess),
      );
}

class CategorySettingsWideScreen extends StatefulWidget {
  final RoomCategory category;

  const CategorySettingsWideScreen({super.key, required this.category});

  @override
  State<CategorySettingsWideScreen> createState() => _CategorySettingsWideScreenState();
}

class _CategorySettingsWideScreenState extends State<CategorySettingsWideScreen>
    with ThemeAwareState<CategorySettingsWideScreen>, _FreshCategory<CategorySettingsWideScreen> {
  @override
  RoomCategory get initialCategory => widget.category;

  @override
  Widget build(BuildContext context) => SettingsWindowWide<CategorySettingsSection>(
        spec: _spec(context, category, onDelete: deleteCategory, onLostAccess: lostAccess),
      );
}


const int _kMaxName = 64;
const double _kMaxFormWidth = 560;

class CategoryGeneralSection extends StatefulWidget {
  final RoomCategory category;
  final Widget? header;

  const CategoryGeneralSection({super.key, required this.category, this.header});

  @override
  State<CategoryGeneralSection> createState() => CategoryGeneralSectionState();
}

class CategoryGeneralSectionState extends State<CategoryGeneralSection>
    with UnsavedGuard<CategoryGeneralSection> {
  final _barKey = GlobalKey<UnsavedChangesBarState>();
  late final TextEditingController _nameCtrl;
  late String _saved;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _saved = widget.category.name;
    _nameCtrl = TextEditingController(text: _saved)..addListener(_changed);
  }

  @override
  void didUpdateWidget(CategoryGeneralSection old) {
    super.didUpdateWidget(old);
    if (old.category.name != widget.category.name && !hasUnsaved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !hasUnsaved) _resetTo(widget.category.name);
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  bool get hasUnsaved => _nameCtrl.text.trim() != _saved;

  @override
  void warnUnsaved() => _barKey.currentState?.warn();

  void _changed() {
    if (mounted) setState(() {});
  }

  void _resetTo(String saved) {
    _saved = saved;
    if (_nameCtrl.text != saved) _nameCtrl.text = saved;
    _changed();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      GlitchToast.show(context, context.s.categoryCreateNameEmpty);
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await api.updateCategory(
        widget.category.serverId,
        widget.category.id,
        name: name,
      );
      if (!mounted) return;
      _resetTo(updated.name);
      GlitchToast.show(context, context.s.roomSaved, type: ToastType.success);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
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
                      label: s.categoryGeneralName,
                      controller: _nameCtrl,
                      placeholder: s.categoryCreateNameHint,
                      maxLength: _kMaxName,
                      enabled: !_saving,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        UnsavedChangesDock(
          visible: hasUnsaved,
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
