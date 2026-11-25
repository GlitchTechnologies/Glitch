import 'package:flutter/material.dart';

import '../core/nameplate_palette.dart';
import '../models/collectible.dart';
import 'collectible_image.dart';

class NameplateBackground extends StatelessWidget {
  final CollectibleLook? nameplate;
  final bool animate;
  final BorderRadius borderRadius;
  final Widget child;

  const NameplateBackground({
    super.key,
    required this.nameplate,
    required this.animate,
    required this.borderRadius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final plate = nameplate;
    if (plate == null) return child;
    final color = nameplateColor(plate.palette);
    return Stack(
      children: [
        Positioned.fill(
          key: const ValueKey('nameplate'),
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: borderRadius,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (color != null)
                    DecoratedBox(
                      key: const ValueKey('palette'),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [color.withOpacity(0), color.withOpacity(kNameplateFillStrength)],
                        ),
                      ),
                    ),
                  CollectibleImage(
                    key: const ValueKey('image'),
                    staticUrl: plate.staticUrl,
                    animatedUrl: plate.animated,
                    playing: animate,
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                  ),
                ],
              ),
            ),
          ),
        ),
        KeyedSubtree(key: const ValueKey('row'), child: child),
      ],
    );
  }
}
