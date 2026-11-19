using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DXGI;

namespace ASCIIKoiPond;

/// <summary>
/// Presents GDI-rendered frames through a DXGI flip-model swap chain.
/// Windows 11 25H2 (build 26200+) no longer composites GDI-drawn child windows of other processes inside the
/// desktop (Progman has WS_EX_NOREDIRECTIONBITMAP), but swap-chain content is composited by DWM independently —
/// which is how Wallpaper Engine / Lively keep working. The engine keeps drawing with GDI: we just hand it the
/// swap chain back buffer's GDI DC (IDXGISurface1::GetDC) as the blit target.
/// </summary>
internal sealed class DxPresenter : IDisposable
{
    private ID3D11Device? _device;
    private ID3D11DeviceContext? _context;
    private IDXGISwapChain1? _swapChain;
    private readonly IntPtr _hwnd;
    private int _width, _height;

    public DxPresenter(IntPtr hwnd) => _hwnd = hwnd;

    private void Create(int width, int height)
    {
        DisposeDevice();
        D3D11.D3D11CreateDevice(null!, DriverType.Hardware, DeviceCreationFlags.BgraSupport, null!, out _device, out _context).CheckError();
        using var dxgiDevice = _device!.QueryInterface<IDXGIDevice>();
        using var adapter = dxgiDevice.GetAdapter();
        using var factory = adapter.GetParent<IDXGIFactory2>();
        var desc = new SwapChainDescription1
        {
            Width = (uint)width,
            Height = (uint)height,
            Format = Format.B8G8R8A8_UNorm,
            BufferCount = 2,
            BufferUsage = Usage.RenderTargetOutput,
            SampleDescription = new SampleDescription(1, 0),
            SwapEffect = SwapEffect.FlipDiscard,
            Flags = SwapChainFlags.GdiCompatible,
        };
        _swapChain = factory.CreateSwapChainForHwnd(_device, _hwnd, desc);
        factory.MakeWindowAssociation(_hwnd, WindowAssociationFlags.IgnoreAll);
        _width = width;
        _height = height;
    }

    /// <summary>Gets a GDI DC for the back buffer, lets <paramref name="draw"/> blit into it, then presents.</summary>
    public void Present(int width, int height, Action<IntPtr> draw)
    {
        width = Math.Max(16, width);
        height = Math.Max(16, height);
        try
        {
            if (_swapChain == null) Create(width, height);
            else if (width != _width || height != _height)
            {
                _swapChain.ResizeBuffers(2, (uint)width, (uint)height, Format.B8G8R8A8_UNorm, SwapChainFlags.GdiCompatible).CheckError();
                _width = width;
                _height = height;
            }

            using (var backBuffer = _swapChain!.GetBuffer<IDXGISurface1>(0))
            {
                IntPtr dc = backBuffer.GetDC(false);
                try { draw(dc); }
                finally { backBuffer.ReleaseDC(null); }
            }
            _swapChain.Present(0, PresentFlags.None);
        }
        catch (Exception ex)
        {
            // Device lost / driver reset: drop everything and rebuild on the next frame.
            Log.Error(ex);
            DisposeDevice();
        }
    }

    private void DisposeDevice()
    {
        _swapChain?.Dispose(); _swapChain = null;
        _context?.ClearState();
        _context?.Dispose(); _context = null;
        _device?.Dispose(); _device = null;
    }

    public void Dispose() => DisposeDevice();
}
