import 'dart:async';

import 'package:flutter/material.dart';
import '../main.dart' show navigatorKey;
import '../theme/app_theme.dart';
import '../theme/glitch_ink.dart';
import '../theme/glitch_palette.dart';
import 'glitch_dialog.dart' show GlitchCheckMark, glitchWindowShape;
import 'glitch_divider.dart';
import 'glitch_icon_button.dart';
import 'glitch_tooltip.dart' show GlitchTooltip;

const EdgeInsets kGlitchMenuContentPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 6);
const EdgeInsets kMenuItemPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 9);

const double _kMenuRadius = 12;

ShapeBorder glitchMenuShape(BuildContext context) =>
    glitchWindowShape(radius: _kMenuRadius, outline: GlitchInk.of(context).borderWindow);

Widget glitchMenuRow(IconData icon, String label, {bool danger = false}) => Builder(builder: (context) {
      final color = danger ? GlitchColors.error : GlitchInk.of(context).textPrimary;
      return Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: color, fontSize: 15)),
      ]);
    });

Widget glitchMenuTextRow(String label, {bool danger = false, bool? checked, bool enabled = true}) =>
    Builder(builder: (context) {
      final ink = GlitchInk.of(context);
      final color = !enabled
          ? ink.textHint
          : danger
              ? GlitchColors.error
              : ink.textPrimary;
      return Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: color, fontSize: 15))),
        if (checked != null) ...[const SizedBox(width: 12), GlitchCheckMark(value: checked, enabled: enabled)],
      ]);
    });

// Пункт GlitchMenuButton — НЕ flutter'овский PopupMenuItem (тот полагается на
// Navigator.pop изнутри PopupRoute, что сломало бы навигацию экрана в нашем
// собственном Overlay-меню).
class GlitchMenuItem<T> {
  final T? value;
  final Widget child;
  final bool isControl;

  const GlitchMenuItem({required T this.value, required this.child}) : isControl = false;

  const GlitchMenuItem.control({required this.child})
      : value = null,
        isControl = true;
}

GlitchMenuItem<T> glitchMenuDivider<T>() => GlitchMenuItem<T>.control(
      child: glitchMenuSeparator(),
    );

Widget glitchMenuSeparator() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: GlitchDivider(),
    );

Widget _menuEntry<T>(GlitchMenuItem<T> it, VoidCallback onTap) {
  if (it.isControl) return it.child;
  return GlitchMenuTapRow(onTap: onTap, child: it.child);
}

class GlitchMenuTapRow extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const GlitchMenuTapRow({super.key, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(padding: kMenuItemPadding, child: child),
      );
}

class GlitchMenuToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const GlitchMenuToggle({super.key, required this.label, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) => GlitchMenuTapRow(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: glitchMenuTextRow(label, checked: value, enabled: onChanged != null),
      );
}

OverlayState glitchOverlayOf(BuildContext context) =>
    Overlay.maybeOf(context, rootOverlay: true) ?? navigatorKey.currentState!.overlay!;

Offset glitchOverlayPoint(OverlayState overlay, Offset global) {
  final box = overlay.context.findRenderObject();
  return box is RenderBox && box.hasSize ? box.globalToLocal(global) : global;
}

class GlitchMenuButton<T> extends StatefulWidget {
  final Widget icon;
  final List<GlitchMenuItem<T>> Function(BuildContext) itemBuilder;
  final ValueChanged<T> onSelected;
  final double size;
  final double? extent;
  final double iconSize;

  const GlitchMenuButton({
    super.key,
    required this.icon,
    required this.itemBuilder,
    required this.onSelected,
    this.size = 40,
    this.extent = 48,
    this.iconSize = 24,
  });

  // В стопке — «снять» каждого: ОДИН раз, сколько бы раз ни позвали. Снять
  // могут из трёх мест: барьер (касание мимо), выбор пункта и закрытие сверху
  // (кнопка «назад», открытие следующего). Закрытие идёт через анимацию
  // (160 мс), и всё это время меню ещё в дереве и принимает касания — два
  // закрытия внахлёст не гипотеза, а обычный быстрый двойной клик.
  // `OverlayEntry.remove()` второй раз падает, поэтому «снять» идемпотентно —
  // и одной функцией на все три места.
  static final List<({OverlayEntry entry, VoidCallback remove})> _stack = [];

