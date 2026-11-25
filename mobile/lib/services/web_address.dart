import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import '../core/adaptive_open.dart';
import '../core/chat_open.dart';
import '../core/glitch_link.dart';
import '../core/glitch_link_open.dart';
import '../core/l10n.dart';
import '../core/platform_info.dart';
import '../core/shell_controller.dart';
import '../main.dart' show navigatorKey;
import '../providers/server_provider.dart';
import '../widgets/glitch_toast.dart';
import 'api_service.dart';
import 'center_place.dart';

/// • ШИРОКОЕ окно — история мест, как у Discord: новое место — новая запись,
///   «назад»/«вперёд» браузера ходят по местам (приходят в [arrive]).
/// • УЗКОЕ окно (браузер телефона) — как приложение на телефоне: «назад»
///   закрывает верхний экран (профиль, переписку), а адрес лишь
///   ПЕРЕПИСЫВАЕТСЯ — обновление страницы и копирование адреса работают.
///   История мест здесь сломала бы привычное: «назад» из профиля поверх
///   переписки уводил бы из переписки целиком.
class WebAddress with WidgetsBindingObserver {
  WebPlace? _pending;

  Object? _owner;
  bool get _attached => _owner != null;

  Route<dynamic>? _shellRoute;

  bool? _wide;

  WebPlace? _shown;

  WebPlace? _target;
  Timer? _targetTimer;
  static const _targetTimeout = Duration(seconds: 10);

  bool _fixNext = false;

  bool _scheduled = false;


  void start() {
    if (!isWebPlatform) return;
    usePathUrlStrategy();
    final place = webPlaceFromPath(Uri.base.path);
    if (place != const ChatsPlace()) _pending = place;
  }

  void attach(Object owner, Route<dynamic>? shellRoute) {
    if (!isWebPlatform) return;
    _owner = owner;
    _shellRoute = shellRoute;
    _wide = null;
    shellController.addListener(_schedule);
    serverRail.addListener(_schedule);
    centerPlace.addListener(_schedule);
    WidgetsBinding.instance.addObserver(this);
    final pending = _pending;
    _pending = null;
    if (pending != null) {
      _shown = pending;
      _go(pending);
    } else {
      _shown = null;
    }
    _schedule();
  }

  void detach(Object owner) {
    if (_owner != owner) return;
    _owner = null;
    _shellRoute = null;
    shellController.removeListener(_schedule);
    serverRail.removeListener(_schedule);
    centerPlace.removeListener(_schedule);
    WidgetsBinding.instance.removeObserver(this);
    _clearTarget();
    _shown = null;
    _fixNext = false;
  }

  @override
  void didChangeMetrics() => _schedule();


  void arrive(Uri uri) {
    final place = webPlaceFromPath(uri.path);
    if (!_attached) {
      _pending = place;
      return;
    }
    _shown = place;
    _go(place);
  }


  Future<void> _go(WebPlace place) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    if (place is LinkPlace) {
      _clearTarget();
      _fixNext = true;
      _schedule();
      await openGlitchLink(ctx, place.target, onNotFound: () {
        if (ctx.mounted) GlitchToast.show(ctx, ctx.s.linkNotFound);
      });
      return;
    }

    _setTarget(place);
    final shellRoute = _shellRoute;
    Navigator.of(ctx).popUntil((r) => r == shellRoute || r.isFirst);

