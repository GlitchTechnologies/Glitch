import 'dart:async';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/call_platform_web.dart' if (dart.library.io) 'services/call_platform_native.dart';
import 'package:media_kit/media_kit.dart';
import 'package:app_links/app_links.dart';
import 'services/keybinds.dart';
import 'services/share_intake_web.dart' if (dart.library.io) 'services/share_intake_native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glitch/gen_l10n/app_localizations.dart';
import 'core/glitch_link.dart';
import 'core/chat_open.dart';
import 'core/column_widths.dart';
import 'core/glitch_link_open.dart';
import 'core/l10n.dart';
import 'core/platform_info.dart';
import 'theme/app_theme.dart';
import 'theme/glitch_ink.dart';
import 'services/account_session.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/app_sounds.dart';
import 'services/cache_service.dart';
import 'services/error_reporter.dart';
import 'services/push_service.dart';
import 'services/push_target.dart';
import 'services/recent_reactions_service.dart';
import 'services/video_note_camera_service.dart';
import 'services/screen_share_quality.dart';
import 'services/center_place.dart';
import 'services/web_address.dart';
import 'services/websocket_service.dart';
import 'providers/call_provider.dart';
import 'providers/voice_channels.dart';
import 'providers/server_provider.dart' show serverRail;
import 'providers/locale_provider.dart';
import 'providers/theme_provider.dart';
import 'widgets/view_as_bar.dart';
import 'widgets/custom_theme_editor.dart' show CustomThemeEditorFrame;
import 'widgets/call_floating_window.dart';
import 'widgets/incoming_call_card.dart';
import 'widgets/glitch_logo.dart';
import 'widgets/glitch_menu.dart';
import 'widgets/glitch_toast.dart';
import 'widgets/mini_player_overlay.dart';
import 'widgets/voice_audio_unlock.dart';
import 'screens/login_screen.dart';
import 'screens/chats_screen.dart';
import 'widgets/adaptive_shell.dart';
import 'widgets/desktop_title_bar.dart';
import 'widgets/desktop_popout_app.dart';
import 'widgets/theme_workspace.dart';
import 'services/desktop_popouts.dart';
import 'services/desktop_shell.dart';
import 'services/desktop_window.dart';
import 'services/glitch_plus_purchase.dart' show kGlitchPlusPendingPaymentKey;
import 'services/shop_purchase.dart';
import 'screens/forward_target_screen.dart';
import 'core/search_open.dart';
import 'models/chat_arrival.dart';
import 'screens/friends_screen.dart' show FriendsTab;
import 'screens/home_section_screen.dart';
import 'models/shared_content.dart';

final navigatorKey = GlobalKey<NavigatorState>();

final routeObserver = RouteObserver<ModalRoute<void>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    errorReporter.report(details.exception, stack: details.stack,
        context: _flutterErrorContext(details));
    previousOnError?.call(details);
  };


  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    errorReporter.report(error, stack: stack);
    return false;
  };

  if (isWebPlatform) await BrowserContextMenu.disableContextMenu();

  final popout = desktopPopouts.current;
  if (popout != null) {
    await runDesktopPopout(popout);
    return;
  }

  // Адрес в браузере (services/web_address.dart): адреса без `#` и запомнить,
  // с каким адресом открыли страницу, — ДО первого runApp, иначе Flutter
  // успеет выбрать адреса с `#`. Вне браузера — ничего.
  webAddress.start();

  MediaKit.ensureInitialized();

  await initNativeCallStack();

  runApp(const _SplashApp());

  await Future.wait([
    initializeDateFormatting('ru', null),
    initializeDateFormatting('en', null),
    initializeDateFormatting('uk', null),
    initializeDateFormatting('zh', null),
    cache.init(),
    localeProvider.load(),
    themeProvider.load(),
    recentReactions.load(),
    videoNoteCamera.load(),
    screenShareQuality.load(),
    screenShareSound.load(),
    columnWidths.load(),
    keybinds.load(),
    appSounds.load(),
  ]);

  desktopWindow.start();

  final loggedIn = await authService.tryAutoLogin();
  _syncThemeAccount();

  unawaited(authService.flushPendingLogouts());

  runApp(AeroApp(loggedIn: loggedIn));
  desktopWindow.signalReadyAfterFirstFrame();
}

void _syncThemeAccount() {
  final user = authService.currentUser;
  themeProvider.bindAccount(user?.id);
}

