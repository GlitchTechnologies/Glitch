import 'package:flutter/material.dart';

import '../core/collectibles.dart';
import '../core/l10n.dart';
import '../core/own_account_open.dart';
import '../models/shop.dart';
import '../models/user.dart';
import '../providers/theme_provider.dart' show ThemeAwareState;
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/glitch_plus_purchase.dart';
import '../services/shop_purchase.dart';
import '../theme/app_theme.dart';
import '../widgets/glitch_action_button.dart';
import '../widgets/glitch_toast.dart';
import '../widgets/home_section_header.dart';
import '../widgets/shop_card.dart';
import '../widgets/shop_glitch_plus_card.dart';
import '../widgets/shop_product_window.dart';
import 'home_section_screen.dart';
import 'user_settings_window.dart' show UserSettingsSection;

enum ShopTab { all, bundles, avatarDecoration, profileEffect, nameplate }

ShopTab shopTabOf(CollectibleKind kind) => switch (kind) {
      CollectibleKind.avatarDecoration => ShopTab.avatarDecoration,
      CollectibleKind.profileEffect => ShopTab.profileEffect,
      CollectibleKind.nameplate => ShopTab.nameplate,
    };

class ShopTabRequest {
  final ShopTab tab;
  ShopTabRequest(this.tab);
}

class ShopScreen extends StatefulWidget {
  final ShopTabRequest? request;

  const ShopScreen({super.key, this.request});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> with ThemeAwareState<ShopScreen> {
  late ShopTab _tab = widget.request?.tab ?? ShopTab.all;

  List<ShopProduct>? _products;

  User? _me;
  bool _failed = false;
  bool _startingGlitchPlus = false;

  @override
  void initState() {
    super.initState();
    _load();
    shopPurchase.completed.addListener(_load);
    authService.currentUserListenable.addListener(_onMeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) shopPurchase.checkPending(context);
    });
  }

  @override
  void dispose() {
    shopPurchase.completed.removeListener(_load);
    authService.currentUserListenable.removeListener(_onMeChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(ShopScreen old) {
    super.didUpdateWidget(old);
    final request = widget.request;
    // Без setState: после didUpdateWidget страница строится и так.
    if (request != null && !identical(request, old.request)) _tab = request.tab;
  }

  void _onMeChanged() {
    final user = authService.currentUser;
    if (mounted && user != null && (_me == null || user.id == _me?.id)) {
      ++_meVersion;
      setState(() => _me = user);
    }
  }

  int _loadVersion = 0;
  int _meVersion = 0;

  Future<void> _load() async {
    final version = ++_loadVersion;
    final meVersion = _meVersion;
    final sessionToken = authService.token;
    setState(() => _failed = false);
    try {
      final results = await Future.wait([api.getShop(), api.getMe()]);
      if (!mounted || version != _loadVersion || authService.token != sessionToken) return;
      setState(() {
        _products = results[0] as List<ShopProduct>;
        if (meVersion == _meVersion) _me = results[1] as User;
      });
    } catch (_) {
      if (mounted && version == _loadVersion && authService.token == sessionToken) setState(() => _failed = true);
    }
  }

  Future<void> _openGlitchPlus() async {
    if (_startingGlitchPlus) return;
    setState(() => _startingGlitchPlus = true);
    try {
      if (_me?.isGlitchPlus == true) {
        await openMySettings(context, section: UserSettingsSection.glitchPlus);
        if (!mounted) return;
        await _load();
      } else {
        await startGlitchPlusPurchase();
      }
    } catch (e) {
      if (mounted) GlitchToast.show(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _startingGlitchPlus = false);
    }
  }

  bool _fits(ShopProduct p) => switch (_tab) {
        ShopTab.all => true,
        ShopTab.bundles => p.isBundle,
        ShopTab.avatarDecoration => p.kind == CollectibleKind.avatarDecoration,
        ShopTab.profileEffect => p.kind == CollectibleKind.profileEffect,
        ShopTab.nameplate => p.kind == CollectibleKind.nameplate,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GlitchColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final s = context.s;
    return HomeSectionHeader(
      section: HomeSection.shop,
      tabs: [
        for (final (tab, label) in [
          (ShopTab.all, s.shopTabAll),
          (ShopTab.bundles, s.shopTabBundles),
          (ShopTab.avatarDecoration, s.shopTabDecorations),
          (ShopTab.profileEffect, s.shopTabEffects),
          (ShopTab.nameplate, s.shopTabNameplates),
        ])
          HomeSectionTab(
            label: label,
            selected: _tab == tab,
            onTap: () {
              if (_tab != tab) setState(() => _tab = tab);
            },
          ),
      ],
    );
  }

  Widget _body() {
    final s = context.s;
    final products = _products;
    final me = _me;
    if (products == null || me == null) {
      return Center(
        child: _failed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.errorLoad, style: TextStyle(fontSize: 14, color: GlitchColors.textPrimary)),
                  const SizedBox(height: 8),
                  GlitchActionButton(label: s.retry, soft: true, compact: true, onTap: _load),
                ],
              )
            : SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.accentBlue),
              ),
      );
    }
    final shown = products.where(_fits).toList();
    return CustomScrollView(
      slivers: [
        if (_tab == ShopTab.all)
          SliverPadding(
            key: const ValueKey('glitchPlus'),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            sliver: SliverToBoxAdapter(
              child: ShopGlitchPlusCard(
                isActive: me.isGlitchPlus,
                loading: _startingGlitchPlus,
                onTap: _openGlitchPlus,
              ),
            ),
          ),
        if (shown.isEmpty)
          SliverFillRemaining(
            key: const ValueKey('empty'),
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  s.shopEmpty,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: GlitchColors.textPrimary),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            key: const ValueKey('products'),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 280,
                mainAxisExtent: ShopCard.height,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final product = shown[i];
                  return ShopCard(
                    key: ValueKey(product.id),
                    product: product,
                    me: me,
                    onTap: () => showShopProduct(context, product: product, me: me),
                  );
                },
                childCount: shown.length,
              ),
            ),
          ),
      ],
    );
  }
}
