import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../core/adaptive_open.dart';
import '../core/column_widths.dart';
import '../core/l10n.dart';
import '../core/platform_info.dart';
import '../core/shell_controller.dart';
import '../screens/chats_screen.dart';
import '../theme/app_theme.dart';
import '../theme/glitch_ink.dart';
import 'theme_workspace.dart';
import '../providers/server_provider.dart';
import '../services/app_fullscreen.dart';
import '../services/desktop_shell.dart';
import '../services/web_address.dart';
import 'account_panel.dart';
import 'resize_handle.dart';
import 'server_catalog_column.dart';
import 'server_channels_view.dart';
import 'server_rail.dart';

class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({super.key});

  static bool detailsFit(BuildContext context, double? width) =>
      _WideLayoutState.columnsFor(MediaQuery.sizeOf(context).width, width ?? kDetailsPanelWidth).details > 0;

  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) webAddress.attach(this, ModalRoute.of(context));
    });
  }

  @override
  void dispose() {
    webAddress.detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isWideLayout(context)) {
      return const Row(
        children: [
          ServerRail(),
          Expanded(child: _RailContent()),
        ],
      );
    }
    return const _CenterSpaceSync(child: _WideLayout());
  }
}

/// Реагирует только на СМЕНУ переписки (её ключа), а не на каждое оповещение
/// каркаса: между выбором «Чатов» и открытием первого чата канал ещё лежит в
/// центре, и любое постороннее оповещение (открылась панель справа) иначе
/// вернуло бы полосу на сообщество.
class _CenterSpaceSync extends StatefulWidget {
  final Widget child;

  const _CenterSpaceSync({required this.child});

  @override
  State<_CenterSpaceSync> createState() => _CenterSpaceSyncState();
}

class _CenterSpaceSyncState extends State<_CenterSpaceSync> {
  Object? _seenMainKey;

  @override
  void initState() {
    super.initState();
    _seenMainKey = shellController.mainKey;
    shellController.addListener(_onShellChange);
  }

  @override
  void dispose() {
    shellController.removeListener(_onShellChange);
    super.dispose();
  }

  void _onShellChange() {
    final key = shellController.mainKey;
    if (key == _seenMainKey) return;
    _seenMainKey = key;
    if (key == null) return;
    serverRail.selectSpace(spaceOfScope(shellController.mainScope));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _WideLayout extends StatefulWidget {
  const _WideLayout();

  @override
  State<_WideLayout> createState() => _WideLayoutState();
}

class _WideLayoutState extends State<_WideLayout> {
  static const _listColumn = ColumnWidth(id: 'list', initial: 328, min: 240, max: 440);

  static const double _handleWidth = 6;

  static final Listenable _changes = Listenable.merge([shellController, columnWidths]);

  static ShellColumns columnsFor(double totalWidth, double? details) => ShellColumns.fit(
        space: totalWidth - ServerRail.width - 1,
        list: _listColumn,
        details: details,
      );

  /// Ширина левой колонки в начале жеста — к ней прибавляется сдвиг мыши.
  /// Берётся та, что ВИДНА (с поправкой на окно), а не сохранённая: иначе на
  /// узком окне колонка при первом же движении прыгнула бы.
  double _dragStart = 0;

  static const Duration _detailsAnimDuration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeWorkspace.surface(context, GlitchColors.bg),
      body: LayoutBuilder(
        builder: (context, box) => AnimatedBuilder(
          animation: _changes,
          builder: (context, _) => _buildColumns(box.maxWidth),
        ),
      ),
    );
  }