/// ЗАЧЕМ (найдено разбором журнала 2026-08-25). В app_logs за 18 дней накопилось
/// 393 записи «Invalid argument(s): string is not well-formed UTF-16» у разных
/// людей и на четырёх разных экранах. Разобрать их было НЕЧЕМ: у ошибок
/// РАЗМЕТКИ стек состоит из одного фреймворка (`addText` → `TextPainter` →
/// `RenderParagraph` → …), ни одного кадра нашего кода в нём нет и быть не
/// может — виджет строился раньше, в другом кадре. Мы отправляли только
/// `exception` и `stack`, то есть ровно ту половину, которая ни на что не
/// отвечает.
String? _flutterErrorContext(FlutterErrorDetails details) {
  try {
    final buf = StringBuffer();
    if (details.library != null) buf.writeln('library: ${details.library}');
    final ctx = details.context;
    if (ctx != null) buf.writeln('context: ${ctx.toDescription()}');
    final info = details.informationCollector?.call();
    if (info != null) {
      for (final node in info) {
        final line = node.toString().trim();
        if (line.isNotEmpty) buf.writeln(line);
      }
    }
    final out = buf.toString().trim();
    return out.isEmpty ? null : out;
  } catch (_) {
    return null;
  }
}

class _SplashApp extends StatelessWidget {
  const _SplashApp();

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0xFF151515),
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF151515),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (_, __) => Scaffold(
          backgroundColor: GlitchColors.bg,
          body: const Center(child: GlitchLogo(size: 88)),
        ),
      ),
    );
  }
}

class AeroApp extends StatefulWidget {
  final bool loggedIn;
  const AeroApp({super.key, required this.loggedIn});

  @override
  State<AeroApp> createState() => _AeroAppState();
}

