import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../core/l10n.dart';
import '../core/achievement_model_style.dart';
import '../theme/app_theme.dart';

class AchievementModelSurface extends StatefulWidget {
  final String url;
  final String poster;
  final VoidCallback onClose;
  const AchievementModelSurface({super.key, required this.url, required this.poster, required this.onClose});
  @override
  State<AchievementModelSurface> createState() => _AchievementModelSurfaceState();
}

class _AchievementModelSurfaceState extends State<AchievementModelSurface> {
  web.HTMLElement? _element;
  JSFunction? _loaded;
  JSFunction? _error;
  JSFunction? _escape;
  Timer? _timeout;
  bool _failed = false;
  bool _loading = true;

  void _created(Object raw) {
    final element = raw as web.HTMLElement;
    if (!mounted) return;
    _element = element;
    element.style.width = '100%';
    element.style.height = '100%';
    _escape = ((web.Event raw) {
      final event = raw as web.KeyboardEvent;
      if (event.key != 'Escape') return;
      event.preventDefault();
      event.stopImmediatePropagation();
      if (mounted) widget.onClose();
    }).toJS;
    web.document.addEventListener('keydown', _escape, true.toJS);
    _loaded = ((web.Event event) {
      _timeout?.cancel();
      if (mounted) setState(() => _loading = false);
    }).toJS;
    _error = ((web.Event event) { _fail(); }).toJS;
    element.addEventListener('load', _loaded);
    element.addEventListener('error', _error);
    unawaited(_start(element));
  }

  Future<void> _start(web.HTMLElement element) async {
    try {
      await _loadEngine();
      if (!mounted || _element != element) return;
      final focusStyle = web.HTMLStyleElement()..textContent = achievementModelFocusCss;
      element.shadowRoot!.appendChild(focusStyle);
      element.setAttribute('camera-controls', '');
      element.setAttribute('reveal', 'auto');
      element.setAttribute('loading', 'eager');
      element.setAttribute('poster', widget.poster);
      element.setAttribute('src', widget.url);
      _timeout = Timer(const Duration(seconds: 90), _fail);
    } catch (error, stack) {
      debugPrint('Achievement model engine: $error\n$stack');
      if (mounted) _fail();
    }
  }

  void _fail() {
    _timeout?.cancel();
    final element = _element;
    if (element != null) element.style.visibility = 'hidden';
    if (mounted) setState(() { _failed = true; _loading = false; });
  }

  @override
  void dispose() {
    _timeout?.cancel();
    if (_escape != null) web.document.removeEventListener('keydown', _escape, true.toJS);
    if (_loaded != null) _element?.removeEventListener('load', _loaded);
    if (_error != null) _element?.removeEventListener('error', _error);
    _element?.removeAttribute('src');
    _element?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      HtmlElementView.fromTagName(key: const ValueKey('surface'), tagName: 'model-viewer', onElementCreated: _created),
      if (_loading)
        const IgnorePointer(key: ValueKey('loading'), child: Center(child: CircularProgressIndicator())),
      if (_failed)
        IgnorePointer(key: const ValueKey('error'),
            child: Center(child: Text(context.s.errorLoad, style: TextStyle(color: GlitchColors.textPrimary)))),
    ],
  );
}

Future<void>? _engine;

Future<void> _loadEngine() => _engine ??= _initializeEngine().catchError((Object error, StackTrace stack) {
  _engine = null;
  Error.throwWithStackTrace(error, stack);
});

Future<void> _initializeEngine() async {
  if (!web.window.customElements.get('model-viewer').isUndefinedOrNull) return;
  final script = web.HTMLScriptElement()
    ..type = 'module'
    ..src = Uri.parse(web.document.baseURI).resolve('assets/packages/model_viewer_plus/assets/model-viewer.min.js').toString();
  final failed = Completer<void>();
  final onError = ((web.Event event) {
    if (!failed.isCompleted) failed.completeError(StateError('model-viewer module failed to load'));
  }).toJS;
  script.addEventListener('error', onError);
  try {
    web.document.head!.appendChild(script);
    await Future.any<void>([
      web.window.customElements.whenDefined('model-viewer').toDart.then<void>((_) {}),
      failed.future,
    ]).timeout(const Duration(seconds: 30));
  } finally {
    script.removeEventListener('error', onError);
    script.remove();
  }
}
