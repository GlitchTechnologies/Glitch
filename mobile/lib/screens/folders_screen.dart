import 'package:flutter/material.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../models/folder.dart';
import '../providers/folders_provider.dart';
import '../services/api_service.dart';
import '../widgets/glitch_dialog.dart';
import '../widgets/glitch_menu.dart';
import '../widgets/glitch_pressable.dart' show ClickableCursor;
import '../widgets/glitch_toast.dart';
import '../providers/theme_provider.dart';
import 'folder_edit_screen.dart';


class FolderListBody extends StatefulWidget {
  const FolderListBody({super.key});

  @override
  State<FolderListBody> createState() => _FolderListBodyState();
}

class _FolderListBodyState extends State<FolderListBody> with ThemeAwareState<FolderListBody> {
  final _provider = FoldersProvider();

  @override
  void initState() {
    super.initState();
    _provider.addListener(_onChange);
    _provider.load();
  }

  @override
  void dispose() {
    _provider.removeListener(_onChange);
    _provider.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _openEditor({ChatFolder? folder}) async {
    final saved = await openFolderEditor(context, folder: folder);
    if (saved && mounted) await _provider.load();
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    try {
      await _provider.reorder(oldIndex, newIndex);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    }
  }

  Future<void> _delete(ChatFolder folder) async {
    final confirmed = await glitchConfirm(context,
        title: context.s.folderDeleteTitle,
        body: context.s.folderDeleteBody,
        confirmLabel: context.s.delete);
    if (!confirmed || !mounted) return;
    try {
      await _provider.remove(folder.id);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_provider.loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue)),
      );
    }
    final folders = _provider.folders;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: GlitchColors.bgCard,
            border: Border.all(color: GlitchColors.borderCard),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              _allChatsRow(),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: folders.length,
                onReorder: _reorder,
                itemBuilder: (_, i) => _folderRow(folders[i], i),
              ),
              _createRow(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
          child: Text(context.s.foldersHint,
              style: TextStyle(fontSize: 13, color: GlitchColors.textPrimary, height: 1.4)),
        ),
      ],
    );
  }

  Widget _folderIcon() => SizedBox(
        width: 34, height: 34,
        child: Icon(Icons.folder_outlined, color: GlitchColors.textPrimary, size: 22),
      );

  Widget _allChatsRow() => _row(
        leading: _folderIcon(),
        label: context.s.foldersAll,
        border: true,
      );

  Widget _folderRow(ChatFolder folder, int index) => _row(
        key: ValueKey(folder.id),
        leading: _folderIcon(),
        label: folder.name,
        subtitle: context.s.folderChatsCount(folder.chatIds.length),
        border: true,
        onTap: () => _openEditor(folder: folder),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.drag_handle_rounded, color: GlitchColors.textPrimary, size: 22),
              ),
            ),
            GlitchMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: GlitchColors.textPrimary, size: 20),
              size: 32,
              onSelected: (v) => v == 'edit' ? _openEditor(folder: folder) : _delete(folder),
              itemBuilder: (_) => [
                GlitchMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit_rounded, color: GlitchColors.textPrimary, size: 18),
                    const SizedBox(width: 10),
                    Text(context.s.edit, style: TextStyle(color: GlitchColors.textPrimary, fontSize: 15)),
                  ]),
                ),
                GlitchMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    const Icon(Icons.delete_outline_rounded, color: GlitchColors.error, size: 18),
                    const SizedBox(width: 10),
                    Text(context.s.delete, style: const TextStyle(color: GlitchColors.error, fontSize: 15)),
                  ]),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _createRow() => _row(
        leading: Icon(Icons.add_rounded, color: GlitchColors.accentBlue, size: 24),
        label: context.s.foldersCreate,
        labelColor: GlitchColors.accentBlue,
        border: false,
        onTap: _openEditor,
      );

  Widget _row({
    Key? key,
    required Widget leading,
    required String label,
    required bool border,
    String? subtitle,
    Color? labelColor,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ClickableCursor(
      key: key,
      enabled: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: GlitchColors.bgCard,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          foregroundDecoration: border
              ? BoxDecoration(border: Border(bottom: BorderSide(color: GlitchColors.border)))
              : null,
          child: Row(
            children: [
              SizedBox(width: 34, child: Center(child: leading)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          color: labelColor ?? GlitchColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        )),
                    if (subtitle != null)
                      Text(subtitle, style: TextStyle(fontSize: 12.5, color: GlitchColors.textSecond)),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }
}
