import 'package:flutter/material.dart';

import '../models/collectible.dart';
import 'avatar_shape.dart';
import 'glitch_avatar.dart' show AvatarDecorationLayer;
import 'glitch_pressable.dart';
import 'image_edit_overlay.dart';

export 'avatar_shape.dart';

class BannerHeaderArt extends StatelessWidget {
  final Widget banner;

  final double bannerAspect;

  final Widget avatar;
  final double avatarSize;

  final AvatarShape avatarShape;

  final Color ringColor;

  final double bannerRadius;
  final Widget? besideAvatar;

  final Widget Function(bool active)? bannerOverlay;
  final Widget Function(bool active)? avatarOverlay;

  final VoidCallback? onBannerTap;
  final VoidCallback? onAvatarTap;

  final VoidCallback? onAvatarEdit;

  /// Украшение логотипа (оформление профиля) — ПОВЕРХ всех слоёв логотипа:
  /// затемнение с карандашом у меняемой аватарки ([onAvatarEdit]) и
  /// [avatarOverlay] его не трогают, как затемнение баннера не трогает эффект
  /// профиля. Тогда [avatar] передаётся без украшения. Где слоёв поверх
  /// логотипа нет, а есть точка «в сети» (карточка участника, профиль),
  /// украшение рисует сама аватарка — под точкой (`GlitchAvatar`).
  final CollectibleLook? avatarDecoration;
  final bool animateDecoration;

  static const double _ring = 4;

  const BannerHeaderArt({
    super.key,
    required this.banner,
    required this.bannerAspect,
    required this.avatar,
    required this.avatarSize,
    required this.avatarShape,
    required this.ringColor,
    this.bannerRadius = 0,
    this.besideAvatar,
    this.bannerOverlay,
    this.avatarOverlay,
    this.onBannerTap,
    this.onAvatarTap,
    this.onAvatarEdit,
    this.avatarDecoration,
    this.animateDecoration = true,
  }) : assert(onAvatarTap == null || onAvatarEdit == null, 'нажатие на логотип — либо открыть, либо сменить');

  Widget _area(Widget Function(bool active) child, VoidCallback? onTap) => onTap == null
      ? child(false)
      : GlitchHoverArea(onTap: onTap, builder: (_, active) => child(active));

  @override
  Widget build(BuildContext context) {
    final overlap = avatarSize * 0.55;

    final bannerArea = _area(
      (active) => ClipRRect(
        borderRadius: BorderRadius.circular(bannerRadius),
        child: AspectRatio(
          aspectRatio: bannerAspect,
          child: Stack(
            fit: StackFit.expand,
            children: [
              banner,
              if (bannerOverlay != null) bannerOverlay!(active),
            ],
          ),
        ),
      ),
      onBannerTap,
    );

    final ring = BoxDecoration(
      color: ringColor,
      borderRadius: avatarShape.ringRadius(avatarSize, _ring),
    );
    Widget withRing(Widget child) => SizedBox.square(
          dimension: avatarSize + _ring * 2,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              ClipRect(
                clipper: _BannerRingClip(overlap),
                child: DecoratedBox(decoration: ring),
              ),
              Padding(padding: const EdgeInsets.all(_ring), child: child),
            ],
          ),
        );

    final Widget picture = onAvatarEdit != null
        ? withRing(EditableAvatar(
            size: avatarSize,
            shape: avatarShape,
            onTap: onAvatarEdit,
            extra: avatarOverlay,
            child: avatar,
          ))
        : _area(
            (active) => withRing(Stack(
              clipBehavior: Clip.none,
              children: [
                AvatarHover(key: const ValueKey('avatar'), active: active, child: avatar),
                if (avatarOverlay != null)
                  Positioned.fill(
                    key: const ValueKey('avatar-overlay'),
                    child: avatarShape.clip(size: avatarSize, child: avatarOverlay!(active)),
                  ),
              ],
            )),
            onAvatarTap,
          );
    final decoration = avatarDecoration;
    // Украшение — над логотипом со всеми его слоями. Нажатия проходят сквозь
    // него (AvatarDecorationLayer — IgnorePointer) к логотипу.
    final Widget logo = decoration == null
        ? picture
        : SizedBox(
            width: avatarSize + _ring * 2,
            height: avatarSize + _ring * 2,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                KeyedSubtree(key: const ValueKey('picture'), child: picture),
                Positioned(
                  key: const ValueKey('decoration'),
                  left: _ring,
                  top: _ring,
                  width: avatarSize,
                  height: avatarSize,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AvatarDecorationLayer(size: avatarSize, decoration: decoration, playing: animateDecoration),
                    ],
                  ),
                ),
              ],
            ),
          );

    Widget header({double? avatarTop}) => Stack(
      // Украшение выходит за круг логотипа и может зайти ниже шапки.
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            bannerArea,
            if (besideAvatar == null)
              SizedBox(height: overlap)
            else SizedBox(
              height: overlap,
              child: Padding(
                padding: EdgeInsets.only(left: 14 + avatarSize + _ring * 2 + 4, right: 8),
                child: Transform.translate(
                  offset: const Offset(0, 2),
                  child: besideAvatar ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
        Positioned(left: 14, top: avatarTop, bottom: avatarTop == null ? 0 : null, child: logo),
      ],
    );
    if (besideAvatar == null) return header();
    return LayoutBuilder(builder: (context, constraints) => header(
      avatarTop: constraints.maxWidth / bannerAspect + overlap - avatarSize - _ring * 2,
    ));
  }
}

class _BannerRingClip extends CustomClipper<Rect> {
  final double overlap;

  const _BannerRingClip(this.overlap);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width, size.height - overlap);

  @override
  bool shouldReclip(_BannerRingClip oldClipper) => oldClipper.overlap != overlap;
}
