import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/l10n.dart';
import 'api_service.dart';
import 'auth_service.dart';

const kGlitchPlusPendingPaymentKey = 'glitchplus_pending_payment_id';

bool _starting = false;

Future<void> startGlitchPlusPurchase() async {
  if (_starting) return;
  _starting = true;
  final sessionToken = authService.token;
  try {
    final checkout = await api.createGlitchPlusCheckout();
    if (authService.token != sessionToken) return;
    final prefs = await SharedPreferences.getInstance();
    if (authService.token != sessionToken) return;
    final saved = await prefs.setString(kGlitchPlusPendingPaymentKey, checkout.paymentId);
    if (!saved) throw ApiException(appStrings.errorGeneric);
    if (authService.token != sessionToken) return;
    final opened = await launchUrl(Uri.parse(checkout.confirmationUrl), mode: LaunchMode.externalApplication);
    if (!opened) throw ApiException(appStrings.errorGeneric);
  } finally {
    _starting = false;
  }
}
