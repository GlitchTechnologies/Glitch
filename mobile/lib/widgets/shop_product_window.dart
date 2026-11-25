import 'package:flutter/material.dart';

import '../core/collectibles.dart';
import '../core/l10n.dart';
import '../core/own_account_open.dart';
import '../core/price_text.dart';
import '../services/api_service.dart';
import '../services/shop_purchase.dart';
import '../models/shop.dart';
import '../models/user.dart';
import '../providers/theme_provider.dart' show ThemeAwareState;
import '../theme/app_theme.dart';
import 'adaptive_sheet.dart';
import 'collectible_image.dart';
import 'glitch_action_button.dart';
import 'glitch_pressable.dart';
import 'glitch_toast.dart';
import 'settings_window.dart' show SettingsPageHeader;
import 'shop_card.dart';
import 'shop_preview.dart';

/// ОКНО ТОВАРА (магазин, 2026-10-24, как у Discord и LOLKA) — по нажатию на
/// карточку витрины. Слева: примерка выбранного предмета (аватарка с
/// украшением, своя строка с плашкой или карточка с эффектом), название, у
/// набора — его предметы плитками (нажал — сверху этот предмет), цена и
/// кнопка. Справа: как будет выглядеть свой профиль со ВСЕМ товаром, у
/// плашки — свой кусок списка участников. На телефоне — страница: примерка,
/// затем то, что было слева.
Future<void> showShopProduct(BuildContext context, {required ShopProduct product, required User me}) =>
    openAdaptiveWindow<void>(
      context,
      narrowBuilder: (_) => _ShopProductView(product: product, me: me, wide: false),
      wideBuilder: (_) => _ShopProductView(product: product, me: me, wide: true),
      wideSize: const Size(960, 640),
    );

class _ShopProductView extends StatefulWidget {
  final ShopProduct product;
  final User me;
  final bool wide;

  const _ShopProductView({required this.product, required this.me, required this.wide});

  @override
  State<_ShopProductView> createState() => _ShopProductViewState();
}

class _ShopProductViewState extends State<_ShopProductView> with ThemeAwareState<_ShopProductView> {
  late ShopItem _item = widget.product.items.first;

  ShopProduct get _product => widget.product;

  late bool _owned = widget.product.owned;

  bool _starting = false;

  @override
  void initState() {
    super.initState();
    shopPurchase.completed.addListener(_onPurchased);
  }

  @override
  void dispose() {
    shopPurchase.completed.removeListener(_onPurchased);
    super.dispose();
  }

  void _onPurchased() {
    if (shopPurchase.completed.value?.productId == _product.id && mounted) setState(() => _owned = true);
  }

  Future<void> _buy() async {
    setState(() => _starting = true);
    try {
      await shopPurchase.start(_product.id);
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _equip() async {
    final nav = Navigator.of(context);
    nav.pop();
    await editMyProfile(nav.context);
  }

  @override
  Widget build(BuildContext context) {
    final whole = ShopFitting.of(widget.me, _product);
    if (widget.wide) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 360,
                child: ColoredBox(
                  color: GlitchColors.bgCard,
                  child: CustomScrollView(
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: Center(child: _itemPreview())),
                              const SizedBox(height: 24),
                              _details(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: _fittingOf(whole),
                  ),
                ),
              ),
            ],
          ),
          AdaptiveWindowCloseButton(onPressed: () => Navigator.pop(context)),
        ],
      );
    }
    return Scaffold(
      backgroundColor: GlitchColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsPageHeader(title: _product.name),
            Divider(height: 1, color: GlitchColors.border),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: _fittingOf(whole)),
                    const SizedBox(height: 24),
                    Center(child: _itemPreview()),
                    const SizedBox(height: 24),
                    _details(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fittingOf(ShopFitting whole) {
    if (_product.kind == CollectibleKind.nameplate) {
      return FittedBox(fit: BoxFit.scaleDown, child: whole.list(animate: true));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: whole.card(context, animate: true),
    );
  }

  Widget _itemPreview() => SizedBox(
        height: 200,
        child: Center(child: _itemFitting(ShopFitting.of(widget.me, _product, only: _item))),
      );

  Widget _details() {
    final s = context.s;
    final product = _product;
    final have = product.items.where((i) => i.owned).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          product.name,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          product.isBundle ? s.shopItemsCount(product.items.length) : shopProductSubtitle(context, product),
          style: TextStyle(fontSize: 13.5, color: GlitchColors.textSecond),
        ),
        if (product.isBundle) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in product.items)
                _ItemThumb(
                  key: ValueKey(item.id),
                  item: item,
                  selected: item.id == _item.id,
                  onTap: () => setState(() => _item = item),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${_item.name} — ${collectibleKindTitle(context, _item.kind)}',
            style: TextStyle(fontSize: 13.5, color: GlitchColors.textPrimary),
          ),
        ],
        const SizedBox(height: 24),
        if (!_owned && have > 0) ...[
          Text(
            s.shopAlreadyHave(have, product.items.length),
            style: TextStyle(fontSize: 13.5, color: GlitchColors.textPrimary),
          ),
          const SizedBox(height: 8),
        ],
        if (!_owned)
          Text(
            formatPrice(product.price),
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
          ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: _owned
              ? GlitchActionButton(label: s.shopEquip, onTap: _equip)
              : GlitchActionButton(
                  label: s.shopBuy(formatPrice(product.price)),
                  loading: _starting,
                  onTap: _starting ? null : _buy,
                ),
        ),
      ],
    );
  }

  /// Примерка одного предмета: украшение — на аватарке, плашка — своей
  /// строкой, эффект — на своей карточке (уменьшенной).
  Widget _itemFitting(ShopFitting one) => switch (_item.kind) {
        CollectibleKind.avatarDecoration => one.avatar(128, animate: true),
        CollectibleKind.nameplate => FittedBox(fit: BoxFit.scaleDown, child: one.row(animate: true)),
        CollectibleKind.profileEffect => ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: FittedBox(fit: BoxFit.contain, child: one.card(context, animate: true)),
          ),
      };
}

class _ItemThumb extends StatelessWidget {
  final ShopItem item;
  final bool selected;
  final VoidCallback onTap;

  const _ItemThumb({super.key, required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GlitchHoverArea(
        onTap: onTap,
        builder: (context, active) => Container(
          width: 56,
          height: 56,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: GlitchColors.bgInput,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? GlitchColors.accentBlue
                  : active
                      ? GlitchColors.border
                      : Colors.transparent,
              width: 2,
            ),
          ),
          child: CollectibleImage(
            staticUrl: item.look.staticUrl,
            animatedUrl: null,
            fit: item.kind == CollectibleKind.avatarDecoration ? BoxFit.contain : BoxFit.cover,
            alignment: item.kind == CollectibleKind.nameplate ? Alignment.centerRight : Alignment.topCenter,
          ),
        ),
      );
}
