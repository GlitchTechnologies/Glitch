import 'package:flutter/material.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../models/chat.dart';
import '../providers/chats_provider.dart';
import '../widgets/adaptive_sheet.dart';
import '../widgets/glitch_avatar.dart';
import '../widgets/glitch_bar_buttons.dart';
import '../widgets/glitch_dialog.dart' show GlitchCheckMark;
import '../widgets/glitch_search_field.dart';
import '../widgets/glitch_icon_button.dart';


const double _kWideListHeight = 380;

Future<Set<int>?> pickFolderChats(BuildContext context, Set<int> initial) {
  var picked = {...initial};
  return openAdaptivePicker<Set<int>>(
    context,
    title: context.s.folderPickTitle,
    narrowBuilder: (_) => FolderChatsPickerScreen(initialSelected: initial),
    wideBodyBuilder: (ctx, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FolderChatsPickerBody(
          initialSelected: initial,
          onChanged: (v) => picked = v,
          maxListHeight: _kWideListHeight,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GlitchPlainButton(label: ctx.s.cancel, onTap: () => Navigator.pop(ctx)),
              const SizedBox(width: 8),
              GlitchFilledButton(label: ctx.s.done, onTap: () => Navigator.pop(ctx, picked)),
            ],
          ),
        ),
      ],
    ),
  );
}


class FolderChatsPickerScreen extends StatefulWidget {
  final Set<int> initialSelected;
  const FolderChatsPickerScreen({super.key, this.initialSelected = const {}});

  @override
  State<FolderChatsPickerScreen> createState() => _FolderChatsPickerScreenState();
}

class _FolderChatsPickerScreenState extends State<FolderChatsPickerScreen> {
  late Set<int> _selected = {...widget.initialSelected};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GlitchColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 14, 8),
              child: Row(
                children: [
                  GlitchIconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded, color: GlitchColors.accentBlue, size: 22),
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(context.s.folderPickTitle,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: Text(context.s.done,
                        style: TextStyle(color: GlitchColors.accentBlue, fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FolderChatsPickerBody(
                initialSelected: widget.initialSelected,
                onChanged: (v) => _selected = v,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class FolderChatsPickerBody extends StatefulWidget {
  final Set<int> initialSelected;
  final ValueChanged<Set<int>> onChanged;
  final double? maxListHeight;

  const FolderChatsPickerBody({
    super.key,
    required this.initialSelected,
    required this.onChanged,
    this.maxListHeight,
  });

  @override
  State<FolderChatsPickerBody> createState() => _FolderChatsPickerBodyState();
}

class _FolderChatsPickerBodyState extends State<FolderChatsPickerBody> {
  final _searchCtrl = TextEditingController();
  List<ChatListItem> _chats = [];
  late final Set<int> _selected = {...widget.initialSelected};
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final chats = await api.getChats();
      if (!mounted) return;
      setState(() { _chats = chats; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Совпадение — одно правило на все списки чатов (ChatListItem.matchesQuery).
  List<ChatListItem> get _filtered => _chats.where((c) => c.matchesQuery(_query)).toList();

  String _subtitle(ChatListItem chat) {
    if (chat.type == 'group') return context.s.group;
    return chat.otherNickname != null ? '@${chat.otherNickname}' : '';
  }

  void _toggle(int chatId) {
    setState(() {
      if (!_selected.remove(chatId)) _selected.add(chatId);
    });
    widget.onChanged({..._selected});
  }

  @override
  Widget build(BuildContext context) {
    final constrained = widget.maxListHeight != null;
    final filtered = _filtered;
    final list = _loading
        ? Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue))
        : filtered.isEmpty
            ? Center(child: Text(context.s.chatsNothingFound, style: TextStyle(color: GlitchColors.textSecond)))
            : ListView.builder(
                shrinkWrap: constrained,
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final chat = filtered[i];
                  final name = ChatsProvider.chatName(chat);
                  return ListTile(
                    onTap: () => _toggle(chat.id),
                    leading: GlitchAvatar(
                      initials: GlitchAvatar.initialsFromName(name),
                      size: 46,
                      colorIndex: GlitchAvatar.colorFromNickname(name),
                      imageUrl: chat.avatar != null ? api.mediaUrl(chat.avatar!) : null,
                      avatarSizes: chat.avatarSizes,
                    ),
                    title: Text(name,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: GlitchColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                    subtitle: Text(_subtitle(chat),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: GlitchColors.textSecond, fontSize: 13)),
                    trailing: GlitchCheckMark(value: _selected.contains(chat.id)),
                  );
                },
              );
    return Column(
      mainAxisSize: constrained ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: GlitchSearchField(
            controller: _searchCtrl,
            hint: context.s.chatsSearch,
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        const SizedBox(height: 8),
        if (constrained)
          SizedBox(height: widget.maxListHeight, child: list)
        else
          Expanded(child: list),
      ],
    );
  }
}
