using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;

namespace ASCIIKoiPond;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();

        string mode = "tray";
        IntPtr previewHwnd = IntPtr.Zero;

        if (args.Length > 0)
        {
            string first = args[0].Trim().ToLowerInvariant();
            if (first.StartsWith("/s") || first.StartsWith("-s"))
            {
                mode = "screensaver";
            }
            else if (first.StartsWith("/c") || first.StartsWith("-c"))
            {
                mode = "config";
            }
            else if (first.StartsWith("/p") || first.StartsWith("-p"))
            {
                mode = "preview";
                string? handleStr = first.Contains(':') ? first[(first.IndexOf(':') + 1)..] : (args.Length > 1 ? args[1] : null);
                if (handleStr != null && long.TryParse(handleStr, out long h))
                    previewHwnd = new IntPtr(h);
            }
        }

        switch (mode)
        {
            case "config":
                using (var dlg = new OptionsForm(PondConfig.Load()))
                    dlg.ShowDialog();
                break;

            case "preview":
                if (previewHwnd != IntPtr.Zero)
                    Application.Run(new PondCanvasForm(PondMode.Preview, previewHwnd));
                break;

            case "screensaver":
                RunScreenSaver();
                break;

            default:
                Application.Run(new TrayAppContext());
                break;
        }
    }

    private static void RunScreenSaver()
    {
        var forms = new List<PondCanvasForm>();
        foreach (var screen in Screen.AllScreens)
        {
            var f = new PondCanvasForm(PondMode.ScreenSaver, IntPtr.Zero, screen.Bounds);
            f.FormClosed += (_, _) =>
            {
                foreach (var other in forms)
                    if (!other.IsDisposed) other.Close();
                Application.Exit();
            };
            forms.Add(f);
            f.Show();
        }
        if (forms.Count > 0) Application.Run(forms[0]);
    }

    public static Icon CreateKoiTrayIcon()
    {
        using var bmp = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bmp))
        {
            g.Clear(Color.FromArgb(6, 26, 32));
            using var white = new SolidBrush(Color.FromArgb(248, 244, 238));
            using var red = new SolidBrush(Color.FromArgb(244, 74, 36));
            using var fin = new SolidBrush(Color.FromArgb(180, 224, 228));
            g.FillEllipse(fin, 4, 11, 10, 10);
            g.FillEllipse(white, 8, 9, 18, 14);
            g.FillEllipse(red, 16, 10, 8, 8);
            g.FillEllipse(red, 10, 13, 6, 6);
        }
        return Icon.FromHandle(bmp.GetHicon());
    }
}

internal enum PondMode { LiveWallpaper, ScreenSaver, Preview, InteractiveWindow }

internal sealed class PondCanvasForm : Form
{
    private readonly PondMode _mode;
    private readonly PondEngine _engine = new();
    private readonly GdiSurface _surface = new();
    private readonly System.Windows.Forms.Timer _timer = new();
    private readonly Stopwatch _watch = Stopwatch.StartNew();
    private double _lastSec;
    private Point _initialMouse;
    private bool _mouseReady;
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    public bool IsPaused { get; set; }

    public PondCanvasForm(PondMode mode, IntPtr previewParent = default, Rectangle? customBounds = null)
    {
        _mode = mode;
        var cfg = PondConfig.Load();
        cfg.IsPreview = (mode == PondMode.Preview);
        _engine.ApplyConfig(cfg);

        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.Opaque, true);
        BackColor = Color.FromArgb(6, 26, 32);
        Icon = Program.CreateKoiTrayIcon();