  Widget _buildColumns(double totalWidth) {
    const listCornerRadius = 12.0;
    final frameEdge = ThemeWorkspace.frameEdge(context);
    final details = shellController.details == null
        ? null
        : (shellController.detailsWidth ?? kDetailsPanelWidth);
    final space = totalWidth - ServerRail.width - 1;
    final cols = columnsFor(totalWidth, details);
    return Stack(
      fit: StackFit.expand,
      children: [
        Row(
          children: [
            SizedBox(
              width: ServerRail.width + cols.list,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ListenableBuilder(
                    listenable: AccountPanel.changes,
                    builder: (context, row) => MediaQuery(
                      data: _withPanelInset(MediaQuery.of(context)),
                      child: row!,
                    ),
                    child: Row(
                      children: [
                        const ServerRail(),

                        SizedBox(
                          width: cols.list,
                          child: ShellPlace(
                            slot: ShellSlot.list,
                            visible: true,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  width: listCornerRadius,
                                  height: listCornerRadius,
                                  child: IgnorePointer(
                                    child: ClipPath(
                                      clipper: const _ListCornerCutout(),
                                      child: ColoredBox(
                                        color: ThemeWorkspace.frameSurface(context, GlitchInk.of(context).bgCard),
                                      ),
                                    ),
                                  ),
                                ),
                                ClipRRect(
                                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(listCornerRadius)),
                                  child: _SlotSwitcher(
                                    child: shellController.list ?? const _RailContent(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: ServerRail.width,
                    top: 0,
                    bottom: 0,
                    width: listCornerRadius,
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _ListEdgePainter(edge: frameEdge, radius: listCornerRadius),
                      ),
                    ),
                  ),
                  const Positioned(left: 0, right: 0, bottom: 0, child: AccountPanel()),
                ],
              ),
            ),
            _columnDivider(context),

            Expanded(child: _MainSlot(stack: shellController.mainStack)),

            _DetailsPanel(
              content: shellController.details,
              width: cols.details,
              duration: _detailsAnimDuration,
            ),
          ],
        ),

        Positioned(
          left: ServerRail.width + listCornerRadius,
          top: 0,
          right: 0,
          height: frameEdge.width,
          child: desktopShell == null
              ? const SizedBox.shrink()
              : ValueListenableBuilder<bool>(
                  valueListenable: appFullscreen,
                  builder: (_, fullscreen, line) => fullscreen ? const SizedBox.shrink() : line!,
                  child: IgnorePointer(child: ColoredBox(color: frameEdge.color)),
                ),
        ),

        Positioned(
          left: ServerRail.width + cols.list + 0.5 - _handleWidth / 2,
          top: 0,
          bottom: 0,
          width: _handleWidth,
          child: ResizeHandle(
            axis: Axis.horizontal,
            onDragStart: () => _dragStart = cols.list,
            onDrag: (shift) => columnWidths.set(
              _listColumn,
              math.min(_dragStart + shift, space - cols.details - kMinCenterWidth),
            ),
            onDragEnd: () => columnWidths.save(_listColumn),
            onReset: () => columnWidths.reset(_listColumn),
          ),
        ),
      ],
    );
  }

  static MediaQueryData _withPanelInset(MediaQueryData media) => media.copyWith(
        padding: media.padding.copyWith(bottom: media.padding.bottom + AccountPanel.footprint),
      );
}

class _ListCornerCutout extends CustomClipper<Path> {
  const _ListCornerCutout();

  @override
  Path getClip(Size size) => Path()
    ..lineTo(0, size.height)
    ..arcToPoint(Offset(size.width, 0), radius: Radius.circular(size.width))
    ..close();

  @override
  bool shouldReclip(covariant _ListCornerCutout oldClipper) => false;
}

class _ListEdgePainter extends CustomPainter {
  final BorderSide edge;
  final double radius;

  const _ListEdgePainter({required this.edge, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final inset = edge.width / 2;
    final line = Path()
      ..moveTo(inset, size.height)
      ..lineTo(inset, radius)
      ..arcToPoint(Offset(radius, inset), radius: Radius.circular(radius - inset));
    canvas.drawPath(line, edge.toPaint());
  }

  @override
  bool shouldRepaint(covariant _ListEdgePainter old) => old.edge != edge || old.radius != radius;
}

Widget _columnDivider(BuildContext context) => Container(
      width: 1,
      color: ThemeWorkspace.surface(context, GlitchInk.of(context).borderCard),
    );

class _DetailsPanel extends StatefulWidget {
  final Widget? content;
  final double width;
  final Duration duration;

  const _DetailsPanel({
    required this.content,
    required this.width,
    required this.duration,
  });

  @override
  State<_DetailsPanel> createState() => _DetailsPanelState();
}

class _DetailsPanelState extends State<_DetailsPanel> {
  Widget? _last;

  double? _lastWidth;

  @override
  void initState() {
    super.initState();
    _last = widget.content;
    if (widget.width > 0) _lastWidth = widget.width;
  }

