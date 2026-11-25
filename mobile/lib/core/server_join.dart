import 'package:flutter/material.dart';
import 'avatar_color.dart';
import 'l10n.dart';
import '../models/server.dart' show ServerDetail, ServerInvitePreview;
import '../providers/server_provider.dart' show serverRail;
import '../services/api_service.dart';
import '../widgets/glitch_avatar.dart';
import '../widgets/glitch_bar_buttons.dart';
import '../widgets/glitch_dialog.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/server_profile_card.dart';
import '../widgets/server_rail.dart' show revealServerInRail;

Future<void> joinServerAndShow(
  BuildContext context,
  ServerInvitePreview preview,
  Future<ServerDetail> Function() join,
) async {
  final root = Navigator.of(context, rootNavigator: true);
  if (preview.alreadyMember) {
    revealServerInRail(root, preview.serverId);
    return;
  }
  try {
    final agreed = await _confirmJoin(context, preview);
    if (!agreed) return;
    final joined = await join();
    serverRail.addCreated(joined);
    // ⚠️ Никакого openAdaptive здесь НЕТ намеренно. Полоса — обрамление, а
    // не место каркаса: выбор сервера сам меняет содержимое левой колонки, а
    // канал в центре откроет колонка каналов (правило «в сообществе всегда
    // открыт канал», server_channels_view.dart::_ensureRoomOpen). Снять
    // нужно только то, что лежит маршрутами поверх (на телефоне — страница
    // каталога или переписка со ссылкой), иначе выбор случился бы под ними.
    revealServerInRail(root, joined.id);
  } catch (e) {
    if (context.mounted) GlitchToast.show(context, errorMessage(e));
  }
}

Future<bool> _confirmJoin(BuildContext context, ServerInvitePreview preview) async {
  final joined = await showGlitchCardDialog<bool>(
    context,
    builder: (ctx) => ServerProfileCard(
      framed: false,
      name: preview.name,
      description: preview.description,
      memberCount: preview.memberCount,
      createdAt: preview.createdAt,
      games: [for (final g in preview.games) g.name],
      banner: ServerBanner(
        url: preview.banner,
        sizes: preview.bannerSizes,
        fallbackColor: parseAvatarColor(preview.avatarColor),
      ),
      avatar: GlitchAvatar(
        initials: GlitchAvatar.initialsFromName(preview.name),
        size: ServerProfileCard.kCardAvatarSize,
        colorIndex: GlitchAvatar.colorFromNickname(preview.name),
        imageUrl: preview.avatar != null ? api.mediaUrl(preview.avatar!) : null,
        avatarSizes: preview.avatarSizes,
        shape: AvatarShape.community,
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GlitchPlainButton(label: ctx.s.cancel, onTap: () => Navigator.pop(ctx, false)),
          const SizedBox(width: 8),
          GlitchFilledButton(label: ctx.s.serverJoinButton, onTap: () => Navigator.pop(ctx, true)),
        ],
      ),
    ),
  );
  return joined == true;
}
