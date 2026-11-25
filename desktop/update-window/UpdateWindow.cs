
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using GlitchSetup;

namespace GlitchUpdate
{
    internal sealed class UpdateWindow : Window
    {
        private const string AppProcess = "Glitch";

        private static readonly TimeSpan Poll = TimeSpan.FromMilliseconds(250);

        private static readonly TimeSpan Settle = TimeSpan.FromMilliseconds(400);

        private static readonly TimeSpan Limit = TimeSpan.FromMinutes(3);

        private readonly DateTime _started = DateTime.Now;
        private readonly DispatcherTimer _poll = new DispatcherTimer { Interval = Poll };
        private bool _leaving;

        public UpdateWindow(UpdateWindowOptions o)
        {
            Title = "Glitch";
            WindowStartupLocation = WindowStartupLocation.Manual;
            Left = o.X;
            Top = o.Y;
            Width = o.Width;
            Height = o.Height;
            ResizeMode = ResizeMode.NoResize;
            WindowStyle = WindowStyle.None;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            Topmost = true;
            ShowInTaskbar = true;
            FontFamily = new FontFamily("Segoe UI");
            UseLayoutRounding = true;

            var panel = new StackPanel
            {
                VerticalAlignment = VerticalAlignment.Center,
                HorizontalAlignment = HorizontalAlignment.Stretch,
            };
            var gif = Assembly.GetExecutingAssembly().GetManifestResourceStream("logo.gif");
            if (gif != null)
            {
                panel.Children.Add(new AnimatedLogo(gif)
                {
                    Width = 112,
                    Height = 112,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    Clip = new RectangleGeometry(new Rect(0, 0, 112, 112), 24, 24),
                });
            }
            panel.Children.Add(new TextBlock
            {
                Text = o.Text,
                Foreground = o.TextColor,
                FontSize = 15,
                FontWeight = FontWeights.SemiBold,
                TextAlignment = TextAlignment.Center,
                TextWrapping = TextWrapping.Wrap,
                LineHeight = 20,
                LineStackingStrategy = LineStackingStrategy.BlockLineHeight,
                MinHeight = 40,
                Margin = new Thickness(0, 28, 0, 0),
            });
            panel.Children.Add(new Border { Height = 34, Margin = new Thickness(0, 14, 0, 0) });

            var card = new Border
            {
                Background = o.Card,
                BorderBrush = o.Border,
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(12),
                Padding = new Thickness(24),
                Child = panel,
            };
            card.MouseLeftButtonDown += (_, e) =>
            {
                if (e.ButtonState == MouseButtonState.Pressed) DragMove();
            };
            Content = card;

            ContentRendered += (_, _) => ReportShown();
            _poll.Tick += OnPoll;
            _poll.Start();
        }

        private static void ReportShown()
        {
            try
            {
                Console.Out.WriteLine("ready");
                Console.Out.Flush();
            }
            catch (IOException)
            {
            }
        }

        private void OnPoll(object? sender, EventArgs e)
        {
            if (_leaving) return;
            if (DateTime.Now - _started > Limit)
            {
                Leave(TimeSpan.Zero);
                return;
            }
            if (NewGlitchShown()) Leave(Settle);
        }

        private void Leave(TimeSpan after)
        {
            _leaving = true;
            _poll.Stop();
            if (after == TimeSpan.Zero)
            {
                Close();
                return;
            }
            var settle = new DispatcherTimer { Interval = after };
            settle.Tick += (_, _) =>
            {
                settle.Stop();
                Close();
            };
            settle.Start();
        }

        private bool NewGlitchShown()
        {
            var shown = false;
            foreach (var process in Process.GetProcessesByName(AppProcess))
            {
                try
                {
                    if (!shown && process.StartTime > _started && process.MainWindowHandle != IntPtr.Zero) shown = true;
                }
                catch (Exception)
                {
                }
                finally
                {
                    process.Dispose();
                }
            }
            return shown;
        }
    }
}
