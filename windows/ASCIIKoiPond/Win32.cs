using System.Runtime.InteropServices;

namespace ASCIIKoiPond;

internal static class Win32
{
    public const uint SMTO_NORMAL = 0x0000;
    public const int GWL_STYLE = -16;
    public const int GWL_EXSTYLE = -20;
    public const int WS_CHILD = 0x40000000;
    public const int WS_EX_LAYERED = 0x00080000;
    public const int WS_EX_TOOLWINDOW = 0x00000080;
    public const uint LWA_ALPHA = 0x00000002;
    public const uint SWP_NOSIZE = 0x0001;
    public const uint SWP_NOMOVE = 0x0002;
    public const uint SWP_NOACTIVATE = 0x0010;
    public const uint SWP_SHOWWINDOW = 0x0040;
    public const int TRANSPARENT = 1;
    public const uint SRCCOPY = 0x00CC0020;
    public const uint SPI_SETDESKWALLPAPER = 0x0014;
    public const uint SPIF_SENDCHANGE = 0x0002;

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left, Top, Right, Bottom;
    }

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindow(string? lpClassName, string? lpWindowName);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindowEx(IntPtr hwndParent, IntPtr hwndChildAfter, string? lpszClass, string? lpszWindow);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SetParent(IntPtr hWndChild, IntPtr hWndNewParent);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint crKey, byte bAlpha, uint dwFlags);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll")]
    public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

    [DllImport("user32.dll")]
    public static extern IntPtr GetDC(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

    [DllImport("user32.dll")]
    public static extern int FillRect(IntPtr hDC, ref RECT lprc, IntPtr hbr);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, string? pvParam, uint fWinIni);

    [DllImport("gdi32.dll")]
    public static extern IntPtr CreateCompatibleDC(IntPtr hdc);

    [DllImport("gdi32.dll")]
    public static extern IntPtr CreateCompatibleBitmap(IntPtr hdc, int nWidth, int nHeight);

    [DllImport("gdi32.dll")]
    public static extern IntPtr SelectObject(IntPtr hdc, IntPtr hgdiobj);

    [DllImport("gdi32.dll")]
    public static extern bool DeleteObject(IntPtr hObject);

    [DllImport("gdi32.dll")]
    public static extern bool DeleteDC(IntPtr hdc);

    [DllImport("gdi32.dll")]
    public static extern IntPtr CreateSolidBrush(uint crColor);

    [DllImport("gdi32.dll")]
    public static extern int SetBkMode(IntPtr hdc, int iBkMode);

    [DllImport("gdi32.dll")]
    public static extern uint SetTextColor(IntPtr hdc, uint crColor);

    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr CreateFontW(
        int cHeight, int cWidth, int cEscapement, int cOrientation,
        int cWeight, uint bItalic, uint bUnderline, uint bStrikeOut,
        uint iCharSet, uint iOutPrecision, uint iClipPrecision,
        uint iQuality, uint iPitchAndFamily, string pszFaceName);

    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    public static extern bool ExtTextOutW(
        IntPtr hdc, int x, int y, uint options, IntPtr lprect,
        string lpString, uint c, IntPtr lpDx);

    [DllImport("gdi32.dll")]
    public static extern bool BitBlt(
        IntPtr hdcDest, int nXDest, int nYDest, int nWidth, int nHeight,
        IntPtr hdcSrc, int nXSrc, int nYSrc, uint dwRop);

    /// <summary>
    /// Attaches a live wallpaper window directly behind the desktop icons.
    /// Supports both Windows 11 24H2+ ("Raised Desktop" under Progman) and Windows 10 / 11 23H2 (top-level WorkerW).
    /// </summary>
    public static bool AttachToDesktop(IntPtr hwnd, int width, int height)
    {
        IntPtr progman = FindWindow("Progman", null);
        if (progman == IntPtr.Zero) return false;

        // Trigger Windows desktop composition to spawn WorkerW
        SendMessageTimeout(progman, 0x052C, new IntPtr(0xD), new IntPtr(0x1), SMTO_NORMAL, 1000, out _);
        SendMessageTimeout(progman, 0x052C, IntPtr.Zero, IntPtr.Zero, SMTO_NORMAL, 1000, out _);

        // Check if this is Windows 11 24H2+ where SHELLDLL_DefView and WorkerW are both direct children of Progman
        IntPtr shellViewUnderProgman = FindWindowEx(progman, IntPtr.Zero, "SHELLDLL_DefView", null);
        IntPtr workerUnderProgman = FindWindowEx(progman, IntPtr.Zero, "WorkerW", null);

        if (shellViewUnderProgman != IntPtr.Zero)
        {
            // Windows 11 24H2+ Raised Desktop recipe:
            // 1. Mark window WS_EX_LAYERED + opaque alpha 255 + WS_CHILD
            int exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
            SetWindowLong(hwnd, GWL_EXSTYLE, exStyle | WS_EX_LAYERED | WS_EX_TOOLWINDOW);
            SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);

            int style = GetWindowLong(hwnd, GWL_STYLE);
            SetWindowLong(hwnd, GWL_STYLE, style | WS_CHILD);

            // 2. Parent directly under Progman
            SetParent(hwnd, progman);

            // 3. Sandwich between SHELLDLL_DefView (icons on top) and WorkerW (static wallpaper below)
            SetWindowPos(hwnd, shellViewUnderProgman, 0, 0, width, height, SWP_NOACTIVATE | SWP_SHOWWINDOW);
            if (workerUnderProgman != IntPtr.Zero)
            {
                SetWindowPos(workerUnderProgman, hwnd, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            }
            return true;
        }

        // Legacy Windows 10 / Windows 11 23H2 path: top-level WorkerW sibling behind SHELLDLL_DefView
        IntPtr legacyWorkerW = IntPtr.Zero;
        EnumWindows((topHandle, _) =>
        {
            IntPtr defView = FindWindowEx(topHandle, IntPtr.Zero, "SHELLDLL_DefView", null);
            if (defView != IntPtr.Zero)
            {
                legacyWorkerW = FindWindowEx(IntPtr.Zero, topHandle, "WorkerW", null);
            }
            return true;
        }, IntPtr.Zero);

        IntPtr parent = legacyWorkerW != IntPtr.Zero ? legacyWorkerW : progman;
        int st = GetWindowLong(hwnd, GWL_STYLE);
        SetWindowLong(hwnd, GWL_STYLE, st | WS_CHILD);
        SetParent(hwnd, parent);
        MoveWindow(hwnd, 0, 0, width, height, true);
        return true;
    }

    public const uint SPI_GETDESKWALLPAPER = 0x0073;

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SystemParametersInfoW")]
    private static extern bool SystemParametersInfoGet(uint uiAction, uint uiParam, System.Text.StringBuilder pvParam, uint fWinIni);

    /// <summary>
    /// Repaints the desktop after the live wallpaper is removed, re-applying the user's CURRENT wallpaper.
    /// (Passing null to SPI_SETDESKWALLPAPER resets the wallpaper to the Windows default — never do that.)
    /// </summary>
    public static void RefreshDesktopWallpaper()
    {
        var sb = new System.Text.StringBuilder(1024);
        if (SystemParametersInfoGet(SPI_GETDESKWALLPAPER, (uint)sb.Capacity, sb, 0))
            SystemParametersInfo(SPI_SETDESKWALLPAPER, 0, sb.ToString(), SPIF_SENDCHANGE);
    }
}

