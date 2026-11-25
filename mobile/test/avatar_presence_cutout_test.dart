import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:glitch/models/presence.dart';
import 'package:glitch/widgets/banner_header_art.dart' show BannerHeaderArt;
import 'package:glitch/widgets/glitch_avatar.dart';

void main() {
  for (final size in [32.0, 80.0, 96.0, 112.0]) {
    testWidgets('avatar $size exposes the background next to the status', (tester) async {
      const captureKey = ValueKey('capture');
      const avatarKey = ValueKey('avatar-under-test');
      final capture = find.byKey(captureKey);

      Future<bool> gapShowsBackground(PresenceStatus status) async {
        final avatar = GlitchAvatar(key: avatarKey, initials: '', size: size, presenceStatus: status);
        await tester.pumpWidget(MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: captureKey,
              child: SizedBox(
                width: 280,
                height: 240,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF341C49), Color(0xFF582B19)],
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: size < 80
                        ? Padding(padding: const EdgeInsets.all(16), child: avatar)
                        : BannerHeaderArt(
                            banner: const ColoredBox(color: Colors.red),
                            bannerAspect: 3,
                            avatar: avatar,
                            avatarSize: size,
                            avatarShape: AvatarShape.person,
                            ringColor: Colors.orange,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ));
        if (status == PresenceStatus.online) {
          final clip = tester.widget<ClipPath>(find.descendant(
            of: find.byKey(avatarKey),
            matching: find.byType(ClipPath),
          ));
          expect(clip.clipper!.getClip(Size.square(size)).computeMetrics().length, 1);
        }
        final origin = tester.getTopLeft(find.byKey(avatarKey)) - tester.getTopLeft(capture);
        final center = AvatarShape.person.cornerPoint(size);
        final radius = math.max(12, size * 0.26 - 5) / 2;
        final gap = origin + Offset(center - radius - 1.25, center);
        final background = Offset(260, gap.dy);
        final boundary = tester.renderObject<RenderRepaintBoundary>(capture);
        return (await tester.runAsync(() async {
          const scale = 4.0;
          final image = await boundary.toImage(pixelRatio: scale);
          try {
            final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
            int pixelOffset(Offset point) =>
                ((point.dy * scale).floor() * image.width + (point.dx * scale).floor()) * 4;
            final gapOffset = pixelOffset(gap);
            final backgroundOffset = pixelOffset(background);
            return [0, 1, 2, 3].every((channel) =>
                (bytes.getUint8(gapOffset + channel) - bytes.getUint8(backgroundOffset + channel)).abs() <= 1);
          } finally {
            image.dispose();
          }
        }))!;
      }

      expect(await gapShowsBackground(PresenceStatus.online), isTrue);
      expect(await gapShowsBackground(PresenceStatus.invisible), isFalse);
    });
  }
}
