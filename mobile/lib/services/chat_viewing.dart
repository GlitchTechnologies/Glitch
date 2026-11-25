import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../core/shell_controller.dart' show ShellPlace;
import '../main.dart' show routeObserver;

class ChatViewing extends ChangeNotifier with WidgetsBindingObserver {
  ChatViewing() {
    WidgetsBinding.instance.addObserver(this);
  }

  final Set<_ChatOnScreenState> _marks = {};
  bool _notifyScheduled = false;

  bool get appInFront => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  bool isVisible(int chatId) => _marks.any((m) => m.chatId == chatId && m.visible);

  bool isWatching(int chatId) => appInFront && isVisible(chatId);

  ModalRoute<void>? routeOf(int chatId) {
    ModalRoute<void>? any;
    for (final m in _marks) {
      if (m.chatId != chatId) continue;
      if (m.visible) return m.route;
      final route = m.route;
      if (route != null && route.isActive) any = route;
    }
    return any;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => notifyListeners();

  void _changed() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
}

final chatViewing = ChatViewing();

class ChatOnScreen extends StatefulWidget {
  final int? chatId;
  final Widget child;

  const ChatOnScreen({super.key, required this.chatId, required this.child});

  @override
  State<ChatOnScreen> createState() => _ChatOnScreenState();
}

class _ChatOnScreenState extends State<ChatOnScreen> with RouteAware {
  ModalRoute<void>? route;
  bool _levelVisible = true;

  int? get chatId => widget.chatId;

  bool get visible => _levelVisible && (route?.isCurrent ?? false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _levelVisible = ShellPlace.visibleForBuild(context);
    final r = ModalRoute.of<void>(context);
    if (r != route) {
      if (route != null) routeObserver.unsubscribe(this);
      route = r;
      if (r != null) routeObserver.subscribe(this, r);
    }
    chatViewing._marks.add(this);
    chatViewing._changed();
  }

  @override
  void didUpdateWidget(ChatOnScreen old) {
    super.didUpdateWidget(old);
    if (old.chatId != widget.chatId) chatViewing._changed();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    chatViewing._marks.remove(this);
    chatViewing._changed();
    super.dispose();
  }

  @override
  void didPushNext() => chatViewing._changed();

  @override
  void didPopNext() => chatViewing._changed();

  @override
  Widget build(BuildContext context) => widget.child;
}
