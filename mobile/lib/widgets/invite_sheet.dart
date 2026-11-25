import 'package:flutter/material.dart';
import '../core/copy_actions.dart';
import '../core/glitch_link.dart';
import '../core/l10n.dart';
import '../models/chat.dart';
import '../models/invite.dart';
import '../providers/chats_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'adaptive_sheet.dart';
import 'glitch_avatar.dart';
import 'glitch_pressable.dart';
import 'glitch_search_field.dart';
import 'glitch_toast.dart';
import 'glitch_icon_button.dart';

Future<void> showInviteSheet(BuildContext context, InviteTarget target) async {
  final searchCtrl = TextEditingController();

  List<Invite> invites = [];
  String? vanityCode;
  int vanityUses = 0;
  List<ChatListItem> chats = [];
  final Set<int> sentTo = {};
  String query = '';
  bool loading = true;
  bool creating = false;
  String? error;
  bool started = false;

  await showAdaptiveSheet(
    context,
    title: context.s.inviteTitle(target.name),
    bodyBuilder: (ctx, setModal) {
      Invite? current() => invites.isEmpty ? null : invites.first;

      Future<void> createLink({bool silent = false}) async {
        if (creating) return;
        setModal(() => creating = true);
        try {
          final made = await api.createInvite(target);
          if (!ctx.mounted) return;
          setModal(() {
            invites = [made, ...invites];
            creating = false;
          });
        } catch (e) {
          if (!ctx.mounted) return;
          setModal(() => creating = false);
          if (!silent) GlitchToast.show(ctx, errorMessage(e));
        }
      }

      Future<void> load() async {
        try {
          final results = await Future.wait([
            api.getInvites(target),
            api.getChats(),
            if (target.isServer) api.getVanity(target.id),
          ]);
          if (!ctx.mounted) return;
          setModal(() {
            invites = results[0] as List<Invite>;
            chats = results[1] as List<ChatListItem>;
            if (target.isServer) {
              final vanity = results[2] as Vanity;
              vanityCode = vanity.code;
              vanityUses = vanity.uses;
            }
            loading = false;
          });
          if (invites.isEmpty) await createLink(silent: true);
        } catch (e) {
          if (!ctx.mounted) return;
          setModal(() {
            error = errorMessage(e);
            loading = false;
          });
        }
      }

      if (!started) {
        started = true;
        load();
      }

      Future<void> sendTo(ChatListItem chat) async {
        final inv = current();
        if (inv == null) return;
        try {
          await api.sendMessage(chat.id, type: 'text', text: inviteLink(inv.code));
          if (!ctx.mounted) return;
          setModal(() => sentTo.add(chat.id));
        } catch (e) {
          if (ctx.mounted) GlitchToast.show(ctx, errorMessage(e));
        }
      }

      // Совпадение — одно правило на все списки чатов (ChatListItem.matchesQuery).
      final visibleChats = chats.where((c) => c.matchesQuery(query)).toList();

      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator())
            else if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Text(error!, style: TextStyle(fontSize: 14, color: GlitchColors.textSecond)),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: GlitchSearchField(
                  controller: searchCtrl,
                  hint: ctx.s.inviteSearchHint,
                  onChanged: (v) => setModal(() => query = v),
                  height: 44,
                ),
              ),
              const SizedBox(height: 10),
              if (visibleChats.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Text(ctx.s.inviteNoChats,
                      style: TextStyle(fontSize: 14, color: GlitchColors.textHint)),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: visibleChats.length,
                    itemBuilder: (_, i) => _ChatRow(
                      chat: visibleChats[i],
                      sent: sentTo.contains(visibleChats[i].id),
                      onTap: () => sendTo(visibleChats[i]),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Divider(color: GlitchColors.borderSoft, height: 18),
              if (current() != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(18, 0, 18, vanityCode != null ? 8 : 18),
                  child: _InviteLinkRow(
                    code: current()!.code,
                    life: current()!.daysLeft == null
                        ? ctx.s.inviteForever
                        : ctx.s.inviteDaysLeft(current()!.daysLeft!),
                    uses: current()!.uses,
                  ),
                ),
              if (vanityCode != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  child: _InviteLinkRow(code: vanityCode!, life: ctx.s.inviteForever, uses: vanityUses),
                ),
            ],
          ],
        ),
      );
    },
  );
  searchCtrl.dispose();
}

class _ChatRow extends StatelessWidget {
  final ChatListItem chat;
  final bool sent;
  final VoidCallback onTap;

  const _ChatRow({required this.chat, required this.sent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = ChatsProvider.chatName(chat);
    final nick = chat.otherNickname;
    final subtitle = chat.type == 'group'
        ? context.s.group
        : (nick != null && nick.isNotEmpty ? '@$nick' : null);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      child: Row(
        children: [
          GlitchAvatar(
            initials: GlitchAvatar.initialsFromName(name),
            size: 38,
            colorIndex: GlitchAvatar.colorFromNickname(chat.otherNickname ?? name),
            imageUrl: chat.avatar != null ? api.mediaUrl(chat.avatar!) : null,
            avatarSizes: chat.avatarSizes,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, color: GlitchColors.textPrimary),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: GlitchColors.textSecond, height: 1.4),
                  ),
              ],
            ),
          ),
          GlitchPressable(
            onTap: sent ? null : onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: sent ? Colors.transparent : GlitchColors.accentBlue,
                border: sent ? Border.all(color: GlitchColors.border) : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                sent ? context.s.inviteSent : context.s.inviteSend,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: sent ? GlitchColors.textSecond : Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteLinkRow extends StatelessWidget {
  final String code;
  final String life;
  final int uses;

  const _InviteLinkRow({required this.code, required this.life, required this.uses});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: GlitchColors.bgCard,
        border: Border.all(color: GlitchColors.borderCard),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inviteLinkShort(code),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  '$life · ${context.s.inviteUses(uses)}',
                  style: TextStyle(fontSize: 12, color: GlitchColors.textHint),
                ),
              ],
            ),
          ),
          GlitchIconButton(
            icon: Icon(Icons.copy_rounded, size: 18, color: GlitchColors.accentBlue),
            onTap: () => copyInviteLink(context, code),
          ),
        ],
      ),
    );
  }
}
