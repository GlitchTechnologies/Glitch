import 'package:flutter/material.dart';
import '../core/group_exit.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/avatar_service.dart';
import '../models/chat.dart';
import '../widgets/glitch_action_button.dart';
import '../widgets/glitch_avatar.dart';
import '../widgets/image_edit_overlay.dart';
import '../widgets/glitch_toast.dart';
import 'group_members_screen.dart';
import 'group_admins_screen.dart';
import 'group_invites_screen.dart';
import '../providers/theme_provider.dart';
import '../widgets/glitch_pressable.dart';
import '../widgets/glitch_icon_button.dart';

class GroupSettingsScreen extends StatefulWidget {
  final Chat chat;
  final void Function(Chat)? onUpdated;

  const GroupSettingsScreen({super.key, required this.chat, this.onUpdated});

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> with ThemeAwareState<GroupSettingsScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  bool _saving = false;
  bool _uploadingAvatar = false;
  late Chat _chat;

  @override
  void initState() {
    super.initState();
    _chat = widget.chat;
    _nameCtrl = TextEditingController(text: _chat.name ?? '');
    _descCtrl = TextEditingController(text: _chat.description ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  bool get _isOwner {
    final me = authService.currentUser;
    if (me == null) return false;
    return _chat.members.where((m) => m.id == me.id).firstOrNull?.role == 'owner';
  }

  bool get _isAdmin {
    final me = authService.currentUser;
    if (me == null) return false;
    final role = _chat.members.where((m) => m.id == me.id).firstOrNull?.role;
    return role == 'admin' || role == 'owner';
  }

  Future<void> _changeAvatar() async {
    final file = await pickAndCropAvatar(context, shape: AvatarShape.group);
    if (file == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      final updated = await api.uploadChatAvatar(_chat.id, file, mimeFromFileName(file.name));
      if (!mounted) return;
      setState(() => _chat = updated);
      widget.onUpdated?.call(updated);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      GlitchToast.show(context, context.s.groupNameEmpty);
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await api.updateChat(
        _chat.id,
        name: name,
        description: _descCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _chat = updated);
      widget.onUpdated?.call(updated);
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) GlitchToast.show(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openAdmins() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupAdminsScreen(
        chat: _chat,
        onUpdated: (c) => setState(() => _chat = c),
      )),
    );
  }

  void _openInvites() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupInvitesScreen(chat: _chat)),
    );
  }

  void _openMembers() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupMembersScreen(
        chat: _chat,
        onUpdated: (c) => setState(() => _chat = c),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adminCount = _chat.members.where((m) => m.role == 'admin' || m.role == 'owner').length;
    final memberCount = _chat.members.length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 16, 14),
              child: Row(
                children: [
                  GlitchIconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded, color: GlitchColors.accentBlue),
                    onTap: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(context.s.edit, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
                  ),
                  if (_isAdmin)
                    TextButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.accentBlue))
                          : Text(context.s.done, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: GlitchColors.accentBlue)),
                    ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: EditableAvatar(
                        size: 90,
                        shape: AvatarShape.group,
                        busy: _uploadingAvatar,
                        onTap: _isAdmin ? _changeAvatar : null,
                        child: Container(
                          width: 90, height: 90,
                          decoration: BoxDecoration(
                            borderRadius: AvatarShape.group.borderRadius(90),
                            gradient: _chat.avatar == null ? GlitchColors.gradientAccent : null,
                          ),
                          child: _chat.avatar != null
                              ? AvatarShape.group.clip(
                                  size: 90,
                                  child: Image.network(api.mediaUrl(_chat.avatar!), fit: BoxFit.cover),
                                )
                              : Center(
                                  child: Text(
                                    GlitchAvatar.initialsFromName(_chat.name ?? context.s.group),
                                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -1),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Container(
                      decoration: BoxDecoration(
                        color: GlitchColors.bgCard,
                        border: Border.all(color: GlitchColors.borderCard),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: TextField(
                        controller: _nameCtrl,
                        enabled: _isAdmin,
                        style: TextStyle(color: GlitchColors.textPrimary, fontSize: 15.5),
                        decoration: InputDecoration(
                          hintText: context.s.groupNameLabel,
                          hintStyle: TextStyle(color: GlitchColors.textHint),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          filled: true,
                          fillColor: Colors.transparent,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(context.s.groupNameHint, style: TextStyle(fontSize: 12.5, color: GlitchColors.textSecond)),
                    ),

                    const SizedBox(height: 18),

                    Container(
                      decoration: BoxDecoration(
                        color: GlitchColors.bgCard,
                        border: Border.all(color: GlitchColors.borderCard),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: TextField(
                        controller: _descCtrl,
                        enabled: _isAdmin,
                        maxLines: 3,
                        minLines: 1,
                        style: TextStyle(color: GlitchColors.textPrimary, fontSize: 15.5),
                        decoration: InputDecoration(
                          hintText: context.s.description,
                          hintStyle: TextStyle(color: GlitchColors.textHint),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          filled: true,
                          fillColor: Colors.transparent,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(context.s.groupDescriptionHint, style: TextStyle(fontSize: 12.5, color: GlitchColors.textSecond)),
                    ),

                    const SizedBox(height: 24),

                    Container(
                      decoration: BoxDecoration(
                        color: GlitchColors.bgCard,
                        border: Border.all(color: GlitchColors.borderCard),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        children: [
                          _NavRow(icon: Icons.star_rounded, label: context.s.admins, count: adminCount, onTap: _openAdmins),
                          Divider(height: 1, color: GlitchColors.borderSoft, indent: 60),
                          _NavRow(icon: Icons.group_rounded, label: context.s.members, count: memberCount, onTap: _openMembers),
                          Divider(height: 1, color: GlitchColors.borderSoft, indent: 60),
                          _NavRow(icon: Icons.link_rounded, label: context.s.invitesTitle, onTap: _openInvites),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    GlitchActionButton(
                      label: _isOwner ? context.s.groupDeleteBtn : context.s.groupLeaveBtn,
                      onTap: () => _isOwner
                          ? confirmDeleteGroup(context, _chat.id)
                          : confirmLeaveGroup(context, _chat.id),
                      destructive: true,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? count;
  final VoidCallback onTap;

  const _NavRow({required this.icon, required this.label, this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClickableCursor(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              SizedBox(width: 32, height: 32, child: Icon(icon, color: GlitchColors.textPrimary, size: 22)),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: TextStyle(fontSize: 15.5, color: GlitchColors.textPrimary))),
              if (count != null) ...[
                Text('$count', style: TextStyle(fontSize: 15, color: GlitchColors.textSecond)),
                const SizedBox(width: 6),
              ],
              Icon(Icons.chevron_right_rounded, color: GlitchColors.textHint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
