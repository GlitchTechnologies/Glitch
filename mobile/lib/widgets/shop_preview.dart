import 'package:flutter/material.dart';

import '../core/collectibles.dart';
import '../core/l10n.dart';
import '../core/name_color.dart';
import '../models/collectible.dart';
import '../models/shop.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'glitch_avatar.dart';
import 'glitch_action_button.dart';
import 'member_card.dart';
import 'profile_parts.dart';
import 'server_roster_panel.dart' show RosterRowFrame;
import 'user_banner.dart';

class ShopFitting {
  final User me;
  final CollectibleLook? decoration;
  final CollectibleLook? nameplate;
  final CollectibleLook? effect;

  const ShopFitting._(this.me, this.decoration, this.nameplate, this.effect);

  factory ShopFitting.of(User me, ShopProduct product, {ShopItem? only}) {
    CollectibleLook? pick(CollectibleKind kind, CollectibleLook? own) {
      if (only != null) return only.kind == kind ? only.look : own;
      return product.firstOf(kind)?.look ?? own;
    }

    return ShopFitting._(
      me,
      pick(CollectibleKind.avatarDecoration, me.avatarDecoration),
      pick(CollectibleKind.nameplate, me.nameplate),
      pick(CollectibleKind.profileEffect, me.profileEffect),
    );
  }

  /// Своя аватарка с украшением примерки.
  Widget avatar(double size, {required bool animate}) => GlitchAvatar(
        initials: GlitchAvatar.initialsFromName(me.displayName),
        size: size,
        colorIndex: GlitchAvatar.colorFromNickname(me.nickname),
        imageUrl: me.avatar != null ? api.mediaUrl(me.avatar!) : null,
        avatarSizes: me.avatarSizes,
        decoration: decoration,
        animateDecoration: animate,
      );

  Widget card(BuildContext context, {required bool animate}) {
    final bio = me.bio?.trim() ?? '';
    return IgnorePointer(
      child: SizedBox(
        width: kMemberCardWidth,
        child: MemberCardLayout(
          effect: effect,
          animateEffect: animate,
          banner: UserBanner(url: me.banner, sizes: me.bannerSizes, color: me.avatarColor, nickname: me.nickname),
          avatar: avatar(kMemberCardAvatar, animate: animate),
          name: Text(
            me.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MemberCardLayout.nameStyle(),
          ),
          nickname: MemberCardLayout.nicknameText(me.nickname),
          body: [
            if (bio.isNotEmpty) ...[
              const SizedBox(height: 16),
              ProfileBio(bio: bio),
            ],
          ],
          bottom: GlitchActionButton(label: context.s.shopExampleButton, onTap: () {}),
        ),
      ),
    );
  }

  Widget row({required bool animate}) => SizedBox(
        width: RosterRowFrame.defaultWidth,
        height: RosterRowFrame.height,
        child: RosterRowFrame(
          nameplate: nameplate,
          animate: animate,
          avatar: avatar(RosterRowFrame.avatarSize, animate: animate),
          name: Text(
            me.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: RosterRowFrame.nameStyle(nameColor(null)),
          ),
        ),
      );

  Widget list({required bool animate}) {
    Widget blank() => SizedBox(
          width: RosterRowFrame.defaultWidth,
          height: RosterRowFrame.height,
          child: Padding(
            padding: RosterRowFrame.padding,
            child: Row(
              children: [
                Container(
                  width: RosterRowFrame.avatarSize,
                  height: RosterRowFrame.avatarSize,
                  decoration: BoxDecoration(color: GlitchColors.bgChip, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 110,
                  height: 8,
                  decoration: BoxDecoration(color: GlitchColors.bgChip, borderRadius: BorderRadius.circular(4)),
                ),
              ],
            ),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        KeyedSubtree(key: const ValueKey('above'), child: blank()),
        const SizedBox(height: 4),
        KeyedSubtree(key: const ValueKey('me'), child: row(animate: animate)),
        const SizedBox(height: 4),
        KeyedSubtree(key: const ValueKey('below'), child: blank()),
      ],
    );
  }
}
