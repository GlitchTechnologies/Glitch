import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';
import 'glitch_hover_row.dart';
import 'glitch_pressable.dart';
import 'settings_row.dart';
import 'settings_two_pane.dart';
import 'unsaved_changes_bar.dart';
import 'glitch_icon_button.dart';


typedef SettingsGroup<S> = (String? title, List<S> sections);

typedef SettingsContentBuilder<S> = Widget Function(
  S section, {
  Widget? header,
  GlobalKey<State>? sectionKey,
  bool wide,
});

class SettingsDangerAction {
  final String label;
  final VoidCallback onTap;

  final String? value;

  final IconData icon;

  const SettingsDangerAction({
    required this.label,
    required this.onTap,
    this.value,
    this.icon = Icons.delete_outline_rounded,
  });
}

class SettingsWindowSpec<S> {
  final String title;

  final String objectName;

  final Widget? wideMenuHeader;

  final Widget narrowHeader;

  final List<SettingsGroup<S>> groups;
  final String Function(S) label;
  final IconData Function(S) icon;

  final String? Function(S)? subtitle;

  final SettingsContentBuilder<S> content;
  final SettingsDangerAction? danger;

  final S? initialSection;

  const SettingsWindowSpec({
    required this.title,
    required this.objectName,
    required this.narrowHeader,
    required this.groups,
    required this.label,
    required this.icon,
    required this.content,
    this.subtitle,
    this.danger,
    this.wideMenuHeader,
    this.initialSection,
  });

  List<S> get allSections => [for (final g in groups) ...g.sections];
}

extension _GroupParts<S> on SettingsGroup<S> {
  String? get title => $1;
  List<S> get sections => $2;
}


class SettingsWindowNarrow<S> extends StatefulWidget {
  final SettingsWindowSpec<S> spec;

  const SettingsWindowNarrow({super.key, required this.spec});

  @override
  State<SettingsWindowNarrow<S>> createState() => _SettingsWindowNarrowState<S>();
}

