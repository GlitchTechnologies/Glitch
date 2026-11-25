import { app, crashReporter, Menu } from 'electron';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { installBridge, sendToApp } from './bridge';
import { APP_ID } from './config';
import { installDownloadHandler } from './downloads';
import { dxgiCaptureAvailable } from './dxgi-screen-capture';
import { initGames, stopGames } from './games';
import { initGlobalKeys, stopGlobalKeys } from './global-keys';
import { pauseProgramHotkeys } from './hotkeys';
import { createMainWindow, markQuitting } from './main-window';
import { initLinks, linkFromArgs, onPageGone, openLink } from './links';
import { requestAttention, setNotificationClickHandler } from './notifications';
import { installPermissionHandlers } from './permissions';
import { closeAllPopouts, initPopouts } from './popouts';
import { bindScreenShareLifecycle, finishScreenShareOnQuit, installDisplayMediaHandler } from './screen-share';
import { bringToFront, reloadApp, startApp } from './startup';
import { store } from './store';
import { launchedAtLogin } from './system-settings';
import { consumeHiddenAfterUpdate } from './updater';
import { applyUnreadBadge, createTray, destroyTray, maybeShowTrayHint, setTrayVoice, setUnread } from './tray';
import { initLog, logEvent, yesNo } from './log';

if (dxgiCaptureAvailable()) {
  const features = new Set(app.commandLine.getSwitchValue('disable-features').split(',').filter(Boolean));
  features.add('BreakoutBoxEagerConversion');
  features.add('WebRtcAllowWgcUsingTexture');
  app.commandLine.appendSwitch('disable-features', [...features].join(','));
}

initLog();

function argvFlags(argv: readonly string[]): string {
  return `автозапуск: ${yesNo(launchedAtLogin(argv))}, ссылка: ${yesNo(linkFromArgs(argv) !== null)}`;
}

if (!app.requestSingleInstanceLock()) {
  logEvent(`второй запуск (${argvFlags(process.argv)}): программа уже работает — передаю ей и выхожу`);
  app.quit();
} else {
  logEvent(`запуск (${argvFlags(process.argv)})`);
  if (app.commandLine.hasSwitch('glitch-capture-crash-diagnostics')) {
    try {
      const dumps = join(app.getPath('userData'), 'capture-crash-dumps');
      mkdirSync(dumps, { recursive: true });
      app.setPath('crashDumps', dumps);
      crashReporter.start({ uploadToServer: false });
      logEvent('диагностика захвата: включено локальное сохранение дампов в capture-crash-dumps');
    } catch (error) {
      console.warn('Диагностика захвата: не удалось включить сохранение дампов', error);
    }
    app.on('child-process-gone', (_event, details) => {
      if (details.type !== 'GPU' || details.reason === 'clean-exit') return;
      console.error('Процесс GPU завершился:', details.reason, 'код:', details.exitCode);
    });
  }
  app.setAppUserModelId(APP_ID);

  app.commandLine.appendSwitch('autoplay-policy', 'no-user-gesture-required');

  Menu.setApplicationMenu(null);

  app.on('second-instance', (_event, argv) => {
    logEvent(`второй запуск получен (${argvFlags(argv)})`);
    if (launchedAtLogin(argv)) return;
    const link = linkFromArgs(argv);
    if (link) openLink(link);
    else bringToFront();
  });

  app.on('before-quit', () => markQuitting('выход программы'));
  app.on('will-quit', () => {
    logEvent('выход: программа закрывается');
    finishScreenShareOnQuit();
    stopGlobalKeys();
    stopGames();
    destroyTray();
    store.flush();
  });

  app.on('window-all-closed', () => undefined);

  app
    .whenReady()
    .then(() => {
      store.load();
      installPermissionHandlers();
      installDisplayMediaHandler();
      installDownloadHandler();
      installBridge();
      initGlobalKeys({
        keys: (keys) => sendToApp('glitch:global-keys', keys),
        status: (status) => sendToApp('glitch:global-keys-status', status),
      });
      initGames({ games: (games) => sendToApp('glitch:running-games', games) });
      initLinks({
        deliver: (url) => sendToApp('glitch:open-link', url),
        attention: () => requestAttention(bringToFront),
      });
      initPopouts({ closed: (kind) => sendToApp('glitch:popout-closed', kind) });
      createTray({
        onOpen: bringToFront,
        onCommand: (command) => sendToApp('glitch:tray-command', command),
      });
      setNotificationClickHandler((chatId, tag) => {
        bringToFront();
        sendToApp('glitch:notification-click', chatId, tag);
      });
      const win = createMainWindow({
        onHiddenByClose: maybeShowTrayHint,
        onReloadRequested: reloadApp,
      });
      win.on('show', applyUnreadBadge);
      bindScreenShareLifecycle(win.webContents);
      win.webContents.on('did-navigate', () => {
        logEvent('страница: загружается заново');
        closeAllPopouts();
        stopGlobalKeys();
        stopGames();
        pauseProgramHotkeys(false);
        onPageGone();
        setUnread(0, null);
        setTrayVoice(null);
      });
      const afterHiddenUpdate = consumeHiddenAfterUpdate(process.argv);
      startApp(win, { hidden: launchedAtLogin(process.argv) || afterHiddenUpdate });
      const startLink = linkFromArgs(process.argv);
      if (startLink) openLink(startLink);
    })
    .catch((e) => {
      console.error('Glitch не запустился', e);
      app.quit();
    });
}
