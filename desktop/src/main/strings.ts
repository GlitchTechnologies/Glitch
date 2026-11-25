import { app } from 'electron';
import { store } from './store';

export type Lang = 'ru' | 'en' | 'uk' | 'zh';
const LANGS: readonly Lang[] = ['ru', 'en', 'uk', 'zh'];
const DEFAULT_LANG: Lang = 'ru';

export interface Strings {
  trayTooltip: string;
  trayOpen: string;
  trayMicOff: string;
  traySoundOff: string;
  trayQuit: string;
  unreadBadge: string;
  stillRunningTitle: string;
  stillRunningBody: string;
  splashStarting: string;
  splashConnecting: string;
  splashCheckingUpdates: string;
  splashDownloadingUpdate: string;
  splashInstallingUpdate: string;
  splashOffline: (seconds: number) => string;
  splashRetryNow: string;
}

const TEXTS: Record<Lang, Strings> = {
  ru: {
    trayTooltip: 'Glitch',
    trayOpen: 'Открыть Glitch',
    trayMicOff: 'Выключить микрофон',
    traySoundOff: 'Выключить звук',
    trayQuit: 'Выйти из Glitch',
    unreadBadge: 'Есть непрочитанные сообщения',
    stillRunningTitle: 'Glitch продолжает работать в трее',
    stillRunningBody: 'Чтобы выйти полностью — значок Glitch у часов → «Выйти из Glitch».',
    splashStarting: 'Запуск…',
    splashConnecting: 'Подключение…',
    splashCheckingUpdates: 'Проверка обновлений…',
    splashDownloadingUpdate: 'Загрузка обновления',
    splashInstallingUpdate: 'Установка обновления…',
    splashOffline: (s) => `Нет соединения. Повтор через ${s}…`,
    splashRetryNow: 'Повторить сейчас',
  },
  en: {
    trayTooltip: 'Glitch',
    trayOpen: 'Open Glitch',
    trayMicOff: 'Mute',
    traySoundOff: 'Deafen',
    trayQuit: 'Quit Glitch',
    unreadBadge: 'Unread messages',
    stillRunningTitle: 'Glitch is still running in the tray',
    stillRunningBody: 'To quit completely, click the Glitch icon near the clock → “Quit Glitch”.',
    splashStarting: 'Starting…',
    splashConnecting: 'Connecting…',
    splashCheckingUpdates: 'Checking for updates…',
    splashDownloadingUpdate: 'Downloading update',
    splashInstallingUpdate: 'Installing update…',
    splashOffline: (s) => `No connection. Retrying in ${s}…`,
    splashRetryNow: 'Retry now',
  },
  uk: {
    trayTooltip: 'Glitch',
    trayOpen: 'Відкрити Glitch',
    trayMicOff: 'Вимкнути мікрофон',
    traySoundOff: 'Вимкнути звук',
    trayQuit: 'Вийти з Glitch',
    unreadBadge: 'Є непрочитані повідомлення',
    stillRunningTitle: 'Glitch продовжує працювати в треї',
    stillRunningBody: 'Щоб вийти повністю — значок Glitch біля годинника → «Вийти з Glitch».',
    splashStarting: 'Запуск…',
    splashConnecting: 'Підключення…',
    splashCheckingUpdates: 'Перевірка оновлень…',
    splashDownloadingUpdate: 'Завантаження оновлення',
    splashInstallingUpdate: 'Встановлення оновлення…',
    splashOffline: (s) => `Немає з’єднання. Повтор через ${s}…`,
    splashRetryNow: 'Повторити зараз',
  },
  zh: {
    trayTooltip: 'Glitch',
    trayOpen: '打开 Glitch',
    trayMicOff: '关闭麦克风',
    traySoundOff: '关闭声音',
    trayQuit: '退出 Glitch',
    unreadBadge: '有未读消息',
    stillRunningTitle: 'Glitch 仍在托盘中运行',
    stillRunningBody: '要完全退出，请点击时钟旁的 Glitch 图标 →“退出 Glitch”。',
    splashStarting: '正在启动…',
    splashConnecting: '正在连接…',
    splashCheckingUpdates: '正在检查更新…',
    splashDownloadingUpdate: '正在下载更新',
    splashInstallingUpdate: '正在安装更新…',
    splashOffline: (s) => `无网络连接。${s} 秒后重试…`,
    splashRetryNow: '立即重试',
  },
};

export function isLang(code: string): code is Lang {
  return (LANGS as readonly string[]).includes(code);
}

export function currentLang(): Lang {
  const saved = store.get().locale;
  if (saved && isLang(saved)) return saved;
  const system = app.getLocale().split('-')[0].toLowerCase();
  return isLang(system) ? system : DEFAULT_LANG;
}

export function t(): Strings {
  return TEXTS[currentLang()];
}