class _SettingsWindowNarrowState<S> extends State<SettingsWindowNarrow<S>>
    with ThemeAwareState<SettingsWindowNarrow<S>> {
  @override
  void initState() {
    super.initState();
    final initial = widget.spec.initialSection;
    if (initial != null && widget.spec.allSections.contains(initial)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openSection(initial);
      });
    }
  }

  void _openSection(S section) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsSectionPage<S>(spec: widget.spec, section: section),
      ),
    );
  }

  List<Widget> _rows(List<S> sections) => [
        for (var i = 0; i < sections.length; i++)
          SettingsRow(
            icon: widget.spec.icon(sections[i]),
            label: widget.spec.label(sections[i]),
            border: i < sections.length - 1,
            onTap: () => _openSection(sections[i]),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SettingsPageHeader(title: spec.title),
            Divider(height: 1, color: GlitchColors.borderSoft),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    spec.narrowHeader,
                    for (final g in spec.groups) ...[
                      const SizedBox(height: 18),
                      if (g.title != null)
                        SettingsGroupTitle(g.title!, padding: const EdgeInsets.fromLTRB(6, 0, 6, 8)),
                      SettingsSection(children: _rows(g.sections)),
                    ],
                    if (spec.danger != null) ...[
                      const SizedBox(height: 18),
                      SettingsSection(children: [
                        SettingsRow(
                          icon: spec.danger!.icon,
                          label: spec.danger!.label,
                          labelColor: GlitchColors.error,
                          value: spec.danger!.value,
                          border: false,
                          onTap: spec.danger!.onTap,
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsSectionPage<S> extends StatefulWidget {
  final SettingsWindowSpec<S> spec;
  final S section;

  const SettingsSectionPage({super.key, required this.spec, required this.section});

  @override
  State<SettingsSectionPage<S>> createState() => _SettingsSectionPageState<S>();
}

class _SettingsSectionPageState<S> extends State<SettingsSectionPage<S>>
    with ThemeAwareState<SettingsSectionPage<S>> {
  final _sectionKey = GlobalKey<State>();
  final _guards = <UnsavedGuard>{};

  @override
  Widget build(BuildContext context) {
    // Уйти с несохранёнными правками раздела нельзя — ни кнопкой шапки (она
    // зовёт maybePop), ни системным «назад». WillPopScope, а не PopScope, — по
    // той же причине, что в chat_screen.dart: на части версий Flutter его нет.
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async => !unsavedBlocksLeaving(_guards),
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              SettingsPageHeader(title: widget.spec.label(widget.section)),
              Divider(height: 1, color: GlitchColors.borderSoft),
              Expanded(
                child: UnsavedGuardScope(
                  guards: _guards,
                  child: widget.spec.content(widget.section, sectionKey: _sectionKey, wide: false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsPageHeader extends StatelessWidget {
  final String title;

  const SettingsPageHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 14),
      child: Row(
        children: [
          GlitchIconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: GlitchColors.accentBlue),
            onTap: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsGroupTitle extends StatelessWidget {
  final String text;
  final EdgeInsets padding;

  const SettingsGroupTitle(this.text, {super.key, required this.padding});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: GlitchColors.textHint,
        ),
      ),
    );
  }
}


class SettingsWindowWide<S> extends StatefulWidget {
  final SettingsWindowSpec<S> spec;

  final bool windowed;

  final bool closable;

  const SettingsWindowWide({super.key, required this.spec, this.windowed = false, this.closable = true});

  @override
  State<SettingsWindowWide<S>> createState() => _SettingsWindowWideState<S>();
}

class _SettingsWindowWideState<S> extends State<SettingsWindowWide<S>>
    with ThemeAwareState<SettingsWindowWide<S>> {
  late S? _selected = widget.spec.initialSection;
  final _sectionKey = GlobalKey<State>();

  GlobalKey<NavigatorState> _paneNav = GlobalKey<NavigatorState>();
  final _crumbs = _PaneCrumbs();

  final _blocks = _SectionBlocks();

  @override
  void dispose() {
    _crumbs.dispose();
    _blocks.dispose();
    super.dispose();
  }

  bool _blockedByUnsaved() => unsavedBlocksLeaving(_guards);

  final _guards = <UnsavedGuard>{};

  void _close() {
    if (_blockedByUnsaved()) return;
    Navigator.pop(context);
  }

  void _select(S section) {
    if (section == _selected || _blockedByUnsaved()) return;
    setState(() {
      _selected = section;
      _paneNav = GlobalKey<NavigatorState>();
    });
    _blocks.active = 0;
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (widget.closable && event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _pane(Widget navigator) => widget.windowed
      ? _BlocksScope(
          blocks: _blocks,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) => _crumbs.depth <= 1 && _blocks.onScroll(n),
            child: navigator,
          ),
        )
      : navigator;

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final groups = spec.groups;
    final all = spec.allSections;
    final selected = all.contains(_selected) ? _selected : (all.isEmpty ? null : all.first);
    // _selected держит то, что РЕАЛЬНО показано, — иначе при первом клике
    // сравнение «тот же раздел?» шло бы с null.
    _selected = selected;

    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async => !_blockedByUnsaved(),
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: GlitchColors.bg,
          body: Stack(
            fit: StackFit.expand,
            children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Builder(
                  builder: (context) {
                    final content = selected == null
                        ? const SizedBox.shrink()
                        : spec.content(
                            selected,
                            sectionKey: _sectionKey,
                            wide: true,
                            header: widget.windowed
                                ? null
                                : SettingsSectionHeader(
                                    title: spec.label(selected),
                                    subtitle: spec.subtitle?.call(selected),
                                  ),
                          );
                    return SettingsTwoPane(
                      windowed: widget.windowed,
                      rightTop: widget.windowed
                          ? _WindowTopBar(crumbs: _crumbs, navigator: _paneNav)
                          : null,
                      left: ListView(
                        padding: EdgeInsets.fromLTRB(
                            8, widget.windowed ? SettingsTwoPane.windowTopPad : SettingsTwoPane.topPad, 8, 40),
                        children: [
                          spec.wideMenuHeader ??
                              SettingsGroupTitle(spec.objectName,
                                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 6)),
                          for (var gi = 0; gi < groups.length; gi++) ...[
                            if (gi > 0) ...[
                              const SettingsMenuDivider(),
                              if (groups[gi].title != null)
                                SettingsGroupTitle(groups[gi].title!,
                                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 6)),
                            ],
                            for (final section in groups[gi].sections) ...[
                              SettingsMenuItem(
                                label: spec.label(section),
                                selected: section == selected,
                                onTap: () => _select(section),
                              ),
                              if (widget.windowed && section == selected)
                                _MenuBlocks(blocks: _blocks),
                            ],
                          ],
                          if (spec.danger != null) ...[
                            const SettingsMenuDivider(),
                            SettingsMenuItem(
                              label: spec.danger!.label,
                              color: GlitchColors.error,
                              trailing: Icon(spec.danger!.icon,
                                  size: 18, color: GlitchColors.error),
                              onTap: spec.danger!.onTap,
                            ),
                          ],
                        ],
                      ),
                      right: KeyedSubtree(
                        key: ValueKey(selected),
                        child: UnsavedGuardScope(
                          guards: _guards,
                          child: selected == null
                            ? content
                            : _pane(
                                SettingsPaneScope(
                                  inline: widget.windowed
                                      ? null
                                      : _InlineCrumbs(crumbs: _crumbs, navigator: _paneNav),
                                  child: Navigator(
                                    key: _paneNav,
                                    observers: [_crumbs],
                                    onGenerateRoute: (_) => MaterialPageRoute(
                                      settings: RouteSettings(name: spec.label(selected)),
                                      builder: (_) => content,
                                    ),
                                  ),
                                ),
                              ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              if (!widget.windowed && widget.closable) SettingsCloseButton.corner(onTap: _close),
            ],
          ),
              if (widget.windowed && widget.closable)
                Positioned(top: 0, right: 0, child: SettingsCloseButton.corner(onTap: _close)),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const SettingsSectionHeader({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, color: GlitchColors.textPrimary)),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: TextStyle(fontSize: 14, height: 1.35, color: GlitchColors.textPrimary),
          ),
        ],
      ],
    );
  }
}

class SettingsMenuItem extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final Widget? trailing;
  final VoidCallback onTap;

  const SettingsMenuItem({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.color,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return GlitchHoverRow(
      onTap: onTap,
      selected: selected,
      highlightInset: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color ?? GlitchColors.textPrimary,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class SettingsMenuDivider extends StatelessWidget {
  const SettingsMenuDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: SettingsDivider(),
    );
  }
}

/// РАЗДЕЛИТЕЛЬНАЯ ЛИНИЯ ОКОН НАСТРОЕК — одна на меню и на содержимое
/// разделов (между частями раздела: «Информация об учётной записи» /
/// «Пароль и безопасность»). Своего `Divider` с цветом по месту не писать.
class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(height: 1, thickness: 1, color: GlitchColors.border);
}

/// МЕСТО КНОПКИ — ТОЖЕ ЗДЕСЬ, а не у вызывающего ([SettingsCloseButton.corner]):
/// правый верхний угол, отступ [cornerInset] одинаковый сверху и справа.
/// До 2026-09-24 угол задавался в окне двумя разными числами (сверху 56 — по
/// верху содержимого, справа 24), и кнопка выглядела сползшей вниз (заметил
/// владелец). Одно число на обе стороны — симметрия, которую нельзя сломать
/// правкой одной стороны.
class SettingsCloseButton extends StatelessWidget {
  final VoidCallback onTap;

  final bool _corner;

  static const double cornerInset = 24;


  const SettingsCloseButton({super.key, required this.onTap}) : _corner = false;

  const SettingsCloseButton.corner({super.key, required this.onTap}) : _corner = true;

  @override
  Widget build(BuildContext context) {
    final button = _button();
    if (!_corner) return button;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, cornerInset, cornerInset, 0),
      child: Align(alignment: Alignment.topRight, child: button),
    );
  }

  Widget _button() {
    return GlitchPressable(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: GlitchColors.textSecond, width: 2),
            ),
            child: Icon(Icons.close_rounded, size: 20, color: GlitchColors.textSecond),
          ),
          const SizedBox(height: 6),
          Text(
            'ESC',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: GlitchColors.textSecond),
          ),
        ],
      ),
    );
  }
}