  static bool closeIfOpen() {
    if (_stack.isEmpty) return false;
    _stack.last.remove();
    return true;
  }

  static void closeAll() => _closeAbove(0);

  static void _closeAbove(int depth) {
    while (_stack.length > depth) {
      _stack.last.remove();
    }
  }

  @override
  State<GlitchMenuButton<T>> createState() => _GlitchMenuButtonState<T>();
}

class _GlitchMenuButtonState<T> extends State<GlitchMenuButton<T>> {
  bool _open = false;

  Future<void> _show() async {
    setState(() => _open = true);
    await openGlitchMenu<T>(
      context,
      items: widget.itemBuilder(context),
      onSelected: widget.onSelected,
    );
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) => GlitchIconButton(
        icon: widget.icon,
        size: widget.size,
        extent: widget.extent,
        iconSize: widget.iconSize,
        selected: _open,
        onTap: _show,
      );
}

class _PopupLayer extends InheritedWidget {
  final int depth;

  const _PopupLayer({required this.depth, required super.child});

  static int of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_PopupLayer>()?.depth ?? 0;

  @override
  bool updateShouldNotify(_PopupLayer old) => old.depth != depth;
}

OverlayEntry _pushLayer(BuildContext anchor, VoidCallback removeOnce, WidgetBuilder builder) {
  GlitchTooltip.hide();
  GlitchMenuButton._closeAbove(_PopupLayer.of(anchor));
  final depth = GlitchMenuButton._stack.length + 1;
  final entry = OverlayEntry(builder: (_) => _PopupLayer(depth: depth, child: Builder(builder: builder)));
  GlitchMenuButton._stack.add((entry: entry, remove: removeOnce));
  return entry;
}

void _dropLayer(OverlayEntry entry) {
  final index = GlitchMenuButton._stack.indexWhere((l) => identical(l.entry, entry));
  if (index < 0) return;
  GlitchMenuButton._closeAbove(index + 1);
  GlitchMenuButton._stack.removeAt(index);
}

Future<void> openGlitchMenu<T>(
  BuildContext anchorContext, {
  required List<GlitchMenuItem<T>> items,
  required ValueChanged<T> onSelected,
  bool growRight = false,
  BuildContext? centerInContext,
  GlitchPalette? ink,
}) {
  return _openAnchored(
    anchorContext,
    growRight: growRight,
    centerInContext: centerInContext,
    fitVertically: true,
    builder: (close, maxHeight) => GlitchInk.wrap(ink, _menuMaterial(items, onSelected, close, maxHeight)),
  );
}

/// ⚠️ Заводить ради этого свой `OverlayEntry` по месту было нельзя: у движка
/// в этом файле накоплено ровно то, что по месту забывают — корневой Overlay
/// (иначе в вебе попап уезжает за край своей колонки, реальный баг 2026-08-27),
/// идемпотентное снятие (два закрытия внахлёст роняли бы `remove()`),
/// закрытие системной кнопкой «назад» и «открыт ровно один».
Future<void> openGlitchPopup(
  BuildContext anchorContext, {
  required Widget Function(Future<void> Function() close, double maxHeight) builder,
  required double width,
  bool growRight = false,
  bool centered = false,
  bool preferAbove = false,
  GlitchPopupSide? side,
  Rect? anchorRect,
  double? horizontalScreenMargin,
  bool tapOutsideCloses = true,
  GlitchPalette? ink,
}) {
  return _openAnchored(
    anchorContext,
    growRight: growRight,
    centerOnAnchor: centered,
    preferAbove: preferAbove,
    fitVertically: true,
    fixedWidth: width,
    side: side,
    anchorRect: anchorRect,
    horizontalScreenMargin: horizontalScreenMargin,
    tapOutsideCloses: tapOutsideCloses,
    builder: (close, maxHeight) => GlitchInk.wrap(ink, builder(close, maxHeight)),
  );
}

enum GlitchPopupSide { left, right }

