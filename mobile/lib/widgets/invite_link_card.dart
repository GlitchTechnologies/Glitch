import 'package:flutter/material.dart';

import '../core/glitch_link.dart';
import '../core/glitch_link_open.dart';
import '../core/l10n.dart';
import '../models/invite.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'glitch_action_button.dart';
import 'glitch_avatar.dart';
import 'message_card.dart';

class InviteLinkCard extends StatefulWidget {
  final String code;

  const InviteLinkCard({super.key, required this.code});

  @override
  State<InviteLinkCard> createState() => _InviteLinkCardState();
}

class _InviteLinkCardState extends State<InviteLinkCard> {
  InvitePreview? _preview;
  bool _loading = true;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _load(widget.code);
  }

  @override
  void didUpdateWidget(InviteLinkCard old) {
    super.didUpdateWidget(old);
    if (old.code != widget.code) {
      setState(() { _preview = null; _loading = true; });
      _load(widget.code);
    }
  }

  Future<void> _load(String code) async {
    final cache = api.invitePreviewCache;
    if (cache.containsKey(code)) {
      if (mounted) setState(() { _preview = cache[code]; _loading = false; });
      return;
    }
    try {
      final p = await api.getInvitePreview(code);
      cache[code] = p;
      if (mounted && widget.code == code) setState(() { _preview = p; _loading = false; });
    } catch (e) {
      final gone = e is ApiException && e.statusCode == 404;
      if (gone) cache[code] = null;
      if (mounted && widget.code == code) setState(() { _preview = null; _loading = false; });
    }
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await openGlitchLink(context, InviteLinkTarget(widget.code));
    } finally {
      api.invitePreviewCache.remove(widget.code);
      if (mounted) {
        setState(() => _opening = false);
        _load(widget.code);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _frame(SizedBox(
        height: 18, width: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.accentBlue),
      ));
    }
    final preview = _preview;
    final server = preview?.server;
    final group = preview?.group;
    if (server == null && group == null) {
      if (!api.invitePreviewCache.containsKey(widget.code)) return const SizedBox.shrink();
      return _frame(_body(
        label: context.s.inviteCardInvalid,
        avatar: Icon(Icons.link_off_rounded, color: GlitchColors.textSecond, size: 28),
        title: context.s.inviteCardInvalidHint,
        titleMuted: true,
        stats: const [],
        button: null,
      ));
    }

    final s = context.s;
    final String name;
    final Widget avatar;
    final List<(String, bool)> stats;
    final bool member;
    if (server != null) {
      name = server.name;
      member = server.alreadyMember;
      avatar = GlitchAvatar(
        initials: GlitchAvatar.initialsFromName(name),
        colorIndex: GlitchAvatar.colorFromNickname(name),
        size: 48,
        imageUrl: server.avatar != null ? api.mediaUrl(server.avatar!) : null,
        avatarSizes: server.avatarSizes,
        shape: AvatarShape.community,
      );
      stats = [(s.catalogOnline(server.onlineCount), true), (s.membersCount(server.memberCount), false)];
    } else {
      name = group!.name ?? s.group;
      member = group.alreadyMember;
      avatar = GlitchAvatar(
        initials: GlitchAvatar.initialsFromName(name),
        colorIndex: GlitchAvatar.colorFromNickname(name),
        size: 48,
        imageUrl: group.avatar != null ? api.mediaUrl(group.avatar!) : null,
        avatarSizes: group.avatarSizes,
        shape: AvatarShape.group,
      );
      stats = [(s.membersCount(group.memberCount), false)];
    }
    return _frame(_body(
      label: server != null ? s.inviteCardServer : s.inviteCardGroup,
      avatar: avatar,
      title: name,
      titleMuted: false,
      stats: stats,
      button: GlitchActionButton(
        label: member ? s.inviteCardOpen : s.inviteCardJoin,
        onTap: _open,
        loading: _opening,
        compact: true,
      ),
    ));
  }

  Widget _frame(Widget child) => MessageCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: child,
      );

  Widget _body({
    required String label,
    required Widget avatar,
    required String title,
    required bool titleMuted,
    required List<(String, bool)> stats,
    required Widget? button,
  }) {
    return IntrinsicWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: GlitchColors.textSecond,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              avatar,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: titleMuted ? GlitchColors.textSecond : GlitchColors.textPrimary,
                        fontWeight: titleMuted ? FontWeight.w500 : FontWeight.w700,
                        fontSize: titleMuted ? 13.5 : 15,
                      ),
                    ),
                    if (stats.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 10,
                        runSpacing: 2,
                        children: [for (final (text, online) in stats) _Stat(text: text, online: online)],
                      ),
                    ],
                  ],
                ),
              ),
              if (button != null) ...[
                const SizedBox(width: 12),
                button,
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String text;
  final bool online;

  const _Stat({required this.text, required this.online});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online ? GlitchColors.online : GlitchColors.textHint,
            ),
          ),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(color: GlitchColors.textSecond, fontSize: 12.5)),
        ],
      );
}