class _AeroAppState extends State<AeroApp> with WidgetsBindingObserver {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _deepLinkSub;
  StreamSubscription<Uri>? _desktopLinkSub;
  StreamSubscription<SharedContent>? _shareSub;
  bool _handlingShare = false;
  StreamSubscription<void>? _loggedOutSub;
  StreamSubscription<void>? _loggedInSub;
  StreamSubscription<PushTarget>? _pushOpenSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    localeProvider.addListener(_onLocaleChange);
    themeProvider.addListener(_onThemeChange);
    authService.currentUserListenable.addListener(_syncThemeAccount);
    _initDeepLinks();
    _initShareIntake();
    _loggedOutSub = authService.onLoggedOut.listen((_) => _onLoggedOut());
    callProvider.addListener(_onCallProviderChanged);
    voiceChannels.addListener(_onVoiceChannelsChanged);
    wsService.addReconnectListener(_onWsReconnected);
    _pushOpenSub = pushService.onOpen.listen(_openFromPush);
    _loggedInSub = authService.onLoggedIn.listen((_) => accountSession.start());
    if (widget.loggedIn) accountSession.start();
  }

  void _onWsReconnected() {
    PaintingBinding.instance.imageCache.clear();
  }

  void _onCallProviderChanged() {
    final failure = callProvider.consumeFailure();
    if (failure == null) return;   // обычное обновление (тик таймера и т.п.)
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final s = S.of(ctx);
    final text = switch (failure) {
      CallFailure.busy => s.callErrorBusy,
      CallFailure.blocked => s.callErrorBlocked,
      CallFailure.noAccess => s.callErrorNoAccess,
      CallFailure.alreadyInCall => s.callErrorAlreadyInCall,
      CallFailure.tooOften => s.callErrorTooOften,
      CallFailure.noMicrophone => s.callErrorNoMicrophone,
      CallFailure.notConnected => s.callErrorNotConnected,
      CallFailure.gone => s.callErrorGone,
      CallFailure.otherDevice => s.callErrorOtherDevice,
      CallFailure.internal => s.callErrorInternal,
    };
    GlitchToast.show(ctx, text);
  }

  void _onVoiceChannelsChanged() {
    final failure = voiceChannels.consumeFailure();
    if (failure == null) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final s = S.of(ctx);
    final text = switch (failure) {
      VoiceChannelFailure.full => s.voiceChannelFull,
      VoiceChannelFailure.disconnectedByModerator => s.voiceDisconnectedByModerator,
      VoiceChannelFailure.unavailable => s.voiceUnavailable,
      VoiceChannelFailure.noAccess => s.voiceNoAccess,
      VoiceChannelFailure.noMicrophone => s.callErrorNoMicrophone,
      VoiceChannelFailure.otherDevice => s.voiceOtherDevice,
      VoiceChannelFailure.removed => s.voiceRemoved,
      VoiceChannelFailure.lost => s.voiceLost,
    };
    GlitchToast.show(ctx, text);
  }

  Future<void> _onLoggedOut() async {
    GlitchMenuButton.closeAll();
    await accountSession.end();
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deepLinkSub?.cancel();
    _desktopLinkSub?.cancel();
    _shareSub?.cancel();
    _loggedOutSub?.cancel();
    _loggedInSub?.cancel();
    _pushOpenSub?.cancel();
    callProvider.removeListener(_onCallProviderChanged);
    voiceChannels.removeListener(_onVoiceChannelsChanged);
    wsService.removeReconnectListener(_onWsReconnected);
    localeProvider.removeListener(_onLocaleChange);
    themeProvider.removeListener(_onThemeChange);
    authService.currentUserListenable.removeListener(_syncThemeAccount);
    super.dispose();
  }

  /// true — «обработано»: иначе Flutter сам сделал бы `pushNamed` по адресу,
  /// а именованных маршрутов в приложении нет (см. onUnknownRoute). Этот
  /// слушатель стоит раньше слушателя самого MaterialApp — он добавлен в
  /// initState корня, до построения MaterialApp, — поэтому спрашивают его
  /// первым. На телефоне адреса нет — false, как раньше.
  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async {
    if (!isWebPlatform) return false;
    webAddress.arrive(routeInformation.uri);
    return true;
  }

  @override
  Future<bool> didPopRoute() async {
    if (GlitchMenuButton.closeIfOpen()) return true;
    return false;
  }

  void _onLocaleChange() => setState(() {});

  void _onThemeChange() => setState(() {});

  void _initDeepLinks() {
    _deepLinkSub = _appLinks.uriLinkStream.listen(_handleLink);

    _desktopLinkSub = desktopShell?.openLinks.listen(_handleLink);
  }

  void _initShareIntake() {
    initialSharedContent().then((content) {
      if (content != null) _handleSharedContent(content);
    });
    _shareSub = listenSharedContent(_handleSharedContent);
  }

  Future<void> _handleSharedContent(SharedContent shared) async {
    if (shared.isEmpty || _handlingShare) return;
    if (authService.currentUser == null) return;
    _handlingShare = true;
    try {
      final ctx = await _rootContext();
      if (ctx == null || !ctx.mounted) return;
      final content = shared;

      final target = await pickShareTarget(ctx);
      if (target == null || !ctx.mounted) return;
      await openSearchHit(ctx, target, arrival: ChatArrival(shared: content));
    } finally {
      _handlingShare = false;
    }
  }

  Future<BuildContext?> _rootContext() async {
    BuildContext? ctx = navigatorKey.currentContext;
    for (int i = 0; i < 30 && ctx == null; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      ctx = navigatorKey.currentContext;
    }
    return ctx;
  }

  Future<void> _openFromPush(PushTarget target) async {
    if (authService.currentUser == null) return;
    final ctx = await _rootContext();
    if (ctx == null || !ctx.mounted) return;
    try {
      switch (target) {
        case ChatPushTarget(:final chatId):
          await openChatById(ctx, chatId);
        case RoomPushTarget(:final serverId, :final roomId):
          serverRail.openRoom(serverId, roomId);
        case FriendsPushTarget(:final pending):
          await openHomeSection(
            ctx,
            HomeSection.friends,
            friendsTab: pending ? FriendsTab.pending : FriendsTab.all,
          );
      }
    } catch (e) {
      if (ctx.mounted) GlitchToast.show(ctx, errorMessage(e));
    }
  }

  Future<void> _handleLink(Uri uri) async {
    if (_isGlitchPlusReturn(uri)) {
      await _handleGlitchPlusReturn();
      return;
    }

    final target = glitchTargetFromUri(uri);
    final ctx = await _rootContext();
    if (ctx == null) return;
    if (target == null) {
      final host = uri.host.toLowerCase();
      if ((host == linkDomain || host == 'www.$linkDomain') && ctx.mounted) {
        GlitchToast.show(ctx, ctx.s.linkNotFound);
      }
      return;
    }

    await openGlitchLink(ctx, target, onNotFound: () {
      if (ctx.mounted) GlitchToast.show(ctx, ctx.s.linkNotFound);
    });
  }

  bool _isGlitchPlusReturn(Uri uri) {
    if (uri.scheme == 'glitch') return uri.host == 'glitchplus-return';
    if (uri.host == glitchDomain) {
      return uri.path.replaceAll('/', '').trim() == 'glitchplus-return';
    }
    return false;
  }

  bool _confirmingGlitchPlus = false;

  Future<void> _handleGlitchPlusReturn() async {
    if (_confirmingGlitchPlus) return;
    _confirmingGlitchPlus = true;
    try {
      await _confirmGlitchPlusReturn();
    } finally {
      _confirmingGlitchPlus = false;
    }
  }

  Future<void> _confirmGlitchPlusReturn() async {
    final sessionToken = authService.token;
    if (sessionToken == null) return;
    final ctx = await _rootContext();
    if (ctx == null) return;
    await shopPurchase.checkPending(ctx);
    if (!ctx.mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final paymentId = prefs.getString(kGlitchPlusPendingPaymentKey);
    if (paymentId == null) return;
    if (authService.token != sessionToken) return;

    try {
      final status = await api.confirmGlitchPlusPayment(paymentId);
      if (authService.token != sessionToken) return;
      if (status.isActive) {
        final fresh = await api.getMe();
        if (authService.token != sessionToken) return;
        authService.currentUser = fresh;
        if (prefs.getString(kGlitchPlusPendingPaymentKey) == paymentId) {
          await prefs.remove(kGlitchPlusPendingPaymentKey);
        }
      }
      if (!ctx.mounted || authService.token != sessionToken) return;
      if (status.isActive) {
        GlitchToast.show(ctx, ctx.s.glitchPlusActivated, type: ToastType.success);
      } else {
        GlitchToast.show(ctx, ctx.s.glitchPlusPaymentPending, type: ToastType.info);
      }
    } catch (_) {
      if (ctx.mounted && authService.token == sessionToken) GlitchToast.show(ctx, ctx.s.glitchPlusPaymentCheckFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Glitch',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      navigatorObservers: [routeObserver, centerPlace.observer],
      theme: AppTheme.current,
      themeAnimationDuration: Duration.zero,
      locale: localeProvider.locale,
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      onGenerateInitialRoutes: (_) => [
        MaterialPageRoute<void>(
          builder: (_) => widget.loggedIn ? const AdaptiveShell() : const LoginScreen(),
        ),
      ],
      // Страховка от "Null check operator used on a null value" при
      // Navigator.pushNamed на неизвестное имя маршрута (2026-08-21, журнал:
      // 18 крашей у трёх человек с 02.08). Приложение нигде не использует
      // именованные маршруты (вся навигация — императивный Navigator.push),
      // поэтому pushNamed сюда мог прийти только из системной автомаршрутизации
      // Flutter по deep link — тот же intent уже полностью обрабатывает
      // app_links (_initDeepLinks/_handleLink) отдельным, надёжным путём.
      // Корень починен на стороне Android (MainActivity.shouldHandleDeeplinking
      // = false, см. комментарий там) — а это ВТОРОЙ, защитный слой: если
      // pushNamed всё-таки случится (неизвестный нам источник, будущая
      // регрессия), приложение не должно падать целиком. Просто ничего не
      // показываем и снимаем маршрут со стека на следующем кадре — реальная
      // навигация уже сделана обработчиком ссылок.
      onUnknownRoute: (settings) => PageRouteBuilder<void>(
        settings: settings,
        opaque: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, _, __) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final nav = navigatorKey.currentState;
            if (nav != null && nav.canPop()) nav.pop();
          });
          return const SizedBox.shrink();
        },
      ),
      builder: (context, child) {
        Widget content = ThemeWorkspace(
          child: DesktopTitleBarFrame(
            child: CustomThemeEditorFrame(
              child: VoiceAudioUnlock(
                child: Stack(
                  children: [
                    if (child != null) Positioned.fill(child: ViewAsFrame(child: child)),
                    const MiniPlayerOverlay(),
                    const CallFloatingWindow(),
                    const IncomingCallCard(),
                  ],
                ),
              ),
            ),
          ),
        );
        return GlitchInk(
          palette: themeProvider.palette,
          child: ValueListenableBuilder<SystemUiOverlayStyle?>(
            valueListenable: systemOverlayOverride,
            child: content,
            builder: (context, override, child) => AnnotatedRegion<SystemUiOverlayStyle>(
              value: override ?? AppTheme.systemOverlayStyle,
              child: child!,
            ),
          ),
        );
      },
    );
  }
}