class GlitchPopupCard extends StatelessWidget {
  final Widget child;
  final double maxHeight;

  const GlitchPopupCard({super.key, required this.child, this.maxHeight = double.infinity});

  @override
  Widget build(BuildContext context) {
    final ink = GlitchInk.of(context);
    return Material(
      color: ink.bgMenu,
      shape: glitchMenuShape(context),
      elevation: 8,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: child,
      ),
    );
  }
}

const double _kPopupScreenGap = 12;
const double _kPopupTightHeight = 220;
const double kGlitchPopupSideGap = 8;

Future<void> _openAnchored(
  BuildContext context, {
  required Widget Function(Future<void> Function() close, double maxHeight) builder,
  bool growRight = false,
  BuildContext? centerInContext,
  bool fitVertically = false,
  double? fixedWidth,
  GlitchPopupSide? side,
  bool centerOnAnchor = false,
  bool preferAbove = false,
  Rect? anchorRect,
  double? horizontalScreenMargin,
  bool tapOutsideCloses = true,
}) {
  assert(side == null || fixedWidth != null, 'Сбоку встаёт только попап с известной шириной');
  final overlay = glitchOverlayOf(context);
  final renderBox = context.findRenderObject() as RenderBox;
  final buttonOffset = glitchOverlayPoint(overlay, anchorRect?.topLeft ?? renderBox.localToGlobal(Offset.zero));
  final buttonSize = anchorRect?.size ?? renderBox.size;
  final columnBox = (centerInContext ?? context).findRenderObject() as RenderBox;
  final columnOffset = glitchOverlayPoint(overlay, columnBox.localToGlobal(Offset.zero));
  final columnWidth = columnBox.size.width;
  late OverlayEntry entry;
  final menuKey = GlobalKey<_AnimatedMenuPopState>();

  final closed = Completer<void>();
  var removed = false;
  void removeOnce() {
    if (removed) return;
    removed = true;
    entry.remove();
    closed.complete();
    _dropLayer(entry);
  }

  Future<void> close() async {
    await menuKey.currentState?.hide();
    removeOnce();
  }

  entry = _pushLayer(
    context,
    removeOnce,
    (ctx) {
      final screen = MediaQuery.of(ctx).size;
      final screenW = screen.width;
      final keyboard = MediaQuery.of(ctx).viewInsets.bottom;
      final barrier = tapOutsideCloses
          ? Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => close(),
                child: const SizedBox.shrink(),
              ),
            )
          : const Positioned(left: 0, top: 0, child: SizedBox.shrink());
      if (side != null) {
        final maxHeight = (screen.height - keyboard - _kPopupScreenGap * 2).clamp(0.0, double.infinity);
        return Stack(
          children: [
            barrier,
            Positioned.fill(
              child: CustomSingleChildLayout(
                delegate: _SidePopupLayout(
                  anchor: buttonOffset & buttonSize,
                  side: side,
                  bottomInset: keyboard,
                ),
                child: _AnimatedMenuPop(
                  key: menuKey,
                  alignment: side == GlitchPopupSide.left ? Alignment.topRight : Alignment.topLeft,
                  child: SizedBox(width: fixedWidth, child: builder(close, maxHeight)),
                ),
              ),
            ),
          ],
        );
      }
      final below = screen.height - keyboard - (buttonOffset.dy + buttonSize.height) - _kPopupScreenGap;
      final above = buttonOffset.dy - _kPopupScreenGap;
      final up = fitVertically && (preferAbove ? above > 0 : below < _kPopupTightHeight && above > below);
      final maxHeight = fitVertically ? (up ? above : below).clamp(0.0, double.infinity) : double.infinity;
      final content = fixedWidth == null
          ? builder(close, maxHeight)
          : SizedBox(width: fixedWidth, child: builder(close, maxHeight));
      double? fixedLeft;
      if (fixedWidth != null) {
        final wanted = centerOnAnchor
            ? buttonOffset.dx + (buttonSize.width - fixedWidth) / 2
            : growRight
                ? buttonOffset.dx
                : buttonOffset.dx + buttonSize.width - fixedWidth;
        final horizontalGap = horizontalScreenMargin ?? _kPopupScreenGap;
        final maxLeft = (screenW - fixedWidth - horizontalGap).clamp(horizontalGap, double.infinity);
        fixedLeft = wanted.clamp(horizontalGap, maxLeft);
      }
      return Stack(
        children: [
          barrier,
          Positioned(
            left: fixedLeft ??
                (centerInContext != null ? columnOffset.dx : (growRight ? buttonOffset.dx : null)),
            right: fixedLeft != null
                ? null
                : (centerInContext != null
                    ? screenW - (columnOffset.dx + columnWidth)
                    : (growRight ? null : screenW - (buttonOffset.dx + buttonSize.width))),
            top: up ? null : buttonOffset.dy + buttonSize.height,
            bottom: up ? screen.height - buttonOffset.dy : null,
            child: centerInContext != null
                ? Align(
                    alignment: up ? Alignment.bottomCenter : Alignment.topCenter,
                    child: _AnimatedMenuPop(
                      key: menuKey,
                      alignment: up ? Alignment.bottomCenter : Alignment.topCenter,
                      child: content,
                    ),
                  )
                : _AnimatedMenuPop(
                    key: menuKey,
                    alignment: centerOnAnchor
                        ? (up ? Alignment.bottomCenter : Alignment.topCenter)
                        : growRight
                            ? (up ? Alignment.bottomLeft : Alignment.topLeft)
                            : (up ? Alignment.bottomRight : Alignment.topRight),
                    child: content,
                  ),
          ),
        ],
      );
    },
  );
  overlay.insert(entry);
  return closed.future;
}

