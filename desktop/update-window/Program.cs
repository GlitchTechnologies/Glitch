
using System;
using System.Globalization;
using System.Windows;
using System.Windows.Media;

namespace GlitchUpdate
{
    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            var options = UpdateWindowOptions.Parse(args);
            if (options == null) return;
            var app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
            app.Run(new UpdateWindow(options));
        }
    }

    internal sealed class UpdateWindowOptions
    {
        public double X { get; private set; }
        public double Y { get; private set; }
        public double Width { get; private set; }
        public double Height { get; private set; }
        public Brush Card { get; private set; } = Brushes.Black;
        public Brush Border { get; private set; } = Brushes.Black;
        public Brush TextColor { get; private set; } = Brushes.White;
        public string Text { get; private set; } = "";

        public static UpdateWindowOptions? Parse(string[] args)
        {
            string? bounds = null, card = null, border = null, textColor = null, text = null;
            foreach (var arg in args)
            {
                if (TryValue(arg, "--bounds=", out var v)) bounds = v;
                else if (TryValue(arg, "--card=", out v)) card = v;
                else if (TryValue(arg, "--border=", out v)) border = v;
                else if (TryValue(arg, "--text-color=", out v)) textColor = v;
                else if (TryValue(arg, "--text=", out v)) text = v;
            }
            if (bounds == null || card == null || border == null || textColor == null || string.IsNullOrEmpty(text)) return null;

            var parts = bounds.Split(',');
            if (parts.Length != 4) return null;
            var numbers = new double[4];
            for (var i = 0; i < 4; i++)
            {
                if (!double.TryParse(parts[i], NumberStyles.Float, CultureInfo.InvariantCulture, out numbers[i])) return null;
            }
            if (numbers[2] <= 0 || numbers[3] <= 0) return null;

            var cardBrush = Hex(card);
            var borderBrush = Hex(border);
            var textBrush = Hex(textColor);
            if (cardBrush == null || borderBrush == null || textBrush == null) return null;

            return new UpdateWindowOptions
            {
                X = numbers[0],
                Y = numbers[1],
                Width = numbers[2],
                Height = numbers[3],
                Card = cardBrush,
                Border = borderBrush,
                TextColor = textBrush,
                Text = text!,
            };
        }

        private static bool TryValue(string arg, string key, out string value)
        {
            if (arg.StartsWith(key, StringComparison.Ordinal))
            {
                value = arg.Substring(key.Length);
                return true;
            }
            value = "";
            return false;
        }

        private static Brush? Hex(string hex)
        {
            if (hex.Length != 7 || hex[0] != '#') return null;
            try
            {
                var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
                brush.Freeze();
                return brush;
            }
            catch (FormatException)
            {
                return null;
            }
        }
    }
}
