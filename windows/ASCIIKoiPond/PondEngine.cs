using System.Text.Json;

namespace ASCIIKoiPond;

public sealed class PondConfig
{
    public string TimeMode { get; set; } = "auto";   // auto | day | sunset | night
    public string Season { get; set; } = "auto";     // auto | spring | summer | autumn | winter
    public int KoiCount { get; set; } = 3;
    public bool ShowClock { get; set; } = true;
    public bool RainOn { get; set; } = false;
    public bool MonoMode { get; set; } = false;
    public bool IsPreview { get; set; } = false;

    private static string ConfigPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ASCIIKoiPond", "config.json");

    public static PondConfig Load()
    {
        try
        {
            if (File.Exists(ConfigPath))
            {
                var cfg = JsonSerializer.Deserialize<PondConfig>(File.ReadAllText(ConfigPath));
                if (cfg != null) return cfg;
            }
        }
        catch { }
        return new PondConfig();
    }

    public void Save()
    {
        try
        {
            var dir = Path.GetDirectoryName(ConfigPath)!;
            Directory.CreateDirectory(dir);
            File.WriteAllText(ConfigPath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
    }
}

internal readonly struct Rgb(float r, float g, float b)
{
    public readonly float R = r;
    public readonly float G = g;
    public readonly float B = b;
}

internal sealed class PondPalette
{
    public string Tod = "day";
    public Rgb Bg, WaterDeep, Stone, Clock, Water, Ripple, Shadow;
    public float WaterAlpha, ShadowAlpha;
    public Rgb Lotus, LotusVein, Flower;
    public Rgb White, Red, Black, Gold, Fin, FinBlack, Barbel;
    public Rgb TurtleShell, TurtleRim, TurtleSkin, Minnow;
    public Rgb Plant, PlantTip, Bubble, Splash;
    public Rgb Dragonfly, Wing, Frog, Firefly, Moon, Snow, Eye;
    public Rgb[] LeafAutumn = [], LeafSpring = [], LeafSummer = [];
}

internal enum KoiVariety { Showa, Utsuri, Sanke, Ogon, Kumonryu }

internal sealed class PondEngine
{
    public PondConfig Config { get; private set; } = new();

    private float _width = 1280;
    private float _height = 720;
    private float _cellW = 6.2f;
    private float _cellH = 10.6f;
    private int _fontPx = 11;
    private int _cols = 180;
    private int _rows = 68;
    private bool _initialized;

    private readonly Random _rng = new();
    private float _time;
    private float _rainTimer;
    private float _leafSpawnTimer = 1.6f;
    private readonly float _patternSeed;

    private static readonly string[] ShadeRamp = Array.ConvertAll(" .,:;i1tfLCG08#%@W".ToCharArray(), c => c.ToString());
    private static readonly string[] ScaleRamp = Array.ConvertAll(" .,:;coO08@#".ToCharArray(), c => c.ToString());
    private static readonly string[] FinRamp = Array.ConvertAll(" .,:~-=+*#".ToCharArray(), c => c.ToString());
    private static readonly string[] StoneRamp = Array.ConvertAll(" .,:;oO".ToCharArray(), c => c.ToString());
    private static readonly string[] LeafBladeRamp = Array.ConvertAll(" .:+*#%@".ToCharArray(), c => c.ToString());
    private static readonly KoiVariety[] AllVarieties = Enum.GetValues<KoiVariety>();

    private static readonly Dictionary<char, string[]> Digits = new()
    {
        ['0'] = ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        ['1'] = ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        ['2'] = ["01110", "10001", "00001", "00110", "01000", "10000", "11111"],
        ['3'] = ["01110", "10001", "00001", "00110", "00001", "10001", "01110"],
        ['4'] = ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        ['5'] = ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        ['6'] = ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        ['7'] = ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        ['8'] = ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        ['9'] = ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        [':'] = ["00000", "00100", "00100", "00000", "00100", "00100", "00000"]
    };

    private struct Vec2 { public float X, Y; }
    private struct RenderNode { public float X, Y, Nx, Ny; }
    private struct SpineSeg { public float Ax, Ay, Abx, Aby, InvLenSq, Anx, Any, Dnx, Dny; }
    private struct BarbelNode { public float X, Y, Vx, Vy; }

    private sealed class Koi
    {
        public KoiVariety Variety;
        public float Seed, BaseScale, Scale, Z, TargetZ, ZTimer, SegLen, BarbelSegLen;
        public int N;
        public Vec2[] Nodes = [];
        public RenderNode[] RenderNodes = [];
        public SpineSeg[] Segs = [];
        public BarbelNode[][] Barbels = [];
        public float Angle, TurnVel, TargetX, TargetY, Phase, BaseSpeed, Speed, TurnRate;
        public float TailTimer, WanderTimer;
        public bool Breaching, HasEntered, Leaving;
        public float BreachProgress, BreachCooldown, BreachSplashTick;
    }

    private sealed class Turtle
    {
        public float X, Y, Angle, TargetX, TargetY, Z, TargetZ, ZTimer, Scale, Speed, TurnRate, Phase, HeadYaw, WanderTimer;
    }

    private sealed class Minnow
    {
        public float X, Y, Vx, Vy, Angle, Z, Phase, Boost;
        public Vec2[] Nodes = [];
    }

    private sealed class Dragonfly
    {
        public float X, Y, Z, Angle, TargetX, TargetY, StateTimer, WingPhase;
        public bool Perched;
        public int PerchPadIdx = -1;
    }

    private sealed class Frog
    {
        public float X, Y, Z, Angle, SwimPhase, RestTimer;
        public int PadIdx, TargetPadIdx;
        public bool Swimming;
    }

    private struct LotusPad { public float X, Y, R, NotchAngle, Phase; public bool Flower; }
    private struct PlantFrond { public float Ang, Len, Bend; }
    private sealed class PondPlant { public float X, Y, R, Phase, BubbleTimer; public PlantFrond[] Fronds = []; }
    private struct Ripple { public float X, Y, R, MaxR, Alpha; }
    private struct Bubble { public float X, Y, Z, Vz, WigglePhase, WiggleAmp; }
    private struct Splash { public float X, Y, Z, Vx, Vy, Vz; public bool Big; }
    private struct Leaf
    {
        public float X, Y, Z, Vx, Vy, Rot, RotSpd, Tumble, TumbleSpd, SwayPhase, Size, Age, MaxAge;
        public int ColorIdx;
        public bool Maple, IsSnow, Floating;
    }
    private struct Firefly { public float X, Y, Vx, Vy, Phase, BlinkSpd; }
    private struct Star { public float X, Y, Phase, Spd; }

    private struct SampleHit
    {
        public int Kind; // 0=none, 1=eye, 2=barbel, 3=body, 4=fin, 5=tShell, 6=tSkin, 7=minnow, 8=shadow
        public bool FlagA, FlagB, FlagC;
        public float ValA, ValB, DepthZ;
        public int IntA;
        public KoiVariety Variety;
    }

    private struct ActorBox
    {
        public int Kind, Index, MinC, MaxC, MinR, MaxR;
        public float Z, ShX, ShY;
    }

    private readonly List<Koi> _fishes = [];
    private Turtle? _turtle;
    private readonly List<Minnow> _minnows = [];
    private Dragonfly? _dragonfly;
    private Frog? _frog;
    private readonly List<LotusPad> _lotusPads = [];
    private readonly List<PondPlant> _plants = [];
    private float[] _stoneMap = [];
    private readonly List<Ripple> _ripples = [];
    private readonly List<Bubble> _bubbles = [];
    private readonly List<Splash> _splashes = [];
    private readonly List<Leaf> _leaves = [];
    private readonly List<Firefly> _fireflies = [];
    private readonly List<Star> _stars = [];
    private readonly List<ActorBox> _actors = [];

    public PondEngine()
    {
        _patternSeed = RandRange(1f, 99f);
    }

    private float RandRange(float min, float max) => min + (float)_rng.NextDouble() * (max - min);
    private float ScreenScale() => Math.Clamp(Math.Min(_width / 1150f, _height / 720f), 0.35f, 1.38f);

    private static float Hash2(float x, float y)
    {
        double s = Math.Sin(x * 127.1 + y * 311.7) * 43758.5453123;
        return (float)(s - Math.Floor(s));
    }

    private static float ValueNoise(float x, float y)
    {
        float ix = MathF.Floor(x), iy = MathF.Floor(y);
        float fx = x - ix, fy = y - iy;
        float ux = fx * fx * (3f - 2f * fx), uy = fy * fy * (3f - 2f * fy);
        float a = Hash2(ix, iy), b = Hash2(ix + 1, iy);
        float c = Hash2(ix, iy + 1), d = Hash2(ix + 1, iy + 1);
        return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy;
    }

    private static float Fbm(float x, float y) =>
        ValueNoise(x, y) * 0.60f +
        ValueNoise(x * 2.15f + 13.7f, y * 2.15f - 7.3f) * 0.28f +
        ValueNoise(x * 4.4f - 5.1f, y * 4.4f + 19.2f) * 0.12f;

    private static float NormalizeAngle(float a)
    {
        while (a > MathF.PI) a -= MathF.Tau;
        while (a < -MathF.PI) a += MathF.Tau;
        return a;
    }

    private static float Hypot(float x, float y) => MathF.Sqrt(x * x + y * y);

    public void ApplyConfig(PondConfig cfg)
    {
        bool countChanged = cfg.KoiCount != Config.KoiCount;
        bool seasonChanged = cfg.Season != Config.Season;
        Config = cfg;
        if (_initialized && countChanged) InitEcosystem();
        if (_initialized && seasonChanged)
        {
            _leaves.Clear();
            SpawnLeaf(true);
        }
    }

    public void Resize(int w, int h)
    {
        float fw = Math.Max(160, w), fh = Math.Max(100, h);
        if (_initialized && MathF.Abs(fw - _width) < 2f && MathF.Abs(fh - _height) < 2f) return;
        _width = fw;
        _height = fh;

        if (_width < 480) { _cellW = 3.6f; _cellH = 6.2f; _fontPx = 7; }
        else if (_width > 1650) { _cellW = 7.4f; _cellH = 12.6f; _fontPx = 13; }
        else { _cellW = 6.2f; _cellH = 10.6f; _fontPx = 11; }

        _cols = Math.Max(24, (int)(_width / _cellW));
        _rows = Math.Max(16, (int)(_height / _cellH));

        InitLotus();
        InitPlants();
        BuildStoneMap();
        if (!_initialized)
        {
            InitEcosystem();
            _initialized = true;
        }
        else
        {
            InitSkyEntities();
        }
    }

    public void OnClick(float x, float y)
    {
        float s = ScreenScale();
        _ripples.Add(new Ripple { X = x, Y = y, R = 3 * s, MaxR = 96 * s, Alpha = 0.88f });
        _ripples.Add(new Ripple { X = x, Y = y, R = 1 * s, MaxR = 54 * s, Alpha = 0.62f });
        if (_fishes.Count > 0)
        {
            _fishes[0].Leaving = false;
            _fishes[0].TargetX = Math.Clamp(x, 60, _width - 60);
            _fishes[0].TargetY = Math.Clamp(y, 60, _height - 60);
            _fishes[0].TargetZ = 0.94f;
            _fishes[0].WanderTimer = 4.5f;
        }
        foreach (var m in _minnows)
        {
            float dx = m.X - x, dy = m.Y - y;
            float d = Math.Max(1f, Hypot(dx, dy));
            if (d < 150 * s) { m.Vx += (dx / d) * 160; m.Vy += (dy / d) * 160; m.Boost = 1f; }
        }
    }

    private string ActiveTimeOfDay()
    {
        if (Config.TimeMode != "auto") return Config.TimeMode;
        int hr = DateTime.Now.Hour;
        if (hr >= 6 && hr < 17) return "day";
        if (hr >= 17 && hr < 20) return "sunset";
        return "night";
    }

    private string ActiveSeason()
    {
        if (Config.Season != "auto") return Config.Season;
        int m = DateTime.Now.Month;
        if (m >= 3 && m <= 5) return "spring";
        if (m >= 6 && m <= 8) return "summer";
        if (m >= 9 && m <= 11) return "autumn";
        return "winter";
    }

    private PondPalette CurrentPalette()
    {
        string tod = ActiveTimeOfDay();
        if (Config.MonoMode)
        {
            return new PondPalette
            {
                Tod = tod, Bg = new(8, 11, 16), WaterDeep = new(16, 22, 32), Stone = new(44, 52, 66), Clock = new(54, 66, 82),
                Water = new(148, 163, 184), WaterAlpha = 0.14f, Ripple = new(208, 218, 232), Shadow = new(0, 0, 0), ShadowAlpha = 0.68f,
                Lotus = new(78, 90, 104), LotusVein = new(118, 134, 150), Flower = new(222, 230, 240),
                White = new(236, 242, 250), Red = new(168, 180, 196), Black = new(56, 66, 80), Gold = new(214, 222, 232),
                Fin = new(146, 160, 178), FinBlack = new(62, 72, 86), Barbel = new(232, 240, 248),
                TurtleShell = new(148, 162, 178), TurtleRim = new(198, 210, 224), TurtleSkin = new(122, 136, 152),
                Minnow = new(212, 222, 236), Plant = new(68, 82, 92), PlantTip = new(112, 130, 144),
                Bubble = new(214, 230, 244), Splash = new(246, 250, 255),
                Dragonfly = new(226, 236, 248), Wing = new(152, 168, 188), Frog = new(172, 186, 198),
                Firefly = new(248, 252, 255), Moon = new(195, 210, 228),
                LeafAutumn = [new(198, 210, 224), new(164, 176, 192), new(224, 232, 242)],
                LeafSpring = [new(212, 222, 236), new(184, 196, 212), new(232, 240, 248)],
                LeafSummer = [new(154, 168, 182), new(184, 198, 212), new(134, 148, 164)],
                Snow = new(238, 244, 252), Eye = new(3, 5, 8)
            };
        }
        if (tod == "sunset")
        {
            return new PondPalette
            {
                Tod = tod, Bg = new(18, 16, 26), WaterDeep = new(30, 24, 40), Stone = new(54, 42, 54), Clock = new(78, 58, 70),
                Water = new(235, 148, 86), WaterAlpha = 0.22f, Ripple = new(255, 206, 148), Shadow = new(8, 5, 14), ShadowAlpha = 0.68f,
                Lotus = new(54, 96, 62), LotusVein = new(98, 142, 88), Flower = new(255, 192, 196),
                White = new(252, 238, 222), Red = new(248, 82, 42), Black = new(24, 24, 34), Gold = new(255, 196, 66),
                Fin = new(236, 218, 208), FinBlack = new(38, 36, 48), Barbel = new(252, 232, 210),
                TurtleShell = new(82, 108, 62), TurtleRim = new(192, 152, 86), TurtleSkin = new(96, 120, 74),
                Minnow = new(235, 206, 184), Plant = new(46, 84, 58), PlantTip = new(88, 138, 86),
                Bubble = new(255, 224, 192), Splash = new(255, 238, 216),
                Dragonfly = new(120, 224, 238), Wing = new(255, 224, 190), Frog = new(96, 162, 74),
                Firefly = new(255, 228, 108), Moon = new(255, 214, 158),
                LeafAutumn = [new(242, 88, 46), new(252, 174, 52), new(214, 54, 48)],
                LeafSpring = [new(255, 184, 208), new(255, 216, 228), new(244, 148, 184)],
                LeafSummer = [new(72, 158, 84), new(96, 184, 96), new(56, 134, 72)],
                Snow = new(245, 236, 248), Eye = new(8, 6, 12)
            };
        }
        if (tod == "night")
        {
            return new PondPalette
            {
                Tod = tod, Bg = new(4, 11, 22), WaterDeep = new(8, 22, 42), Stone = new(20, 42, 68), Clock = new(38, 68, 98),
                Water = new(92, 152, 220), WaterAlpha = 0.20f, Ripple = new(176, 220, 255), Shadow = new(1, 4, 10), ShadowAlpha = 0.74f,
                Lotus = new(26, 76, 64), LotusVein = new(52, 114, 92), Flower = new(224, 198, 232),
                White = new(222, 236, 252), Red = new(224, 72, 52), Black = new(16, 24, 38), Gold = new(234, 186, 78),
                Fin = new(184, 216, 242), FinBlack = new(24, 34, 52), Barbel = new(216, 232, 248),
                TurtleShell = new(50, 88, 72), TurtleRim = new(134, 134, 96), TurtleSkin = new(62, 102, 82),
                Minnow = new(168, 212, 248), Plant = new(20, 66, 62), PlantTip = new(46, 112, 96),
                Bubble = new(186, 232, 255), Splash = new(224, 244, 255),
                Dragonfly = new(110, 222, 252), Wing = new(192, 226, 252), Frog = new(68, 138, 86),
                Firefly = new(244, 255, 118), Moon = new(216, 234, 255),
                LeafAutumn = [new(204, 84, 64), new(222, 158, 68), new(178, 56, 64)],
                LeafSpring = [new(234, 176, 208), new(242, 208, 232), new(214, 142, 188)],
                LeafSummer = [new(52, 126, 86), new(74, 152, 102), new(40, 104, 76)],
                Snow = new(226, 240, 255), Eye = new(2, 5, 12)
            };
        }
        return new PondPalette
        {
            Tod = tod, Bg = new(6, 26, 32), WaterDeep = new(10, 44, 54), Stone = new(28, 72, 78), Clock = new(44, 96, 102),
            Water = new(84, 178, 188), WaterAlpha = 0.22f, Ripple = new(182, 244, 250), Shadow = new(1, 8, 12), ShadowAlpha = 0.65f,
            Lotus = new(42, 116, 72), LotusVein = new(78, 164, 102), Flower = new(252, 200, 218),
            White = new(248, 244, 238), Red = new(246, 74, 34), Black = new(22, 28, 36), Gold = new(250, 196, 54),
            Fin = new(220, 236, 238), FinBlack = new(32, 40, 50), Barbel = new(246, 238, 222),
            TurtleShell = new(72, 116, 66), TurtleRim = new(176, 154, 88), TurtleSkin = new(88, 126, 78),
            Minnow = new(182, 232, 244), Plant = new(30, 94, 66), PlantTip = new(72, 158, 104),
            Bubble = new(204, 248, 255), Splash = new(238, 254, 255),
            Dragonfly = new(66, 224, 242), Wing = new(216, 246, 255), Frog = new(84, 174, 78),
            Firefly = new(248, 255, 130), Moon = new(220, 240, 255),
            LeafAutumn = [new(236, 84, 42), new(248, 176, 46), new(208, 48, 44)],
            LeafSpring = [new(252, 184, 210), new(255, 216, 232), new(242, 146, 184)],
            LeafSummer = [new(68, 164, 84), new(96, 192, 100), new(52, 138, 72)],
            Snow = new(240, 248, 255), Eye = new(3, 8, 11)
        };
    }

    private void InitLotus()
    {
        float s = ScreenScale();
        _lotusPads.Clear();
        _lotusPads.Add(new LotusPad { X = _width * 0.13f, Y = _height * 0.21f, R = 74 * s, NotchAngle = 0.62f, Flower = true, Phase = 0.2f });
        _lotusPads.Add(new LotusPad { X = _width * 0.87f, Y = _height * 0.78f, R = 80 * s, NotchAngle = -2.35f, Flower = false, Phase = 1.7f });
        _lotusPads.Add(new LotusPad { X = _width * 0.83f, Y = _height * 0.18f, R = 56 * s, NotchAngle = 2.35f, Flower = true, Phase = 3.1f });
        _lotusPads.Add(new LotusPad { X = _width * 0.18f, Y = _height * 0.82f, R = 60 * s, NotchAngle = -0.75f, Flower = false, Phase = 4.4f });
    }

    private void InitPlants()
    {
        float s = ScreenScale();
        _plants.Clear();
        (float x, float y, int n, float r, float ph)[] specs =
        [
            (_width * 0.24f, _height * 0.74f, 7, 46 * s, 0.4f),
            (_width * 0.46f, _height * 0.15f, 6, 40 * s, 1.8f),
            (_width * 0.74f, _height * 0.45f, 7, 46 * s, 3.2f),
            (_width * 0.30f, _height * 0.35f, 6, 38 * s, 4.5f),
            (_width * 0.62f, _height * 0.86f, 7, 44 * s, 5.7f)
        ];
        for (int idx = 0; idx < specs.Length; idx++)
        {
            var sp = specs[idx];
            var fronds = new PlantFrond[sp.n];
            for (int f = 0; f < sp.n; f++)
            {
                fronds[f] = new PlantFrond
                {
                    Ang = (f / (float)sp.n) * MathF.Tau + Hash2(idx * 3.1f, f * 2.7f) * 0.45f,
                    Len = sp.r * (0.68f + Hash2(idx * 5.3f, f * 4.1f) * 0.45f),
                    Bend = (Hash2(idx, f) - 0.5f) * 0.5f
                };
            }
            _plants.Add(new PondPlant { X = sp.x, Y = sp.y, R = sp.r, Phase = sp.ph, Fronds = fronds, BubbleTimer = RandRange(0.4f, 1.8f) });
        }
    }

    private void InitSkyEntities()
    {
        _fireflies.Clear();
        for (int i = 0; i < 16; i++)
        {
            _fireflies.Add(new Firefly
            {
                X = RandRange(0, _width), Y = RandRange(0, _height),
                Vx = RandRange(-9, 9), Vy = RandRange(-9, 9),
                Phase = RandRange(0, MathF.Tau), BlinkSpd = RandRange(1.4f, 3.0f)
            });
        }
        _stars.Clear();
        for (int i = 0; i < 42; i++)
        {
            _stars.Add(new Star
            {
                X = Hash2(i * 4.7f, 9.1f) * _width,
                Y = Hash2(i * 8.3f, 2.7f) * _height,
                Phase = Hash2(i * 1.9f, 5.3f) * MathF.Tau,
                Spd = 1.2f + Hash2(i * 6.1f, 3.7f) * 2.2f
            });
        }
    }

    private void BuildStoneMap()
    {
        _stoneMap = new float[_cols * _rows];
        float s = ScreenScale();
        var stones = new (float sx, float sy, float rx, float ry, float c, float sn, float tone)[50];
        for (int i = 0; i < stones.Length; i++)
        {
            float sx = Hash2(i * 3.7f, 1.1f) * _width;
            float sy = Hash2(i * 5.3f, 2.9f) * _height;
            float rx = (20 + Hash2(i * 7.1f, 4.3f) * 44) * s;
            float ry = rx * (0.58f + Hash2(i * 2.3f, 8.7f) * 0.38f);
            float ang = Hash2(i * 9.1f, 6.2f) * MathF.PI;
            float tone = 0.55f + Hash2(i * 4.9f, 3.3f) * 0.45f;
            stones[i] = (sx, sy, rx, ry, MathF.Cos(ang), MathF.Sin(ang), tone);
        }
        for (int r = 0; r < _rows; r++)
        {
            float py = (r + 0.5f) * _cellH;
            int rowOff = r * _cols;
            for (int c = 0; c < _cols; c++)
            {
                float px = (c + 0.5f) * _cellW;
                float best = 0;
                for (int i = 0; i < stones.Length; i++)
                {
                    var st = stones[i];
                    float dx = px - st.sx, dy = py - st.sy;
                    if (MathF.Abs(dx) > st.rx + 2 || MathF.Abs(dy) > st.rx + 2) continue;
                    float lx = (dx * st.c + dy * st.sn) / st.rx;
                    float ly = (-dx * st.sn + dy * st.c) / st.ry;
                    float d2 = lx * lx + ly * ly;
                    if (d2 < 1f)
                    {
                        float z = MathF.Sqrt(1f - d2);
                        float lit = MathF.Max(0.12f, (z * 0.65f - lx * 0.25f - ly * 0.28f) * st.tone);
                        if (lit > best) best = lit;
                    }
                }
                _stoneMap[rowOff + c] = best;
            }
        }
    }

    private static float BodyHalfWidth(float t, float scale)
    {
        if (t < 0 || t > 0.76f) return 0;
        float u = t / 0.76f;
        float w = u < 0.08f
            ? 0.44f * MathF.Pow(MathF.Sin((u / 0.08f) * (MathF.PI / 2f)), 0.55f)
            : (u < 0.30f
                ? 0.44f + 0.56f * MathF.Sin(((u - 0.08f) / 0.22f) * (MathF.PI / 2f))
                : 0.115f + 0.885f * MathF.Pow(1f - (u - 0.30f) / 0.70f, 1.52f));
        float eyeBulge = MathF.Exp(-MathF.Pow((t - 0.082f) / 0.018f, 2f)) * 0.075f;
        return (w + eyeBulge) * 26.5f * scale;
    }

    private Koi CreateKoi(KoiVariety variety, float seed, float x, float y, float angle, float scale, float z, float speed, float phase, float turnRate)
    {
        const int N = 28;
        float segLen = 9.4f * scale;
        var nodes = new Vec2[N];
        var rNodes = new RenderNode[N];
        for (int i = 0; i < N; i++)
        {
            float nx = x - MathF.Cos(angle) * i * segLen;
            float ny = y - MathF.Sin(angle) * i * segLen;
            nodes[i] = new Vec2 { X = nx, Y = ny };
            rNodes[i] = new RenderNode { X = nx, Y = ny };
        }
        float bSegLen = 5.2f * scale;
        BarbelNode[] MakeBarbel(float side)
        {
            float initAng = angle + side * 1.15f;
            var arr = new BarbelNode[7];
            for (int i = 0; i < 7; i++)
                arr[i] = new BarbelNode { X = x + MathF.Cos(initAng) * i * bSegLen, Y = y + MathF.Sin(initAng) * i * bSegLen };
            return arr;
        }
        return new Koi
        {
            Variety = variety, Seed = seed, BaseScale = scale, Scale = scale,
            Z = z, TargetZ = z, ZTimer = RandRange(2f, 6f),
            SegLen = segLen, N = N, Nodes = nodes, RenderNodes = rNodes, Segs = new SpineSeg[N - 1],
            Barbels = [MakeBarbel(-1f), MakeBarbel(1f)], BarbelSegLen = bSegLen,
            Angle = angle, TargetX = x + MathF.Cos(angle) * 180, TargetY = y + MathF.Sin(angle) * 180,
            Phase = phase, BaseSpeed = speed, Speed = speed, TurnRate = turnRate,
            TailTimer = 0.5f, WanderTimer = 2.5f, BreachCooldown = RandRange(6f, 16f), HasEntered = true
        };
    }

    private Koi SpawnKoiFromEdge()
    {
        float s = ScreenScale();
        int edge = _rng.Next(4);
        var variety = AllVarieties[_rng.Next(AllVarieties.Length)];
        float scale = RandRange(1.38f, 1.90f) * s;
        float z = RandRange(0.22f, 0.92f);
        float off = 95 * scale;
        float x, y, angle;
        switch (edge)
        {
            case 0: x = -off; y = _height * RandRange(0.18f, 0.82f); angle = RandRange(-0.28f, 0.28f); break;
            case 1: x = _width + off; y = _height * RandRange(0.18f, 0.82f); angle = MathF.PI + RandRange(-0.28f, 0.28f); break;
            case 2: x = _width * RandRange(0.18f, 0.82f); y = -off; angle = MathF.PI * 0.5f + RandRange(-0.28f, 0.28f); break;
            default: x = _width * RandRange(0.18f, 0.82f); y = _height + off; angle = -MathF.PI * 0.5f + RandRange(-0.28f, 0.28f); break;
        }
        var koi = CreateKoi(variety, RandRange(0, 100), x, y, angle, scale, z, RandRange(48, 66) * s, RandRange(0, MathF.Tau), RandRange(1.15f, 1.5f));
        koi.TargetX = _width * RandRange(0.22f, 0.78f);
        koi.TargetY = _height * RandRange(0.22f, 0.78f);
        koi.WanderTimer = RandRange(4.5f, 8.0f);
        koi.HasEntered = false;
        return koi;
    }

    private void InitEcosystem()
    {
        float s = ScreenScale();
        int count = Math.Clamp(Config.KoiCount, 1, 5);
        (KoiVariety v, float x, float y, float a, float sc, float z, float sp)[] presets =
        [
            (KoiVariety.Showa, 0.36f, 0.48f, -0.12f, 1.84f, 0.90f, 52f),
            (KoiVariety.Utsuri, 0.66f, 0.30f, MathF.PI * 0.85f, 1.56f, 0.54f, 58f),
            (KoiVariety.Ogon, 0.52f, 0.74f, -MathF.PI * 0.72f, 1.38f, 0.24f, 46f),
            (KoiVariety.Sanke, 0.22f, 0.26f, 0.4f, 1.50f, 0.72f, 50f),
            (KoiVariety.Kumonryu, 0.78f, 0.66f, -2.4f, 1.44f, 0.38f, 54f)
        ];
        _fishes.Clear();
        for (int i = 0; i < count; i++)
        {
            var p = presets[i % presets.Length];
            _fishes.Add(CreateKoi(p.v, _patternSeed + i * 13.7f, _width * p.x, _height * p.y, p.a, p.sc * s, p.z, p.sp * s, i * 1.9f, 1.2f + (i % 3) * 0.12f));
        }
        _turtle = new Turtle
        {
            X = _width * 0.70f, Y = _height * 0.65f, Angle = -2.4f,
            TargetX = _width * 0.35f, TargetY = _height * 0.35f,
            Z = 0.38f, TargetZ = 0.44f, ZTimer = 4f, Scale = 1.54f * s, Speed = 22 * s, TurnRate = 0.55f, WanderTimer = 5f
        };
        _minnows.Clear();
        float cx = _width * 0.28f, cy = _height * 0.70f;
        for (int i = 0; i < 6; i++)
        {
            float ang = -0.3f + RandRange(-0.2f, 0.2f);
            float mx = cx + RandRange(-35, 35), my = cy + RandRange(-25, 25);
            var segs = new Vec2[6];
            for (int k = 0; k < 6; k++) segs[k] = new Vec2 { X = mx - MathF.Cos(ang) * k * 4.8f * s, Y = my - MathF.Sin(ang) * k * 4.8f * s };
            _minnows.Add(new Minnow { X = mx, Y = my, Vx = MathF.Cos(ang) * 62 * s, Vy = MathF.Sin(ang) * 62 * s, Angle = ang, Z = RandRange(0.78f, 0.96f), Phase = RandRange(0, MathF.Tau), Nodes = segs });
        }
        _dragonfly = new Dragonfly { X = _width * 0.2f, Y = _height * 0.25f, Z = 1.75f, Angle = 0.3f, TargetX = _width * 0.7f, TargetY = _height * 0.3f, StateTimer = 3.5f };
        var pad0 = _lotusPads.Count > 0 ? _lotusPads[0] : new LotusPad { X = _width * 0.13f, Y = _height * 0.21f };
        _frog = new Frog { X = pad0.X + 12, Y = pad0.Y + 8, Z = 1.02f, Angle = 0.55f, PadIdx = 0, RestTimer = 6f };
        InitSkyEntities();
        _leaves.Clear();
        SpawnLeaf(true);
    }

    private void SpawnLeaf(bool forceVisible)
    {
        float s = ScreenScale();
        bool isWinter = ActiveSeason() == "winter";
        bool fromTop = _rng.Next(2) == 0;
        _leaves.Add(new Leaf
        {
            X = fromTop ? RandRange(0, _width * 0.85f) : -52 * s,
            Y = fromTop ? -52 * s : RandRange(0, _height * 0.78f),
            Z = forceVisible ? 2.15f : RandRange(2.15f, 2.55f),
            Vx = ((isWinter ? 18 : 34) + RandRange(0, 22)) * s,
            Vy = ((isWinter ? 20 : 22) + RandRange(0, 18)) * s,
            Rot = RandRange(0, MathF.Tau), RotSpd = RandRange(-0.8f, 0.8f),
            Tumble = RandRange(0, MathF.Tau), TumbleSpd = RandRange(2.2f, 3.6f),
            SwayPhase = RandRange(0, MathF.Tau), ColorIdx = _rng.Next(3),
            Size = (isWinter ? RandRange(13, 19) : RandRange(28, 39)) * s,
            Maple = _rng.NextDouble() > 0.25, IsSnow = isWinter,
            MaxAge = isWinter ? 0.2f : RandRange(34, 50)
        });
    }

    private void SpawnSplashBurst(float x, float y, int count, float power)
    {
        float s = ScreenScale();
        for (int i = 0; i < count; i++)
        {
            float ang = RandRange(0, MathF.Tau);
            float spd = RandRange(28, 104) * power * s;
            _splashes.Add(new Splash
            {
                X = x + RandRange(-8, 8) * s, Y = y + RandRange(-8, 8) * s, Z = 1.02f,
                Vx = MathF.Cos(ang) * spd, Vy = MathF.Sin(ang) * spd, Vz = RandRange(1.2f, 2.7f) * power,
                Big = _rng.Next(2) == 0
            });
        }
        _ripples.Add(new Ripple { X = x, Y = y, R = 5 * s, MaxR = 86 * power * s, Alpha = 0.94f });
        _ripples.Add(new Ripple { X = x, Y = y, R = 1 * s, MaxR = 52 * power * s, Alpha = 0.74f });
    }

    public void Step(float rawDt)
    {
        float dt = Math.Clamp(rawDt, 0.001f, 0.05f);
        _time += dt;

        for (int i = 0; i < _fishes.Count; i++)
        {
            var f = _fishes[i];
            UpdateKoi(f, dt);
            if (f.Leaving)
            {
                float padOut = 110 * f.Scale;
                bool allOut = true;
                for (int n = 0; n < f.N; n++)
                {
                    var rn = f.RenderNodes[n];
                    if (rn.X > -padOut && rn.X < _width + padOut && rn.Y > -padOut && rn.Y < _height + padOut) { allOut = false; break; }
                }
                if (allOut) _fishes[i] = SpawnKoiFromEdge();
            }
        }
        if (_turtle != null) UpdateTurtle(_turtle, dt);
        UpdateMinnows(dt);
        if (_dragonfly != null) UpdateDragonfly(_dragonfly, dt);
        if (_frog != null) UpdateFrog(_frog, dt);
        UpdatePlantsAndBubbles(dt);
        UpdateSplashesAndLeaves(dt);

        if (Config.RainOn)
        {
            _rainTimer -= dt;
            if (_rainTimer <= 0)
            {
                _ripples.Add(new Ripple { X = RandRange(20, Math.Max(21, _width - 20)), Y = RandRange(20, Math.Max(21, _height - 20)), R = 2, MaxR = RandRange(28, 56), Alpha = 0.58f });
                _rainTimer = RandRange(0.16f, 0.40f);
            }
        }

        for (int i = _ripples.Count - 1; i >= 0; i--)
        {
            var rp = _ripples[i];
            rp.R += dt * 48f;
            if (rp.R >= rp.MaxR) _ripples.RemoveAt(i);
            else _ripples[i] = rp;
        }
    }

    private void UpdateKoi(Koi fish, float dt)
    {
        if (!fish.Breaching)
        {
            fish.BreachCooldown -= dt;
            if (fish.BreachCooldown <= 0 && fish.Z > 0.68f && !fish.Leaving)
            {
                var h = fish.Nodes[0];
                if (h.X > _width * 0.14f && h.X < _width * 0.86f && h.Y > _height * 0.14f && h.Y < _height * 0.86f)
                {
                    fish.Breaching = true; fish.BreachProgress = 0; fish.BreachSplashTick = 0;
                    fish.BreachCooldown = RandRange(10f, 22f);
                    var pt = fish.RenderNodes[Math.Min(2, fish.N - 1)];
                    SpawnSplashBurst(pt.X, pt.Y, 16, 1.1f);
                }
                else fish.BreachCooldown = 3f;
            }
        }
        if (fish.Breaching)
        {
            fish.BreachProgress += dt / 1.38f;
            float p = Math.Min(1f, fish.BreachProgress);
            fish.Z = 0.88f + MathF.Sin(p * MathF.PI) * 0.42f;
            fish.BreachSplashTick -= dt;
            if (fish.BreachSplashTick <= 0 && p > 0.12f && p < 0.88f)
            {
                var pt = fish.RenderNodes[Math.Min(fish.N - 1, (int)(p * 12))];
                SpawnSplashBurst(pt.X, pt.Y, 5, 0.75f);
                fish.BreachSplashTick = 0.14f;
            }
            if (fish.BreachProgress >= 1f)
            {
                fish.Breaching = false; fish.BreachProgress = 0;
                fish.TargetZ = RandRange(0.55f, 0.85f);
                var mid = fish.RenderNodes[fish.N / 3];
                SpawnSplashBurst(mid.X, mid.Y, 18, 1.15f);
            }
        }
        else
        {
            fish.ZTimer -= dt;
            if (fish.ZTimer <= 0) { fish.TargetZ = RandRange(0.20f, 0.96f); fish.ZTimer = RandRange(4f, 9f); }
            fish.Z += (fish.TargetZ - fish.Z) * Math.Min(1f, dt * 0.55f);
        }

        float breachBoost = fish.Z > 1f ? (fish.Z - 1f) * 0.34f : 0f;
        fish.Scale = fish.BaseScale * (0.86f + Math.Min(1f, fish.Z) * 0.18f + breachBoost);
        fish.SegLen = 9.4f * fish.Scale;
        fish.BarbelSegLen = 5.2f * fish.Scale;

        fish.WanderTimer -= dt;
        var head = fish.Nodes[0];
        if (head.X > 40 && head.X < _width - 40 && head.Y > 40 && head.Y < _height - 40) fish.HasEntered = true;

        if (!fish.Leaving && (Hypot(fish.TargetX - head.X, fish.TargetY - head.Y) < 85 || fish.WanderTimer <= 0))
        {
            if (fish.HasEntered && _rng.NextDouble() < 0.35)
            {
                fish.Leaving = true;
                int exitEdge = _rng.Next(4);
                float far = 440 * fish.Scale;
                switch (exitEdge)
                {
                    case 0: fish.TargetX = -far; fish.TargetY = RandRange(0, _height); break;
                    case 1: fish.TargetX = _width + far; fish.TargetY = RandRange(0, _height); break;
                    case 2: fish.TargetX = RandRange(0, _width); fish.TargetY = -far; break;
                    default: fish.TargetX = RandRange(0, _width); fish.TargetY = _height + far; break;
                }
            }
            else
            {
                fish.TargetX = RandRange(35, Math.Max(36, _width - 35));
                fish.TargetY = RandRange(35, Math.Max(36, _height - 35));
                fish.WanderTimer = RandRange(3.6f, 7.8f);
            }
        }

        float diff = NormalizeAngle(MathF.Atan2(fish.TargetY - head.Y, fish.TargetX - head.X) - fish.Angle);
        float maxTurn = fish.TurnRate * dt;
        float deltaAngle = Math.Clamp(diff, -maxTurn, maxTurn);
        fish.Angle += deltaAngle;
        fish.TurnVel = deltaAngle / dt;

        float turnEffort = Math.Min(1f, MathF.Abs(diff) * 0.9f);
        float targetSpeed = fish.BaseSpeed * (fish.Breaching ? 1.38f : 1f) * (1f + turnEffort * 0.28f);
        fish.Speed += (targetSpeed - fish.Speed) * Math.Min(1f, dt * 3.2f);
        fish.Phase += dt * (4.5f + turnEffort * 2.2f + (fish.Breaching ? 2.5f : 0f));

        fish.Nodes[0].X += MathF.Cos(fish.Angle) * fish.Speed * dt;
        fish.Nodes[0].Y += MathF.Sin(fish.Angle) * fish.Speed * dt;

        for (int i = 1; i < fish.N; i++)
        {
            var prev = fish.Nodes[i - 1]; var curr = fish.Nodes[i];
            float dx = curr.X - prev.X, dy = curr.Y - prev.Y;
            float d = Math.Max(0.0001f, Hypot(dx, dy));
            fish.Nodes[i].X = prev.X + (dx / d) * fish.SegLen;
            fish.Nodes[i].Y = prev.Y + (dy / d) * fish.SegLen;
        }

        for (int i = 0; i < fish.N; i++)
        {
            float t = i / (float)(fish.N - 1);
            var prev = fish.Nodes[Math.Max(0, i - 1)];
            var next = fish.Nodes[Math.Min(fish.N - 1, i + 1)];
            float tx = prev.X - next.X, ty = prev.Y - next.Y;
            float len = Math.Max(0.0001f, Hypot(tx, ty));
            tx /= len; ty /= len;
            float nx = -ty, ny = tx;
            float sway = MathF.Sin(fish.Phase - t * 6.5f) * (1.1f + 20f * MathF.Pow(t, 1.95f)) * fish.Scale;
            fish.RenderNodes[i] = new RenderNode { X = fish.Nodes[i].X + nx * sway, Y = fish.Nodes[i].Y + ny * sway, Nx = nx, Ny = ny };
        }

        for (int i = 0; i < fish.N - 1; i++)
        {
            var a = fish.RenderNodes[i]; var b = fish.RenderNodes[i + 1];
            float abx = b.X - a.X, aby = b.Y - a.Y;
            float lenSq = Math.Max(0.0001f, abx * abx + aby * aby);
            fish.Segs[i] = new SpineSeg { Ax = a.X, Ay = a.Y, Abx = abx, Aby = aby, InvLenSq = 1f / lenSq, Anx = a.Nx, Any = a.Ny, Dnx = b.Nx - a.Nx, Dny = b.Ny - a.Ny };
        }

        // Barbel physics
        var r0 = fish.RenderNodes[0]; var r1 = fish.RenderNodes[1];
        float headTx = r0.X - r1.X, headTy = r0.Y - r1.Y;
        float headLen = Math.Max(0.0001f, Hypot(headTx, headTy));
        headTx /= headLen; headTy /= headLen;
        float headNx = -headTy, headNy = headTx;
        float snoutEdgeW = BodyHalfWidth(0.025f, fish.Scale) + 1.6f * fish.Scale;
        float drag = MathF.Exp(-5.8f * dt);
        var cheekNode = fish.RenderNodes[4];
        float cheekRepelR = BodyHalfWidth(0.13f, fish.Scale) + 11.5f * fish.Scale;

        for (int bIdx = 0; bIdx < 2; bIdx++)
        {
            float side = bIdx == 0 ? -1f : 1f;
            var chain = fish.Barbels[bIdx];
            chain[0] = new BarbelNode { X = r0.X - headTx * (1.2f * fish.Scale) + headNx * (side * snoutEdgeW), Y = r0.Y - headTy * (1.2f * fish.Scale) + headNy * (side * snoutEdgeW) };

            for (int i = 1; i < chain.Length; i++)
            {
                var prev = chain[i - 1]; var curr = chain[i];
                float oldX = curr.X, oldY = curr.Y;
                float f = i / (float)(chain.Length - 1);
                float splayOut = (1.15f - f * 0.55f) * 145 * fish.Scale;
                float forwardAtBase = Math.Max(0f, 0.45f - f) * 95 * fish.Scale;
                float backDrag = (f * 66 + fish.Speed * 0.22f * f) * fish.Scale;
                float flutter = MathF.Sin(fish.Phase * 1.5f - i * 0.72f + bIdx * 1.9f) * (32 * f * fish.Scale);
                float fx = headNx * (side * splayOut + flutter) + headTx * (forwardAtBase - backDrag);
                float fy = headNy * (side * splayOut + flutter) + headTy * (forwardAtBase - backDrag);

                float cdx = curr.X - cheekNode.X, cdy = curr.Y - cheekNode.Y;
                float cDist = Math.Max(0.001f, Hypot(cdx, cdy));
                if (cDist < cheekRepelR)
                {
                    float push = (1f - cDist / cheekRepelR) * 260 * fish.Scale;
                    fx += (cdx / cDist) * push; fy += (cdy / cDist) * push;
                }

                curr.Vx = (curr.Vx + fx * dt) * drag; curr.Vy = (curr.Vy + fy * dt) * drag;
                curr.X += curr.Vx * dt; curr.Y += curr.Vy * dt;

                float dx = curr.X - prev.X, dy = curr.Y - prev.Y;
                float d = Math.Max(0.0001f, Hypot(dx, dy));
                curr.X = prev.X + (dx / d) * fish.BarbelSegLen;
                curr.Y = prev.Y + (dy / d) * fish.BarbelSegLen;
                curr.Vx = curr.Vx * 0.40f + ((curr.X - oldX) / dt) * 0.60f;
                curr.Vy = curr.Vy * 0.40f + ((curr.Y - oldY) / dt) * 0.60f;
                chain[i] = curr;
            }
        }

        fish.TailTimer -= dt;
        if (fish.TailTimer <= 0 && fish.Z > 0.58f)
        {
            var tail = fish.RenderNodes[fish.N - 1];
            _ripples.Add(new Ripple { X = tail.X, Y = tail.Y, R = 4, MaxR = 42 * fish.Scale, Alpha = 0.24f + Math.Min(0.5f, (fish.Z - 0.58f) * 0.7f) });
            fish.TailTimer = RandRange(0.65f, 1.15f);
        }
    }

    private void UpdateTurtle(Turtle t, float dt)
    {
        t.ZTimer -= dt;
        if (t.ZTimer <= 0) { t.TargetZ = RandRange(0.25f, 0.75f); t.ZTimer = RandRange(6f, 11f); }
        t.Z += (t.TargetZ - t.Z) * Math.Min(1f, dt * 0.35f);
        t.WanderTimer -= dt;
        if (Hypot(t.TargetX - t.X, t.TargetY - t.Y) < 60 || t.WanderTimer <= 0)
        {
            t.TargetX = RandRange(80, Math.Max(81, _width - 80));
            t.TargetY = RandRange(70, Math.Max(71, _height - 70));
            t.WanderTimer = RandRange(6f, 11f);
        }
        float diff = NormalizeAngle(MathF.Atan2(t.TargetY - t.Y, t.TargetX - t.X) - t.Angle);
        t.Angle += Math.Clamp(diff, -t.TurnRate * dt, t.TurnRate * dt);
        t.HeadYaw = MathF.Sin(t.Phase * 0.45f) * 0.16f + Math.Clamp(diff * 0.5f, -0.25f, 0.25f);
        t.Phase += dt * 2.1f;
        float surge = 0.72f + 0.45f * Math.Max(0f, MathF.Sin(t.Phase));
        t.X += MathF.Cos(t.Angle) * t.Speed * surge * dt;
        t.Y += MathF.Sin(t.Angle) * t.Speed * surge * dt;
    }

    private void UpdateMinnows(float dt)
    {
        float s = ScreenScale();
        for (int i = 0; i < _minnows.Count; i++)
        {
            var m = _minnows[i];
            float ax = 0, ay = 0, cx = 0, cy = 0, avx = 0, avy = 0; int count = 0;
            for (int j = 0; j < _minnows.Count; j++)
            {
                if (i == j) continue;
                var o = _minnows[j];
                float dx = o.X - m.X, dy = o.Y - m.Y;
                float d = Math.Max(0.01f, Hypot(dx, dy));
                if (d < 95 * s)
                {
                    cx += o.X; cy += o.Y; avx += o.Vx; avy += o.Vy; count++;
                    if (d < 24 * s) { ax -= (dx / d) * 150; ay -= (dy / d) * 150; }
                }
            }
            if (count > 0)
            {
                ax += ((cx / count) - m.X) * 1.4f + ((avx / count) - m.Vx) * 1.8f;
                ay += ((cy / count) - m.Y) * 1.4f + ((avy / count) - m.Vy) * 1.8f;
            }
            foreach (var f in _fishes)
            {
                var kh = f.RenderNodes[0];
                float dx = m.X - kh.X, dy = m.Y - kh.Y;
                float d = Math.Max(1f, Hypot(dx, dy));
                if (d < 95 * s) { ax += (dx / d) * 260; ay += (dy / d) * 260; m.Boost = Math.Min(1f, m.Boost + dt * 3f); }
            }
            if (m.X < 45) ax += 190; else if (m.X > _width - 45) ax -= 190;
            if (m.Y < 45) ay += 190; else if (m.Y > _height - 45) ay -= 190;
            m.Vx += ax * dt; m.Vy += ay * dt;
            m.Boost = Math.Max(0f, m.Boost - dt * 1.6f);
            float targetSpd = (62 + m.Boost * 80) * s;
            float spd = Math.Max(1f, Hypot(m.Vx, m.Vy));
            m.Vx = (m.Vx / spd) * targetSpd; m.Vy = (m.Vy / spd) * targetSpd;
            m.X += m.Vx * dt; m.Y += m.Vy * dt;
            m.Angle = MathF.Atan2(m.Vy, m.Vx);
            m.Phase += dt * (11 + m.Boost * 9);
            m.Nodes[0] = new Vec2 { X = m.X, Y = m.Y };
            for (int k = 1; k < m.Nodes.Length; k++)
            {
                var prev = m.Nodes[k - 1]; var curr = m.Nodes[k];
                float dx = curr.X - prev.X, dy = curr.Y - prev.Y;
                float d = Math.Max(0.01f, Hypot(dx, dy));
                m.Nodes[k] = new Vec2 { X = prev.X + (dx / d) * 4.8f * s, Y = prev.Y + (dy / d) * 4.8f * s };
            }
        }
    }

    private void UpdateDragonfly(Dragonfly df, float dt)
    {
        df.WingPhase += dt * (df.Perched ? 6f : 42f);
        df.StateTimer -= dt;
        if (df.Perched)
        {
            if (df.PerchPadIdx >= 0 && df.PerchPadIdx < _lotusPads.Count)
            {
                var pad = _lotusPads[df.PerchPadIdx];
                df.X = pad.X + MathF.Sin(_time * 0.55f + pad.Phase) * 2.5f - 10;
                df.Y = pad.Y + MathF.Cos(_time * 0.45f + pad.Phase) * 2.0f - 8;
                df.Z += (1.06f - df.Z) * Math.Min(1f, dt * 6f);
            }
            bool spooked = _fishes.Any(f => Hypot(f.Nodes[0].X - df.X, f.Nodes[0].Y - df.Y) < 110);
            if (df.StateTimer <= 0 || spooked)
            {
                df.Perched = false; df.StateTimer = RandRange(4.0f, 8.5f);
                df.TargetX = RandRange(80, Math.Max(81, _width - 80));
                df.TargetY = RandRange(80, Math.Max(81, _height - 80));
                _ripples.Add(new Ripple { X = df.X, Y = df.Y, R = 2, MaxR = 22, Alpha = 0.45f });
            }
        }
        else
        {
            df.Z += (1.72f - df.Z) * Math.Min(1f, dt * 2.5f);
            float dx = df.TargetX - df.X, dy = df.TargetY - df.Y;
            float dist = Hypot(dx, dy);
            if (dist < 28)
            {
                if (df.StateTimer <= 0 && _lotusPads.Count > 0 && _rng.Next(2) == 0)
                {
                    int pIdx = _rng.Next(_lotusPads.Count);
                    df.PerchPadIdx = pIdx;
                    df.TargetX = _lotusPads[pIdx].X - 10; df.TargetY = _lotusPads[pIdx].Y - 8;
                    if (Hypot(df.TargetX - df.X, df.TargetY - df.Y) < 30) { df.Perched = true; df.StateTimer = RandRange(2.8f, 6.3f); }
                }
                else
                {
                    df.TargetX = RandRange(70, Math.Max(71, _width - 70));
                    df.TargetY = RandRange(70, Math.Max(71, _height - 70));
                }
            }
            float diff = NormalizeAngle(MathF.Atan2(dy, dx) - df.Angle);
            df.Angle += Math.Clamp(diff, -4.5f * dt, 4.5f * dt);
            float spd = dist < 80 ? 68f : 138f;
            df.X += MathF.Cos(df.Angle) * spd * dt; df.Y += MathF.Sin(df.Angle) * spd * dt;
        }
    }

    private void UpdateFrog(Frog fr, float dt)
    {
        if (_lotusPads.Count == 0) return;
        if (!fr.Swimming)
        {
            var pad = _lotusPads[fr.PadIdx % _lotusPads.Count];
            fr.X = pad.X + MathF.Sin(_time * 0.55f + pad.Phase) * 2.5f + 10;
            fr.Y = pad.Y + MathF.Cos(_time * 0.45f + pad.Phase) * 2.0f + 8;
            fr.Z = 1.03f; fr.RestTimer -= dt;
            bool startled = _fishes.Any(f => Hypot(f.Nodes[0].X - fr.X, f.Nodes[0].Y - fr.Y) < 95);
            if (startled || fr.RestTimer <= 0)
            {
                fr.Swimming = true;
                fr.TargetPadIdx = (fr.PadIdx + 1 + _rng.Next(Math.Max(1, _lotusPads.Count - 1))) % _lotusPads.Count;
                fr.SwimPhase = 0;
                SpawnSplashBurst(fr.X, fr.Y, 6, 0.55f);
            }
        }
        else
        {
            var tPad = _lotusPads[fr.TargetPadIdx % _lotusPads.Count];
            float dx = (tPad.X + 10) - fr.X, dy = (tPad.Y + 8) - fr.Y;
            float dist = Hypot(dx, dy);
            fr.Angle = MathF.Atan2(dy, dx);
            fr.SwimPhase += dt * 4.8f;
            float kick = 0.45f + 0.95f * Math.Max(0f, MathF.Sin(fr.SwimPhase));
            fr.X += MathF.Cos(fr.Angle) * 52 * kick * dt; fr.Y += MathF.Sin(fr.Angle) * 52 * kick * dt;
            fr.Z = 0.94f;
            if (MathF.Sin(fr.SwimPhase) > 0.94f) _ripples.Add(new Ripple { X = fr.X, Y = fr.Y, R = 3, MaxR = 22, Alpha = 0.42f });
            if (dist < tPad.R * 0.45f)
            {
                fr.Swimming = false; fr.PadIdx = fr.TargetPadIdx; fr.RestTimer = RandRange(7f, 15f);
                _ripples.Add(new Ripple { X = fr.X, Y = fr.Y, R = 2, MaxR = 24, Alpha = 0.52f });
            }
        }
    }

    private void UpdatePlantsAndBubbles(float dt)
    {
        foreach (var pl in _plants)
        {
            pl.BubbleTimer -= dt;
            if (pl.BubbleTimer <= 0 && pl.Fronds.Length > 0)
            {
                var fr = pl.Fronds[_rng.Next(pl.Fronds.Length)];
                float ang = fr.Ang + MathF.Sin(_time * 1.15f + pl.Phase) * 0.24f;
                float rOff = fr.Len * RandRange(0.55f, 0.95f);
                _bubbles.Add(new Bubble { X = pl.X + MathF.Cos(ang) * rOff, Y = pl.Y + MathF.Sin(ang) * rOff, Z = 0.08f, Vz = RandRange(0.26f, 0.42f), WigglePhase = RandRange(0, MathF.Tau), WiggleAmp = RandRange(5, 11) });
                pl.BubbleTimer = RandRange(0.8f, 2.7f);
            }
        }
        for (int i = _bubbles.Count - 1; i >= 0; i--)
        {
            var b = _bubbles[i];
            b.Z += b.Vz * dt; b.WigglePhase += dt * 4.5f;
            b.X += MathF.Cos(b.WigglePhase) * b.WiggleAmp * dt;
            b.Y += MathF.Sin(b.WigglePhase * 0.8f) * b.WiggleAmp * dt;
            if (b.Z >= 1f)
            {
                _ripples.Add(new Ripple { X = b.X, Y = b.Y, R = 2, MaxR = RandRange(18, 30), Alpha = 0.64f });
                _bubbles.RemoveAt(i);
            }
            else _bubbles[i] = b;
        }
    }

    private void UpdateSplashesAndLeaves(float dt)
    {
        string actSeason = ActiveSeason();
        for (int i = _splashes.Count - 1; i >= 0; i--)
        {
            var sp = _splashes[i];
            sp.X += sp.Vx * dt; sp.Y += sp.Vy * dt;
            float d = MathF.Exp(-1.4f * dt); sp.Vx *= d; sp.Vy *= d;
            sp.Vz -= 4.2f * dt; sp.Z += sp.Vz * dt;
            if (sp.Z <= 1f && sp.Vz < 0)
            {
                if (sp.Big || _rng.Next(2) == 0)
                    _ripples.Add(new Ripple { X = sp.X, Y = sp.Y, R = 1.5f, MaxR = sp.Big ? 24 : 14, Alpha = sp.Big ? 0.72f : 0.50f });
                _splashes.RemoveAt(i);
            }
            else _splashes[i] = sp;
        }

        _leafSpawnTimer -= dt;
        int maxLeaves = actSeason == "winter" ? 12 : (actSeason == "summer" ? 4 : 8);
        float spawnGap = actSeason == "winter" ? 0.55f : (actSeason == "summer" ? 4.5f : 2.1f);
        if (_leafSpawnTimer <= 0 && _leaves.Count < maxLeaves)
        {
            SpawnLeaf(false);
            _leafSpawnTimer = spawnGap + RandRange(0, spawnGap);
        }

        for (int i = _leaves.Count - 1; i >= 0; i--)
        {
            var lf = _leaves[i];
            lf.SwayPhase += dt * (lf.Floating ? 1.1f : 3.4f);
            lf.Rot += lf.RotSpd * dt;
            if (!lf.Floating)
            {
                lf.Z -= dt * (lf.IsSnow ? 0.46f : 0.34f);
                lf.Tumble += lf.TumbleSpd * dt;
                lf.X += (lf.Vx + MathF.Sin(lf.SwayPhase) * 34) * dt;
                lf.Y += (lf.Vy + MathF.Cos(lf.SwayPhase * 0.85f) * 18) * dt;
                if (lf.Z <= 1f)
                {
                    lf.Z = 1f; lf.Floating = true; lf.RotSpd *= 0.18f;
                    _ripples.Add(new Ripple { X = lf.X, Y = lf.Y, R = 3, MaxR = lf.IsSnow ? 20 : 42, Alpha = lf.IsSnow ? 0.58f : 0.85f });
                    if (!lf.IsSnow) _ripples.Add(new Ripple { X = lf.X, Y = lf.Y, R = 0.5f, MaxR = 25, Alpha = 0.62f });
                }
                _leaves[i] = lf;
            }
            else
            {
                lf.Age += dt;
                lf.X += (lf.Vx * 0.42f + MathF.Sin(lf.SwayPhase) * 3.5f) * dt;
                lf.Y += (lf.Vy * 0.42f + MathF.Cos(lf.SwayPhase * 0.7f) * 2.5f) * dt;
                if (lf.Age > lf.MaxAge || lf.X < -90 || lf.X > _width + 90 || lf.Y < -90 || lf.Y > _height + 90)
                    _leaves.RemoveAt(i);
                else _leaves[i] = lf;
            }
        }

        for (int i = 0; i < _fireflies.Count; i++)
        {
            var ff = _fireflies[i];
            ff.Phase += dt * ff.BlinkSpd;
            ff.X += (ff.Vx + MathF.Sin(_time * 0.9f + i) * 10) * dt;
            ff.Y += (ff.Vy + MathF.Cos(_time * 0.7f + i * 1.3f) * 10) * dt;
            if (ff.X < 10) ff.X = _width - 10; else if (ff.X > _width - 10) ff.X = 10;
            if (ff.Y < 10) ff.Y = _height - 10; else if (ff.Y > _height - 10) ff.Y = 10;
            _fireflies[i] = ff;
        }
    }

    private (float t, float lat, float dist, float nx, float ny) ProjectToSpine(Koi fish, float px, float py)
    {
        int nSeg = fish.N - 1;
        float bestD2 = float.PositiveInfinity, bestU = 0; int bestIdx = 0;
        for (int i = 0; i < nSeg; i++)
        {
            var s = fish.Segs[i];
            float u = ((px - s.Ax) * s.Abx + (py - s.Ay) * s.Aby) * s.InvLenSq;
            if (u < 0) u = 0; else if (u > 1) u = 1;
            float dx = px - (s.Ax + s.Abx * u), dy = py - (s.Ay + s.Aby * u);
            float d2 = dx * dx + dy * dy;
            if (d2 < bestD2) { bestD2 = d2; bestIdx = i; bestU = u; }
        }
        var seg = fish.Segs[bestIdx];
        float bdx = px - (seg.Ax + seg.Abx * bestU), bdy = py - (seg.Ay + seg.Aby * bestU);
        float nx = seg.Anx + seg.Dnx * bestU, ny = seg.Any + seg.Dny * bestU;
        float nLen = Math.Max(0.0001f, Hypot(nx, ny));
        nx /= nLen; ny /= nLen;
        return ((bestIdx + bestU) / nSeg, bdx * nx + bdy * ny, MathF.Sqrt(bestD2), nx, ny);
    }

    private static int GetPigment(Koi fish, float t, float normLat)
    {
        if (fish.Variety == KoiVariety.Ogon) return 3;
        float sd = fish.Seed;
        float n1 = Fbm(t * 4.3f + sd, normLat * 1.5f + sd * 0.7f);
        float n2 = Fbm(t * 5.8f - sd * 1.3f, normLat * 1.9f + sd * 1.1f);
        float n3 = Fbm(t * 8.8f + sd * 2.1f, normLat * 2.7f - sd * 0.9f);
        return fish.Variety switch
        {
            KoiVariety.Showa => n1 > 0.55f ? 2 : (n2 > 0.48f ? 1 : (n3 > 0.66f && t > 0.14f ? 2 : 0)),
            KoiVariety.Utsuri => (n1 > 0.48f || (n2 > 0.65f && t > 0.10f)) ? 2 : 0,
            KoiVariety.Kumonryu => (n1 > 0.62f || (MathF.Abs(normLat) > 0.64f && n2 > 0.56f)) ? 0 : 2,
            KoiVariety.Sanke => (n3 > 0.66f && t > 0.15f && t < 0.74f) ? 2 : (n2 > 0.46f ? 1 : 0),
            _ => 3
        };
    }

    private SampleHit SampleKoi(Koi fish, float px, float py, bool shadowOnly)
    {
        var proj = ProjectToSpine(fish, px, py);
        float t = proj.t, lat = proj.lat, absLat = MathF.Abs(lat), s = fish.Scale;
        if (proj.dist > 78 * s) return default;

        if (t >= 0 && t <= 0.76f)
        {
            float bw = BodyHalfWidth(t, s);
            if (absLat <= bw)
            {
                if (shadowOnly) return new SampleHit { Kind = 8, ValA = 0.78f };
                float normLat = bw > 0.01f ? lat / bw : 0;
                float z = MathF.Sqrt(Math.Max(0.02f, 1f - normLat * normLat));

                const float eyeT = 0.082f;
                float eyeLat = BodyHalfWidth(eyeT, s) * 0.80f;
                float dEye = Hypot((t - eyeT) * 265 * s, absLat - eyeLat);
                if (dEye < 3.6f * s)
                {
                    bool glint = Hypot((t - (eyeT - 0.005f)) * 265 * s, absLat - (eyeLat - 0.9f * s)) < 1.25f * s;
                    return new SampleHit { Kind = 1, FlagA = glint, FlagB = dEye > 2.6f * s, DepthZ = fish.Z };
                }

                float shade = (proj.nx * normLat * 0.9f) * -0.50f + (proj.ny * normLat * 0.9f) * -0.56f + z * 0.66f;
                shade = Math.Clamp(0.30f + shade * 0.76f, 0.14f, 1f);
                float caustic = MathF.Sin(px * 0.08f + _time * 1.4f + MathF.Sin(py * 0.07f - _time)) * MathF.Cos(py * 0.10f + _time * 0.9f);
                if (caustic > 0.55f && z > 0.55f) shade = Math.Min(1f, shade + (caustic - 0.55f) * 0.35f * Math.Min(1f, fish.Z));

                float gillCurve = 0.188f - 0.032f * (1f - normLat * normLat);
                bool isGill = MathF.Abs(t - gillCurve) < 0.0075f && absLat > bw * 0.28f;
                if (isGill) shade *= 0.55f;

                bool isScaleEdge = false;
                if (t > 0.195f && t < 0.74f)
                {
                    float scaleRow = t * 48f;
                    float stagger = ((int)MathF.Floor(scaleRow) % 2 == 0) ? 0f : 0.5f;
                    float su = scaleRow - MathF.Floor(scaleRow);
                    float sv = ((normLat * 5f + 12f + stagger) % 1f + 1f) % 1f;
                    float dScale = Hypot(su - 0.5f, sv - 0.5f);
                    if (dScale > 0.37f && dScale < 0.52f) { shade = Math.Max(0.12f, shade - 0.12f); isScaleEdge = true; }
                    else if (dScale < 0.20f) shade = Math.Min(1f, shade + 0.08f);
                }

                bool isDorsal = false;
                if (t >= 0.29f && t <= 0.66f)
                {
                    float df = (t - 0.29f) / 0.37f;
                    float dorsalOffset = MathF.Sin(fish.Phase - t * 7f - 1f) * (4.8f * s * MathF.Sin(df * MathF.PI));
                    float dorsalThick = (2.4f * s) * (0.4f + 0.6f * MathF.Sin(df * MathF.PI));
                    if (MathF.Abs(lat - dorsalOffset) < dorsalThick) { isDorsal = true; shade = Math.Min(1f, shade + 0.16f); }
                    else if (MathF.Abs(lat - (dorsalOffset + 3f * s)) < dorsalThick * 0.9f) shade *= 0.78f;
                }

                return new SampleHit { Kind = 3, ValA = shade, IntA = GetPigment(fish, t, normLat), FlagA = isDorsal, FlagB = isScaleEdge, FlagC = isGill, DepthZ = fish.Z };
            }
        }

        // Barbels
        var headNode = fish.RenderNodes[0];
        if (Hypot(px - headNode.X, py - headNode.Y) < 76 * s)
        {
            float bestD2 = float.PositiveInfinity, bestU = 0, bestAng = 0;
            for (int bIdx = 0; bIdx < 2; bIdx++)
            {
                var chain = fish.Barbels[bIdx];
                for (int i = 0; i < chain.Length - 1; i++)
                {
                    var a = chain[i]; var b = chain[i + 1];
                    float abx = b.X - a.X, aby = b.Y - a.Y;
                    float lenSq = Math.Max(0.0001f, abx * abx + aby * aby);
                    float u = Math.Clamp(((px - a.X) * abx + (py - a.Y) * aby) / lenSq, 0f, 1f);
                    float dx = px - (a.X + abx * u), dy = py - (a.Y + aby * u);
                    float d2 = dx * dx + dy * dy;
                    if (d2 < bestD2) { bestD2 = d2; bestU = (i + u) / (chain.Length - 1); bestAng = MathF.Atan2(aby, abx); }
                }
            }
            float thick = (3.1f - bestU * 1.4f) * s;
            if (bestD2 <= thick * thick)
                return shadowOnly ? new SampleHit { Kind = 8, ValA = 0.25f * (1f - bestU * 0.55f) }
                                  : new SampleHit { Kind = 2, ValA = bestU, ValB = bestAng, Variety = fish.Variety, DepthZ = fish.Z };
        }

        // Caudal Fin
        if (t >= 0.71f && t <= 1f)
        {
            float v = (t - 0.71f) / 0.29f;
            float tailWhip = MathF.Sin(fish.Phase - 6.5f - v * 2.5f) * (9.5f * v * v * s);
            float absEff = MathF.Abs(lat - tailWhip);
            float tailOuter = (3.8f + 31.5f * MathF.Pow(v, 0.76f)) * s;
            float notchInner = v > 0.36f ? MathF.Pow((v - 0.36f) / 0.64f, 1.15f) * 18f * s : -1f;
            if (absEff <= tailOuter && absEff >= notchInner)
            {
                if (shadowOnly) return new SampleHit { Kind = 8, ValA = 0.32f * (1f - v * 0.55f) };
                float rayFrac = absEff / Math.Max(0.01f, tailOuter);
                float ray = 0.5f + 0.5f * MathF.Sin(rayFrac * 26 - v * 3f);
                bool spine = rayFrac > 0.88f && v < 0.78f;
                float density = spine ? 0.92f : (1f - v * 0.64f) * (0.36f + 0.64f * ray);
                bool dark = (fish.Variety is KoiVariety.Showa or KoiVariety.Utsuri or KoiVariety.Kumonryu) && v < 0.58f && MathF.Sin(rayFrac * 10 + fish.Seed) > 0.52f;
                return new SampleHit { Kind = 4, ValA = density, FlagA = dark, FlagB = spine, DepthZ = fish.Z };
            }
        }

        // Pectoral Fins
        float turnFlare = Math.Clamp(fish.TurnVel * 0.025f, -0.04f, 0.04f);
        float rowL = MathF.Sin(fish.Phase * 0.60f) * 0.022f + turnFlare;
        float rowR = MathF.Sin(fish.Phase * 0.60f + 0.38f) * 0.022f - turnFlare;
        float tStartP = 0.18f + (lat > 0 ? rowL : rowR);
        float tEndP = 0.46f + (lat > 0 ? rowL : rowR);
        if (t >= tStartP && t <= tEndP)
        {
            float f = (t - tStartP) / (tEndP - tStartP);
            float bw = BodyHalfWidth(t, s);
            float reach = 35f * s * MathF.Sin(MathF.Pow(f, 0.58f) * MathF.PI);
            float innerCut = f > 0.55f ? bw + ((f - 0.55f) / 0.45f) * 12 * s : bw * 0.88f;
            if (absLat > innerCut && absLat <= bw + reach)
            {
                if (shadowOnly) return new SampleHit { Kind = 8, ValA = 0.30f };
                float distFromBody = (absLat - bw) / Math.Max(0.01f, reach);
                float ray = 0.5f + 0.5f * MathF.Sin(f * 22 - distFromBody * 5.2f);
                bool spine = f < 0.13f && distFromBody < 0.92f;
                float density = spine ? 0.95f : (1f - distFromBody * 0.62f) * (0.38f + 0.62f * ray);
                bool dark = (fish.Variety is KoiVariety.Showa or KoiVariety.Utsuri or KoiVariety.Kumonryu) && distFromBody < 0.45f && f > 0.10f && f < 0.72f;
                return new SampleHit { Kind = 4, ValA = density, FlagA = dark, FlagB = spine, DepthZ = fish.Z };
            }
        }

        // Pelvic Fins
        if (t >= 0.46f && t <= 0.62f)
        {
            float f = (t - 0.46f) / 0.16f;
            float bw = BodyHalfWidth(t, s);
            float reach = 15f * s * MathF.Sin(MathF.Pow(f, 0.68f) * MathF.PI);
            if (absLat > bw * 0.88f && absLat <= bw + reach)
                return shadowOnly ? new SampleHit { Kind = 8, ValA = 0.22f }
                                  : new SampleHit { Kind = 4, ValA = (1f - (absLat - bw) / Math.Max(0.01f, reach) * 0.68f) * 0.65f, DepthZ = fish.Z };
        }
        return default;
    }

    private SampleHit SampleTurtle(Turtle tr, float px, float py, bool shadowOnly)
    {
        float s = tr.Scale * (0.86f + tr.Z * 0.18f);
        float dx = px - tr.X, dy = py - tr.Y;
        if (dx * dx + dy * dy > (54 * s) * (54 * s)) return default;
        float c = MathF.Cos(-tr.Angle), sn = MathF.Sin(-tr.Angle);
        float lx = (dx * c - dy * sn) / s, ly = (dx * sn + dy * c) / s;

        float sx = lx / 24.5f, sy = ly / 19.5f, r2 = sx * sx + sy * sy;
        if (r2 <= 1f)
        {
            if (shadowOnly) return new SampleHit { Kind = 8, ValA = 0.82f };
            float z = MathF.Sqrt(Math.Max(0.02f, 1f - r2));
            bool scuteRing = MathF.Abs(MathF.Sqrt(r2) - 0.45f) < 0.055f;
            bool scuteSpoke = MathF.Abs(MathF.Sin(MathF.Atan2(ly, lx) * 5)) > 0.93f && r2 > 0.20f;
            float shade = 0.36f + z * 0.58f - sx * 0.18f - sy * 0.18f;
            if (scuteRing || scuteSpoke) shade *= 0.62f;
            if (MathF.Abs(ly) < 2f && MathF.Abs(lx) < 18f) shade = Math.Min(1f, shade + 0.15f);
            return new SampleHit { Kind = 5, ValA = Math.Clamp(shade, 0.18f, 1f), FlagA = r2 > 0.76f, DepthZ = tr.Z };
        }

        float hx = lx - 27.5f, hy = ly - MathF.Sin(tr.HeadYaw) * 6f;
        if ((hx * hx) / (9.5f * 9.5f) + (hy * hy) / (6.2f * 6.2f) <= 1f && lx > 20)
        {
            if (shadowOnly) return new SampleHit { Kind = 8, ValA = 0.65f };
            if (Hypot(hx - 2.5f, MathF.Abs(hy) - 3.6f) < 1.8f) return new SampleHit { Kind = 1, DepthZ = tr.Z };
            return new SampleHit { Kind = 6, ValA = 0.65f - (hx * hx + hy * hy) / 140f, DepthZ = tr.Z };
        }

        float pF = MathF.Sin(tr.Phase) * 0.48f, pB = MathF.Sin(tr.Phase + MathF.PI * 0.7f) * 0.42f;
        ReadOnlySpan<(float ox, float oy, float ang, float rx, float ry)> flippers =
        [
            (12, -16, -1.15f - pF, 13.5f, 5.2f), (12, 16, 1.15f + pF, 13.5f, 5.2f),
            (-14, -14, -2.25f + pB, 11f, 4.5f), (-14, 14, 2.25f - pB, 11f, 4.5f)
        ];
        foreach (var fl in flippers)
        {
            float fx = lx - fl.ox, fy = ly - fl.oy;
            float cf = MathF.Cos(-fl.ang), sf = MathF.Sin(-fl.ang);
            float ux = (fx * cf - fy * sf - fl.rx * 0.45f) / fl.rx;
            float uy = (fx * sf + fy * cf) / fl.ry;
            if (ux * ux + uy * uy <= 1f)
                return shadowOnly ? new SampleHit { Kind = 8, ValA = 0.45f } : new SampleHit { Kind = 6, ValA = 0.48f + (1f - (ux * ux + uy * uy)) * 0.35f, DepthZ = tr.Z };
        }
        if (lx < -22 && lx > -32 && MathF.Abs(ly) < (1f - (-lx - 22) / 10f) * 3.2f)
            return shadowOnly ? new SampleHit { Kind = 8, ValA = 0.35f } : new SampleHit { Kind = 6, ValA = 0.42f, DepthZ = tr.Z };
        return default;
    }

    private (int part, float shade)? SampleFrog(Frog fr, float px, float py)
    {
        float s = 1.32f * ScreenScale();
        float dx = px - fr.X, dy = py - fr.Y;
        if (dx * dx + dy * dy > (36 * s) * (36 * s)) return null;
        float c = MathF.Cos(-fr.Angle), sn = MathF.Sin(-fr.Angle);
        float lx = (dx * c - dy * sn) / s, ly = (dx * sn + dy * c) / s;
        float absY = MathF.Abs(ly);

        float dEye = Hypot(lx - 8.2f, absY - 5.4f);
        if (dEye < 3.1f) return (dEye < 1.55f ? 3 : 2, 1f);

        if (lx >= -13.5f && lx <= 14.5f)
        {
            float u = (14.5f - lx) / 28f;
            float halfW = u < 0.28f
                ? 9.5f * MathF.Pow(MathF.Sin((u / 0.28f) * (MathF.PI / 2f)), 0.62f)
                : 10.6f * MathF.Sin(MathF.Pow(1f - ((u - 0.28f) / 0.72f) * 0.86f, 0.78f) * (MathF.PI / 2f));
            if (absY <= halfW)
            {
                float z = MathF.Sqrt(Math.Max(0.05f, 1f - MathF.Pow(absY / Math.Max(0.1f, halfW), 2)));
                bool isStripe = absY < 1.4f && lx < 7 && lx > -11;
                bool isSpot = Hypot(lx + 1.5f, absY - 4.8f) < 2.4f || Hypot(lx + 7f, absY - 3.6f) < 2.1f;
                float shade = Math.Clamp(0.35f + z * 0.62f - (ly / Math.Max(1f, halfW)) * 0.16f, 0.25f, 1f);
                return ((isSpot || isStripe) ? 1 : 0, shade);
            }
        }

        float fAx = lx - 4.2f, fAy = absY - 10.5f;
        if ((fAx * fAx) / (5.2f * 5.2f) + (fAy * fAy) / (3.2f * 3.2f) <= 1f) return (0, 0.62f);

        float kick = fr.Swimming ? Math.Max(0f, MathF.Sin(fr.SwimPhase)) : 0f;
        float thighX = lx - (-6.8f - kick * 4.5f), thighY = absY - (10.5f + kick * 2f);
        float tAng = -0.55f - kick * 0.75f;
        float tc = MathF.Cos(-tAng), ts = MathF.Sin(-tAng);
        float tux = (thighX * tc - thighY * ts) / 8.2f, tuy = (thighX * ts + thighY * tc) / 4.2f;
        if (tux * tux + tuy * tuy <= 1f) return (1, 0.58f + (1f - (tux * tux + tuy * tuy)) * 0.3f);

        float footX = lx - (-11.5f - kick * 13.5f), footY = absY - (9.2f + kick * 5.8f);
        float fAng = 0.65f - kick * 1.15f;
        float fc = MathF.Cos(-fAng), fs = MathF.Sin(-fAng);
        float fux = (footX * fc - footY * fs) / (7.8f + kick * 3.5f), fuy = (footX * fs + footY * fc) / 3.4f;
        if (fux * fux + fuy * fuy <= 1f) return (0, 0.52f + (1f - (fux * fux + fuy * fuy)) * 0.25f);
        return null;
    }

    private SampleHit SampleMinnow(Minnow m, float px, float py, bool shadowOnly)
    {
        float s = ScreenScale(), bestD2 = float.PositiveInfinity, bestT = 0;
        for (int i = 0; i < m.Nodes.Length - 1; i++)
        {
            var a = m.Nodes[i]; var b = m.Nodes[i + 1];
            float abx = b.X - a.X, aby = b.Y - a.Y;
            float lenSq = Math.Max(0.001f, abx * abx + aby * aby);
            float u = Math.Clamp(((px - a.X) * abx + (py - a.Y) * aby) / lenSq, 0f, 1f);
            float dx = px - (a.X + abx * u), dy = py - (a.Y + aby * u);
            float d2 = dx * dx + dy * dy;
            if (d2 < bestD2) { bestD2 = d2; bestT = (i + u) / (m.Nodes.Length - 1); }
        }
        float w = (bestT < 0.72f ? MathF.Sin(MathF.Pow(bestT / 0.72f, 0.7f) * MathF.PI) * 3.8f + 0.9f : 3f * ((bestT - 0.72f) / 0.28f)) * s;
        if (bestD2 <= w * w) return shadowOnly ? new SampleHit { Kind = 8, ValA = 0.35f } : new SampleHit { Kind = 7, ValA = bestT, DepthZ = m.Z };
        return default;
    }

    private (bool flower, float norm, bool vein)? SampleLotus(float px, float py)
    {
        foreach (var lp in _lotusPads)
        {
            float dx = px - (lp.X + MathF.Sin(_time * 0.55f + lp.Phase) * 2.5f);
            float dy = py - (lp.Y + MathF.Cos(_time * 0.45f + lp.Phase) * 2.0f);
            float d = Hypot(dx, dy);
            if (d <= lp.R)
            {
                float ang = MathF.Atan2(dy, dx);
                if (MathF.Abs(NormalizeAngle(ang - lp.NotchAngle)) < 0.28f) return null;
                float normR = d / lp.R;
                if (lp.Flower && d < lp.R * 0.24f)
                {
                    float petal = MathF.Sin(ang * 6) * 0.5f + 0.5f;
                    if (d < lp.R * (0.16f + petal * 0.08f)) return (true, d / (lp.R * 0.24f), false);
                }
                return (false, normR, MathF.Abs(MathF.Sin(ang * 7)) > 0.94f && normR > 0.18f);
            }
        }
        return null;
    }

    private bool SampleLotusShadow(float px, float py)
    {
        foreach (var lp in _lotusPads)
            if (Hypot(px - (lp.X + 20), py - (lp.Y + 18)) <= lp.R) return true;
        return false;
    }

    private (float tip, string ch)? SamplePlant(float px, float py)
    {
        foreach (var pl in _plants)
        {
            float dx = px - pl.X, dy = py - pl.Y;
            float dist = Hypot(dx, dy);
            if (dist > pl.R + 10) continue;
            if (dist < 5f) return (0.15f, "%");
            float sway = MathF.Sin(_time * 1.15f + pl.Phase) * 0.24f;
            for (int f = 0; f < pl.Fronds.Length; f++)
            {
                var fr = pl.Fronds[f];
                float ang = fr.Ang + sway * (0.6f + 0.4f * MathF.Sin(f + _time * 0.8f));
                float c = MathF.Cos(-ang), sn = MathF.Sin(-ang);
                float lx = dx * c - dy * sn, ly = dx * sn + dy * c;
                if (lx >= 0 && lx <= fr.Len)
                {
                    float u = lx / fr.Len;
                    float curveY = MathF.Sin(u * MathF.PI) * fr.Bend * 13 + MathF.Sin(u * 4f + _time * 1.6f + f) * 2f * u;
                    float leafW = MathF.Sin(MathF.Pow(u, 0.72f) * MathF.PI) * 4.2f + 1f;
                    if (MathF.Abs(ly - curveY) <= leafW)
                    {
                        string ch = u > 0.78f ? (u > 0.9f ? "·" : "~") : (MathF.Abs(ly - curveY) < 1.3f ? "=" : (u < 0.35f ? "#" : "+"));
                        return (u, ch);
                    }
                }
            }
        }
        return null;
    }

    private static (int part, float shade)? SampleLeafLocal(Leaf lf, float lx, float ly, string actSeason)
    {
        if (lf.IsSnow)
        {
            float r = Hypot(lx, ly);
            if (r > 1f) return null;
            if (r < 0.25f || MathF.Abs(MathF.Sin(MathF.Atan2(ly, lx) * 3)) < 0.17f) return (r < 0.35f ? 1 : 0, 1f - r * 0.35f);
            return null;
        }
        if (actSeason == "spring")
        {
            if (lx < -0.95f || lx > 1f) return null;
            float u = (lx + 0.95f) / 1.95f;
            float halfW = MathF.Sin(MathF.Pow(u, 0.72f) * MathF.PI) * 0.72f;
            float absY = MathF.Abs(ly);
            if (absY > halfW || (u > 0.76f && absY < (u - 0.76f) * 0.95f)) return null;
            return (absY < 0.08f && u > 0.12f && u < 0.74f ? 1 : 0, Math.Min(1f, 0.55f + (1f - absY / Math.Max(0.01f, halfW)) * 0.35f + (1f - u) * 0.15f));
        }
        if (actSeason == "autumn" && lf.Maple)
        {
            if (lx < -0.08f && lx > -0.78f && MathF.Abs(ly) < 0.085f) return (2, 0.65f);
            float r = Hypot(lx, ly);
            if (r > 1.06f) return null;
            float absA = MathF.Abs(MathF.Atan2(ly, lx));
            float l1 = MathF.Exp(-MathF.Pow(absA / 0.30f, 2)) * 1.02f;
            float l2 = MathF.Exp(-MathF.Pow((absA - 0.92f) / 0.28f, 2)) * 0.88f;
            float l3 = MathF.Exp(-MathF.Pow((absA - 1.82f) / 0.26f, 2)) * 0.58f;
            float maxR = Math.Max(absA < 2.15f ? 0.34f : 0.12f, Math.Max(l1, Math.Max(l2, l3)));
            if (r <= maxR)
            {
                bool onVein = (absA < 0.09f && r < 0.86f) || (MathF.Abs(absA - 0.92f) < 0.09f && r < 0.74f) || (MathF.Abs(absA - 1.82f) < 0.10f && r < 0.48f);
                return (onVein ? 1 : 0, Math.Clamp((1f - MathF.Pow(r / Math.Max(0.01f, maxR), 2.2f) * 0.42f) * 0.95f - ly * 0.16f, 0.28f, 1f));
            }
            return null;
        }
        if (lx < -0.92f && lx > -1.48f && MathF.Abs(ly) < 0.08f) return (2, 0.62f);
        if (lx < -0.95f || lx > 1f) return null;
        float u2 = (lx + 0.95f) / 1.95f;
        float halfW2 = MathF.Sin(MathF.Pow(u2, 0.78f) * MathF.PI) * 0.56f;
        float absY2 = MathF.Abs(ly);
        if (absY2 > halfW2) return null;
        return (absY2 < 0.075f && u2 > 0.05f && u2 < 0.92f ? 1 : 0, Math.Clamp(0.50f + (1f - absY2 / Math.Max(0.01f, halfW2)) * 0.42f - ly * 0.18f, 0.28f, 1f));
    }

    private bool IsClockCell(int c, int r, string timeStr)
    {
        if (!Config.ShowClock || Config.IsPreview) return false;
        int sx = _cols > 150 ? 2 : 1, sy = _rows > 55 ? 2 : 1;
        int charW = 6 * sx, totalW = timeStr.Length * charW - sx, totalH = 7 * sy;
        int lc = c - (_cols - totalW) / 2, lr = r - (_rows - totalH) / 2;
        if (lc < 0 || lc >= totalW || lr < 0 || lr >= totalH) return false;
        int inC = (lc % charW) / sx;
        if (inC >= 5) return false;
        return Digits.TryGetValue(timeStr[lc / charW], out var g) && g[lr / sy][inC] == '1';
    }

    private static byte ClampByte(float v) => (byte)Math.Clamp((int)v, 0, 255);

    private void Put(GdiSurface surf, string ch, int c, int r, Rgb rgb, Rgb bg, float mult = 1f, float alpha = 1f)
    {
        float a = Math.Clamp(alpha, 0f, 1f);
        byte rr = ClampByte(bg.R * (1f - a) + rgb.R * mult * a);
        byte gg = ClampByte(bg.G * (1f - a) + rgb.G * mult * a);
        byte bb = ClampByte(bg.B * (1f - a) + rgb.B * mult * a);
        surf.DrawChar(ch, (int)(c * _cellW), (int)(r * _cellH), rr, gg, bb);
    }

    private void PutDepth(GdiSurface surf, string ch, int c, int r, Rgb rgb, float z, PondPalette pal, float mult = 1f, float alpha = 1f)
    {
        float cz = Math.Clamp(z, 0f, 1f);
        float glow = z > 1f ? 1f + (z - 1f) * 0.72f : 1f;
        float cl = 0.42f + cz * 0.58f;
        var mixed = new Rgb(
            pal.WaterDeep.R * (1f - cl) + rgb.R * mult * glow * cl,
            pal.WaterDeep.G * (1f - cl) + rgb.G * mult * glow * cl,
            pal.WaterDeep.B * (1f - cl) + rgb.B * mult * glow * cl);
        Put(surf, ch, c, r, mixed, pal.Bg, 1f, alpha);
    }

    public void Render(GdiSurface surf, IntPtr targetDc, int width, int height)
    {
        Resize(width, height);
        surf.EnsureSize(targetDc, width, height, _fontPx);

        var pal = CurrentPalette();
        string actSeason = ActiveSeason();
        string timeStr = DateTime.Now.ToString("HH:mm");

        surf.Clear(ClampByte(pal.Bg.R), ClampByte(pal.Bg.G), ClampByte(pal.Bg.B));

        _actors.Clear();
        for (int i = 0; i < _fishes.Count; i++)
        {
            var fish = _fishes[i];
            float minX = float.PositiveInfinity, maxX = float.NegativeInfinity, minY = float.PositiveInfinity, maxY = float.NegativeInfinity;
            for (int n = 0; n < fish.N; n++)
            {
                var rn = fish.RenderNodes[n];
                if (rn.X < minX) minX = rn.X; if (rn.X > maxX) maxX = rn.X;
                if (rn.Y < minY) minY = rn.Y; if (rn.Y > maxY) maxY = rn.Y;
            }
            float pad = 84 * fish.Scale, shX = 6 + Math.Min(1.25f, fish.Z) * 28, shY = 5 + Math.Min(1.25f, fish.Z) * 24;
            _actors.Add(new ActorBox
            {
                Kind = 0, Index = i, Z = fish.Z, ShX = shX, ShY = shY,
                MinC = Math.Max(0, (int)MathF.Floor((minX - pad) / _cellW)), MaxC = Math.Min(_cols - 1, (int)MathF.Ceiling((maxX + pad + shX) / _cellW)),
                MinR = Math.Max(0, (int)MathF.Floor((minY - pad) / _cellH)), MaxR = Math.Min(_rows - 1, (int)MathF.Ceiling((maxY + pad + shY) / _cellH))
            });
        }
        if (_turtle != null)
        {
            float pad = 54 * _turtle.Scale, shX = 6 + _turtle.Z * 28, shY = 5 + _turtle.Z * 24;
            _actors.Add(new ActorBox
            {
                Kind = 1, Index = 0, Z = _turtle.Z, ShX = shX, ShY = shY,
                MinC = Math.Max(0, (int)MathF.Floor((_turtle.X - pad) / _cellW)), MaxC = Math.Min(_cols - 1, (int)MathF.Ceiling((_turtle.X + pad + shX) / _cellW)),
                MinR = Math.Max(0, (int)MathF.Floor((_turtle.Y - pad) / _cellH)), MaxR = Math.Min(_rows - 1, (int)MathF.Ceiling((_turtle.Y + pad + shY) / _cellH))
            });
        }
        for (int i = 0; i < _minnows.Count; i++)
        {
            var m = _minnows[i];
            float shX = 6 + m.Z * 25, shY = 5 + m.Z * 22;
            _actors.Add(new ActorBox
            {
                Kind = 2, Index = i, Z = m.Z, ShX = shX, ShY = shY,
                MinC = Math.Max(0, (int)MathF.Floor((m.X - 36) / _cellW)), MaxC = Math.Min(_cols - 1, (int)MathF.Ceiling((m.X + 36 + shX) / _cellW)),
                MinR = Math.Max(0, (int)MathF.Floor((m.Y - 36) / _cellH)), MaxR = Math.Min(_rows - 1, (int)MathF.Ceiling((m.Y + 36 + shY) / _cellH))
            });
        }
        _actors.Sort((a, b) => b.Z.CompareTo(a.Z));

        float moonX = _width * 0.78f, moonY = _height * 0.26f;

        for (int r = 0; r < _rows; r++)
        {
            float py = (r + 0.5f) * _cellH;
            int rowOff = r * _cols;
            for (int c = 0; c < _cols; c++)
            {
                float px = (c + 0.5f) * _cellW;

                var lp = SampleLotus(px, py);
                if (lp.HasValue)
                {
                    var lv = lp.Value;
                    if (lv.flower) Put(surf, lv.norm < 0.4f ? "@" : "*", c, r, pal.Flower, pal.Bg, 1.05f - lv.norm * 0.2f);
                    else
                    {
                        bool edge = lv.norm > 0.88f;
                        Put(surf, lv.vein ? ":" : (edge ? "+" : (lv.norm < 0.35f ? "%" : "#")), c, r, lv.vein ? pal.LotusVein : pal.Lotus, pal.Bg, lv.vein ? 1f : (edge ? 0.72f : 0.85f + (1f - lv.norm) * 0.25f));
                    }
                    continue;
                }

                string? rippleCh = null; float rippleAlpha = 0;
                for (int i = 0; i < _ripples.Count; i++)
                {
                    var rp = _ripples[i];
                    float d = Hypot(px - rp.X, py - rp.Y);
                    if (MathF.Abs(d - rp.R) < 3.2f)
                    {
                        float fade = (1f - rp.R / rp.MaxR) * rp.Alpha;
                        if (fade > 0.06f)
                        {
                            float ang = MathF.Atan2(py - rp.Y, px - rp.X);
                            rippleCh = MathF.Abs(MathF.Cos(ang)) > 0.72f ? (MathF.Cos(ang) > 0 ? ")" : "(") : (fade > 0.28f ? "~" : "·");
                            rippleAlpha = Math.Min(0.95f, fade * 1.48f);
                            break;
                        }
                    }
                }

                SampleHit hit = default, shHit = default;
                for (int a = 0; a < _actors.Count; a++)
                {
                    var ac = _actors[a];
                    if (c >= ac.MinC && c <= ac.MaxC && r >= ac.MinR && r <= ac.MaxR)
                    {
                        if (hit.Kind == 0)
                        {
                            hit = ac.Kind == 0 ? SampleKoi(_fishes[ac.Index], px, py, false)
                                : (ac.Kind == 1 && _turtle != null ? SampleTurtle(_turtle, px, py, false) : SampleMinnow(_minnows[ac.Index], px, py, false));
                            if (hit.Kind != 0) break;
                        }
                        if (shHit.Kind == 0)
                        {
                            shHit = ac.Kind == 0 ? SampleKoi(_fishes[ac.Index], px - ac.ShX, py - ac.ShY, true)
                                  : (ac.Kind == 1 && _turtle != null ? SampleTurtle(_turtle, px - ac.ShX, py - ac.ShY, true) : SampleMinnow(_minnows[ac.Index], px - ac.ShX, py - ac.ShY, true));
                        }
                    }
                }

                if (hit.Kind != 0)
                {
                    switch (hit.Kind)
                    {
                        case 1:
                            if (hit.FlagA) Put(surf, "·", c, r, new(255, 255, 255), pal.Bg);
                            else if (hit.FlagB) PutDepth(surf, "o", c, r, pal.Fin, hit.DepthZ, pal, 0.7f);
                            else Put(surf, "@", c, r, pal.Eye, pal.Bg);
                            break;
                        case 2:
                            string bCh;
                            if (hit.ValA > 0.84f) bCh = "·";
                            else if (hit.ValA < 0.22f) bCh = "=";
                            else
                            {
                                float ang = ((hit.ValB % MathF.PI) + MathF.PI) % MathF.PI;
                                bCh = (ang < MathF.PI / 8f || ang >= 7f * MathF.PI / 8f) ? "-" : (ang < 3f * MathF.PI / 8f ? "\\" : (ang < 5f * MathF.PI / 8f ? "|" : "/"));
                            }
                            PutDepth(surf, bCh, c, r, hit.Variety == KoiVariety.Ogon ? pal.Gold : pal.Barbel, hit.DepthZ, pal, 1.02f, Math.Max(0.42f, 0.96f - hit.ValA * 0.48f));
                            break;
                        case 3:
                            var ramp = hit.FlagB ? ScaleRamp : ShadeRamp;
                            int idx = Math.Clamp((int)(hit.ValA * (ramp.Length - 1)), 1, ramp.Length - 1);
                            string ch = hit.FlagA ? (idx > 10 ? "W" : "+") : (hit.FlagC ? "(" : ramp[idx]);
                            Rgb baseRgb = hit.IntA switch { 1 => pal.Red, 2 => pal.Black, 3 => pal.Gold, _ => pal.White };
                            float boost = hit.IntA switch { 1 => 0.50f + hit.ValA * 0.62f, 2 => 0.70f + hit.ValA * 1.50f, 3 => 0.50f + hit.ValA * 0.68f, _ => 0.45f + hit.ValA * 0.65f };
                            if (hit.IntA == 2) ch = hit.ValA > 0.80f ? "#" : (hit.FlagB ? ":" : "%");
                            PutDepth(surf, ch, c, r, baseRgb, hit.DepthZ, pal, boost);
                            break;
                        case 4:
                            int fIdx = Math.Clamp((int)(hit.ValA * FinRamp.Length), 1, FinRamp.Length - 1);
                            string fCh = hit.FlagB ? "=" : FinRamp[fIdx];
                            if (fCh != " ") PutDepth(surf, fCh, c, r, hit.FlagA ? pal.FinBlack : pal.Fin, hit.DepthZ, pal, hit.FlagB ? 1.05f : 0.9f, Math.Min(0.95f, 0.32f + hit.ValA * 0.65f));
                            break;
                        case 5:
                            int tIdx = Math.Clamp((int)(hit.ValA * (ShadeRamp.Length - 1)), 1, ShadeRamp.Length - 1);
                            PutDepth(surf, hit.FlagA ? "=" : ShadeRamp[tIdx], c, r, hit.FlagA ? pal.TurtleRim : pal.TurtleShell, hit.DepthZ, pal, 0.65f + hit.ValA * 0.55f);
                            break;
                        case 6:
                            PutDepth(surf, hit.ValA > 0.6f ? "+" : ":", c, r, pal.TurtleSkin, hit.DepthZ, pal, 0.6f + hit.ValA * 0.5f);
                            break;
                        case 7:
                            PutDepth(surf, hit.ValA < 0.25f ? "o" : (hit.ValA < 0.72f ? "=" : "~"), c, r, pal.Minnow, hit.DepthZ, pal, 1f, hit.ValA > 0.72f ? 0.65f : 0.92f);
                            break;
                    }
                    continue;
                }

                if (shHit.Kind == 8 || SampleLotusShadow(px, py))
                {
                    Put(surf, shHit.Kind == 8 && shHit.ValA > 0.5f ? ":" : "·", c, r, pal.Shadow, pal.Bg, 1f, pal.ShadowAlpha);
                    continue;
                }

                if (rippleCh != null)
                {
                    Put(surf, rippleCh, c, r, pal.Ripple, pal.Bg, 1f, rippleAlpha);
                    continue;
                }

                var plHit = SamplePlant(px, py);
                if (plHit.HasValue)
                {
                    PutDepth(surf, plHit.Value.ch, c, r, plHit.Value.tip > 0.55f ? pal.PlantTip : pal.Plant, 0.16f + plHit.Value.tip * 0.24f, pal, 0.82f + plHit.Value.tip * 0.35f);
                    continue;
                }

                if (IsClockCell(c, r, timeStr))
                {
                    Put(surf, ":", c, r, pal.Clock, pal.Bg, 0.75f + 0.25f * MathF.Sin(c * 0.2f + _time * 1.1f), 0.62f);
                    continue;
                }

                float wave = MathF.Sin(c * 0.14f + _time * 0.75f + MathF.Sin(r * 0.23f + _time * 0.4f)) * MathF.Cos(r * 0.20f - _time * 0.5f + c * 0.05f);
                if (pal.Tod == "night")
                {
                    float md = Hypot((px - moonX) * 0.9f, (py - moonY) * 1.15f);
                    if (md < 52 + wave * 12)
                    {
                        float ma = (1f - md / 64f) * (0.28f + 0.25f * Math.Max(0f, wave));
                        if (ma > 0.08f) { Put(surf, md < 26 ? "~" : "·", c, r, pal.Moon, pal.Bg, 1f, ma); continue; }
                    }
                }

                float stVal = _stoneMap[rowOff + c];
                if (stVal > 0.15f)
                {
                    float cb = wave > 0.55f ? (wave - 0.55f) * 0.75f : 0f;
                    int sIdx = Math.Clamp((int)((stVal + cb * 0.4f) * (StoneRamp.Length - 1)), 1, StoneRamp.Length - 1);
                    Put(surf, StoneRamp[sIdx], c, r, pal.Stone, pal.Bg, 0.55f + stVal * 0.65f + cb * 0.6f);
                    continue;
                }

                if (wave > 0.78f)
                {
                    Put(surf, wave > 0.91f ? "~" : "·", c, r, pal.Water, pal.Bg, 1f, pal.WaterAlpha);
                    continue;
                }

                if (pal.Tod != "night")
                {
                    float cloud = Fbm(px * 0.0042f - _time * 0.028f + wave * 0.08f, py * 0.0052f - _time * 0.012f);
                    if (cloud > 0.64f)
                        Put(surf, cloud > 0.74f ? "~" : "·", c, r, pal.Tod == "sunset" ? pal.Ripple : pal.White, pal.Bg, 1f, Math.Min(0.24f, (cloud - 0.64f) * 0.95f));
                }
            }
        }

        if (pal.Tod == "night")
        {
            foreach (var st in _stars)
            {
                if (SampleLotus(st.X, st.Y).HasValue) continue;
                float tw = MathF.Sin(_time * st.Spd + st.Phase);
                if (tw > 0.20f)
                {
                    int sc = (int)((st.X + MathF.Sin(_time * 1.4f + st.Phase) * 2.2f) / _cellW), sr = (int)(st.Y / _cellH);
                    if (sc >= 0 && sc < _cols && sr >= 0 && sr < _rows)
                        Put(surf, tw > 0.82f ? "*" : (tw > 0.52f ? "+" : "·"), sc, sr, pal.Moon, pal.Bg, 1f, (tw - 0.15f) * 0.68f);
                }
            }
        }

        foreach (var b in _bubbles)
        {
            if (SampleLotus(b.X, b.Y).HasValue) continue;
            int bc = (int)(b.X / _cellW), br = (int)(b.Y / _cellH);
            if (bc >= 0 && bc < _cols && br >= 0 && br < _rows)
                PutDepth(surf, b.Z < 0.35f ? "·" : (b.Z < 0.65f ? "°" : (b.Z < 0.88f ? "o" : "O")), bc, br, pal.Bubble, b.Z, pal, 1.08f, 0.34f + b.Z * 0.64f);
        }

        if (_frog != null)
        {
            float fPad = 40 * ScreenScale();
            int fMinC = Math.Max(0, (int)MathF.Floor((_frog.X - fPad) / _cellW)), fMaxC = Math.Min(_cols - 1, (int)MathF.Ceiling((_frog.X + fPad) / _cellW));
            int fMinR = Math.Max(0, (int)MathF.Floor((_frog.Y - fPad) / _cellH)), fMaxR = Math.Min(_rows - 1, (int)MathF.Ceiling((_frog.Y + fPad) / _cellH));
            if (fMinR <= fMaxR && fMinC <= fMaxC)
            {
                float shX = _frog.Swimming ? 14 : 5, shY = _frog.Swimming ? 12 : 4;
                for (int r = fMinR; r <= fMaxR; r++)
                {
                    float py = (r + 0.5f) * _cellH;
                    for (int c = fMinC; c <= fMaxC; c++)
                    {
                        float px = (c + 0.5f) * _cellW;
                        var fh = SampleFrog(_frog, px, py);
                        if (fh.HasValue)
                        {
                            var fv = fh.Value;
                            if (fv.part == 3) Put(surf, "@", c, r, pal.Eye, pal.Bg);
                            else if (fv.part == 2) Put(surf, "o", c, r, pal.Gold, pal.Bg, 1.05f);
                            else if (fv.part == 1) Put(surf, fv.shade > 0.65f ? "#" : "%", c, r, new(pal.Frog.R * 0.72f, pal.Frog.G * 0.88f, pal.Frog.B * 0.72f), pal.Bg, 0.55f + fv.shade * 0.45f);
                            else
                            {
                                int idx = Math.Clamp((int)(fv.shade * (ShadeRamp.Length - 1)), 2, ShadeRamp.Length - 1);
                                Put(surf, ShadeRamp[idx], c, r, pal.Frog, pal.Bg, 0.72f + fv.shade * 0.48f);
                            }
                        }
                        else if (SampleFrog(_frog, px - shX, py - shY).HasValue)
                            Put(surf, ":", c, r, pal.Shadow, pal.Bg, 1f, pal.ShadowAlpha * 0.75f);
                    }
                }
            }
        }

        var leafPal = actSeason == "spring" ? pal.LeafSpring : (actSeason == "summer" ? pal.LeafSummer : pal.LeafAutumn);
        foreach (var lf in _leaves)
        {
            float h = Math.Max(0f, lf.Z - 1f);
            float fadeOut = (lf.Floating && lf.Age > lf.MaxAge - 3) ? Math.Max(0f, (lf.MaxAge - lf.Age) / 3f) : 1f;
            float drawR = lf.Size * (1f + h * 0.52f);
            float tiltY = lf.Floating ? 1f : (0.58f + 0.42f * MathF.Abs(MathF.Cos(lf.Tumble)));
            float cCos = MathF.Cos(-lf.Rot), cSin = MathF.Sin(-lf.Rot);
            var colRgb = leafPal[lf.ColorIdx % leafPal.Length];
            float bright = (0.94f + h * 0.22f) * (0.85f + tiltY * 0.18f);
            float pad = drawR * 1.55f;

            if (!lf.IsSnow)
            {
                float shX = 14 + h * 38, shY = 12 + h * 32;
                int sMinC = Math.Max(0, (int)MathF.Floor((lf.X + shX - pad) / _cellW)), sMaxC = Math.Min(_cols - 1, (int)MathF.Ceiling((lf.X + shX + pad) / _cellW));
                int sMinR = Math.Max(0, (int)MathF.Floor((lf.Y + shY - pad) / _cellH)), sMaxR = Math.Min(_rows - 1, (int)MathF.Ceiling((lf.Y + shY + pad) / _cellH));
                if (sMinR <= sMaxR && sMinC <= sMaxC)
                {
                    float shA = fadeOut * Math.Max(0.28f, 0.72f - h * 0.25f);
                    for (int r = sMinR; r <= sMaxR; r++)
                    {
                        float py = (r + 0.5f) * _cellH - (lf.Y + shY);
                        for (int c = sMinC; c <= sMaxC; c++)
                        {
                            float px = (c + 0.5f) * _cellW - (lf.X + shX);
                            if (SampleLeafLocal(lf, (px * cCos - py * cSin) / drawR, (px * cSin + py * cCos) / (drawR * tiltY), actSeason).HasValue)
                                Put(surf, h < 0.28f ? ":" : "·", c, r, pal.Shadow, pal.Bg, 1f, shA);
                        }
                    }
                }
            }

            int minC = Math.Max(0, (int)MathF.Floor((lf.X - pad) / _cellW)), maxC = Math.Min(_cols - 1, (int)MathF.Ceiling((lf.X + pad) / _cellW));
            int minR = Math.Max(0, (int)MathF.Floor((lf.Y - pad) / _cellH)), maxR = Math.Min(_rows - 1, (int)MathF.Ceiling((lf.Y + pad) / _cellH));
            if (minR <= maxR && minC <= maxC)
            {
                for (int r = minR; r <= maxR; r++)
                {
                    float py = (r + 0.5f) * _cellH - lf.Y;
                    for (int c = minC; c <= maxC; c++)
                    {
                        float px = (c + 0.5f) * _cellW - lf.X;
                        var lh = SampleLeafLocal(lf, (px * cCos - py * cSin) / drawR, (px * cSin + py * cCos) / (drawR * tiltY), actSeason);
                        if (!lh.HasValue) continue;
                        var lv = lh.Value;
                        if (lf.IsSnow) Put(surf, lv.part == 1 ? "*" : "+", c, r, pal.Snow, pal.Bg, 1.05f, fadeOut * (0.68f + h * 0.28f));
                        else if (lv.part == 2)
                        {
                            float ang = ((lf.Rot % MathF.PI) + MathF.PI) % MathF.PI;
                            string sCh = (ang < MathF.PI / 8f || ang >= 7f * MathF.PI / 8f) ? "-" : (ang < 3f * MathF.PI / 8f ? "\\" : (ang < 5f * MathF.PI / 8f ? "|" : "/"));
                            Put(surf, sCh, c, r, colRgb, pal.Bg, bright * 0.62f, fadeOut * 0.92f);
                        }
                        else if (lv.part == 1) Put(surf, "=", c, r, colRgb, pal.Bg, bright * 1.28f, fadeOut * 0.98f);
                        else
                        {
                            int idx = Math.Clamp((int)(lv.shade * (LeafBladeRamp.Length - 1)), 2, LeafBladeRamp.Length - 1);
                            Put(surf, LeafBladeRamp[idx], c, r, colRgb, pal.Bg, bright * (0.68f + lv.shade * 0.42f), fadeOut * 0.96f);
                        }
                    }
                }
            }
        }

        foreach (var sp in _splashes)
        {
            int sc = (int)(sp.X / _cellW), sr = (int)(sp.Y / _cellH);
            if (sc >= 0 && sc < _cols && sr >= 0 && sr < _rows)
            {
                float h = Math.Max(0f, sp.Z - 1f);
                Put(surf, h > 0.32f ? (sp.Big ? "*" : "°") : (h > 0.14f ? "o" : "'"), sc, sr, pal.Splash, pal.Bg, 1.08f, Math.Min(1f, 0.58f + h * 1.4f));
            }
        }

        if (_dragonfly != null)
        {
            var df = _dragonfly; float h = Math.Max(0f, df.Z - 1f);
            int shC = (int)((df.X + 14 + h * 36) / _cellW), shR = (int)((df.Y + 12 + h * 30) / _cellH);
            if (shC >= 1 && shC < _cols - 1 && shR >= 1 && shR < _rows - 1) Put(surf, "+", shC, shR, pal.Shadow, pal.Bg, 1f, pal.ShadowAlpha);
            int dc = (int)(df.X / _cellW), dr = (int)(df.Y / _cellH);
            if (dc >= 3 && dc < _cols - 3 && dr >= 3 && dr < _rows - 3)
            {
                float tx = MathF.Cos(df.Angle), ty = MathF.Sin(df.Angle), nx = -ty, ny = tx;
                Put(surf, "o", (int)MathF.Round(dc + tx), (int)MathF.Round(dr + ty), pal.Dragonfly, pal.Bg, 1.15f);
                Put(surf, "#", dc, dr, pal.Dragonfly, pal.Bg, 1.15f);
                Put(surf, "=", (int)MathF.Round(dc - tx), (int)MathF.Round(dr - ty), pal.Dragonfly, pal.Bg);
                Put(surf, ":", (int)MathF.Round(dc - tx * 2), (int)MathF.Round(dr - ty * 2), pal.Dragonfly, pal.Bg, 0.85f);
                float fl = MathF.Sin(df.WingPhase) > 0 ? 1f : 0.65f, wa = 0.55f + fl * 0.35f, w1 = MathF.Round(1.6f + fl * 0.8f);
                Put(surf, "~", (int)MathF.Round(dc + nx * w1), (int)MathF.Round(dr + ny * w1), pal.Wing, pal.Bg, 1f, wa);
                Put(surf, "~", (int)MathF.Round(dc - nx * w1), (int)MathF.Round(dr - ny * w1), pal.Wing, pal.Bg, 1f, wa);
                Put(surf, "-", (int)MathF.Round(dc + nx), (int)MathF.Round(dr + ny), pal.Wing, pal.Bg, 1f, wa);
                Put(surf, "-", (int)MathF.Round(dc - nx), (int)MathF.Round(dr - ny), pal.Wing, pal.Bg, 1f, wa);
            }
        }

        if (pal.Tod == "night" || pal.Tod == "sunset")
        {
            float mult = pal.Tod == "night" ? 1f : 0.45f;
            foreach (var ff in _fireflies)
            {
                float glow = Math.Max(0f, MathF.Sin(ff.Phase));
                if (glow > 0.15f)
                {
                    int fc = (int)(ff.X / _cellW), fr = (int)(ff.Y / _cellH);
                    if (fc >= 0 && fc < _cols && fr >= 0 && fr < _rows)
                        Put(surf, glow > 0.72f ? "*" : "·", fc, fr, pal.Firefly, pal.Bg, 1.15f, glow * mult);
                }
            }
        }

        surf.BlitTo(targetDc);
    }
}