Widget _menuMaterial<T>(
  List<GlitchMenuItem<T>> items,
  ValueChanged<T> onSelected,
  Future<void> Function() close,
  double maxHeight,
) {
  return Builder(builder: (context) {
    final ink = GlitchInk.of(context);
    return Material(
      color: ink.bgMenu,
      shape: glitchMenuShape(context),
      elevation: 8,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: IntrinsicWidth(
          child: SingleChildScrollView(
            child: Padding(
              padding: kGlitchMenuContentPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: items
                    .map((it) => _menuEntry(it, () async {
                          await close();
                          onSelected(it.value as T);
                        }))
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  });
}

// Тот же движок, что у GlitchMenuButton (Overlay, закрытие по касанию мимо,
// один открытый экземпляр одновременно, системная кнопка "назад"), но
// открывается не от RenderBox кнопки-триггера, а от точки касания — нужно для
// меню по тапу на сообщение, где нет отдельной кнопки. Клэмпим к границам
// экрана, т.к. точка нажатия может быть где угодно.
Future<void> showGlitchContextMenuAt<T>(
  BuildContext context,
  Offset position,
  List<GlitchMenuItem<T>> items,
  ValueChanged<T> onSelected, {
  GlitchPalette? ink,
  Widget Function(Future<void> Function() close)? headerBuilder,
}) {
  final overlay = glitchOverlayOf(context);
  late OverlayEntry entry;
  final menuKey = GlobalKey<_AnimatedMenuPopState>();

  final closed = Completer<void>();
  var removed = false;
  void removeOnce() {
    if (removed) return;
    removed = true;
    entry.remove();
    closed.complete();
    _dropLayer(entry);
  }

  Future<void> close() async {
    await menuKey.currentState?.hide();
    removeOnce();
  }

  entry = _pushLayer(
    context,
    removeOnce,
    (ctx) => Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => close(),
            child: const SizedBox.shrink(),
          ),
        ),
        GlitchInk.wrap(
          ink,
          _MenuBody<T>(
            tapPosition: glitchOverlayPoint(overlay, position),
            items: items,
            menuKey: menuKey,
            header: headerBuilder == null ? null : headerBuilder(close),
            onSelected: (v) async {
              await close();
              onSelected(v);
            },
          ),
        ),
      ],
    ),
  );
  overlay.insert(entry);
  return closed.future;
}

class _MenuBody<T> extends StatefulWidget {
  final Offset tapPosition;
  final List<GlitchMenuItem<T>> items;
  final GlobalKey<_AnimatedMenuPopState> menuKey;
  final Widget? header;
  final ValueChanged<T> onSelected;