  @override
  void didUpdateWidget(covariant _DetailsPanel old) {
    super.didUpdateWidget(old);
    if (widget.content != null) _last = widget.content;
    if (widget.width > 0) _lastWidth = widget.width;
    if (widget.content == null && old.content != null && old.width == 0) {
      _last = null;
      _lastWidth = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = widget.content != null;
    final visible = open && widget.width > 0;
    final layoutWidth = _lastWidth;
    final shown = layoutWidth == null ? null : _last;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: visible ? 1 : 0),
      duration: widget.duration,
      // easeOutCubic — быстрый старт и мягкое торможение: панель успевает
      // «доехать» до того, как глаз начнёт её ждать.
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => SizedBox(width: (layoutWidth ?? 0) * t, child: child),
      onEnd: () {
        if (!open && _last != null && mounted) {
          setState(() {
            _last = null;
            _lastWidth = null;
          });
        }
      },
      child: shown == null
          ? const SizedBox.shrink()
          : ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: layoutWidth!,
                maxWidth: layoutWidth!,
                child: Row(
                  children: [
                    _columnDivider(context),
                    Expanded(
                      child: ExcludeFocus(
                        excluding: !visible,
                        child: TickerMode(
                          enabled: visible,
                          child: ShellPlace(
                            slot: ShellSlot.details,
                            visible: visible,
                            child: _SlotSwitcher(child: shown),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// ПОЧЕМУ КАЖДЫЙ УРОВЕНЬ ОБЁРНУТ ОДИНАКОВО, включая одиночный и даже пустоту.
/// Пробовать «верхний — через _SlotSwitcher, остальные напрямую» нельзя: при
/// снятии верхнего уровня нижний сменил бы форму обёртки, для Flutter это
/// другое место в дереве — и состояние, ради которого всё затевалось,
/// потерялось бы именно в момент возврата назад. По той же причине пустая
/// колонка — не отдельная ветка, а тот же Stack с одним ребёнком: иначе
/// на переходе «пусто ↔ открыт чат» менялся бы тип виджета, и плавное
/// появление (на телефоне и десктопе) пропадало бы.
class _MainSlot extends StatelessWidget {
  final List<Widget> stack;
  const _MainSlot({required this.stack});

  @override
  Widget build(BuildContext context) {
    final List<Widget> levels = stack.isEmpty ? const [_EmptyMain()] : stack;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (int i = 0; i < levels.length; i++)
          Offstage(
            offstage: i != levels.length - 1,
            child: ExcludeFocus(
              excluding: i != levels.length - 1,
              child: TickerMode(
                enabled: i == levels.length - 1,
                child: ShellPlace(
                  slot: ShellSlot.main,
                  visible: i == levels.length - 1,
                  child: _SlotSwitcher(child: levels[i]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Переход внутри уже показанного вложенного Navigator (тот самый «профиль →
/// настройки») эта обёртка не трогает и не может сломать: пока идёт push/pop
/// внутри него, сам объект `shellController.list` не меняется, значит с точки
/// зрения AnimatedSwitcher ничего не произошло.
class _SlotSwitcher extends StatelessWidget {
  final Widget child;
  const _SlotSwitcher({required this.child});

  @override
  Widget build(BuildContext context) {
    if (isWebPlatform) return child;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.04, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _EmptyMain extends StatelessWidget {
  const _EmptyMain();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined, size: 64, color: GlitchColors.textHint),
          const SizedBox(height: 16),
          Text(
            context.s.shellSelectChat,
            style: TextStyle(fontSize: 16, color: GlitchColors.textSecond),
          ),
        ],
      ),
    );
  }
}


class _RailContent extends StatefulWidget {
  const _RailContent();

  @override
  State<_RailContent> createState() => _RailContentState();
}

class _RailContentState extends State<_RailContent> {
  @override
  void initState() {
    super.initState();
    serverRail.addListener(_onChange);
  }

  @override
  void dispose() {
    serverRail.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (serverRail.onCatalog) return const ServerCatalogColumn();
    final id = serverRail.selectedId;
    if (id == null) return const ChatsScreen();

    String? name;
    for (final s in serverRail.servers) {
      if (s.id == id) {
        name = s.name;
        break;
      }
    }

    // ValueKey обязателен: без него переключение между сообществами
    // переиспользовало бы состояние прошлого (прокрутку, свёрнутые
    // категории). Внутри ServerChannelsView есть и didUpdateWidget на этот же
    // случай — это две независимые страховки, и обе нужны: ключ спасает от
    // переиспользования состояния, didUpdateWidget — от устаревших данных,
    // если ключ однажды забудут.
    return ServerChannelsView(key: ValueKey(id), serverId: id, initialName: name);
  }
}