class SettingsPaneScope extends InheritedWidget {
  final Widget? inline;

  const SettingsPaneScope({super.key, this.inline, required super.child});

  static SettingsPaneScope? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsPaneScope>();

  static bool inPane(BuildContext context) => _of(context) != null;

  @override
  bool updateShouldNotify(SettingsPaneScope oldWidget) => false;
}

Future<T?> pushSettingsPage<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
}) {
  final pane = SettingsPaneScope._of(context);
  final inline = pane?.inline;
  return Navigator.of(context).push<T>(
    MaterialPageRoute(
      settings: RouteSettings(name: title),
      builder: (ctx) => _GuardedSubpage(
        child: pane == null
          ? SettingsSubpageFrame(title: title, child: builder(ctx))
          : Material(
              color: GlitchColors.bg,
              child: inline == null
                  ? builder(ctx)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, SettingsTwoPane.topPad, 16, 4),
                          child: inline,
                        ),
                        Expanded(child: builder(ctx)),
                      ],
                    ),
            ),
      ),
    ),
  );
}

class _GuardedSubpage extends StatefulWidget {
  final Widget child;

  const _GuardedSubpage({required this.child});

  @override
  State<_GuardedSubpage> createState() => _GuardedSubpageState();
}

class _GuardedSubpageState extends State<_GuardedSubpage> {
  final _guards = <UnsavedGuard>{};

  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async => !unsavedBlocksLeaving(_guards),
      child: UnsavedGuardScope(guards: _guards, child: widget.child),
    );
  }
}

