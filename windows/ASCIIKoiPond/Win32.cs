using System.Runtime.InteropServices;

namespace ASCIIKoiPond;

internal static class Win32
{
    public const uint SMTO_NORMAL = 0x0000;
    public const int GWL_STYLE = -16;
    public const int WS_CHILD = 0x40000000;
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
    /// Locates the desktop WorkerW window behind desktop icons (works on Windows 10 & Windows 11).
    /// </summary>
    public static IntPtr GetDesktopWorkerW()
    {
        IntPtr progman = FindWindow("Progman", null);
        if (progman == IntPtr.Zero) return IntPtr.Zero;

        // Spawn WorkerW behind SHELLDLL_DefView
        SendMessageTimeout(progman, 0x052C, new IntPtr(0xD), new IntPtr(0x1), SMTO_NORMAL, 1000, out _);

        IntPtr workerW = IntPtr.Zero;
        EnumWindows((topHandle, _) =>
        {
            IntPtr defView = FindWindowEx(topHandle, IntPtr.Zero, "SHELLDLL_DefView", null);
            if (defView != IntPtr.Zero)
            {
                workerW = FindWindowEx(IntPtr.Zero, topHandle, "WorkerW", null);
            }
            return true;
        }, IntPtr.Zero);

        // Windows 11 24H2+ fallback: WorkerW may be a child of Progman
        if (workerW == IntPtr.Zero)
        {
            workerW = FindWindowEx(progman, IntPtr.Zero, "WorkerW", null);
        }

        return workerW != IntPtr.Zero ? workerW : progman;
    }

    public static void RefreshDesktopWallpaper()
    {
        SystemParametersInfo(SPI_SETDESKWALLPAPER, 0, null, SPIF_SENDCHANGE);
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