/// <summary>
/// High-speed double-buffered Win32 GDI text surface using ExtTextOutW (~2-4ms per frame).
/// </summary>
internal sealed class GdiSurface : IDisposable
{
    private IntPtr _memDc = IntPtr.Zero;
    private IntPtr _bmp = IntPtr.Zero;
    private IntPtr _oldBmp = IntPtr.Zero;
    private IntPtr _font = IntPtr.Zero;
    private IntPtr _oldFont = IntPtr.Zero;
    private int _width;
    private int _height;
    private int _fontPx;
    private uint _lastColor = uint.MaxValue;

    public void EnsureSize(IntPtr targetDc, int width, int height, int fontHeightPx)
    {
        width = Math.Max(16, width);
        height = Math.Max(16, height);

        if (_memDc == IntPtr.Zero || _width != width || _height != height)
        {
            DisposeBuffers();
            _width = width;
            _height = height;
            _memDc = Win32.CreateCompatibleDC(targetDc);
            _bmp = Win32.CreateCompatibleBitmap(targetDc, width, height);
            _oldBmp = Win32.SelectObject(_memDc, _bmp);
            Win32.SetBkMode(_memDc, Win32.TRANSPARENT);
            _fontPx = 0; // force font rebind
        }

        if (_font == IntPtr.Zero || _fontPx != fontHeightPx)
        {
            if (_font != IntPtr.Zero)
            {
                Win32.SelectObject(_memDc, _oldFont);
                Win32.DeleteObject(_font);
            }
            _fontPx = fontHeightPx;
            // ClearType quality (5), Fixed pitch (1)
            _font = Win32.CreateFontW(-fontHeightPx, 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 1, "Consolas");
            _oldFont = Win32.SelectObject(_memDc, _font);
        }

        _lastColor = uint.MaxValue;
    }

    public void Clear(byte r, byte g, byte b)
    {
        if (_memDc == IntPtr.Zero) return;
        uint colorRef = (uint)(r | (g << 8) | (b << 16));
        IntPtr brush = Win32.CreateSolidBrush(colorRef);
        var rc = new Win32.RECT { Left = 0, Top = 0, Right = _width, Bottom = _height };
        Win32.FillRect(_memDc, ref rc, brush);
        Win32.DeleteObject(brush);
    }

    public void DrawChar(string ch, int x, int y, byte r, byte g, byte b)
    {
        if (_memDc == IntPtr.Zero) return;
        uint colorRef = (uint)(r | (g << 8) | (b << 16));
        if (colorRef != _lastColor)
        {
            Win32.SetTextColor(_memDc, colorRef);
            _lastColor = colorRef;
        }
        Win32.ExtTextOutW(_memDc, x, y, 0, IntPtr.Zero, ch, 1, IntPtr.Zero);
    }

    public void BlitTo(IntPtr targetDc)
    {
        if (_memDc == IntPtr.Zero) return;
        Win32.BitBlt(targetDc, 0, 0, _width, _height, _memDc, 0, 0, Win32.SRCCOPY);
    }

    private void DisposeBuffers()
    {
        if (_memDc != IntPtr.Zero)
        {
            if (_oldFont != IntPtr.Zero) { Win32.SelectObject(_memDc, _oldFont); _oldFont = IntPtr.Zero; }
            if (_font != IntPtr.Zero) { Win32.DeleteObject(_font); _font = IntPtr.Zero; }
            if (_oldBmp != IntPtr.Zero) { Win32.SelectObject(_memDc, _oldBmp); _oldBmp = IntPtr.Zero; }
            if (_bmp != IntPtr.Zero) { Win32.DeleteObject(_bmp); _bmp = IntPtr.Zero; }
            Win32.DeleteDC(_memDc);
            _memDc = IntPtr.Zero;
        }
    }

    public void Dispose()
    {
        DisposeBuffers();
    }
}
