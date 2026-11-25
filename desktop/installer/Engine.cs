
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace GlitchSetup
{
    internal enum InstallOutcome
    {
        Done,
        /// <summary>Человек отказал Windows в разрешении (UAC) — просто вернуться к выбору.</summary>
        Declined,
        NoSpace,
        Failed,
    }

    internal enum InstallFailure
    {
        None,
        EngineCode,
        NotInstalled,
        /// <summary>Стандартный установщик не запустился или что-то сломалось по дороге (<see cref="InstallResult.Message"/>).</summary>
        Error,
    }

    internal sealed class InstallResult
    {
        public InstallOutcome Outcome;
        public InstallFailure Failure;
        public int? Code;
        public string? Message;
        /// <summary>Где Glitch теперь стоит (у <see cref="InstallOutcome.Done"/>).</summary>
        public string Folder = "";

        public static InstallResult Of(InstallOutcome outcome) => new InstallResult { Outcome = outcome };

        public static InstallResult Failed(InstallFailure failure, int? code = null, string? message = null) =>
            new InstallResult { Outcome = InstallOutcome.Failed, Failure = failure, Code = code, Message = message };
    }

    internal static class Engine
    {
        public const string AppFolderName = "Glitch";

        private const string AppExe = "Glitch.exe";

        /// <summary>Имя в «Установленных приложениях» (nsis.uninstallDisplayName).</summary>
        private const string DisplayName = "Glitch";

        private const int ErrorCancelled = 1223;

        public static string DefaultFolder()
        {
            var existing = FindExistingInstall();
            if (existing != null) return existing;
            var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            return Path.Combine(local, "Programs", AppFolderName);
        }

        public static string FolderFromPicked(string picked)
        {
            var trimmed = picked.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (trimmed.Length == 0) trimmed = picked;
            return string.Equals(Path.GetFileName(trimmed), AppFolderName, StringComparison.OrdinalIgnoreCase)
                ? trimmed
                : Path.Combine(picked, AppFolderName);
        }

        public static string? ExistingParent(string folder)
        {
            try
            {
                var dir = new DirectoryInfo(folder);
                while (dir != null && !dir.Exists) dir = dir.Parent;
                return dir?.FullName;
            }
            catch (Exception)
            {
                return null;
            }
        }

        public static bool IsValidFolder(string folder)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(folder) || !Path.IsPathRooted(folder)) return false;
                if (folder.StartsWith(@"\\", StringComparison.Ordinal)) return false; // сетевые пути
                if (folder.IndexOfAny(Path.GetInvalidPathChars()) >= 0 || folder.Contains("\"")) return false;
                var full = Path.GetFullPath(folder);
                return new DriveInfo(Path.GetPathRoot(full)).DriveType == DriveType.Fixed;
            }
            catch (Exception)
            {
                return false;
            }
        }

        public static long PayloadSize()
        {
            using var stream = Resource("payload-size.txt");
            using var reader = new StreamReader(stream);
            return long.TryParse(reader.ReadToEnd().Trim(), out var size) && size > 0 ? size : 1;
        }

        public static async Task<InstallResult> InstallAsync(string folder, IProgress<double> progress)
        {
            var total = PayloadSize();
            if (!HasSpaceFor(folder, total)) return InstallResult.Of(InstallOutcome.NoSpace);

            var temp = Path.Combine(Path.GetTempPath(), "GlitchSetup-" + Guid.NewGuid().ToString("N"));
            try
            {
                Directory.CreateDirectory(temp);
                var engine = Path.Combine(temp, "glitch-engine.exe");
                await Task.Run(() =>
                {
                    using var source = Resource("glitch-engine.exe");
                    using var target = File.Create(engine);
                    source.CopyTo(target);
                });

                // /D — последним и без кавычек (правило NSIS). /currentuser —
                // установка для этого пользователя, как по умолчанию.
                var start = new ProcessStartInfo(engine, "/S /currentuser /D=" + folder)
                {
                    UseShellExecute = true,
                    WorkingDirectory = temp,
                };
                if (!CanWrite(folder)) start.Verb = "runas"; // Windows спросит разрешение

                Process? process;
                try
                {
                    process = Process.Start(start);
                }
                catch (Win32Exception e) when (e.NativeErrorCode == ErrorCancelled)
                {
                    return InstallResult.Of(InstallOutcome.Declined);
                }
                if (process == null) return InstallResult.Failed(InstallFailure.Error, message: "Process.Start returned null");

                using (process)
                using (var watch = new CancellationTokenSource())
                {
                    var watching = WatchProgress(folder, total, progress, watch.Token);
                    await Task.Run(() => process.WaitForExit());
                    watch.Cancel();
                    await watching;
                    int? code = null;
                    try
                    {
                        code = process.ExitCode;
                    }
                    catch (Exception)
                    {
                    }
                    if (code != null && code != 0) return InstallResult.Failed(InstallFailure.EngineCode, code);
                    var installed = File.Exists(Path.Combine(folder, AppExe)) ? folder : FindExistingInstall();
                    if (installed == null) return InstallResult.Failed(InstallFailure.NotInstalled, code);
                    progress.Report(1);
                    return new InstallResult { Outcome = InstallOutcome.Done, Folder = installed };
                }
            }
            catch (Exception e)
            {
                Trace.WriteLine("GlitchSetup: " + e);
                return InstallResult.Failed(InstallFailure.Error, message: e.Message);
            }
            finally
            {
                // Временный файл — всегда, на любом пути выхода.
                try
                {
                    if (Directory.Exists(temp)) Directory.Delete(temp, true);
                }
                catch (Exception)
                {
                }
            }
        }

        public static void Launch(string folder)
        {
            Process.Start(new ProcessStartInfo(Path.Combine(folder, AppExe))
            {
                UseShellExecute = true,
                WorkingDirectory = folder,
            })?.Dispose();
        }


        private static Stream Resource(string name) =>
            Assembly.GetExecutingAssembly().GetManifestResourceStream(name)
            ?? throw new InvalidOperationException("Нет вложенного файла " + name);

        private static async Task WatchProgress(string folder, long total, IProgress<double> progress, CancellationToken token)
        {
            double shown = 0;
            while (!token.IsCancellationRequested)
            {
                var size = await Task.Run(() => FolderSize(folder));
                var share = Math.Min(0.97, (double)size / total);
                if (share > shown)
                {
                    shown = share;
                    progress.Report(shown);
                }
                try
                {
                    await Task.Delay(250, token);
                }
                catch (TaskCanceledException)
                {
                    return;
                }
            }
        }

        private static long FolderSize(string folder)
        {
            try
            {
                if (!Directory.Exists(folder)) return 0;
                return new DirectoryInfo(folder).EnumerateFiles("*", SearchOption.AllDirectories).Sum(f =>
                {
                    try { return f.Length; }
                    catch (IOException) { return 0L; }
                });
            }
            catch (Exception)
            {
                return 0; // файлы появляются и исчезают на ходу — посчитаем в следующий раз
            }
        }

        private static bool HasSpaceFor(string folder, long total)
        {
            try
            {
                var drive = new DriveInfo(Path.GetPathRoot(Path.GetFullPath(folder)));
                return drive.AvailableFreeSpace > total + total / 2;
            }
            catch (Exception)
            {
                return true; // не смогли узнать — пусть решает сам установщик
            }
        }

        private static bool CanWrite(string folder)
        {
            try
            {
                Directory.CreateDirectory(folder);
                var probe = Path.Combine(folder, ".glitch-write-test");
                File.WriteAllText(probe, "");
                File.Delete(probe);
                return true;
            }
            catch (Exception)
            {
                return false;
            }
        }

        private static string? FindExistingInstall()
        {
            foreach (var hive in new[] { RegistryHive.CurrentUser, RegistryHive.LocalMachine })
            {
                foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
                {
                    try
                    {
                        using var root = RegistryKey.OpenBaseKey(hive, view);
                        using var uninstall = root.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall");
                        if (uninstall == null) continue;
                        foreach (var name in uninstall.GetSubKeyNames())
                        {
                            using var app = uninstall.OpenSubKey(name);
                            if (app == null || !string.Equals(app.GetValue("DisplayName") as string, DisplayName, StringComparison.Ordinal))
                                continue;
                            var folder = app.GetValue("InstallLocation") as string;
                            if (string.IsNullOrWhiteSpace(folder))
                                folder = FolderOfCommand(app.GetValue("UninstallString") as string);
                            if (!string.IsNullOrWhiteSpace(folder) && File.Exists(Path.Combine(folder!, AppExe)))
                                return folder!.TrimEnd('\\');
                        }
                    }
                    catch (Exception)
                    {
                    }
                }
            }
            return null;
        }

        /// <summary>«"C:\...\Uninstall Glitch.exe" /currentuser» → «C:\...».</summary>
        private static string? FolderOfCommand(string? command)
        {
            if (string.IsNullOrWhiteSpace(command)) return null;
            var c = command!.Trim();
            string exe;
            if (c.StartsWith("\"", StringComparison.Ordinal))
            {
                var end = c.IndexOf('"', 1);
                if (end < 0) return null;
                exe = c.Substring(1, end - 1);
            }
            else
            {
                var dot = c.IndexOf(".exe", StringComparison.OrdinalIgnoreCase);
                if (dot < 0) return null;
                exe = c.Substring(0, dot + 4);
            }
            try
            {
                return Path.GetDirectoryName(exe);
            }
            catch (Exception)
            {
                return null;
            }
        }
    }
}
