import 'package:flutter/widgets.dart';

/// На Android Flutter-кнопка уже получает курсор и нажатия поверх WebView.
class PlatformViewButtonInterceptor extends StatelessWidget {
  final bool enabled;
  final Widget child;

  const PlatformViewButtonInterceptor({super.key, required this.enabled, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
