import 'package:flutter/material.dart';

import 'avatar_shape.dart';
import 'glitch_pressable.dart';


class ImageHoverShade extends StatelessWidget {
  final Widget? child;

  const ImageHoverShade({super.key, this.child});

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0x66000000),
        child: child == null ? null : Center(child: child),
      );
}

/// «Аватарка под мышью» — для аватарки, которая по нажатию что-то
/// ОТКРЫВАЕТ. Её затемнение ([ImageHoverShade]) рисует сама `GlitchAvatar`:
/// только поверх картинки, под украшением и точкой «в сети» — затемнить их
/// вместе с ней значило бы потушить чужое оформление (как с украшением у
/// меняемой аватарки, 2026-10-26). Ставит его `BannerHeaderArt` вокруг
/// аватарки, пока на неё наведена мышь; аватарка может быть завёрнута во что
/// угодно (`ServerUserAvatar`) — знак доходит до неё сквозь обёртки.
class AvatarHover extends InheritedWidget {
  final bool active;

  const AvatarHover({super.key, required this.active, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AvatarHover>()?.active ?? false;

  @override
  bool updateShouldNotify(AvatarHover old) => active != old.active;
}

class ImageEditHint extends StatelessWidget {
  final double iconSize;

  const ImageEditHint({super.key, required this.iconSize});

  @override
  Widget build(BuildContext context) =>
      ImageHoverShade(child: Icon(Icons.edit_rounded, color: Colors.white, size: iconSize));
}

class ImageRemoveBadge extends StatelessWidget {
  final VoidCallback? onTap;

  const ImageRemoveBadge({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlitchPressable(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(color: Color(0x8A000000), shape: BoxShape.circle),
        child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
      ),
    );
  }
}

class EditableAvatar extends StatelessWidget {
  final Widget child;
  final double size;
  final AvatarShape shape;
  final VoidCallback? onTap;
  final bool busy;
  final Widget Function(bool active)? extra;

  const EditableAvatar({
    super.key,
    required this.child,
    required this.size,
    required this.shape,
    required this.onTap,
    this.busy = false,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    Widget layers(bool active) => SizedBox(
          width: size,
          height: size,
          child: Stack(
            children: [
              child,
              Positioned.fill(
                child: shape.clip(
                  size: size,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (busy)
                        const ImageHoverShade(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          ),
                        )
                      else if (active)
                        ImageEditHint(iconSize: (size * 0.3).clamp(16, 30).toDouble()),
                      if (extra != null) extra!(active),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
    final tap = busy ? null : onTap;
    return tap == null ? layers(false) : GlitchHoverArea(onTap: tap, builder: (_, active) => layers(active));
  }
}
