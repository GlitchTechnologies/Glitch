import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/l10n.dart';
import '../providers/locale_provider.dart';
import '../theme/app_theme.dart';
import 'banner_header_art.dart';
import 'banner_picture.dart';
import 'selectable_content.dart';
import 'user_banner.dart' show kUserBannerAspect;

const int kServerBannerWidth = 1600;
const int kServerBannerHeight = 900;

const double kServerBannerAspect = kServerBannerWidth / kServerBannerHeight;

const double kServerBannerStripAspect = kUserBannerAspect;

class ServerBanner extends StatelessWidget {
  final String? url;
  final Map<String, String>? sizes;
  final Uint8List? localBytes;
  final Color? fallbackColor;

  const ServerBanner({
    super.key,
    this.url,
    this.sizes,
    this.localBytes,
    this.fallbackColor,
  });

  @override
  Widget build(BuildContext context) => BannerPicture(
        url: url,
        sizes: sizes,
        localBytes: localBytes,
        fallback: ColoredBox(color: fallbackColor ?? GlitchColors.bgInput),
      );
}

class ServerProfileCard extends StatelessWidget {
  final String name;
  final String? description;
  final Widget banner;

  final Widget avatar;
  final int? memberCount;
  final DateTime? createdAt;

  final List<String> games;
  final Widget? footer;

  final bool framed;

  static const double kCardAvatarSize = 64;

  const ServerProfileCard({
    super.key,
    required this.name,
    required this.banner,
    required this.avatar,
    this.description,
    this.memberCount,
    this.createdAt,
    this.games = const [],
    this.footer,
    this.framed = true,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final created = createdAt;
    final desc = description?.trim() ?? '';

    return Container(
      clipBehavior: framed ? Clip.antiAlias : Clip.none,
      decoration: framed
          ? BoxDecoration(
              color: GlitchColors.bgCard,
              border: Border.all(color: GlitchColors.borderCard),
              borderRadius: BorderRadius.circular(16),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          BannerHeaderArt(
            bannerAspect: kServerBannerAspect,
            banner: banner,
            avatar: avatar,
            avatarSize: kCardAvatarSize,
            avatarShape: AvatarShape.community,
            ringColor: GlitchColors.bgCard,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
                ),
                if (memberCount != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    s.membersCount(memberCount!),
                    style: TextStyle(fontSize: 13.5, color: GlitchColors.textSecond),
                  ),
                ],
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SelectableContent(
                    fillWidth: true,
                    child: Text(
                      desc,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      textWidthBasis: TextWidthBasis.longestLine,
                      style: TextStyle(fontSize: 14.5, height: 1.35, color: GlitchColors.textPrimary),
                    ),
                  ),
                ],
                if (games.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ServerGameChips(names: games),
                ],
                if (created != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    s.serverCreatedAt(
                      DateFormat.yMMMM(localeProvider.locale.languageCode).format(created),
                    ),
                    style: TextStyle(fontSize: 13, color: GlitchColors.textSecond),
                  ),
                ],
                if (footer != null) ...[
                  const SizedBox(height: 16),
                  footer!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ServerGameChips extends StatelessWidget {
  final List<String> names;

  const ServerGameChips({super.key, required this.names});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final name in names)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: GlitchColors.bgInput,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(name, style: TextStyle(fontSize: 13, color: GlitchColors.textPrimary)),
          ),
      ],
    );
  }
}
