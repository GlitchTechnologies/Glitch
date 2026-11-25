import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'adaptive_sheet.dart';
import 'author_tag.dart';
import 'glitch_avatar.dart';
import 'glitch_menu.dart' show GlitchPopupSide;
import 'member_card.dart' show kMemberCardWidth;

Future<void> showWebhookCard(
  BuildContext anchorContext, {
  required String name,
  String? avatar,
  Rect? anchorRect,
}) =>
    openAdaptivePopup(
      anchorContext,
      width: kMemberCardWidth,
      side: GlitchPopupSide.right,
      anchorRect: anchorRect,
      builder: (close, _) => _WebhookCardView(name: name, avatar: avatar),
    );

class _WebhookCardView extends StatelessWidget {
  final String name;
  final String? avatar;

  const _WebhookCardView({required this.name, this.avatar});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlitchAvatar(
            initials: GlitchAvatar.initialsFromName(name),
            size: 72,
            colorIndex: GlitchAvatar.colorFromNickname(name),
            imageUrl: avatar != null ? api.mediaUrl(avatar!) : null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
                ),
              ),
              const SizedBox(width: 8),
              AuthorTag(s.authorTagWebhook),
            ],
          ),
          const SizedBox(height: 10),
          Text(s.webhookCardHint, style: TextStyle(fontSize: 13.5, color: GlitchColors.textPrimary)),
        ],
      ),
    );
  }
}