  const _MenuBody({
    super.key,
    required this.tapPosition,
    required this.items,
    required this.menuKey,
    required this.header,
    required this.onSelected,
  });

  @override
  State<_MenuBody<T>> createState() => _MenuBodyState<T>();
}

class _MenuBodyState<T> extends State<_MenuBody<T>> {
  final GlobalKey _contentKey = GlobalKey();
  Size? _measured;

  void _scheduleRemeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderBox = _contentKey.currentContext?.findRenderObject() as RenderBox?;
      final real = renderBox?.size;
      if (real != null && real != _measured) setState(() => _measured = real);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final size = _measured ?? Size(236, widget.items.length * 38.0 + (widget.header != null ? 52 : 0));

    double left = widget.tapPosition.dx - size.width / 2;
    double top = widget.tapPosition.dy - size.height / 2;

    if (left + size.width > screenSize.width - 12) left = screenSize.width - size.width - 12;
    if (left < 12) left = 12;
    if (top + size.height > screenSize.height - 24) top = screenSize.height - size.height - 24;
    if (top < 24) top = 24;

    final originX = ((widget.tapPosition.dx - left) / size.width).clamp(0.0, 1.0);
    final originY = ((widget.tapPosition.dy - top) / size.height).clamp(0.0, 1.0);

    _scheduleRemeasure();

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      left: left,
      top: top,
      child: _AnimatedMenuPop(
        key: widget.menuKey,
        alignment: Alignment(originX * 2 - 1, originY * 2 - 1),
        child: NotificationListener<SizeChangedLayoutNotification>(
          onNotification: (_) {
            _scheduleRemeasure();
            return true;
          },
          child: SizeChangedLayoutNotifier(
            child: Column(
              key: _contentKey,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (widget.header != null) widget.header!,
                if (widget.header != null) const SizedBox(height: 8),
                Material(
                  color: GlitchInk.of(context).bgMenu,
                  shape: glitchMenuShape(context),
                  elevation: 8,
                  clipBehavior: Clip.antiAlias,
                  child: IntrinsicWidth(
                    child: Padding(
                      padding: kGlitchMenuContentPadding,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: widget.items
                            .map((it) => _menuEntry(it, () => widget.onSelected(it.value as T)))
                            .toList(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidePopupLayout extends SingleChildLayoutDelegate {
  final Rect anchor;
  final GlitchPopupSide side;
  final double bottomInset;

  _SidePopupLayout({required this.anchor, required this.side, required this.bottomInset});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    const gap = _kPopupScreenGap;
    final leftX = anchor.left - kGlitchPopupSideGap - child.width;
    final rightX = anchor.right + kGlitchPopupSideGap;
    final fitsLeft = leftX >= gap;
    final fitsRight = rightX + child.width <= size.width - gap;
    final double x = side == GlitchPopupSide.left
        ? (fitsLeft || !fitsRight ? leftX : rightX)
        : (fitsRight || !fitsLeft ? rightX : leftX);
    final maxX = (size.width - child.width - gap).clamp(gap, double.infinity);
    final maxY = (size.height - bottomInset - child.height - gap).clamp(gap, double.infinity);
    return Offset(x.clamp(gap, maxX), anchor.top.clamp(gap, maxY));
  }

  @override
  bool shouldRelayout(_SidePopupLayout old) =>
      old.anchor != anchor || old.side != side || old.bottomInset != bottomInset;
}

class _AnimatedMenuPop extends StatefulWidget {
  final Widget child;
  final Alignment alignment;
  const _AnimatedMenuPop({super.key, required this.child, required this.alignment});

  @override
  State<_AnimatedMenuPop> createState() => _AnimatedMenuPopState();
}

class _AnimatedMenuPopState extends State<_AnimatedMenuPop> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 160));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  Future<void> hide() => _ctrl.reverse().orCancel.catchError((_) {});

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 0.85, end: 1.0).animate(_scale),
      alignment: widget.alignment,
      child: FadeTransition(opacity: _fade, child: widget.child),
    );
  }
}
