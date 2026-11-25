import 'package:flutter/material.dart';
import '../widgets/adaptive_shell.dart' show AdaptiveShell;
import 'shell_controller.dart';

const double kWideLayoutBreakpoint = 900;

bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;

String chatSlotKey(Object chatId) => 'chat:$chatId';

String voiceRoomSlotKey(Object roomId) => 'voice:$roomId';

int? placeIdOfSlotKey(Object? key) {
  if (key is! String) return null;
  for (final prefix in const ['chat:', 'voice:']) {
    if (key.startsWith(prefix)) return int.tryParse(key.substring(prefix.length));
  }
  return null;
}

@immutable
class ServerScope {
  final int serverId;

  const ServerScope(this.serverId);

  @override
  bool operator ==(Object other) => other is ServerScope && other.serverId == serverId;

  @override
  int get hashCode => serverId.hashCode;
}

@immutable
class CatalogScope {
  const CatalogScope._();

  @override
  bool operator ==(Object other) => other is CatalogScope;

  @override
  int get hashCode => (CatalogScope).hashCode;
}

const catalogScope = CatalogScope._();

Object? spaceOfScope(Object? scope) =>
    scope is ServerScope || scope is CatalogScope ? scope : null;

int? serverIdOfScope(Object? scope) => scope is ServerScope ? scope.serverId : null;

@immutable
class CenterRouteTag {
  final Object slotKey;
  final Object? scope;

  const CenterRouteTag(this.slotKey, this.scope);
}

RouteSettings? _centerRouteSettings(ShellSlot slot, Object slotKey, Object? scope) =>
    slot == ShellSlot.main ? RouteSettings(arguments: CenterRouteTag(slotKey, scope)) : null;

Future<T?> openAdaptive<T>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
  ShellSlot slot = ShellSlot.main,
  required Object slotKey,
  bool fullscreenDialog = false,
  double? detailsWidth,
  // Только для `ShellSlot.details`: панель открывается САМА, а не по просьбе
  // человека (список участников и профиль собеседника при входе в
  // переписку). Не помещается в окно — всё равно ложится в каркас и ждёт
  // скрытой, пока окно не расширят. Без него (человек нажал) неуместившаяся
  // панель открывается страницей поверх, как в узком окне: иначе нажатие
  // ничего бы не показало.
  bool ambient = false,
  Object? scope,
}) {
  final noRoom = slot == ShellSlot.details &&
      !ambient &&
      isWideLayout(context) &&
      !AdaptiveShell.detailsFit(context, detailsWidth);
  if (isWideLayout(context) && !noRoom) {
    final content = (slot == ShellSlot.list || slot == ShellSlot.details)
        ? Navigator(
            key: ValueKey(slotKey),
            onGenerateRoute: (_) => MaterialPageRoute(builder: builder),
          )
        : KeyedSubtree(key: ValueKey(slotKey), child: builder(context));
    return shellController
        .show(slot, content, detailsWidth: detailsWidth, scope: scope)
        .then<T?>((_) => null);
  }
  return Navigator.push<T>(
    context,
    MaterialPageRoute(
      builder: builder,
      fullscreenDialog: fullscreenDialog,
      settings: _centerRouteSettings(slot, slotKey, scope),
    ),
  );
}

Future<T?> pushAdaptive<T>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
  required Object slotKey,
}) {
  if (isWideLayout(context) && !Navigator.canPop(context)) {
    return shellController
        .pushMain(KeyedSubtree(key: ValueKey(slotKey), child: builder(context)))
        .then<T?>((_) => null);
  }
  return Navigator.push<T>(context, MaterialPageRoute(builder: builder));
}

Future<T?> openAdaptiveReplacing<T>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
  required Object slotKey,
  ShellSlot slot = ShellSlot.main,
}) {
  final here = ShellPlace.slotOf(context);
  if (here == null) {
    return Navigator.pushAndRemoveUntil<T>(
      context,
      MaterialPageRoute(builder: builder, settings: _centerRouteSettings(slot, slotKey, null)),
      (route) => route.isFirst,
    );
  }
  final future = openAdaptive<T>(
    context,
    builder: builder,
    slot: slot,
    slotKey: slotKey,
  );
  if (here != slot) shellController.close(here);
  return future;
}

Future<T?> openAdaptiveFromLink<T>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
  required Object slotKey,
  ShellSlot slot = ShellSlot.main,
}) {
  if (Navigator.canPop(context)) {
    return Navigator.push<T>(
      context,
      MaterialPageRoute(builder: builder, settings: _centerRouteSettings(slot, slotKey, null)),
    );
  }
  return openAdaptive<T>(context, builder: builder, slot: slot, slotKey: slotKey);
}

void closeAdaptive(BuildContext context, {ShellSlot slot = ShellSlot.main}) {
  if (Navigator.canPop(context)) {
    Navigator.pop(context);
  } else {
    shellController.close(slot);
  }
}

Future<T?> openAdaptiveModal<T>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
  bool fullscreenDialog = true,
}) {
  return Navigator.push<T>(
    context,
    MaterialPageRoute(builder: builder, fullscreenDialog: fullscreenDialog),
  );
}

Future<T?> openAdaptiveOverlay<T>(BuildContext context, {required WidgetBuilder builder}) =>
    Navigator.of(context, rootNavigator: true).push<T>(PageRouteBuilder<T>(
      opaque: false,
      barrierColor: Colors.black.withOpacity(0.75),
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      pageBuilder: (context, _, __) => builder(context),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
    ));

Future<T?> openAdaptiveFullscreen<T>(
  BuildContext context, {
  required Widget Function(BuildContext) narrowBuilder,
  required Widget Function(BuildContext) wideBuilder,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  if (isWideLayout(context)) {
    return navigator.push<T>(PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (ctx, _, __) => wideBuilder(ctx),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.03, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    ));
  }
  return navigator.push<T>(MaterialPageRoute(builder: narrowBuilder));
}

void closeAdaptiveAll(BuildContext context, {ShellSlot slot = ShellSlot.main}) {
  if (ShellPlace.slotOf(context) != null) {
    shellController.closeAll(slot);
  } else {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}
