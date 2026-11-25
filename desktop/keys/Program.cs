// Как слышит: Raw Input с RIDEV_INPUTSINK — штатный способ Windows отдавать
// ввод программе, чьё окно не активно (так ввод получают игры). Это НЕ перехват
// клавиатуры: нажатия идут дальше как обычно, у других программ ничего не
// отнимается. Окно — невидимое, только для сообщений (HWND_MESSAGE).
//
// Протокол — строки UTF-8 через стандартные ввод и вывод:
//   программа → сюда:
//     watch <имя> <имя> …   слушать эти клавиши (пусто — никакие);
//     reset                 считать всё отпущенным (экран заблокировали, сон);
//   отсюда → программе:
//     ready                 слушаю;
//     heard                 услышал первое нажатие (любое; какое — не говорю);
//     unknown <имя> …       таких клавиш в таблице нет — их не слушаю;
//     keys <имя> …          какие из слушаемых зажаты сейчас (пусто — ни одна);
//     error <текст>         не завёлся.
// Ввод закрылся (программа вышла или упала) — выход: этот процесс не должен
// пережить программу и держать её файлы при обновлении.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace GlitchKeys
{
    internal static class Program
    {
        [STAThread]
        private static int Main()
        {
            var output = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false))
            {
                AutoFlush = true,
                NewLine = "\n",
            };
            Listener listener;
            try
            {
                listener = new Listener(output);
            }
            catch (Exception e)
            {
                output.WriteLine("error " + OneLine(e.Message));
                return 1;
            }

            // Команды читаются в своём потоке, а исполняются в потоке окна:
            // Raw Input принадлежит окну.
            var context = new WindowsFormsSynchronizationContext();
            SynchronizationContext.SetSynchronizationContext(context);
            var reader = new Thread(() =>
            {
                var input = new StreamReader(Console.OpenStandardInput(), new UTF8Encoding(false));
                try
                {
                    string? line;
                    while ((line = input.ReadLine()) != null)
                    {
                        var command = line;
                        context.Post(_ => listener.Command(command), null);
                    }
                }
                catch (IOException)
                {
                }
                context.Post(_ => Application.ExitThread(), null);
            })
            {
                IsBackground = true,
            };
            reader.Start();

            output.WriteLine("ready");
            Application.Run();
            listener.Dispose();
            return 0;
        }

        internal static string OneLine(string text) => text.Replace('\r', ' ').Replace('\n', ' ');
    }

    /// <summary>Невидимое окно, которому Windows отдаёт Raw Input.</summary>
    internal sealed class Listener : NativeWindow, IDisposable
    {
        private readonly StreamWriter _out;

        private HashSet<string> _watched = new HashSet<string>();

        private readonly Dictionary<int, string> _heldKeys = new Dictionary<int, string>();

        private readonly HashSet<string> _heldMouse = new HashSet<string>();
        private string? _sent;
        private bool _heard;
        private bool _mouseOn;

        public Listener(StreamWriter output)
        {
            _out = output;
            CreateHandle(new CreateParams { Parent = HwndMessage });
            Register(Usage.Keyboard, on: true);
        }

        public void Command(string line)
        {
            var parts = line.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 0) return;
            switch (parts[0])
            {
                case "watch":
                    Watch(parts.Skip(1));
                    break;
                case "reset":
                    _heldKeys.Clear();
                    _heldMouse.Clear();
                    Report();
                    break;
            }
        }

        private void Watch(IEnumerable<string> names)
        {
            var list = names.ToList();
            var unknown = list.Where(n => !KeyTable.Known.Contains(n)).ToList();
            if (unknown.Count > 0) _out.WriteLine("unknown " + string.Join(" ", unknown));
            _watched = new HashSet<string>(list.Where(KeyTable.Known.Contains));
            var mouse = _watched.Any(n => n.StartsWith("Mouse", StringComparison.Ordinal));
            if (mouse != _mouseOn)
            {
                Register(Usage.Mouse, mouse);
                _mouseOn = mouse;
                if (!mouse) _heldMouse.Clear();
            }
            Report();
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WmInput) Read(m.LParam);
            base.WndProc(ref m);
        }

        private void Read(IntPtr handle)
        {
            uint size = 0;
            var header = (uint)Marshal.SizeOf(typeof(RawInputHeader));
            if (GetRawInputData(handle, RidInput, IntPtr.Zero, ref size, header) != 0 || size == 0) return;
            var buffer = Marshal.AllocHGlobal((int)size);
            try
            {
                if (GetRawInputData(handle, RidInput, buffer, ref size, header) != size) return;
                var type = Marshal.ReadInt32(buffer);
                var data = IntPtr.Add(buffer, (int)header);
                if (type == RimTypeKeyboard) OnKey(data);
                else if (type == RimTypeMouse) OnMouse(data);
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }

        private void OnKey(IntPtr data)
        {
            var makeCode = (ushort)Marshal.ReadInt16(data, 0);
            var flags = (ushort)Marshal.ReadInt16(data, 2);
            var vKey = (ushort)Marshal.ReadInt16(data, 6);
            var up = (flags & RiKeyBreak) != 0;
            Heard();
            var name = KeyTable.NameOf(makeCode, (flags & RiKeyE0) != 0, vKey, out var id);
            if (name == null) return;
            if (up)
            {
                if (_heldKeys.Remove(id)) Report();
            }
            else if (_watched.Contains(name) && !_heldKeys.ContainsKey(id))
            {
                _heldKeys[id] = name;
                Report();
            }
        }

        private void OnMouse(IntPtr data)
        {
            var buttons = (ushort)Marshal.ReadInt16(data, 4);
            if (buttons == 0) return; // движение и колесо
            Heard();
            var changed = false;
            changed |= Button(buttons, 0x0010, 0x0020, "Mouse3");
            changed |= Button(buttons, 0x0040, 0x0080, "Mouse4");
            changed |= Button(buttons, 0x0100, 0x0200, "Mouse5");
            if (changed) Report();
        }

        private bool Button(ushort buttons, ushort down, ushort up, string name)
        {
            if ((buttons & up) != 0) return _heldMouse.Remove(name);
            if ((buttons & down) != 0 && _watched.Contains(name)) return _heldMouse.Add(name);
            return false;
        }

        private void Heard()
        {
            if (_heard) return;
            _heard = true;
            _out.WriteLine("heard");
        }

        private void Report()
        {
            var held = _heldKeys.Values.Concat(_heldMouse).Where(_watched.Contains).Distinct().OrderBy(n => n, StringComparer.Ordinal);
            var text = string.Join(" ", held);
            if (text == _sent) return;
            _sent = text;
            _out.WriteLine(text.Length == 0 ? "keys" : "keys " + text);
        }

        private void Register(Usage usage, bool on)
        {
            var device = new RawInputDevice
            {
                UsagePage = 0x01,
                Usage = (ushort)usage,
                Flags = on ? RidevInputSink : RidevRemove,
                Target = on ? Handle : IntPtr.Zero,
            };
            if (!RegisterRawInputDevices(new[] { device }, 1, (uint)Marshal.SizeOf(typeof(RawInputDevice))))
            {
                throw new InvalidOperationException("RegisterRawInputDevices failed: " + Marshal.GetLastWin32Error());
            }
        }

        public void Dispose() => DestroyHandle();

        // ── Windows ──────────────────────────────────────────────────────────

        private static readonly IntPtr HwndMessage = new IntPtr(-3);
        private const int WmInput = 0x00FF;
        private const uint RidInput = 0x10000003;
        private const int RimTypeMouse = 0;
        private const int RimTypeKeyboard = 1;
        private const ushort RiKeyBreak = 0x01;
        private const ushort RiKeyE0 = 0x02;
        private const uint RidevRemove = 0x00000001;
        private const uint RidevInputSink = 0x00000100;

        private enum Usage : ushort
        {
            Mouse = 0x02,
            Keyboard = 0x06,
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct RawInputDevice
        {
            public ushort UsagePage;
            public ushort Usage;
            public uint Flags;
            public IntPtr Target;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct RawInputHeader
        {
            public uint Type;
            public uint Size;
            public IntPtr Device;
            public IntPtr WParam;
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterRawInputDevices(RawInputDevice[] devices, uint count, uint size);

        [DllImport("user32.dll")]
        private static extern uint GetRawInputData(IntPtr rawInput, uint command, IntPtr data, ref uint size, uint headerSize);
    }

    /// <summary>
    /// Клавиша по скан-коду (набор 1, как отдаёт Raw Input; E0 — «расширенная»:
    /// стрелки, правые Ctrl/Alt, Win…) → имя `KeyboardEvent.code`. По месту на
    /// клавиатуре, а не по букве — раскладка не мешает. Левые и правые
    /// Ctrl/Shift/Alt/Win — одно имя, но разные номера: отпустить одну, держа
    /// другую, — не отпустить.
    /// </summary>
    internal static class KeyTable
    {
        private static readonly Dictionary<int, string> Table = new Dictionary<int, string>
        {
            [0x01] = "Escape",
            [0x02] = "Digit1", [0x03] = "Digit2", [0x04] = "Digit3", [0x05] = "Digit4", [0x06] = "Digit5",
            [0x07] = "Digit6", [0x08] = "Digit7", [0x09] = "Digit8", [0x0A] = "Digit9", [0x0B] = "Digit0",
            [0x0C] = "Minus", [0x0D] = "Equal", [0x0E] = "Backspace", [0x0F] = "Tab",
            [0x10] = "KeyQ", [0x11] = "KeyW", [0x12] = "KeyE", [0x13] = "KeyR", [0x14] = "KeyT",
            [0x15] = "KeyY", [0x16] = "KeyU", [0x17] = "KeyI", [0x18] = "KeyO", [0x19] = "KeyP",
            [0x1A] = "BracketLeft", [0x1B] = "BracketRight", [0x1C] = "Enter", [0x1D] = "Control",
            [0x1E] = "KeyA", [0x1F] = "KeyS", [0x20] = "KeyD", [0x21] = "KeyF", [0x22] = "KeyG",
            [0x23] = "KeyH", [0x24] = "KeyJ", [0x25] = "KeyK", [0x26] = "KeyL",
            [0x27] = "Semicolon", [0x28] = "Quote", [0x29] = "Backquote", [0x2A] = "Shift", [0x2B] = "Backslash",
            [0x2C] = "KeyZ", [0x2D] = "KeyX", [0x2E] = "KeyC", [0x2F] = "KeyV", [0x30] = "KeyB",
            [0x31] = "KeyN", [0x32] = "KeyM", [0x33] = "Comma", [0x34] = "Period", [0x35] = "Slash",
            [0x36] = "Shift", [0x37] = "NumpadMultiply", [0x38] = "Alt", [0x39] = "Space", [0x3A] = "CapsLock",
            [0x3B] = "F1", [0x3C] = "F2", [0x3D] = "F3", [0x3E] = "F4", [0x3F] = "F5",
            [0x40] = "F6", [0x41] = "F7", [0x42] = "F8", [0x43] = "F9", [0x44] = "F10",
            [0x46] = "ScrollLock",
            [0x47] = "Numpad7", [0x48] = "Numpad8", [0x49] = "Numpad9", [0x4A] = "NumpadSubtract",
            [0x4B] = "Numpad4", [0x4C] = "Numpad5", [0x4D] = "Numpad6", [0x4E] = "NumpadAdd",
            [0x4F] = "Numpad1", [0x50] = "Numpad2", [0x51] = "Numpad3", [0x52] = "Numpad0", [0x53] = "NumpadDecimal",
            [0x56] = "IntlBackslash", [0x57] = "F11", [0x58] = "F12",
            [0x64] = "F13", [0x65] = "F14", [0x66] = "F15", [0x67] = "F16", [0x68] = "F17", [0x69] = "F18",
            [0x6A] = "F19", [0x6B] = "F20", [0x6C] = "F21", [0x6D] = "F22", [0x6E] = "F23", [0x76] = "F24",
            [E0 | 0x1C] = "NumpadEnter", [E0 | 0x1D] = "Control", [E0 | 0x35] = "NumpadDivide",
            [E0 | 0x38] = "Alt", [E0 | 0x47] = "Home", [E0 | 0x48] = "ArrowUp", [E0 | 0x49] = "PageUp",
            [E0 | 0x4B] = "ArrowLeft", [E0 | 0x4D] = "ArrowRight", [E0 | 0x4F] = "End", [E0 | 0x50] = "ArrowDown",
            [E0 | 0x51] = "PageDown", [E0 | 0x52] = "Insert", [E0 | 0x53] = "Delete",
            [E0 | 0x5B] = "Meta", [E0 | 0x5C] = "Meta", [E0 | 0x5D] = "ContextMenu",
        };

        private static readonly Dictionary<ushort, string> ByVirtualKey = new Dictionary<ushort, string>
        {
            [0x13] = "Pause",
            [0x90] = "NumLock",
            [0x2C] = "PrintScreen",
        };

        private const int E0 = 0x100;
        private const int VirtualKeyBase = 0x10000;

        public static readonly HashSet<string> Known =
            new HashSet<string>(Table.Values.Concat(ByVirtualKey.Values)) { "Mouse3", "Mouse4", "Mouse5" };

        public static string? NameOf(ushort makeCode, bool e0, ushort vKey, out int id)
        {
            if (ByVirtualKey.TryGetValue(vKey, out var special))
            {
                id = VirtualKeyBase | vKey;
                return special;
            }
            id = makeCode | (e0 ? E0 : 0);
            return Table.TryGetValue(id, out var name) ? name : null;
        }
    }
}
