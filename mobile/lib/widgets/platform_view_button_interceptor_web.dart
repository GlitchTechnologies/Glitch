import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

class PlatformViewButtonInterceptor extends StatelessWidget {
  final bool enabled;
  final Widget child;

  const PlatformViewButtonInterceptor({super.key, required this.enabled, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: HtmlElementView.fromTagName(
            tagName: 'div',
            isVisible: false,
            onElementCreated: (raw) {
              final element = raw as web.HTMLElement;
              element.style.width = '100%';
              element.style.height = '100%';
              element.style.cursor = 'pointer';
              element.addEventListener('mousedown', ((web.Event event) {
                event.preventDefault();
              }).toJS);
            },
          ),
        ),
        child,
      ],
    );
  }
}
