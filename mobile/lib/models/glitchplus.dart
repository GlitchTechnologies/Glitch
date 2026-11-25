import '../core/time_json.dart';

class GlitchPlusStatus {
  final bool isActive;
  final DateTime? currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final bool hasPaymentMethod;

  final bool willRenew;
  final int priceRub;

  const GlitchPlusStatus({
    required this.isActive,
    this.currentPeriodEnd,
    required this.cancelAtPeriodEnd,
    required this.hasPaymentMethod,
    required this.willRenew,
    required this.priceRub,
  });

  factory GlitchPlusStatus.fromJson(Map<String, dynamic> j) => GlitchPlusStatus(
    isActive: j['is_active'] == true,
    currentPeriodEnd: j['current_period_end'] != null ? parseUtcLocal(j['current_period_end']) : null,
    cancelAtPeriodEnd: j['cancel_at_period_end'] == true,
    hasPaymentMethod: j['has_payment_method'] == true,
    willRenew: j['will_renew'] as bool? ?? j['cancel_at_period_end'] != true,
    priceRub: j['price_rub'] as int,
  );
}