class SettingsSubpageFrame extends StatelessWidget {
  final String title;
  final Widget child;

  const SettingsSubpageFrame({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: GlitchColors.bg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsPageHeader(title: title),
              Divider(height: 1, color: GlitchColors.borderSoft),
              Expanded(child: child),
            ],
          ),
        ),
      );
}

class _PaneCrumbs extends NavigatorObserver with ChangeNotifier {
  final List<Route<dynamic>> _routes = [];

  List<String> get titles => [
        for (final r in _routes)
          if (r.settings.name != null) r.settings.name!,
      ];

  int get depth => _routes.length;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) _routes.clear();
    _routes.add(route);
    _notifyLater();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _notifyLater();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _notifyLater();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) _routes[i] = newRoute;
    _notifyLater();
  }

  void _notifyLater() {
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
  }
}

class _WindowTopBar extends StatelessWidget {
  final _PaneCrumbs crumbs;
  final GlobalKey<NavigatorState> navigator;

  const _WindowTopBar({required this.crumbs, required this.navigator});

  static const double height = 52;

  static const double cornerGap = SettingsCloseButton.cornerInset * 2 + 36;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: crumbs,
      builder: (context, _) {
        final titles = crumbs.titles;
        final nested = crumbs.depth > 1;
        return Container(
          height: height,
          margin: const EdgeInsets.only(right: cornerGap),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: GlitchColors.border)),
          ),
          child: Row(
            children: [
              if (nested) ...[
                GlitchPressable(
                  onTap: () => navigator.currentState?.maybePop(),
                  child: Icon(Icons.arrow_back_rounded, size: 20, color: GlitchColors.textPrimary),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Row(
                  children: [
                    for (var i = 0; i < titles.length; i++) ...[
                      if (i > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text('/', style: TextStyle(fontSize: 15, color: GlitchColors.textSecond)),
                        ),
                      Flexible(child: _crumb(titles[i], last: i == titles.length - 1)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _crumb(String title, {required bool last}) {
    final text = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 15,
        fontWeight: last ? FontWeight.w700 : FontWeight.w500,
        color: last ? GlitchColors.textPrimary : GlitchColors.textSecond,
      ),
    );
    if (last) return text;
    return ClickableCursor(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => navigator.currentState?.maybePop(),
        child: text,
      ),
    );
  }
}


class _InlineCrumbs extends StatelessWidget {
  final _PaneCrumbs crumbs;
  final GlobalKey<NavigatorState> navigator;

  const _InlineCrumbs({required this.crumbs, required this.navigator});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: crumbs,
      builder: (context, _) {
        final titles = crumbs.titles;
        return Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < titles.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.chevron_right_rounded, size: 22, color: GlitchColors.textSecond),
                ),
              _crumb(titles[i], last: i == titles.length - 1),
            ],
          ],
        );
      },
    );
  }

  Widget _crumb(String title, {required bool last}) {
    final text = Text(
      title,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: last ? GlitchColors.textPrimary : GlitchColors.textSecond,
      ),
    );
    if (last) return text;
    return GlitchPressable(
      onTap: () => navigator.currentState?.maybePop(),
      child: text,
    );
  }
}



