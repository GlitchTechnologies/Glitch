import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'glitch_action_button.dart';
import 'glitch_avatar.dart';
import 'glitch_toast.dart';

class BlockedUsersList extends StatefulWidget {
  const BlockedUsersList({super.key});

  @override
  State<BlockedUsersList> createState() => _BlockedUsersListState();
}

class _BlockedUsersListState extends State<BlockedUsersList> {
  List<BlockedUser> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final users = await api.getBlockedUsers();
      if (mounted) setState(() { _users = users; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unblock(BlockedUser user) async {
    try {
      await api.unblockUser(user.nickname);
      if (!mounted) return;
      setState(() => _users.removeWhere((u) => u.id == user.id));
      GlitchToast.show(context, context.s.contactUnblockedTitle, type: ToastType.success);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: GlitchColors.accentBlue)),
      );
    }
    if (_users.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(context.s.blockedUsersEmpty, style: TextStyle(color: GlitchColors.textSecond, fontSize: 14)),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: GlitchColors.bgCard,
        border: Border.all(color: GlitchColors.borderCard),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          for (int i = 0; i < _users.length; i++)
            _row(_users[i], border: i < _users.length - 1),
        ],
      ),
    );
  }

  Widget _row(BlockedUser user, {bool border = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: border ? BoxDecoration(border: Border(bottom: BorderSide(color: GlitchColors.border))) : null,
      child: Row(
        children: [
          GlitchAvatar(
            initials: GlitchAvatar.initialsFromName(user.displayName),
            size: 44,
            colorIndex: GlitchAvatar.colorFromNickname(user.nickname),
            imageUrl: user.avatar != null ? api.mediaUrl(user.avatar!) : null,
            avatarSizes: user.avatarSizes,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: GlitchColors.textPrimary)),
                const SizedBox(height: 1),
                Text('@${user.nickname}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: GlitchColors.textSecond)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GlitchActionButton(
            label: context.s.contactUnblock,
            soft: true,
            compact: true,
            onTap: () => _unblock(user),
          ),
        ],
      ),
    );
  }
}
