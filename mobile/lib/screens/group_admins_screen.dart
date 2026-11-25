import 'package:flutter/material.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/chat.dart';
import '../widgets/adaptive_sheet.dart';
import '../widgets/glitch_avatar.dart';
import '../widgets/glitch_search_field.dart';
import '../widgets/glitch_toast.dart';
import '../providers/theme_provider.dart';
import '../core/text_match.dart';
import '../widgets/glitch_icon_button.dart';

class GroupAdminsScreen extends StatefulWidget {
  final Chat chat;
  final void Function(Chat)? onUpdated;

  const GroupAdminsScreen({super.key, required this.chat, this.onUpdated});

  @override
  State<GroupAdminsScreen> createState() => _GroupAdminsScreenState();
}

class _GroupAdminsScreenState extends State<GroupAdminsScreen> with ThemeAwareState<GroupAdminsScreen> {
  late Chat _chat;

  @override
  void initState() {
    super.initState();
    _chat = widget.chat;
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

  List<ChatMember> get _admins =>
      _chat.members.where((m) => m.role == 'admin' || m.role == 'owner').toList();

  Future<void> _setRole(int userId, String role) async {
    final previous = _chat;
    final newMembers = _chat.members
        .map((m) => m.id == userId
            ? ChatMember(id: m.id, nickname: m.nickname, displayName: m.displayName, avatar: m.avatar, role: role, isOnline: m.isOnline, presenceStatus: m.presenceStatus, lastSeen: m.lastSeen)
            : m)
        .toList();
    setState(() => _chat = Chat(
          id: _chat.id, type: _chat.type, name: _chat.name,
          description: _chat.description, avatar: _chat.avatar, members: newMembers,
        ));
    widget.onUpdated?.call(_chat);

    try {
      final updated = await api.setMemberRole(previous.id, userId, role);
      if (!mounted) return;
      setState(() => _chat = updated);
      widget.onUpdated?.call(updated);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _chat = previous);
        widget.onUpdated?.call(previous);
        GlitchToast.show(context, e.message);
      }
    }
  }

  Future<void> _showAddAdmin() async {
    final searchCtrl = TextEditingController();
    List<ChatMember> results = [];

    await showAdaptiveSheet(
      context,
      title: context.s.adminsAdd,
      bodyBuilder: (ctx, setModal) {
        void search(String q) {
          if (normalizeTextQuery(q).isEmpty) {
            setModal(() => results = []);
            return;
          }
          final adminIds = _admins.map((a) => a.id).toSet();
          setModal(() {
            // Совпадение — одно правило на списки участников (ChatMember.matchesQuery).
            results = _chat.members.where((m) => !adminIds.contains(m.id) && m.matchesQuery(q)).toList();
          });
        }

        Future<void> promote(ChatMember member) async {
          Navigator.pop(ctx);
          await _setRole(member.id, 'admin');
          if (mounted) GlitchToast.show(context, context.s.adminsPromoted(member.displayName), type: ToastType.success);
        }

        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: GlitchSearchField(
                  controller: searchCtrl,
                  hint: context.s.adminsSearchHint,
                  onChanged: search,
                  autofocus: true,
                ),
              ),
              const SizedBox(height: 8),
              if (results.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: results.length,
                    itemBuilder: (_, i) {
                      final m = results[i];
                      return ListTile(
                        leading: GlitchAvatar(
                          initials: GlitchAvatar.initialsFromName(m.displayName),
                          size: 44,
                          colorIndex: GlitchAvatar.colorFromNickname(m.nickname),
                          imageUrl: m.avatar != null ? api.mediaUrl(m.avatar!) : null,
                          avatarSizes: m.avatarSizes,
                        ),
                        title: Text(m.displayName,
                            style: TextStyle(color: GlitchColors.textPrimary, fontWeight: FontWeight.w500)),
                        subtitle: Text('@${m.nickname}',
                            style: TextStyle(color: GlitchColors.textSecond, fontSize: 13)),
                        trailing: Container(
                          width: 30, height: 30,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: GlitchColors.accentBlue, width: 1.5)),
                          child: Icon(Icons.add_rounded, color: GlitchColors.accentBlue, size: 18),
                        ),
                        onTap: () => promote(m),
                      );
                    },
                  ),
                )
              else if (searchCtrl.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(context.s.adminsNotFound, style: TextStyle(color: GlitchColors.textHint, fontSize: 14)),
                ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
    searchCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final admins = _admins;
    final me = authService.currentUser;

    return Scaffold(
      backgroundColor: GlitchColors.bg,
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
                    child: Text(context.s.adminsTitle,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 14),
                    child: Text(
                      context.s.adminsDescription,
                      style: TextStyle(fontSize: 13, color: GlitchColors.textSecond, height: 1.45),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 10),
                    child: Text(
                      context.s.adminsCount(admins.length).toUpperCase(),
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
                          letterSpacing: 0.4, color: GlitchColors.textHint),
                    ),
                  ),

                  Container(
                    decoration: BoxDecoration(
                      color: GlitchColors.bgCard,
                      border: Border.all(color: GlitchColors.borderCard),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: [
                        for (int i = 0; i < admins.length; i++)
                          _memberRow(
                            admins[i],
                            border: i < admins.length - 1,
                            trailing: _isAdmin && admins[i].id != me?.id && admins[i].role != 'owner'
                                ? GestureDetector(
                                    onTap: () => _setRole(admins[i].id, 'member'),
                                    child: Container(
                                      height: 30,
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(
                                          border: Border.all(color: GlitchColors.border),
                                          borderRadius: BorderRadius.circular(9)),
                                      child: Center(
                                        child: Text(context.s.adminsRemove,
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                                color: GlitchColors.textDim)),
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                      ],
                    ),
                  ),

                  if (_isOwner) ...[
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _showAddAdmin,
                      child: Container(
                        decoration: BoxDecoration(
                          color: GlitchColors.bgCard,
                          border: Border.all(color: GlitchColors.borderCard),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(children: [
                          Container(
                            width: 38, height: 38,
                            decoration: BoxDecoration(
                                color: GlitchColors.accentDark, shape: BoxShape.circle),
                            child: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 13),
                          Text(context.s.adminsAdd,
                              style: TextStyle(fontSize: 15.5, color: GlitchColors.accentBlue,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberRow(ChatMember member, {bool border = false, Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: border
          ? BoxDecoration(border: Border(bottom: BorderSide(color: GlitchColors.borderMuted)))
          : null,
      child: Row(
        children: [
          GlitchAvatar(
            initials: GlitchAvatar.initialsFromName(member.displayName),
            size: 44,
            colorIndex: GlitchAvatar.colorFromNickname(member.nickname),
            imageUrl: member.avatar != null ? api.mediaUrl(member.avatar!) : null,
            avatarSizes: member.avatarSizes,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.displayName,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: GlitchColors.textPrimary)),
                const SizedBox(height: 1),
                Text(
                  member.role == 'owner' ? context.s.roleOwner : context.s.roleAdmin,
                  style: TextStyle(fontSize: 12.5, color: GlitchColors.textSecond),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

}
