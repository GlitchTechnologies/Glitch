import 'package:flutter/material.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../models/chat.dart';
import '../models/folder.dart';
import '../providers/chats_provider.dart';
import '../widgets/adaptive_sheet.dart';
import '../widgets/glitch_avatar.dart';
import '../widgets/glitch_bar_buttons.dart';
import '../widgets/glitch_dialog.dart';
import '../widgets/glitch_pressable.dart' show ClickableCursor;
import '../providers/theme_provider.dart';
import 'folder_chats_picker_screen.dart';
import '../widgets/glitch_icon_button.dart';



const int kFolderNameMaxLength = 64;

const double _kWideChatsHeight = 260;

Future<bool> openFolderEditor(BuildContext context, {ChatFolder? folder}) async {
  final saved = await openAdaptiveForm<bool>(
    context,
    narrowBuilder: (_) => FolderEditScreen(folder: folder),
    wideBuilder: (_) => _FolderEditDialog(folder: folder),
  );
  return saved == true;
}


class FolderDraft extends ChangeNotifier {
  final ChatFolder? folder;
  final TextEditingController name;
  Set<int> chatIds;

  List<ChatListItem> chats = [];
  bool saving = false;

  String? error;

  bool _disposed = false;

  FolderDraft(this.folder)
      : name = TextEditingController(text: folder?.name ?? ''),
        chatIds = {...?folder?.chatIds} {
    _loadChats();
  }

  bool get isNew => folder == null;

  List<ChatListItem> get selectedChats => chats.where((c) => chatIds.contains(c.id)).toList();

  Future<void> _loadChats() async {
    try {
      final list = await api.getChats();
      if (_disposed) return;
      chats = list;
      _notify();
    } catch (_) {/* без списка форма всё равно работает: имя правится, состав — через выбор */}
  }

  void setChats(Set<int> ids) {
    chatIds = ids;
    _notify();
  }

  void removeChat(int id) {
    chatIds = {...chatIds}..remove(id);
    _notify();
  }

  Future<bool> save({required String emptyName}) async {
    if (saving) return false; // двойное нажатие
    final title = name.text.trim();
    if (title.isEmpty) {
      error = emptyName;
      _notify();
      return false;
    }
    saving = true;
    error = null;
    _notify();
    try {
      final existing = folder;
      if (existing == null) {
        await api.createFolder(title, chatIds.toList());
      } else {
        await api.updateFolder(existing.id, name: title, chatIds: chatIds.toList());
      }
      return true;
    } catch (e) {
      error = errorMessage(e);
      return false;
    } finally {
      saving = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    name.dispose();
    super.dispose();
  }
}


class FolderEditorFields extends StatelessWidget {
  final FolderDraft draft;
  final double? maxChatsHeight;

  const FolderEditorFields({super.key, required this.draft, this.maxChatsHeight});

  Future<void> _pickChats(BuildContext context) async {
    final picked = await pickFolderChats(context, draft.chatIds);
    if (picked != null) draft.setChats(picked);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) {
        final selected = draft.selectedChats;
        final rows = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < selected.length; i++)
              _ChatRow(chat: selected[i], border: i < selected.length - 1, onRemove: draft.removeChat),
          ],
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlitchDialogField(
              controller: draft.name,
              hint: s.folderNameHint,
              maxLength: kFolderNameMaxLength,
              autofocus: draft.isNew,
            ),
            const SizedBox(height: 16),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: GlitchColors.bgCard,
                border: Border.all(color: GlitchColors.border),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AddRow(border: selected.isNotEmpty, onTap: () => _pickChats(context)),
                  if (selected.isNotEmpty)
                    maxChatsHeight == null
                        ? rows
                        : ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: maxChatsHeight!),
                            child: SingleChildScrollView(child: rows),
                          ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
              child: Text(
                draft.chatIds.isEmpty ? s.folderEmpty : s.folderChatsCount(draft.chatIds.length),
                style: TextStyle(fontSize: 13, color: GlitchColors.textPrimary),
              ),
            ),
            if (draft.error != null) ...[
              const SizedBox(height: 12),
              Text(draft.error!, style: const TextStyle(color: GlitchColors.error, fontSize: 14)),
            ],
          ],
        );
      },
    );
  }
}