        if (mode == PondMode.InteractiveWindow)
        {
            Text = "ASCII Koi Pond — Interactive Preview";
            Size = new Size(1120, 680);
            StartPosition = FormStartPosition.CenterScreen;
            MouseDown += (_, e) => _engine.OnClick(e.X, e.Y);
        }
        else if (mode == PondMode.Preview && previewParent != IntPtr.Zero)
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            Win32.SetParent(Handle, previewParent);
            Win32.SetWindowLong(Handle, Win32.GWL_STYLE, Win32.GetWindowLong(Handle, Win32.GWL_STYLE) | Win32.WS_CHILD);
            Win32.GetClientRect(previewParent, out var rc);
            Bounds = new Rectangle(0, 0, Math.Max(100, rc.Right - rc.Left), Math.Max(60, rc.Bottom - rc.Top));
        }
        else if (mode == PondMode.ScreenSaver)
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            TopMost = true;
            Bounds = customBounds ?? Screen.PrimaryScreen!.Bounds;
            Cursor.Hide();
            KeyDown += (_, _) => Close();
            MouseDown += (_, _) => Close();
            MouseMove += (_, e) =>
            {
                if (!_mouseReady) { _initialMouse = e.Location; _mouseReady = true; return; }
                if (Math.Abs(e.X - _initialMouse.X) > 14 || Math.Abs(e.Y - _initialMouse.Y) > 14) Close();
            };
        }
        else if (mode == PondMode.LiveWallpaper)
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            Bounds = SystemInformation.VirtualScreen;
        }

        _timer.Interval = 33; // ~30 FPS native GDI
        _timer.Tick += (_, _) => TickFrame();
        _timer.Start();
    }

    public void AttachToDesktop()
    {
        if (_mode != PondMode.LiveWallpaper) return;
        var vs = SystemInformation.VirtualScreen;
        Win32.AttachToDesktop(Handle, vs.Width, vs.Height);
    }

    public void ReloadConfig(PondConfig cfg)
    {
        cfg.IsPreview = (_mode == PondMode.Preview);
        _engine.ApplyConfig(cfg);
    }

    private void TickFrame()
    {
        if (IsDisposed || !Visible) return;
        double now = _watch.Elapsed.TotalSeconds;
        float dt = _lastSec > 0 ? (float)(now - _lastSec) : 0.033f;
        _lastSec = now;

        if (!IsPaused)
            _engine.Step(dt);

        IntPtr dc = Win32.GetDC(Handle);
        if (dc != IntPtr.Zero)
        {
            try
            {
                _engine.Render(_surface, dc, ClientSize.Width, ClientSize.Height);
            }
            finally
            {
                Win32.ReleaseDC(Handle, dc);
            }
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        // Painted directly via GDI BitBlt in TickFrame
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        _timer.Stop();
        _timer.Dispose();
        _surface.Dispose();
        if (_mode == PondMode.ScreenSaver) Cursor.Show();
        base.OnFormClosed(e);
    }
}

internal sealed class TrayAppContext : ApplicationContext
{
    private readonly NotifyIcon _tray;
    private PondCanvasForm? _wallpaperForm;
    private PondCanvasForm? _previewForm;
    private readonly ToolStripMenuItem _wallpaperItem;
    private readonly ToolStripMenuItem _pauseItem;
    private PondConfig _config;

    public TrayAppContext()
    {
        _config = PondConfig.Load();

        _wallpaperItem = new ToolStripMenuItem("Live Wallpaper", null, (_, _) => ToggleWallpaper()) { Checked = true };
        _pauseItem = new ToolStripMenuItem("Pause", null, (_, _) => TogglePause());

        var menu = new ContextMenuStrip();
        menu.Items.Add(_wallpaperItem);
        menu.Items.Add(new ToolStripMenuItem("Open Interactive Window", null, (_, _) => OpenPreviewWindow()));
        menu.Items.Add(new ToolStripMenuItem("Launch Screen Saver", null, (_, _) => LaunchScreenSaver()));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Options...", null, (_, _) => ShowOptions()));
        menu.Items.Add(_pauseItem);
        menu.Items.Add(new ToolStripMenuItem("Create Screen Saver (.scr) Copy", null, (_, _) => CreateScrCopy()));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Exit", null, (_, _) => ExitApp()));

        _tray = new NotifyIcon
        {
            Icon = Program.CreateKoiTrayIcon(),
            Text = "ASCII Koi Pond",
            ContextMenuStrip = menu,
            Visible = true
        };
        _tray.DoubleClick += (_, _) => OpenPreviewWindow();

        StartWallpaper();
    }

    private void StartWallpaper()
    {
        if (_wallpaperForm != null && !_wallpaperForm.IsDisposed) return;
        _wallpaperForm = new PondCanvasForm(PondMode.LiveWallpaper);
        _wallpaperForm.Show();
        _wallpaperForm.AttachToDesktop();
        _wallpaperItem.Checked = true;
    }

    private void StopWallpaper()
    {
        if (_wallpaperForm != null && !_wallpaperForm.IsDisposed)
        {
            _wallpaperForm.Close();
            _wallpaperForm = null;
        }
        Win32.RefreshDesktopWallpaper();
        _wallpaperItem.Checked = false;
    }

    private void ToggleWallpaper()
    {
        if (_wallpaperForm != null && !_wallpaperForm.IsDisposed) StopWallpaper();
        else StartWallpaper();
    }

    private void TogglePause()
    {
        bool next = !(_wallpaperForm?.IsPaused ?? false);
        if (_wallpaperForm != null && !_wallpaperForm.IsDisposed) _wallpaperForm.IsPaused = next;
        if (_previewForm != null && !_previewForm.IsDisposed) _previewForm.IsPaused = next;
        _pauseItem.Text = next ? "Resume" : "Pause";
    }

    private void OpenPreviewWindow()
    {
        if (_previewForm != null && !_previewForm.IsDisposed)
        {
            _previewForm.Activate();
            return;
        }
        _previewForm = new PondCanvasForm(PondMode.InteractiveWindow);
        _previewForm.Show();
    }

    private void LaunchScreenSaver()
    {
        var f = new PondCanvasForm(PondMode.ScreenSaver, IntPtr.Zero, Screen.PrimaryScreen!.Bounds);
        f.Show();
    }

