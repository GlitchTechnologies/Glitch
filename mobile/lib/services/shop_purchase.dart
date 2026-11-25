import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/l10n.dart';
import '../main.dart' show navigatorKey;
import '../widgets/glitch_toast.dart';
import 'api_service.dart';

class ShopPurchase with WidgetsBindingObserver {
  ShopPurchase._();

  static const _keyId = 'shop_pending_payment_id';
  static const _keyAt = 'shop_pending_payment_at';
  static const _pendingFor = Duration(hours: 1);

  final completed = ValueNotifier<({int productId})?>(null);

  bool _observing = false;
  bool _checking = false;

  Future<void> start(int productId) async {
    final checkout = await api.shopCheckout(productId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyId, checkout.paymentId);
    await prefs.setInt(_keyAt, DateTime.now().millisecondsSinceEpoch);
    _observe(true);
    await launchUrl(Uri.parse(checkout.confirmationUrl), mode: LaunchMode.externalApplication);
  }

  Future<void> checkPending(BuildContext context) async {
    if (_checking) return;
    _checking = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final paymentId = prefs.getString(_keyId);
      final at = prefs.getInt(_keyAt) ?? 0;
      if (paymentId == null) {
        _observe(false);
        return;
      }
      final stale = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at)) > _pendingFor;
      final result = await api.confirmPayment(paymentId);
      if (result.status == 'pending' && !stale) return;
      await prefs.remove(_keyId);
      await prefs.remove(_keyAt);
      _observe(false);
      if (result.status == 'succeeded') {
        final productId = result.productId;
        if (productId != null) completed.value = (productId: productId);
        if (context.mounted) GlitchToast.show(context, context.s.shopPurchased, type: ToastType.success);
      }
    } catch (_) {
    } finally {
      _checking = false;
    }
  }

  void _observe(bool on) {
    if (on == _observing) return;
    _observing = on;
    if (on) {
      WidgetsBinding.instance.addObserver(this);
    } else {
      WidgetsBinding.instance.removeObserver(this);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final context = navigatorKey.currentContext;
    if (context != null) checkPending(context);
  }
}

final shopPurchase = ShopPurchase._();
