import 'package:flutter/material.dart';

import '../core/collectibles.dart';
import '../core/l10n.dart';
import '../core/price_text.dart';
import '../models/shop.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';
import 'glitch_pressable.dart';
import 'shop_preview.dart';

/// КАРТОЧКА ТОВАРА НА ВИТРИНЕ (магазин, 2026-10-24, как у Discord и LOLKA):
/// картинка-примерка на себе, название, вид («Набор · 3 предмета»), цена или
/// «В коллекции». Картинку не рисует художник — её собирает примерка
/// (`ShopFitting`): украшение на своей аватарке, эффект на своей карточке,
/// плашка — своей строкой, набор — всё вместе. Оживает при наведении.
class ShopCard extends StatelessWidget {
  final ShopProduct product;
  final User me;
  final VoidCallback onTap;

  const ShopCard({super.key, required this.product, required this.me, required this.onTap});

  static const double height = 290;
  static const double _radius = 12;

  @override
  Widget build(BuildContext context) {
    return GlitchHoverArea(
      onTap: onTap,
      builder: (context, active) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: GlitchColors.bgCard,
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(color: active ? GlitchColors.border : Colors.transparent),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: ShopArt(product: product, me: me, animate: animateInList(active))),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    shopProductSubtitle(context, product),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: GlitchColors.textSecond),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    product.owned ? context.s.shopOwned : formatPrice(product.price),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String shopProductSubtitle(BuildContext context, ShopProduct product) {
  final s = context.s;
  final kind = product.kind;
  if (kind == null) return '${s.shopKindBundle} · ${s.shopItemsCount(product.items.length)}';
  return collectibleKindTitle(context, kind);
}

String collectibleKindTitle(BuildContext context, CollectibleKind kind) {
  final s = context.s;
  return switch (kind) {
    CollectibleKind.avatarDecoration => s.shopKindDecoration,
    CollectibleKind.profileEffect => s.shopKindEffect,
    CollectibleKind.nameplate => s.shopKindNameplate,
  };
}

/// КАРТИНКА ТОВАРА — примерка на себе в рамке картинки (карточка витрины).
/// Одиночный товар — его образец по центру; набор — как у LOLKA: аватарка с
/// украшением слева сверху, карточка с эффектом справа с наклоном, строка с
/// плашкой снизу слева (чего в наборе нет — того и нет).
class ShopArt extends StatelessWidget {
  final ShopProduct product;
  final User me;
  final bool animate;

  const ShopArt({super.key, required this.product, required this.me, required this.animate});

  @override
  Widget build(BuildContext context) {
    final fitting = ShopFitting.of(me, product);
    final kind = product.kind;
    final Widget art;
    if (kind == CollectibleKind.avatarDecoration) {
      art = Center(child: fitting.avatar(100, animate: animate));
    } else if (kind == CollectibleKind.profileEffect) {
      art = _scaled(fitting.card(context, animate: animate), padding: const EdgeInsets.only(top: 14));
    } else if (kind == CollectibleKind.nameplate) {
      art = _scaled(fitting.list(animate: animate), padding: const EdgeInsets.all(18));
    } else {
      art = _bundle(context, fitting);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [GlitchColors.bgInput, GlitchColors.bgCard],
        ),
      ),
      child: ClipRect(child: art),
    );
  }

  Widget _scaled(Widget child, {required EdgeInsets padding}) => Padding(
        padding: padding,
        child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topCenter, child: child),
      );

  Widget _bundle(BuildContext context, ShopFitting fitting) {
    final hasDecoration = product.firstOf(CollectibleKind.avatarDecoration) != null;
    final hasEffect = product.firstOf(CollectibleKind.profileEffect) != null;
    final hasPlate = product.firstOf(CollectibleKind.nameplate) != null;
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        if (hasEffect)
          Positioned(
            key: const ValueKey('card'),
            right: 14,
            top: 16,
            width: 120,
            child: Transform.rotate(
              angle: 0.1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: FittedBox(fit: BoxFit.fitWidth, child: fitting.card(context, animate: animate)),
              ),
            ),
          ),
        if (hasDecoration)
          Positioned(
            key: const ValueKey('avatar'),
            left: 26,
            top: 18,
            child: fitting.avatar(84, animate: animate),
          ),
        if (hasPlate)
          Positioned(
            key: const ValueKey('plate'),
            left: 10,
            bottom: 14,
            width: 170,
            child: FittedBox(fit: BoxFit.fitWidth, child: fitting.row(animate: animate)),
          ),
      ],
    );
  }
}