    private void ShowOptions()
    {
        using var dlg = new OptionsForm(_config);
        if (dlg.ShowDialog() == DialogResult.OK)
        {
            _config = dlg.UpdatedConfig;
            _config.Save();
            _wallpaperForm?.ReloadConfig(_config);
            _previewForm?.ReloadConfig(_config);
        }
    }

    private void CreateScrCopy()
    {
        try
        {
            string exePath = Environment.ProcessPath ?? Application.ExecutablePath;
            string outDir = Path.GetDirectoryName(exePath) ?? Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
            string scrPath = Path.Combine(outDir, "ASCIIKoiPond.scr");
            File.Copy(exePath, scrPath, overwrite: true);
            MessageBox.Show(
                $"Created:\n{scrPath}\n\nRight-click ASCIIKoiPond.scr and choose 'Install' to set it as your Windows Screen Saver.",
                "ASCII Koi Pond", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Could not create .scr file:\n{ex.Message}", "ASCII Koi Pond", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void ExitApp()
    {
        StopWallpaper();
        if (_previewForm != null && !_previewForm.IsDisposed) _previewForm.Close();
        _tray.Visible = false;
        _tray.Dispose();
        ExitThread();
    }
}

internal sealed class OptionsForm : Form
{
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    public PondConfig UpdatedConfig { get; private set; }
    private readonly ComboBox _timeBox = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox _seasonBox = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox _koiBox = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly CheckBox _clockCheck = new() { Text = "Show submerged stone clock", AutoSize = true };
    private readonly CheckBox _rainCheck = new() { Text = "Enable gentle rain", AutoSize = true };
    private readonly CheckBox _monoCheck = new() { Text = "Pure ASCII mode (monochrome)", AutoSize = true };

    private static readonly string[] TimeValues = ["auto", "day", "sunset", "night"];
    private static readonly string[] SeasonValues = ["auto", "spring", "summer", "autumn", "winter"];

    public OptionsForm(PondConfig current)
    {
        UpdatedConfig = new PondConfig
        {
            TimeMode = current.TimeMode, Season = current.Season, KoiCount = current.KoiCount,
            ShowClock = current.ShowClock, RainOn = current.RainOn, MonoMode = current.MonoMode
        };

        Text = "ASCII Koi Pond Options";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(390, 275);
        Icon = Program.CreateKoiTrayIcon();

        void AddRow(string label, Control ctrl, int y)
        {
            Controls.Add(new Label { Text = label, Left = 18, Top = y + 3, Width = 115, TextAlign = ContentAlignment.MiddleRight });
            ctrl.Left = 142; ctrl.Top = y; ctrl.Width = 220;
            Controls.Add(ctrl);
        }

        _timeBox.Items.AddRange(["Automatic (System Clock)", "Day", "Sunset", "Night (Fireflies)"]);
        _timeBox.SelectedIndex = Math.Max(0, Array.IndexOf(TimeValues, current.TimeMode));
        AddRow("Time of Day:", _timeBox, 20);

        _seasonBox.Items.AddRange(["Automatic (Calendar)", "Spring (Sakura)", "Summer", "Autumn (Maple Leaves)", "Winter (Snow)"]);
        _seasonBox.SelectedIndex = Math.Max(0, Array.IndexOf(SeasonValues, current.Season));
        AddRow("Season:", _seasonBox, 56);

        _koiBox.Items.AddRange(["2 Koi", "3 Koi", "4 Koi", "5 Koi"]);
        _koiBox.SelectedIndex = Math.Clamp(current.KoiCount - 2, 0, 3);
        AddRow("Koi Count:", _koiBox, 92);

        _clockCheck.Checked = current.ShowClock; _clockCheck.Left = 142; _clockCheck.Top = 132; Controls.Add(_clockCheck);
        _rainCheck.Checked = current.RainOn; _rainCheck.Left = 142; _rainCheck.Top = 160; Controls.Add(_rainCheck);
        _monoCheck.Checked = current.MonoMode; _monoCheck.Left = 142; _monoCheck.Top = 188; Controls.Add(_monoCheck);

        var cancelBtn = new Button { Text = "Cancel", DialogResult = DialogResult.Cancel, Left = 194, Top = 230, Width = 80, Height = 28 };
        var okBtn = new Button { Text = "OK", DialogResult = DialogResult.OK, Left = 282, Top = 230, Width = 80, Height = 28 };
        okBtn.Click += (_, _) =>
        {
            UpdatedConfig.TimeMode = TimeValues[Math.Max(0, _timeBox.SelectedIndex)];
            UpdatedConfig.Season = SeasonValues[Math.Max(0, _seasonBox.SelectedIndex)];
            UpdatedConfig.KoiCount = _koiBox.SelectedIndex + 2;
            UpdatedConfig.ShowClock = _clockCheck.Checked;
            UpdatedConfig.RainOn = _rainCheck.Checked;
            UpdatedConfig.MonoMode = _monoCheck.Checked;
            UpdatedConfig.Save();
        };
        Controls.Add(cancelBtn);
        Controls.Add(okBtn);
        AcceptButton = okBtn;
        CancelButton = cancelBtn;
    }
}
