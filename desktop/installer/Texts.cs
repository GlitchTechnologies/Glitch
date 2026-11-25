
using System.Globalization;

namespace GlitchSetup
{
    internal sealed class Texts
    {
        public string InstallTo = "";
        public string Change = "";
        public string Install = "";
        public string Installing = "";
        public string Launching = "";
        public string Failed = "";
        public string Retry = "";
        public string NoSpace = "";
        public string BadFolder = "";
        public string PickFolder = "";

        // Почему не установилось — под «Не удалось установить Glitch».
        // Коды — стандартного установщика (NSIS): 1 — отменили, 2 — прервал
        // сам (у electron-builder чаще всего — не смог удалить прежнюю версию).
        public string FailAborted = "";
        public string FailCancelled = "";
        public string FailCode = "";        // {0} — код
        public string FailNotInstalled = ""; // {0} — папка
        public string FailError = "";       // {0} — текст ошибки

        public string Explain(InstallResult result, string folder) => result.Failure switch
        {
            InstallFailure.EngineCode when result.Code == 2 => FailAborted,
            InstallFailure.EngineCode when result.Code == 1 => FailCancelled,
            InstallFailure.EngineCode => string.Format(FailCode, result.Code),
            InstallFailure.NotInstalled => string.Format(FailNotInstalled, folder),
            _ => string.Format(FailError, result.Message ?? "?"),
        };

        public static readonly Texts Current = ForLanguage(CultureInfo.CurrentUICulture.TwoLetterISOLanguageName);

        private static Texts ForLanguage(string lang)
        {
            switch (lang)
            {
                case "en":
                    return new Texts
                    {
                        InstallTo = "Install to",
                        Change = "Change",
                        Install = "Install",
                        Installing = "Installing…",
                        Launching = "Starting Glitch…",
                        Failed = "Couldn't install Glitch",
                        Retry = "Try again",
                        NoSpace = "Not enough disk space",
                        BadFolder = "Glitch can't be installed to this folder",
                        PickFolder = "Where to install Glitch",
                        FailAborted = "Code 2: the installer stopped. Most often it couldn't remove the previous version of Glitch because its files are in use: Glitch is still running (check the tray) or an antivirus is scanning them. Close Glitch and press Retry.",
                        FailCancelled = "Code 1: the installation was cancelled.",
                        FailCode = "The installer finished with an error, code {0}.",
                        FailNotInstalled = "The installer finished without an error, but Glitch didn't appear in {0}.",
                        FailError = "The installer couldn't start: {0}",
                    };
                case "uk":
                    return new Texts
                    {
                        InstallTo = "Встановити в",
                        Change = "Змінити",
                        Install = "Встановити",
                        Installing = "Встановлення…",
                        Launching = "Запуск Glitch…",
                        Failed = "Не вдалося встановити Glitch",
                        Retry = "Повторити",
                        NoSpace = "Недостатньо місця на диску",
                        BadFolder = "У цю папку встановити Glitch не можна",
                        PickFolder = "Куди встановити Glitch",
                        FailAborted = "Код 2: інсталятор перервав роботу. Найчастіше він не зміг видалити попередню версію Glitch — її файли зайняті: Glitch ще працює (перевірте трей) або їх перевіряє антивірус. Закрийте Glitch і натисніть «Повторити».",
                        FailCancelled = "Код 1: встановлення скасовано.",
                        FailCode = "Інсталятор завершився з помилкою, код {0}.",
                        FailNotInstalled = "Інсталятор завершився без помилки, але Glitch не з’явився в папці {0}.",
                        FailError = "Інсталятор не зміг запуститися: {0}",
                    };
                case "zh":
                    return new Texts
                    {
                        InstallTo = "安装到",
                        Change = "更改",
                        Install = "安装",
                        Installing = "正在安装…",
                        Launching = "正在启动 Glitch…",
                        Failed = "无法安装 Glitch",
                        Retry = "重试",
                        NoSpace = "磁盘空间不足",
                        BadFolder = "无法将 Glitch 安装到此文件夹",
                        PickFolder = "选择 Glitch 的安装位置",
                        FailAborted = "代码 2：安装程序已中止。最常见的原因是无法删除旧版本 Glitch——其文件正被占用：Glitch 仍在运行（请检查托盘），或杀毒软件正在扫描。请关闭 Glitch 后点击“重试”。",
                        FailCancelled = "代码 1：安装已取消。",
                        FailCode = "安装程序出错结束，代码 {0}。",
                        FailNotInstalled = "安装程序已正常结束，但 Glitch 没有出现在 {0} 中。",
                        FailError = "安装程序无法启动：{0}",
                    };
                default:
                    return new Texts
                    {
                        InstallTo = "Установить в",
                        Change = "Изменить",
                        Install = "Установить",
                        Installing = "Установка…",
                        Launching = "Запуск Glitch…",
                        Failed = "Не удалось установить Glitch",
                        Retry = "Повторить",
                        NoSpace = "Недостаточно места на диске",
                        BadFolder = "В эту папку установить Glitch нельзя",
                        PickFolder = "Куда установить Glitch",
                        FailAborted = "Код 2: установщик прервал работу. Чаще всего он не смог удалить прежнюю версию Glitch — её файлы заняты: Glitch ещё работает (проверьте трей) или их проверяет антивирус. Закройте Glitch и нажмите «Повторить».",
                        FailCancelled = "Код 1: установку отменили.",
                        FailCode = "Установщик завершился с ошибкой, код {0}.",
                        FailNotInstalled = "Установщик закончил без ошибки, но Glitch не появился в папке {0}.",
                        FailError = "Установщик не смог запуститься: {0}",
                    };
            }
        }
    }
}
