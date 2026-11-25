
using System;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

namespace GlitchSetup
{
    internal static class Palette
    {
        public static readonly Brush Card = Hex("#1C1C1C");
        public static readonly Brush Border = Hex("#2C2C2C");
        public static readonly Brush Input = Hex("#212121");
        public static readonly Brush Text = Hex("#EDEDED");
        public static readonly Brush TextSecond = Hex("#8A8A8A");
        public static readonly Brush Accent = Hex("#2FAE9A");
        public static readonly Brush Error = Hex("#FF6B6B");
        public static readonly Brush White = Brushes.White;
        public static readonly Brush SoftFill = Hex("#14EDEDED");
        public static readonly Brush SoftFillActive = Hex("#24EDEDED");

        private static Brush Hex(string hex)
        {
            var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
            brush.Freeze();
            return brush;
        }
    }

    internal sealed class SetupWindow : Window
    {
        private readonly Texts _t = Texts.Current;
        private string _folder = Engine.DefaultFolder();
        private bool _installing;

        private readonly TextBlock _status = new TextBlock();

        private readonly TextBlock _detail = new TextBlock();
        private readonly TextBlock _path = new TextBlock();
        private readonly TextBlock _inlineError = new TextBlock();
        private readonly StackPanel _choosePanel = new StackPanel();
        private readonly StackPanel _progressPanel = new StackPanel();
        private readonly StackPanel _errorPanel = new StackPanel();
        private readonly ColumnDefinition _done = new ColumnDefinition { Width = new GridLength(0, GridUnitType.Star) };
        private readonly ColumnDefinition _left = new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) };
        private readonly Border _close;

        public SetupWindow()
        {
            Title = "Glitch";
            Width = 380;
            Height = 380;
            ResizeMode = ResizeMode.NoResize;
            WindowStyle = WindowStyle.None;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            FontFamily = new FontFamily("Segoe UI");
            UseLayoutRounding = true;

            var grid = new Grid();
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            _close = MakeButton(
                new TextBlock { Text = "✕", Foreground = Palette.TextSecond, FontSize = 13, Margin = new Thickness(10, 6, 10, 6) },
                Close,
                hoverBackground: Palette.Border);
            _close.HorizontalAlignment = HorizontalAlignment.Right;
            _close.Margin = new Thickness(0, 8, 8, 0);
            _close.CornerRadius = new CornerRadius(6);
            Grid.SetRow(_close, 0);
            grid.Children.Add(_close);

            var center = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            var gif = Assembly.GetExecutingAssembly().GetManifestResourceStream("logo.gif");
            if (gif != null)
            {
                center.Children.Add(new AnimatedLogo(gif)
                {
                    Width = 112,
                    Height = 112,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    Clip = new RectangleGeometry(new Rect(0, 0, 112, 112), 24, 24),
                });
            }
            _status.Text = "Glitch";
            _status.Foreground = Palette.Text;
            _status.FontSize = 15;
            _status.FontWeight = FontWeights.SemiBold;
            _status.TextAlignment = TextAlignment.Center;
            _status.TextWrapping = TextWrapping.Wrap;
            _status.Margin = new Thickness(24, 20, 24, 0);
            center.Children.Add(_status);
            _detail.Foreground = Palette.TextSecond;
            _detail.FontSize = 12;
            _detail.TextAlignment = TextAlignment.Center;
            _detail.TextWrapping = TextWrapping.Wrap;
            _detail.Margin = new Thickness(24, 8, 24, 0);
            _detail.Visibility = Visibility.Collapsed;
            center.Children.Add(_detail);
            Grid.SetRow(center, 1);
            grid.Children.Add(center);

            var bottom = new Grid { Margin = new Thickness(24, 0, 24, 24) };
            BuildChoosePanel();
            BuildProgressPanel();
            BuildErrorPanel();
            bottom.Children.Add(_choosePanel);
            bottom.Children.Add(_progressPanel);
            bottom.Children.Add(_errorPanel);
            Grid.SetRow(bottom, 2);
            grid.Children.Add(bottom);

            var card = new Border
            {
                Background = Palette.Card,
                BorderBrush = Palette.Border,
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(12),
                Child = grid,
            };
            card.MouseLeftButtonDown += (_, e) =>
            {
                if (e.ButtonState == MouseButtonState.Pressed) DragMove();
            };
            Content = card;

            KeyDown += OnKeyDown;
            Closing += (_, e) =>
            {
                if (_installing) e.Cancel = true;
            };

            ShowChoose();
        }


        private void BuildChoosePanel()
        {
            _choosePanel.Children.Add(new TextBlock
            {
                Text = _t.InstallTo,
                Foreground = Palette.TextSecond,
                FontSize = 12,
                Margin = new Thickness(0, 0, 0, 6),
            });

            var row = new DockPanel { LastChildFill = true };
            var change = MakeSoftButton(_t.Change, PickFolder);
            change.Margin = new Thickness(8, 0, 0, 0);
            DockPanel.SetDock(change, Dock.Right);
            row.Children.Add(change);

            _path.Foreground = Palette.Text;
            _path.FontSize = 13;
            _path.TextTrimming = TextTrimming.CharacterEllipsis;
            _path.VerticalAlignment = VerticalAlignment.Center;
            row.Children.Add(new Border
            {
                Background = Palette.Input,
                CornerRadius = new CornerRadius(6),
                Padding = new Thickness(10, 7, 10, 7),
                Child = _path,
            });
            _choosePanel.Children.Add(row);

            _inlineError.Foreground = Palette.Error;
            _inlineError.FontSize = 12;
            _inlineError.TextWrapping = TextWrapping.Wrap;
            _inlineError.Margin = new Thickness(0, 6, 0, 0);
            _inlineError.Visibility = Visibility.Collapsed;
            _choosePanel.Children.Add(_inlineError);

            var install = MakePrimaryButton(_t.Install, () => _ = InstallAsync());
            install.Margin = new Thickness(0, 14, 0, 0);
            _choosePanel.Children.Add(install);
        }

        private void BuildProgressPanel()
        {
            var track = new Grid { Height = 6 };
            track.ColumnDefinitions.Add(_done);
            track.ColumnDefinitions.Add(_left);
            var under = new Border { Background = Palette.Border, CornerRadius = new CornerRadius(3) };
            Grid.SetColumnSpan(under, 2);
            var fill = new Border { Background = Palette.Accent, CornerRadius = new CornerRadius(3) };
            Grid.SetColumn(fill, 0);
            track.Children.Add(under);
            track.Children.Add(fill);
            _progressPanel.Children.Add(track);
            _progressPanel.Margin = new Thickness(0, 0, 0, 44);
        }

        private void BuildErrorPanel()
        {
            var retry = MakePrimaryButton(_t.Retry, ShowChoose);
            _errorPanel.Children.Add(retry);
        }


        private void ShowChoose()
        {
            _installing = false;
            _status.Text = "Glitch";
            _status.Foreground = Palette.Text;
            _detail.Visibility = Visibility.Collapsed;
            _path.Text = _folder;
            _inlineError.Visibility = Visibility.Collapsed;
            _choosePanel.Visibility = Visibility.Visible;
            _progressPanel.Visibility = Visibility.Collapsed;
            _errorPanel.Visibility = Visibility.Collapsed;
            _close.Visibility = Visibility.Visible;
        }

        private void ShowInlineError(string text)
        {
            _inlineError.Text = text;
            _inlineError.Visibility = Visibility.Visible;
        }

        private void ShowProgress(double share)
        {
            _done.Width = new GridLength(share, GridUnitType.Star);
            _left.Width = new GridLength(1 - share, GridUnitType.Star);
        }

        private void ShowFailed(InstallResult result)
        {
            _installing = false;
            _status.Text = _t.Failed;
            _status.Foreground = Palette.Error;
            _detail.Text = _t.Explain(result, _folder);
            _detail.Visibility = Visibility.Visible;
            _choosePanel.Visibility = Visibility.Collapsed;
            _progressPanel.Visibility = Visibility.Collapsed;
            _errorPanel.Visibility = Visibility.Visible;
            _close.Visibility = Visibility.Visible;
        }


        private void PickFolder()
        {
            var owner = new WindowInteropHelper(this).Handle;
            var picked = FolderPicker.Pick(owner, _t.PickFolder, Engine.ExistingParent(_folder));
            if (picked == null) return;
            var folder = Engine.FolderFromPicked(picked);
            if (!Engine.IsValidFolder(folder))
            {
                ShowInlineError(_t.BadFolder);
                return;
            }
            _folder = folder;
            ShowChoose();
        }

        private async System.Threading.Tasks.Task InstallAsync()
        {
            if (_installing) return;
            if (!Engine.IsValidFolder(_folder))
            {
                ShowInlineError(_t.BadFolder);
                return;
            }
            _installing = true;
            _status.Text = _t.Installing;
            _status.Foreground = Palette.Text;
            _detail.Visibility = Visibility.Collapsed;
            _choosePanel.Visibility = Visibility.Collapsed;
            _errorPanel.Visibility = Visibility.Collapsed;
            _progressPanel.Visibility = Visibility.Visible;
            _close.Visibility = Visibility.Collapsed;
            ShowProgress(0);

            var result = await Engine.InstallAsync(_folder, new Progress<double>(ShowProgress));
            switch (result.Outcome)
            {
                case InstallOutcome.Done:
                    _status.Text = _t.Launching;
                    try
                    {
                        Engine.Launch(result.Folder);
                    }
                    catch (Exception)
                    {
                    }
                    _installing = false;
                    Close();
                    break;
                case InstallOutcome.Declined:
                    ShowChoose();
                    break;
                case InstallOutcome.NoSpace:
                    ShowChoose();
                    ShowInlineError(_t.NoSpace);
                    break;
                default:
                    ShowFailed(result);
                    break;
            }
        }

        private void OnKeyDown(object sender, KeyEventArgs e)
        {
            if (_installing) return;
            if (e.Key == Key.Enter && _choosePanel.Visibility == Visibility.Visible)
            {
                _ = InstallAsync();
                e.Handled = true;
            }
            else if (e.Key == Key.Escape)
            {
                Close();
                e.Handled = true;
            }
        }


        private static Border MakePrimaryButton(string label, Action onClick)
        {
            var button = MakeButton(
                new TextBlock
                {
                    Text = label,
                    Foreground = Palette.White,
                    FontSize = 14,
                    FontWeight = FontWeights.SemiBold,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                },
                onClick,
                hoverBackground: null);
            button.Background = Palette.Accent;
            button.Height = 40;
            button.CornerRadius = new CornerRadius(8);
            return button;
        }

        private static Border MakeSoftButton(string label, Action onClick)
        {
            var button = MakeButton(
                new TextBlock
                {
                    Text = label,
                    Foreground = Palette.Text,
                    FontSize = 14,
                    FontWeight = FontWeights.SemiBold,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                },
                onClick,
                hoverBackground: Palette.SoftFillActive);
            button.Background = Palette.SoftFill;
            button.Height = 36;
            button.Padding = new Thickness(16, 0, 16, 0);
            button.CornerRadius = new CornerRadius(10);
            return button;
        }

        private static Border MakeButton(UIElement content, Action onClick, Brush? hoverBackground)
        {
            var button = new Border { Child = content, Cursor = Cursors.Hand, Background = Brushes.Transparent };
            Brush? normal = null;
            button.MouseEnter += (_, __) =>
            {
                normal = button.Background;
                if (hoverBackground != null) button.Background = hoverBackground;
                else button.Opacity = 0.9;
            };
            button.MouseLeave += (_, __) =>
            {
                if (hoverBackground != null && normal != null) button.Background = normal;
                button.Opacity = 1;
            };
            button.MouseLeftButtonDown += (_, e) =>
            {
                button.CaptureMouse();
                e.Handled = true; // не тянуть окно
            };
            button.MouseLeftButtonUp += (_, e) =>
            {
                if (!button.IsMouseCaptured) return;
                button.ReleaseMouseCapture();
                e.Handled = true;
                if (button.IsMouseOver) onClick();
            };
            return button;
        }
    }
}
