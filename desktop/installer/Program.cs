
using System;
using System.Windows;

namespace GlitchSetup
{
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            var app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
            app.Run(new SetupWindow());
        }
    }
}
