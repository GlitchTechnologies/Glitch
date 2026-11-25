// Как узнаёт: перечень процессов Windows; у каждого — полный путь к файлу
// (QueryFullProcessImageName) и время запуска (GetProcessTimes). Доступ —
// PROCESS_QUERY_LIMITED_INFORMATION: самый узкий, его хватает и для
// процессов, запущенных от имени администратора (кроме защищённых системных
// — те не игры). Ничего не читает из памяти процессов и не вмешивается в них.
//
// Протокол — строки UTF-8 через стандартные ввод и вывод:
//   программа → сюда:
//     scan                    перечислить запущенные программы;
//   отсюда → программе:
//     ready                   готов;
//     p <мс> <путь>           процесс: время запуска (мс от 1970, UTC) и путь
//                             (путь — до конца строки: в нём бывают пробелы,
//                             перевода строки в пути Windows не бывает);
//     end                     перечень закончен;
//     error <текст>           сбой.
// Ввод закрылся (программа вышла или упала) — выход: этот процесс не должен
// пережить программу и держать её файлы при обновлении.
// ═════════════════════════════════════════════════════════════════════════════

using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace GlitchGames
{
    internal static class Program
    {
        private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;

        // Разница между началом отсчёта Windows (1601) и Unix (1970) в 100 нс.
        private const long UNIX_EPOCH_FILETIME = 116444736000000000L;

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(uint access, bool inherit, int pid);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr handle);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool QueryFullProcessImageName(IntPtr process, uint flags, StringBuilder name, ref uint size);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetProcessTimes(IntPtr process, out long creation, out long exit, out long kernel, out long user);

        private static int Main()
        {
            var output = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false))
            {
                AutoFlush = false,
                NewLine = "\n",
            };
            var input = new StreamReader(Console.OpenStandardInput(), new UTF8Encoding(false));
            try
            {
                output.WriteLine("ready");
                output.Flush();
                string? line;
                while ((line = input.ReadLine()) != null)
                {
                    if (line.Trim() != "scan") continue;
                    Scan(output);
                    output.Flush();
                }
                return 0;
            }
            catch (IOException)
            {
                return 0;
            }
            catch (Exception e)
            {
                try
                {
                    output.WriteLine("error " + OneLine(e.Message));
                    output.Flush();
                }
                catch (IOException)
                {
                }
                return 1;
            }
        }

        private static void Scan(StreamWriter output)
        {
            // С запасом под длинные пути (до 32 767 знаков у Windows).
            var name = new StringBuilder(32768);
            foreach (var process in Process.GetProcesses())
            {
                try
                {
                    if (process.Id == 0 || process.Id == 4) continue;
                    var handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, process.Id);
                    if (handle == IntPtr.Zero) continue;
                    try
                    {
                        name.Clear();
                        uint size = (uint)name.Capacity;
                        if (!QueryFullProcessImageName(handle, 0, name, ref size)) continue;
                        if (!GetProcessTimes(handle, out var creation, out _, out _, out _)) continue;
                        var path = name.ToString(0, (int)size);
                        if (path.IndexOf('\n') >= 0 || path.IndexOf('\r') >= 0) continue;
                        var startedMs = (creation - UNIX_EPOCH_FILETIME) / 10000;
                        output.WriteLine("p " + startedMs + " " + path);
                    }
                    finally
                    {
                        CloseHandle(handle);
                    }
                }
                finally
                {
                    process.Dispose();
                }
            }
            output.WriteLine("end");
        }

        private static string OneLine(string text) =>
            text.Replace("\r", " ").Replace("\n", " ");
    }
}
