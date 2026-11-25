import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import '../core/adaptive_open.dart';
import '../core/shell_controller.dart' show ShellSlot;
import '../widgets/local_image_web.dart' if (dart.library.io) '../widgets/local_image_native.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/avatar_service.dart';
import '../widgets/glitch_avatar.dart';
import '../widgets/glitch_pressable.dart';
import '../widgets/image_edit_overlay.dart';
import '../widgets/glitch_search_field.dart';
import '../widgets/glitch_toast.dart';
import 'chat_screen.dart';
import '../providers/theme_provider.dart';
import '../widgets/glitch_icon_button.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> with ThemeAwareState<CreateGroupScreen> {
  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final Map<String, SearchUserItem> _selected = {};
  List<SearchUserItem> _foundUsers = [];
  bool _searching = false;
  bool _creating = false;
  String? _searchError;
  XFile? _avatarFile;

  Future<void> _pickAvatar() async {
    final file = await pickAndCropAvatar(context, shape: AvatarShape.group);
    if (file != null && mounted) setState(() => _avatarFile = file);
  }

  Future<void> _search(String query) async {
    final q = query.trim().replaceFirst('@', '');
    if (q.isEmpty) {
      setState(() { _foundUsers = []; _searchError = null; });
      return;
    }
    setState(() { _searching = true; _searchError = null; _foundUsers = []; });
    try {
      final result = await api.searchAll(q);
      if (mounted) setState(() { _foundUsers = result.users; _searching = false; });
    } on ApiException {
      if (mounted) setState(() { _searchError = context.s.createGroupNotFound; _searching = false; });
    }
  }

  void _toggle(SearchUserItem user) {
    setState(() {
      if (_selected.containsKey(user.nickname)) {
        _selected.remove(user.nickname);
      } else {
        _selected[user.nickname] = user;
      }
    });
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      GlitchToast.show(context, context.s.createGroupNameEmpty);
      return;
    }
    setState(() => _creating = true);
    try {
      var chat = await api.createGroupChat(name);
      for (final user in _selected.values) {
        await api.addMember(chat.id, user.nickname);
      }
      if (_avatarFile != null) {
        chat = await api.uploadChatAvatar(chat.id, _avatarFile!, mimeFromFileName(_avatarFile!.name));
      }
      if (!mounted) return;
      openAdaptiveReplacing(
        context,
        slotKey: chatSlotKey(chat.id),
        builder: (_) => ChatScreen(
          chatId: chat.id,
          chatName: name,
          colorIndex: GlitchAvatar.colorFromNickname(name),
          isGroup: true,
          avatarUrl: chat.avatar != null ? api.mediaUrl(chat.avatar!) : null,
          avatarSizes: chat.avatarSizes,
        ),
      );
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _selected.values.toList();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 16, 12),
              child: Row(
                children: [
                  GlitchIconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded, color: GlitchColors.accentBlue),
                    onTap: () => closeAdaptive(context, slot: ShellSlot.list),
                  ),
                  Text(context.s.createGroupTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
                  const Spacer(),
                  if (_selected.isNotEmpty)
                    Text(context.s.selectedCount(_selected.length), style: TextStyle(fontSize: 12.5, color: GlitchColors.textSecond)),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Row(
                children: [
                  EditableAvatar(
                    size: 60,
                    shape: AvatarShape.group,
                    onTap: _pickAvatar,
                    child: Container(
                      width: 60, height: 60,
                      decoration: BoxDecoration(color: GlitchColors.bgInput, border: Border.all(color: GlitchColors.border), borderRadius: AvatarShape.group.borderRadius(60)),
                      child: _avatarFile != null
                          ? AvatarShape.group.clip(size: 58, child: localImage(_avatarFile!.path, fit: BoxFit.cover))
                          : Icon(Icons.add_photo_alternate_outlined, color: GlitchColors.textSecond, size: 26),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      style: TextStyle(color: GlitchColors.textPrimary, fontSize: 17),
                      decoration: InputDecoration(
                        hintText: context.s.createGroupNameHint,
                        border: UnderlineInputBorder(borderSide: BorderSide(color: GlitchColors.border)),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: GlitchColors.border)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: GlitchColors.accentBlue)),
                        filled: false,
                        contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (chosen.isNotEmpty)
              SizedBox(
                height: 88,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  itemCount: chosen.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final m = chosen[i];
                    return GestureDetector(
                      onTap: () => _toggle(m),
                      child: SizedBox(
                        width: 58,
                        child: Column(
                          children: [
                            Stack(
                              children: [
                                GlitchAvatar(
                                  initials: GlitchAvatar.initialsFromName(m.displayName),
                                  size: 50,
                                  colorIndex: GlitchAvatar.colorFromNickname(m.nickname),
                                  imageUrl: m.avatar != null ? api.mediaUrl(m.avatar!) : null,
                                  avatarSizes: m.avatarSizes,
                                ),
                                Positioned(
                                  right: -1, top: -1,
                                  child: Container(
                                    width: 19, height: 19,
                                    decoration: BoxDecoration(color: GlitchColors.bgChip, shape: BoxShape.circle, border: Border.all(color: GlitchColors.bg, width: 2)),
                                    child: Center(child: Text('✕', style: TextStyle(fontSize: 10, color: GlitchColors.textSecond))),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              m.displayName.split(' ').first,
                              style: TextStyle(fontSize: 11.5, color: GlitchColors.textSecond),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
              child: GlitchSearchField(
                controller: _searchCtrl,
                hint: context.s.createGroupAddMembers,
                onChanged: _search,
                loading: _searching,
                height: 44,
              ),
            ),

            Expanded(
              child: _foundUsers.isNotEmpty
                  ? ListView(children: _foundUsers.map(_userTile).toList())
                  : _searchError != null
                      ? Center(child: Text(_searchError!, style: TextStyle(color: GlitchColors.textSecond, fontSize: 14)))
                      : Center(child: Text(context.s.createGroupSearchHint, style: TextStyle(color: GlitchColors.textHint, fontSize: 14))),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
              child: GlitchPressable(
                onTap: _creating ? null : _create,
                child: Container(
                  width: double.infinity, height: 54,
                  decoration: BoxDecoration(
                    gradient: GlitchColors.gradientAccent,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: _creating
                      ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text(context.s.createGroupSubmit, style: const TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w600)),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _userTile(SearchUserItem user) {
    final checked = _selected.containsKey(user.nickname);
    return GestureDetector(
      onTap: () => _toggle(user),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        child: Row(
          children: [
            GlitchAvatar(
              initials: GlitchAvatar.initialsFromName(user.displayName),
              size: 46,
              colorIndex: GlitchAvatar.colorFromNickname(user.nickname),
              imageUrl: user.avatar != null ? api.mediaUrl(user.avatar!) : null,
              avatarSizes: user.avatarSizes,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.displayName, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary)),
                  Text('@${user.nickname}', style: TextStyle(fontSize: 13, color: GlitchColors.textSecond, height: 1.4)),
                ],
              ),
            ),
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: checked ? GlitchColors.accentBlue : Colors.transparent,
                border: Border.all(color: checked ? GlitchColors.accentBlue : GlitchColors.border, width: 1.6),
              ),
              child: checked ? const Icon(Icons.check_rounded, color: Colors.white, size: 15) : null,
            ),
          ],
        ),
      ),
    );
  }
}
