import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/services.dart';
import '../core/platform_info.dart';
import '../providers/theme_provider.dart';
import 'glitch_palette.dart';

class _NoPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

/// ⚠️ ПОЧЕМУ РАЗВИЛКА ИМЕННО ПО `isWebPlatform`, А НЕ ПО СПИСКУ ПЛАТФОРМ ВНУТРИ
/// ТЕМЫ. У Flutter Web нет своей `TargetPlatform`: в браузере она равна
/// операционной системе ПОСЕТИТЕЛЯ (сверено с `_platform_web.dart` тега
/// 3.44.4) — Windows даёт `windows`, макбук `macOS`, а телефонный браузер
/// `android`. Значит «отключить анимации для веба», прописав их отключение
/// платформам внутри `builders`, невозможно: ветка `android` там — это ОДИН И
/// ТОТ ЖЕ ключ и для настоящего телефона, и для браузера на телефоне, и
/// отключение убило бы анимации в APK.
PageTransitionsTheme? get _pageTransitions => isWebPlatform
    ? const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: _NoPageTransitionsBuilder(),
          TargetPlatform.iOS: _NoPageTransitionsBuilder(),
          TargetPlatform.macOS: _NoPageTransitionsBuilder(),
          TargetPlatform.windows: _NoPageTransitionsBuilder(),
          TargetPlatform.linux: _NoPageTransitionsBuilder(),
          TargetPlatform.fuchsia: _NoPageTransitionsBuilder(),
        },
      )
    : null;

class GlitchColors {
  static Color get bg        => themeProvider.palette.bg;         // основной фон
  static Color get bgInput   => themeProvider.palette.bgInput;    // поля ввода, поиск
  static Color get bgCard    => themeProvider.palette.bgCard;     // карточки, блоки инфо
  static Color get bgMessage => themeProvider.palette.bgMessage;  // чужое сообщение, typing
  static Color get bgChip    => themeProvider.palette.bgChip;     // крестик удаления участника

  static Color get bgMenu => themeProvider.palette.bgMenu;  // фон PopupMenuButton — единый везде
  static Color get bgToolbar => themeProvider.palette.bgToolbar;
  static Color get bgEmbed => themeProvider.palette.bgEmbed;  // карточка сообщения (embed)
  static Color get bgEmbedForm => themeProvider.palette.bgEmbedForm;  // плашка карточки в конструкторе вебхука
  static Color get bgPicker => themeProvider.palette.bgPicker;          // окно выбора эмодзи/стикеров/гифок на ПК
  static Color get bgPickerNarrow => themeProvider.palette.bgPickerNarrow;  // оно же на телефоне
  static Color get bgPickerRail => themeProvider.palette.bgPickerRail;  // полоса категорий в нём  // панель действий над сообщением (на два тона темнее меню)

  static Color get border      => themeProvider.palette.border;       // основная граница (поля, кнопки)
  static Color get borderCard  => themeProvider.palette.borderCard;   // граница карточек
  static Color get borderSoft  => themeProvider.palette.borderSoft;   // нежная граница (разделители)
  static Color get borderMuted => themeProvider.palette.borderMuted;  // граница строк внутри карточки
  static Color get borderWindow => themeProvider.palette.borderWindow;  // контур окон, попапов, меню
  static Color get borderMessageCard => themeProvider.palette.borderMessageCard;  // контур карточки в переписке (тише окон)
  static Color get borderMenu  => themeProvider.palette.borderMenu;

  static Color get textPrimary => themeProvider.palette.textPrimary;  // основной текст — ДЕФОЛТНЫЙ цвет пунктов меню/кнопок
  static Color get textSecond  => themeProvider.palette.textSecond;   // вторичный текст
  static Color get textHint    => themeProvider.palette.textHint;     // подсказки, метки, время
  static Color get textDim     => themeProvider.palette.textDim;      // иконки, кнопка без звука
  static Color get textNavIdle => themeProvider.palette.textNavIdle; // пункт навигации в покое (канал, разделы над чатами)

  static Color get bgTabBar        => bgCard;     // фон контейнера табов
  static Color get bgTabActive     => bgInput;    // фон активного таба
  static Color get borderTabBar    => borderCard; // граница контейнера
  static Color get borderTabActive => border;     // граница активного таба

  static Color get accentBlue => themeProvider.palette.accent;
  static Color get accentDark => themeProvider.palette.accentDark;
  static const online = Color(0xFF35D07F);  // статус "в сети" — фиксирован, не зависит от темы/акцента
  static const presenceIdle = Color(0xFFF0B232);
  static const presenceDnd = Color(0xFFF23F43);
  static const error  = Color(0xFFFF6B6B);  // деструктивные действия — фиксирован
  static const live   = Color(0xFFED4245);
  static const badge  = Color(0xFFF23F43);
  static const switchOn  = Color(0xFF34c759);
  static const switchOff = Color(0xFF3a3a3a);
  static const inputCut  = Color(0xFFF0B232);
  static const inputPass = Color(0xFF23A55A);
  static const glitchRed  = Color(0xFFFF2D55);
  static const glitchCyan = Color(0xFF00E5FF);

