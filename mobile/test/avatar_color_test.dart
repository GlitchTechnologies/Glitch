
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:glitch/core/avatar_color.dart';

void main() {
  test('формат сервера разбирается', () {
    expect(parseAvatarColor('#28a046'), const Color(0xFF28A046));
    expect(parseAvatarColor('#AABBCC'), const Color(0xFFAABBCC));
  });

  test('записанное читается обратно тем же цветом', () {
    const color = Color(0xFF3A7BD5);
    expect(parseAvatarColor(avatarColorToJson(color)), color);
    expect(avatarColorToJson(color), '#3a7bd5');
  });

  test('ведущие нули не теряются', () {
    expect(avatarColorToJson(const Color(0xFF000A0B)), '#000a0b');
  });

  test('нет цвета и мусор — null, а не падение', () {
    for (final bad in [null, '', 'red', '#abc', '#gggggg', 'aabbcc', 42, '#aabbccdd']) {
      expect(parseAvatarColor(bad), isNull, reason: 'значение $bad');
    }
    expect(avatarColorToJson(null), isNull);
  });
}
