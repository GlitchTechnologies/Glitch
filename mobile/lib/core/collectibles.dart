/// ОФОРМЛЕНИЕ ПРОФИЛЯ — правила показа (2026-10-24, как у Discord). Зеркало
/// сервера — `app/core/collectible.py` (виды и размер украшения).
library;

import 'platform_info.dart';

enum CollectibleKind {
  avatarDecoration('avatar_decoration'),
  nameplate('nameplate'),
  profileEffect('profile_effect');

  const CollectibleKind(this.wire);

  final String wire;

  static CollectibleKind? fromWire(String value) {
    for (final k in values) {
      if (k.wire == value) return k;
    }
    return null;
  }
}

/// Во сколько раз украшение больше аватарки: файл 288×288, аватарка в нём —
/// круг 240 по центру (сервер: `DECORATION_SCALE`).
const double kDecorationScale = 1.2;

const double kProfileEffectAspect = 600 / 1173;

bool animateInList(bool hovered) => hovered && hasPointerInput;
