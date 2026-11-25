import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../models/presence.dart';
import '../services/user_presences.dart';
import 'presence_indicator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';
import '../core/avatar_sizes.dart';
import '../core/media_content.dart';
import '../services/api_service.dart';
import '../core/collectibles.dart';
import '../models/collectible.dart';
import 'animated_network_image.dart';
import 'avatar_shape.dart';
import 'collectible_image.dart';
import 'image_edit_overlay.dart' show AvatarHover, ImageHoverShade;

export 'avatar_shape.dart';

/// ТЕПЕРЬ ЭТО ТОЛЬКО ПРО ПАМЯТЬ, НЕ ПРО КАЧЕСТВО. Раньше здесь же чинилось и
/// качество: одна большая аватарка ужималась в кружок прямо при рисовании,
/// дешёвым фильтром, отсюда рваные края. На Android это лечилось, а в браузере
/// то же указание не работает вовсе — там картинку грузит сам браузер обычным
/// <img>.
int avatarDecodeSize(BuildContext context, double size) {
  final ratio = MediaQuery.devicePixelRatioOf(context);
  return (size * math.max(ratio, 2.0)).round();
}

class GlitchAvatar extends StatelessWidget {
  static const double _presenceGap = 2.5;

  final String initials;
  final double size;
  final int colorIndex;
  final bool showOnline;
  final int? presenceUserId;
  final PresenceStatus? presenceStatus;
  final bool presenceBlocked;
  final bool personalPresence;

  final String? imageUrl;

  final Map<String, String>? avatarSizes;

  final AvatarShape shape;

  /// Украшение аватарки — надетый предмет оформления человека (2026-10-24,
  /// core/collectibles.dart). Рисуется здесь, в одном месте на всё
  /// приложение: в [kDecorationScale] раз больше аватарки, по центру, поверх
  /// неё и под точкой «в сети». Места, где Discord украшение не показывает
  /// (мелкие значки в подсказках и выборе людей), его просто не передают.
  final CollectibleLook? decoration;

  /// Играет ли анимация украшения: в списках — при наведении на строку,
  /// в открытом профиле — всегда (core/collectibles.dart).
  final bool animateDecoration;

  const GlitchAvatar({
    super.key,
    required this.initials,
    this.size = 54,
    this.colorIndex = 0,
    this.showOnline = false,
    this.presenceUserId,
    this.presenceStatus,
    this.presenceBlocked = false,
    this.personalPresence = false,
    this.imageUrl,
    this.avatarSizes,
    this.shape = AvatarShape.person,
    this.decoration,
    this.animateDecoration = false,
  });