  static LinearGradient get gradientAccent => _actionGradient(themeProvider.palette);

  static final brandActionGradient = _actionGradient(GlitchThemePreset.dark.palette(ThemeProvider.defaultAccent));

  static LinearGradient _actionGradient(GlitchPalette palette) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [palette.accent, palette.accentDark],
  );

  static LinearGradient get gradientMyMessage => LinearGradient(
    begin: const Alignment(-.5, -1),
    end: const Alignment(.5, 1),
    colors: [accentBlue, accentDark],
  );

  static const avatarGradients = [
    LinearGradient(colors: [Color(0xFF5AB8FF), Color(0xFF2B7AF2)]),
    LinearGradient(colors: [Color(0xFFFF7EB3), Color(0xFFFF6A88)]),
    LinearGradient(colors: [Color(0xFF6A8DFF), Color(0xFF7A5CFF)]),
    LinearGradient(colors: [Color(0xFFFFB86B), Color(0xFFFF8C5A)]),
    LinearGradient(colors: [Color(0xFFB06BFF), Color(0xFF7A5CFF)]),
    LinearGradient(colors: [Color(0xFF5AD1A8), Color(0xFF2FAE9A)]),
  ];
}

class AppTheme {
  static ThemeData get current {
    final isLight = themeProvider.isLight;
    return ThemeData(
      brightness: themeProvider.palette.brightness,
      scaffoldBackgroundColor: GlitchColors.bg,
      pageTransitionsTheme: _pageTransitions,
      colorScheme: (isLight ? const ColorScheme.light() : const ColorScheme.dark()).copyWith(
        primary: GlitchColors.accentBlue,
        surface: GlitchColors.bgCard,
      ),
      // Без этой строки движок веб-версии (CanvasKit) качал бы эмодзи-шрифт с
      // серверов Google уже во время работы, и до конца загрузки эмодзи в
      // никах могли бы отображаться чёрно-белым контуром.
      textTheme: (isLight ? ThemeData.light() : ThemeData.dark()).textTheme.apply(
        fontFamily: 'Inter Tight',
        fontFamilyFallback: const ['Noto Color Emoji'],
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: GlitchColors.bgInput,
        hoverColor: Colors.transparent,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        hintStyle: TextStyle(color: GlitchColors.textHint, fontSize: 16),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: GlitchColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: GlitchColors.textPrimary,
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        iconTheme: IconThemeData(color: GlitchColors.accentBlue),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        side: BorderSide(color: GlitchColors.textHint, width: 1.6),
      ),
      dividerColor: GlitchColors.borderSoft,
    );
  }

  static SystemUiOverlayStyle get systemOverlayStyle {
    final isLight = themeProvider.isLight;
    return SystemUiOverlayStyle(
      statusBarColor: GlitchColors.bg,
      statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: GlitchColors.bg,
      systemNavigationBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
    );
  }
}

final ValueNotifier<SystemUiOverlayStyle?> systemOverlayOverride = ValueNotifier(null);

SystemUiOverlayStyle _dimmedOverlayStyle(double alpha, Color barrier) {
  final isLight = themeProvider.isLight;
  return SystemUiOverlayStyle(
    statusBarColor: Color.alphaBlend(barrier.withOpacity(alpha), GlitchColors.bg),
    // Иконки на светлой теме перекрашиваются в белые на середине затемнения:
    // раньше — фон ещё светлый, белые иконки на нём не читались бы; позже —
    // тёмные иконки утонули бы в уже потемневшем фоне. На тёмной теме они и
    // так белые, там переключать нечего.
    statusBarIconBrightness:
        (isLight && alpha < barrier.opacity / 2) ? Brightness.dark : Brightness.light,
  );
}

final Map<Object, ({double alpha, Color barrier})> _statusBarDimmers = {};

final Map<Object, double> _statusBarDimSuppressors = {};

void _setStatusBarDim(Object key, double alpha, Color barrier) {
  if (alpha <= 0.001) {
    _statusBarDimmers.remove(key);
  } else {
    _statusBarDimmers[key] = (alpha: alpha, barrier: barrier);
  }
  _scheduleStatusBarApply();
}

void _setStatusBarDimSuppression(Object key, double factor) {
  if (factor <= 0.001) {
    _statusBarDimSuppressors.remove(key);
  } else {
    _statusBarDimSuppressors[key] = factor.clamp(0.0, 1.0);
  }
  _scheduleStatusBarApply();
}