class _AddRow extends StatelessWidget {
  final bool border;
  final VoidCallback onTap;
  const _AddRow({required this.border, required this.onTap});

  @override
  Widget build(BuildContext context) => ClickableCursor(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: border
                ? BoxDecoration(border: Border(bottom: BorderSide(color: GlitchColors.border)))
                : null,
            child: Row(
              children: [
                SizedBox(width: 26, child: Center(child: Icon(Icons.add_rounded, color: GlitchColors.accentBlue, size: 22))),
                const SizedBox(width: 14),
                Text(context.s.folderAddChats,
                    style: TextStyle(fontSize: 16, color: GlitchColors.accentBlue, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      );
}

class _ChatRow extends StatelessWidget {
  final ChatListItem chat;
  final bool border;
  final ValueChanged<int> onRemove;
  const _ChatRow({required this.chat, required this.border, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final name = ChatsProvider.chatName(chat);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
      decoration: border
          ? BoxDecoration(border: Border(bottom: BorderSide(color: GlitchColors.border)))
          : null,
      child: Row(
        children: [
          GlitchAvatar(
            initials: GlitchAvatar.initialsFromName(name),
            size: 38,
            colorIndex: GlitchAvatar.colorFromNickname(name),
            imageUrl: chat.avatar != null ? api.mediaUrl(chat.avatar!) : null,
            avatarSizes: chat.avatarSizes,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15.5, color: GlitchColors.textPrimary, fontWeight: FontWeight.w500)),
          ),
          GlitchIconButton(
            icon: Icon(Icons.close_rounded, color: GlitchColors.textPrimary, size: 20),
            onTap: () => onRemove(chat.id),
          ),
        ],
      ),
    );
  }
}


class _FolderEditDialog extends StatefulWidget {
  final ChatFolder? folder;
  const _FolderEditDialog({this.folder});

  @override
  State<_FolderEditDialog> createState() => _FolderEditDialogState();
}

class _FolderEditDialogState extends State<_FolderEditDialog> {
  late final _draft = FolderDraft(widget.folder);

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await _draft.save(emptyName: context.s.folderNameEmpty);
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return GlitchDialog(
      title: _draft.isNew ? s.folderNew : s.folderEditTitle,
      content: SizedBox(
        width: 440,
        child: FolderEditorFields(draft: _draft, maxChatsHeight: _kWideChatsHeight),
      ),
      actions: [
        GlitchPlainButton(label: s.cancel, onTap: () => Navigator.pop(context)),
        ListenableBuilder(
          listenable: _draft,
          builder: (_, __) => GlitchFilledButton(label: s.save, loading: _draft.saving, onTap: _save),
        ),
      ],
    );
  }
}


class FolderEditScreen extends StatefulWidget {
  final ChatFolder? folder;
  const FolderEditScreen({super.key, this.folder});

  @override
  State<FolderEditScreen> createState() => _FolderEditScreenState();
}

class _FolderEditScreenState extends State<FolderEditScreen> with ThemeAwareState<FolderEditScreen> {
  late final _draft = FolderDraft(widget.folder);

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await _draft.save(emptyName: context.s.folderNameEmpty);
    if (ok && mounted) Navigator.pop(context, true); // true — список папок надо перечитать
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GlitchColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 8, 14),
              child: Row(
                children: [
                  GlitchIconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded, color: GlitchColors.accentBlue),
                    onTap: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(_draft.isNew ? context.s.folderNew : context.s.folderEditTitle,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
                  ),
                  ListenableBuilder(
                    listenable: _draft,
                    builder: (context, _) => _draft.saving
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.accentBlue),
                            ),
                          )
                        : TextButton(
                            onPressed: _save,
                            child: Text(context.s.save,
                                style: TextStyle(color: GlitchColors.accentBlue, fontSize: 16, fontWeight: FontWeight.w600)),
                          ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [FolderEditorFields(draft: _draft)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