    switch (place) {
      case ChatsPlace(:final chatId?, :final messageId):
        await _openChat(ctx, place, chatId, messageId);
      case ChatsPlace():
        serverRail.selectSpace(null);
      case CatalogPlace():
        serverRail.selectSpace(catalogScope);
      case ServerPlace(:final serverId, :final roomId, :final messageId):
        await _openServer(ctx, place, serverId, roomId, messageId);
      case LinkPlace():
        break; // разобрано выше
    }
  }

  Future<void> _openChat(BuildContext ctx, WebPlace place, int chatId, int? messageId) async {
    try {
      await openChatById(ctx, chatId, messageId: messageId);
    } catch (e) {
      _fail(place);
      final gone = e is ApiException && (e.statusCode == 403 || e.statusCode == 404);
      if (ctx.mounted) GlitchToast.show(ctx, gone ? ctx.s.linkNotFound : errorMessage(e));
    }
  }

  Future<void> _openServer(BuildContext ctx, WebPlace place, int serverId, int? roomId, int? messageId) async {
    await _serversLoaded();
    if (_target != place) return; // перебили другим адресом или вышли
    if (!serverRail.servers.any((server) => server.id == serverId)) {
      _fail(place);
      if (ctx.mounted) GlitchToast.show(ctx, serverRail.error ?? ctx.s.linkNotFound);
      return;
    }
    if (roomId == null) {
      serverRail.selectSpace(ServerScope(serverId));
    } else {
      serverRail.openRoom(serverId, roomId, messageId: messageId);
    }
  }

  Future<void> _serversLoaded() async {
    if (!serverRail.loading) return;
    final done = Completer<void>();
    void check() {
      if (!serverRail.loading && !done.isCompleted) done.complete();
    }
    serverRail.addListener(check);
    try {
      await done.future.timeout(_targetTimeout, onTimeout: () {});
    } finally {
      serverRail.removeListener(check);
    }
  }

  void _setTarget(WebPlace place) {
    _target = place;
    _targetTimer?.cancel();
    _targetTimer = Timer(_targetTimeout, () {
      _target = null;
      _fixNext = true;
      _schedule();
    });
  }

  void _clearTarget() {
    _target = null;
    _targetTimer?.cancel();
    _targetTimer = null;
  }

  void _fail(WebPlace place) {
    if (_target != place) return;
    _clearTarget();
    _fixNext = true;
    _schedule();
  }

  bool _reached(WebPlace place, WebPlace target, {required bool wide}) => switch (target) {
        ChatsPlace(chatId: null) => place is ChatsPlace,
        ChatsPlace(:final chatId) => place is ChatsPlace && place.chatId == chatId,
        ServerPlace(:final serverId, roomId: null) => place is ServerPlace && place.serverId == serverId,
        ServerPlace(:final serverId) => !serverRail.hasRoomRequest &&
            place is ServerPlace &&
            place.serverId == serverId &&
            (place.roomId != null || !wide),
        CatalogPlace() => place is CatalogPlace,
        LinkPlace() => true,
      };


  void _schedule() {
    if (!_attached || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _publish();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _publish() {
    if (!_attached) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    final wide = isWideLayout(ctx);
    if (wide != _wide) {
      _wide = wide;
      _fixNext = true;
    }

    final place = _derive(wide);

    final target = _target;
    if (target != null) {
      if (!_reached(place, target, wide: wide)) return;
      _clearTarget();
      _write(placeWithoutMessage(target) == place ? target : place, replace: true);
      return;
    }

    final shown = _shown;
    if (shown != null && placeWithoutMessage(shown) == place) {
      if (!_fixNext) return;
      _fixNext = false;
      _write(shown, replace: true);
      return;
    }
    final replace = _fixNext || !wide || shown == null || _isAutoStep(shown, place);
    _fixNext = false;
    _write(place, replace: replace);
  }

  void _write(WebPlace place, {required bool replace}) {
    _shown = place;
    if (_wide ?? false) {
      SystemNavigator.selectMultiEntryHistory();
    } else {
      SystemNavigator.selectSingleEntryHistory();
    }
    SystemNavigator.routeInformationUpdated(uri: Uri(path: place.path), replace: replace);
  }

  bool _isAutoStep(WebPlace from, WebPlace to) => switch (from) {
        ChatsPlace(chatId: null) => to is ChatsPlace,
        ServerPlace(:final serverId, roomId: null) => to is ServerPlace && to.serverId == serverId,
        _ => false,
      };

  /// ЧТО СЕЙЧАС В ЦЕНТРЕ — по слоям сверху вниз (`centerPlace.layers`:
  /// переписка-маршрут, переписка в каркасе широкого окна) — первая
  /// переписка с номером, иначе выбранное в полосе пространство.
  WebPlace _derive(bool wide) {
    for (final layer in centerPlace.layers(wide: wide)) {
      final p = _placeOf(layer.slotKey, layer.scope);
      if (p != null) return p;
    }
    final space = serverRail.space;
    if (space is CatalogScope) return const CatalogPlace();
    final serverId = serverIdOfScope(space);
    return serverId != null ? ServerPlace(serverId) : const ChatsPlace();
  }

  WebPlace? _placeOf(Object? slotKey, Object? scope) {
    if (scope is CatalogScope) return const CatalogPlace();
    final id = placeIdOfSlotKey(slotKey);
    if (id == null) return null;
    final serverId = serverIdOfScope(scope);
    return serverId != null ? ServerPlace(serverId, roomId: id) : ChatsPlace(chatId: id);
  }

}

final webAddress = WebAddress();