void _scheduleStatusBarApply() {
  // Запись в systemOverlayOverride помечает на перестройку AnnotatedRegion в
  // main.dart — а он предок всего дерева. Если сделать это ПОСРЕДИ построения
  // кадра, Flutter бросит «setState() or markNeedsBuild() called during
  // build»: предок в этом кадре уже построен. А посреди кадра мы оказываемся
  // как раз в двух местах — didChangeDependencies (первое включение) и dispose
  // (снятие). Тики анимации приходят раньше построения, там писать безопасно.
  final phase = SchedulerBinding.instance.schedulerPhase;
  final midFrame =
      phase == SchedulerPhase.persistentCallbacks || phase == SchedulerPhase.midFrameMicrotasks;
  if (midFrame) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyStatusBarDim());
  } else {
    _applyStatusBarDim();
  }
}

void _applyStatusBarDim() {
  ({double alpha, Color barrier})? strongest;
  for (final v in _statusBarDimmers.values) {
    if (strongest == null || v.alpha > strongest.alpha) strongest = v;
  }
  if (strongest == null) {
    systemOverlayOverride.value = null;
    return;
  }
  double suppression = 0;
  for (final v in _statusBarDimSuppressors.values) {
    if (v > suppression) suppression = v;
  }
  final alpha = strongest.alpha * (1 - suppression);
  systemOverlayOverride.value =
      alpha <= 0.001 ? null : _dimmedOverlayStyle(alpha, strongest.barrier);
}

Future<T> withDimmedStatusBar<T>(Future<T> Function() show) async {
  final key = Object();
  _setStatusBarDim(key, Colors.black54.opacity, Colors.black54);
  try {
    return await show();
  } finally {
    _setStatusBarDim(key, 0, Colors.black54);
  }
}

class ModalStatusBarDim extends StatefulWidget {
  final Widget child;

  const ModalStatusBarDim({super.key, required this.child});

  @override
  State<ModalStatusBarDim> createState() => _ModalStatusBarDimState();
}

class _ModalStatusBarDimState extends State<ModalStatusBarDim> {
  ModalRoute<dynamic>? _route;
  Animation<double>? _animation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == _route) return;
    _animation?.removeListener(_onTick);
    _route = route;
    _animation = route?.animation;
    _animation?.addListener(_onTick);
    _onTick();
  }

  @override
  void dispose() {
    _animation?.removeListener(_onTick);
    _setStatusBarDim(this, 0, Colors.black54);
    super.dispose();
  }

  void _onTick() {
    final route = _route;
    final barrier = route?.barrierColor ?? Colors.black54;
    final raw = (_animation?.value ?? 1.0).clamp(0.0, 1.0);
    final curved = (route?.barrierCurve ?? Curves.ease).transform(raw);
    _setStatusBarDim(this, curved * barrier.opacity, barrier);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class StatusBarDimSuppressor extends StatefulWidget {
  final Widget child;

  const StatusBarDimSuppressor({super.key, required this.child});

  @override
  State<StatusBarDimSuppressor> createState() => _StatusBarDimSuppressorState();
}

class _StatusBarDimSuppressorState extends State<StatusBarDimSuppressor> {
  ModalRoute<dynamic>? _route;
  Animation<double>? _animation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == _route) return;
    _animation?.removeListener(_onTick);
    _route = route;
    _animation = route?.animation;
    _animation?.addListener(_onTick);
    _onTick();
  }

  @override
  void dispose() {
    _animation?.removeListener(_onTick);
    _setStatusBarDimSuppression(this, 0);
    super.dispose();
  }

  void _onTick() {
    _setStatusBarDimSuppression(this, (_animation?.value ?? 1.0).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class StatusBarDimFollow extends StatefulWidget {
  final ValueListenable<double> level;
  final Color barrier;
  final Widget child;

  const StatusBarDimFollow({
    super.key,
    required this.level,
    this.barrier = Colors.black54,
    required this.child,
  });

  @override
  State<StatusBarDimFollow> createState() => _StatusBarDimFollowState();
}

class _StatusBarDimFollowState extends State<StatusBarDimFollow> {
  @override
  void initState() {
    super.initState();
    widget.level.addListener(_onTick);
    _onTick();
  }

  @override
  void didUpdateWidget(StatusBarDimFollow old) {
    super.didUpdateWidget(old);
    if (old.level != widget.level) {
      old.level.removeListener(_onTick);
      widget.level.addListener(_onTick);
      _onTick();
    }
  }

  @override
  void dispose() {
    widget.level.removeListener(_onTick);
    _setStatusBarDim(this, 0, widget.barrier);
    super.dispose();
  }

  void _onTick() =>
      _setStatusBarDim(this, widget.level.value.clamp(0.0, 1.0) * widget.barrier.opacity, widget.barrier);

  @override
  Widget build(BuildContext context) => widget.child;
}