/// БЛОК СТРАНИЦЫ РАЗДЕЛА — «Информация об учётной записи», «Пароль и
/// безопасность». Как у Discord: под выбранным пунктом меню окна
/// раскрывается список блоков его страницы, нажатие прокручивает к блоку, а
/// при прокрутке подсвечивается тот, что сейчас наверху.
class SettingsBlock extends StatefulWidget {
  final String title;
  final Widget child;

  const SettingsBlock({super.key, required this.title, required this.child});

  @override
  State<SettingsBlock> createState() => _SettingsBlockState();
}

class _SettingsBlockState extends State<SettingsBlock> {
  final _key = GlobalKey();
  _BlockEntry? _entry;
  _SectionBlocks? _owner;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final owner = context.dependOnInheritedWidgetOfExactType<_BlocksScope>()?.blocks;
    if (owner == _owner) return;
    _owner?.remove(_entry!);
    _owner = owner;
    if (owner != null) {
      _entry = _BlockEntry(widget.title, _key);
      owner.add(_entry!);
    }
  }

  @override
  void didUpdateWidget(SettingsBlock old) {
    super.didUpdateWidget(old);
    if (old.title != widget.title && _entry != null) {
      _entry!.title = widget.title;
      _owner?.changed();
    }
  }

  @override
  void dispose() {
    if (_entry != null) _owner?.remove(_entry!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(key: _key, child: widget.child);
}

class _BlockEntry {
  String title;
  final GlobalKey key;
  _BlockEntry(this.title, this.key);
}

class _SectionBlocks extends ChangeNotifier {
  final List<_BlockEntry> _entries = [];
  int active = 0;
  bool _disposed = false;

  List<String> get titles => [for (final e in _entries) e.title];

  void add(_BlockEntry e) {
    _entries.add(e);
    changed();
  }

  void remove(_BlockEntry e) {
    _entries.remove(e);
    changed();
  }

  void changed() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) notifyListeners();
    });
  }

  void jumpTo(int i) {
    if (i < 0 || i >= _entries.length) return;
    final ctx = _entries[i].key.currentContext;
    if (ctx == null) return;
    active = i;
    notifyListeners();
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  bool onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical || _entries.isEmpty) return false;
    final viewport = n.context?.findRenderObject();
    if (viewport is! RenderBox) return false;
    final top = viewport.localToGlobal(Offset.zero).dy;
    var next = 0;
    if (n.metrics.pixels >= n.metrics.maxScrollExtent - 1) {
      next = _entries.length - 1;
    } else {
      for (var i = 0; i < _entries.length; i++) {
        final box = _entries[i].key.currentContext?.findRenderObject();
        if (box is! RenderBox) continue;
        if (box.localToGlobal(Offset.zero).dy <= top + 24) next = i;
      }
    }
    if (next != active) {
      active = next;
      notifyListeners();
    }
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _BlocksScope extends InheritedWidget {
  final _SectionBlocks blocks;

  const _BlocksScope({required this.blocks, required super.child});

  @override
  bool updateShouldNotify(_BlocksScope old) => old.blocks != blocks;
}

class _MenuBlocks extends StatelessWidget {
  final _SectionBlocks blocks;

  const _MenuBlocks({required this.blocks});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: blocks,
      builder: (context, _) {
        final titles = blocks.titles;
        if (titles.length < 2) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(26, 2, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < titles.length; i++)
                ClickableCursor(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => blocks.jumpTo(i),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: 2,
                            color: i == blocks.active ? GlitchColors.textPrimary : GlitchColors.border,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                titles[i],
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: i == blocks.active ? FontWeight.w600 : FontWeight.w400,
                                  color: i == blocks.active ? GlitchColors.textPrimary : GlitchColors.textSecond,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
