import 'package:flutter/material.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/chat.dart';
import '../models/invite.dart';
import '../models/user.dart';
import '../widgets/adaptive_sheet.dart';
import '../widgets/glitch_avatar.dart';
import '../widgets/glitch_menu.dart';
import '../widgets/glitch_pressable.dart' show ClickableCursor;
import '../widgets/glitch_search_field.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/invite_sheet.dart';
import '../providers/theme_provider.dart';
import '../widgets/glitch_icon_button.dart';

class GroupMembersScreen extends StatefulWidget {
  final Chat chat;
  final void Function(Chat)? onUpdated;

  const GroupMembersScreen({super.key, required this.chat, this.onUpdated});

  @override
  State<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<GroupMembersScreen> with ThemeAwareState<GroupMembersScreen> {
  late Chat _chat;

  bool _searching = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _chat = widget.chat;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Совпадение — одно правило на списки участников (ChatMember.matchesQuery).
  List<ChatMember> get _filteredMembers =>
      _chat.members.where((m) => m.matchesQuery(_query)).toList();

  void _startSearch() {
    setState(() => _searching = true);
  }

  void _stopSearch() {
    _searchCtrl.clear();
    setState(() { _searching = false; _query = ''; });
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

  Future<void> _removeMember(ChatMember member) async {
    try {
      await api.removeMember(_chat.id, member.id);
      final updated = await api.getChat(_chat.id);
      if (!mounted) return;
      setState(() => _chat = updated);
      widget.onUpdated?.call(updated);
    } on ApiException catch (e) {
      if (mounted) GlitchToast.show(context, e.message);
    }
  }

  Future<void> _toggleAdmin(ChatMember member) async {
    final newRole = member.role == 'admin' ? 'member' : 'admin';
    try {
      final updated = await api.setMemberRole(_chat.id, member.id, newRole);
      if (!mounted) return;
      setState(() => _chat = updated);
      widget.onUpdated?.call(updated);
    } on ApiException catch (e) {
      if (mounted) GlitchToast.show(context, e.message);
    }
  }

  Future<void> _showAddMember() async {
    final searchCtrl = TextEditingController();
    User? foundUser;
    bool searching = false;
    String? searchError;

    await showAdaptiveSheet(
      context,
      title: context.s.membersAddTitle,
      bodyBuilder: (ctx, setModal) {
        Future<void> search(String q) async {
          final nick = q.trim().replaceFirst('@', '');
          if (nick.isEmpty) { setModal(() { foundUser = null; searchError = null; }); return; }
          setModal(() { searching = true; foundUser = null; searchError = null; });
          try {
            final user = await api.getUser(nick);
            setModal(() { foundUser = user; searching = false; });
          } catch (_) {
            setModal(() { searchError = context.s.membersNotFound; searching = false; });
          }
        }

        Future<void> add() async {
          if (foundUser == null) return;
          try {
            final updated = await api.addMember(_chat.id, foundUser!.nickname);
            if (mounted) {
              Navigator.pop(ctx);
              setState(() => _chat = updated);
              widget.onUpdated?.call(updated);
              GlitchToast.show(context, context.s.membersAdded(foundUser!.displayName), type: ToastType.success);
            }
          } on ApiException catch (e) {
            if (mounted) GlitchToast.show(context, e.message);
          }
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
                  loading: searching,
                ),
              ),
              const SizedBox(height: 12),
              if (foundUser != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                  child: Row(
                    children: [
                      GlitchAvatar(
                        initials: GlitchAvatar.initialsFromName(foundUser!.displayName),
                        size: 46,
                        colorIndex: GlitchAvatar.colorFromNickname(foundUser!.nickname),
                        imageUrl: foundUser!.avatar != null ? api.mediaUrl(foundUser!.avatar!) : null,
                        avatarSizes: foundUser!.avatarSizes,
                      ),
                      const SizedBox(width: 13),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(foundUser!.displayName, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: GlitchColors.textPrimary)),
                          Text('@${foundUser!.nickname}', style: TextStyle(fontSize: 13, color: GlitchColors.textSecond)),
                        ],
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                  child: ClickableCursor(
                    child: GestureDetector(
                      onTap: add,
                      child: Container(
                        width: double.infinity, height: 50,
                        decoration: BoxDecoration(gradient: GlitchColors.gradientAccent, borderRadius: BorderRadius.circular(14)),
                        child: Center(child: Text(context.s.membersAddButton, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
                      ),
                    ),
                  ),
                ),
              ] else if (searchError != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(searchError!, style: TextStyle(color: GlitchColors.textSecond, fontSize: 14)),
                ),
              const SizedBox(height: 18),
            ],
          ),
        );
      },
    );
    searchCtrl.dispose();
  }

  Future<void> _inviteByLink() =>
      showInviteSheet(context, InviteTarget.group(_chat.id, _chat.name ?? context.s.group));

  @override
  Widget build(BuildContext context) {
    final me = authService.currentUser;
    final members = _filteredMembers;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 8, 14),
                  child: _searching ? _buildSearchBar() : _buildNormalHeader(),
                ),

                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
                    children: [
                      if (!_searching) Container(
                        decoration: BoxDecoration(
                          color: GlitchColors.bgCard,
                          border: Border.all(color: GlitchColors.borderCard),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          children: [
                            ClickableCursor(child: GestureDetector(
                              onTap: _showAddMember,
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38, height: 38,
                                      decoration: BoxDecoration(color: GlitchColors.accentDark, shape: BoxShape.circle),
                                      child: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                                    ),
                                    const SizedBox(width: 13),
                                    Text(context.s.membersAddTitle, style: TextStyle(fontSize: 15.5, color: GlitchColors.accentBlue, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            )),
                            Divider(height: 1, color: GlitchColors.borderMuted),
                            ClickableCursor(child: GestureDetector(
                              onTap: _inviteByLink,
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38, height: 38,
                                    decoration: BoxDecoration(color: GlitchColors.bgInput, shape: BoxShape.circle),
                                    child: Icon(Icons.link_rounded, color: GlitchColors.accentBlue, size: 20),
                                  ),
                                  const SizedBox(width: 13),
                                  Text(context.s.membersInviteLink, style: TextStyle(fontSize: 15.5, color: GlitchColors.accentBlue, fontWeight: FontWeight.w600)),
                                ],
                              ),
                              ),
                            )),
                          ],
                        ),
                      ),

                      if (!_searching) const SizedBox(height: 24),

                      if (!_searching) Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 10),
                        child: Text(
                          context.s.membersCount(_chat.members.length).toUpperCase(),
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: GlitchColors.textHint),
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
                            for (int i = 0; i < members.length; i++)
                              _memberRow(
                                members[i],
                                border: i < members.length - 1,
                                isMe: members[i].id == me?.id,
                              showMenu: _isAdmin && members[i].id != me?.id && members[i].role != 'owner',
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _memberRow(ChatMember member, {bool border = false, bool isMe = false, bool showMenu = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: border ? BoxDecoration(border: Border(bottom: BorderSide(color: GlitchColors.borderMuted))) : null,
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
                Row(
                  children: [
                    Text(
                      isMe ? '${member.displayName} (${context.s.you})' : member.displayName,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: GlitchColors.textPrimary),
                    ),
                    if (member.role == 'admin' || member.role == 'owner') ...[
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(color: GlitchColors.accentBlue.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                        child: Text(context.s.adminBadge, style: TextStyle(fontSize: 11, color: GlitchColors.accentBlue)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Text(context.s.memberBadge, style: TextStyle(fontSize: 12.5, color: GlitchColors.textSecond)),
              ],
            ),
          ),
          if (showMenu)
            GlitchMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded, size: 22),
              size: 34,
              onSelected: (value) {
                if (value == 'toggle_admin') _toggleAdmin(member);
                if (value == 'remove') _removeMember(member);
              },
              itemBuilder: (ctx) => [
                if (_isOwner)
                  GlitchMenuItem<String>(
                    value: 'toggle_admin',
                    child: Row(children: [
                      Icon(
                        member.role == 'admin' ? Icons.star_border_rounded : Icons.star_rounded,
                        color: member.role == 'admin' ? GlitchColors.textDim : GlitchColors.accentBlue,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        member.role == 'admin' ? context.s.membersRemoveAdmin : context.s.membersMakeAdmin,
                        style: TextStyle(fontSize: 15, color: GlitchColors.textPrimary),
                      ),
                    ]),
                  ),
                GlitchMenuItem<String>(
                  value: 'remove',
                  child: Row(children: [
                    const Icon(Icons.person_remove_rounded, color: GlitchColors.error, size: 20),
                    const SizedBox(width: 12),
                    Text(context.s.membersKick, style: const TextStyle(fontSize: 15, color: GlitchColors.error)),
                  ]),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildNormalHeader() {
    return Row(
      children: [
        GlitchIconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: GlitchColors.accentBlue),
          onTap: () => Navigator.pop(context),
        ),
        Expanded(
          child: Text(context.s.membersTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
        ),
        GlitchIconButton(
          icon: Icon(Icons.search_rounded, color: GlitchColors.accentBlue),
          onTap: _startSearch,
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Row(
      children: [
        GlitchIconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: GlitchColors.accentBlue),
          onTap: _stopSearch,
        ),
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(color: GlitchColors.textPrimary, fontSize: 16),
            decoration: InputDecoration(
              hintText: context.s.membersSearch,
              hintStyle: TextStyle(color: GlitchColors.textHint, fontSize: 16),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: true,
              fillColor: Colors.transparent,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        if (_query.isNotEmpty)
          GlitchIconButton(
            icon: Icon(Icons.close_rounded, size: 20),
            onTap: () {
              _searchCtrl.clear();
              setState(() => _query = '');
            },
          ),
      ],
    );
  }

}