  /// Такую строку нельзя нарисовать: на телефоне раскладка текста падала с
  /// «string is not well-formed UTF-16» (в журнале ошибок — повторяющиеся
  /// записи от 2026-08-22/23, стек ровно на этом Text внутри ClipOval), а в
  /// браузере вместо падения запускался бесконечный поиск шрифта, способного
  /// такое отобразить, — отсюда «Could not find a set of Noto fonts» в консоли
  /// и подвисания страницы.
  static String initialsFromName(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${_firstChar(parts[0])}${_firstChar(parts[1])}'.toUpperCase();
    }
    if (parts.isNotEmpty) return _firstChar(parts[0]).toUpperCase();
    return '?';
  }

  static String _firstChar(String s) =>
      s.isEmpty ? '' : String.fromCharCode(s.runes.first);

  static int colorFromNickname(String nickname) {
    return nickname.codeUnits.fold(0, (a, b) => a + b) % GlitchColors.avatarGradients.length;
  }

  @override
  Widget build(BuildContext context) {
    final url = pickAvatarUrl(
      original: imageUrl,
      sizes: avatarSizes,
      logicalSize: size,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );

    final avatar = Stack(
      children: [
        // Ключи у всех детей: украшение и точка — условные, без ключей
        // Flutter путал бы соседей.
        KeyedSubtree(
          key: const ValueKey('avatar'),
          child: SizedBox(
            width: size,
            height: size,
            child: url == null
                ? _placeholder()
                : isGifUrl(url)
                    ? AnimatedNetworkImage(
                        url: url,
                        fit: BoxFit.cover,
                        placeholder: (_) => _placeholder(),
                        errorWidget: (_) => _placeholder(),
                      )
                    : CachedNetworkImage(
                        imageUrl: url,
                        cacheManager: mediaCacheManager,
                        fit: BoxFit.cover,
                        memCacheWidth: avatarDecodeSize(context, size),
                        memCacheHeight: avatarDecodeSize(context, size),
                        filterQuality: FilterQuality.medium,
                        errorWidget: (_, __, ___) => _placeholder(),
                        placeholder: (_, __) => _placeholder(),
                      ),
          ),
        ),
        // Затемнение под мышью у аватарки, которая что-то открывает
        // (AvatarHover, image_edit_overlay.dart): только поверх картинки, под
        // украшением и точкой «в сети».
        if (AvatarHover.of(context))
          Positioned(
            key: const ValueKey('shade'),
            left: 0,
            top: 0,
            child: SizedBox(width: size, height: size, child: const ImageHoverShade()),
          ),
      ],
    );
    if (presenceUserId == null) return _withPresence(avatar, _visiblePresence());
    return ListenableBuilder(
      listenable: userPresences,
      child: avatar,
      builder: (_, child) => _withPresence(child!, _visiblePresence()),
    );
  }

  PresenceStatus? _visiblePresence() {
    final id = presenceUserId;
    final blocked = personalPresence && id != null
        ? userPresences.blockedFor(id, presenceBlocked)
        : presenceBlocked;
    if (blocked) return null;
    final fallback = presenceStatus ?? (showOnline ? PresenceStatus.online : PresenceStatus.offline);
    final status = id == null ? fallback : userPresences.statusOf(id, fallback);
    return status == PresenceStatus.offline || status == PresenceStatus.invisible ? null : status;
  }

  Widget _withPresence(Widget avatar, PresenceStatus? status) {
    final corner = shape.cornerPoint(size);
    final center = Offset(corner, corner);
    final cutout = status == null
        ? null
        : Rect.fromCircle(center: center, radius: _presenceSize / 2 + _presenceGap);
    // Значок и украшение могут выступать за квадрат аватарки.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _clipPresence(
          ClipRRect(
            borderRadius: shape.borderRadius(size),
            clipBehavior: cutout == null ? Clip.antiAlias : Clip.none,
            child: avatar,
          ),
          cutout,
          key: const ValueKey('avatar-art'),
          shape: shape,
        ),
        if (decoration != null)
          AvatarDecorationLayer(
            key: const ValueKey('decoration'),
            size: size,
            decoration: decoration!,
            playing: animateDecoration,
            presenceCutout: cutout,
          ),
        if (status != null)
          Positioned(
            key: const ValueKey('online'),
            left: center.dx - _presenceSize / 2,
            top: center.dy - _presenceSize / 2,
            child: PresenceIndicator(status: status, size: _presenceSize),
          ),
      ],
    );
  }

  double get _presenceSize => math.max(12, size * 0.26 - 5);

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: shape.borderRadius(size),
        gradient: GlitchColors.avatarGradients[colorIndex % GlitchColors.avatarGradients.length],
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.33,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

Widget _clipPresence(Widget child, Rect? cutout, {Key? key, AvatarShape? shape}) => ClipPath(
      key: key,
      clipBehavior: cutout == null ? Clip.none : Clip.antiAlias,
      clipper: cutout == null ? null : _PresenceCutout(cutout, shape),
      child: child,
    );

class _PresenceCutout extends CustomClipper<Path> {
  final Rect hole;
  final AvatarShape? shape;

  const _PresenceCutout(this.hole, this.shape);

  @override
  Path getClip(Size size) {
    final bounds = Offset.zero & size;
    final outline = shape?.outline(bounds) ?? (Path()..addRect(bounds));
    return Path.combine(PathOperation.difference, outline, Path()..addOval(hole));
  }

  @override
  bool shouldReclip(_PresenceCutout oldClipper) => oldClipper.hole != hole || oldClipper.shape != shape;
}

/// Слой украшения над аватаркой — ПРЯМОЙ ребёнок `Stack` размером с
/// аватарку [size]: в [kDecorationScale] раз больше неё, по центру, выходит
/// за её края. Рисует его [GlitchAvatar]; отдельно — только там, где под
/// украшением не сетевая картинка, а выбранная, но ещё не сохранённая
/// (редактор профиля). Своих расчётов положения украшения не заводить.
class AvatarDecorationLayer extends StatelessWidget {
  final double size;
  final CollectibleLook decoration;
  final bool playing;
  final Rect? presenceCutout;

  const AvatarDecorationLayer({
    super.key,
    required this.size,
    required this.decoration,
    required this.playing,
    this.presenceCutout,
  });

  @override
  Widget build(BuildContext context) {
    final overhang = size * (kDecorationScale - 1) / 2;
    return Positioned(
      left: -overhang,
      top: -overhang,
      width: size * kDecorationScale,
      height: size * kDecorationScale,
      child: IgnorePointer(
        child: _clipPresence(
          CollectibleImage(
            staticUrl: decoration.staticUrl,
            animatedUrl: decoration.animated,
            playing: playing,
          ),
          presenceCutout?.shift(Offset(overhang, overhang)),
        ),
      ),
    );
  }
}
