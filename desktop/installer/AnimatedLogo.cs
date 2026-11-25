
using System;
using System.Collections.Generic;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace GlitchSetup
{
    internal sealed class AnimatedLogo : Image
    {
        private readonly List<BitmapSource> _frames = new List<BitmapSource>();
        private readonly List<TimeSpan> _delays = new List<TimeSpan>();
        private readonly DispatcherTimer _timer = new DispatcherTimer();
        private int _index;

        public AnimatedLogo(System.IO.Stream gif)
        {
            var decoder = new GifBitmapDecoder(gif, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
            var width = decoder.Frames[0].PixelWidth;
            var height = decoder.Frames[0].PixelHeight;
            foreach (var frame in decoder.Frames)
            {
                if (frame.PixelWidth != width || frame.PixelHeight != height)
                {
                    _frames.Clear();
                    _delays.Clear();
                    _frames.Add(decoder.Frames[0]);
                    break;
                }
                _frames.Add(frame);
                _delays.Add(DelayOf(frame));
            }
            Source = _frames[0];
            RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
            if (_frames.Count > 1)
            {
                _timer.Tick += (_, __) => Next();
                _timer.Interval = _delays[0];
                Loaded += (_, __) => _timer.Start();
                Unloaded += (_, __) => _timer.Stop();
            }
        }

        private void Next()
        {
            _index = (_index + 1) % _frames.Count;
            Source = _frames[_index];
            _timer.Interval = _delays[_index];
        }

        /// <summary>Длительность кадра GIF — в сотых долях секунды.</summary>
        private static TimeSpan DelayOf(BitmapFrame frame)
        {
            try
            {
                if (frame.Metadata is BitmapMetadata meta && meta.GetQuery("/grctlext/Delay") is ushort delay && delay > 0)
                    return TimeSpan.FromMilliseconds(delay * 10);
            }
            catch (Exception)
            {
            }
            return TimeSpan.FromMilliseconds(100);
        }
    }
}
