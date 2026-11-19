import AppKit
import CoreGraphics
import CoreText
import Foundation

enum AgentModel: String, Codable {
    case gemini, claude
}

enum AgentState: String, Codable {
    case thinking, editing, waiting, done, error
}

struct AgentDescriptor: Equatable {
    var id: String
    var model: AgentModel
    var state: AgentState
    var isSubagent: Bool = false
    var parentId: String? = nil
    var formationSlot: Int = 0
}

struct SaverConfig {
    var timeMode: String = "auto"   // auto | day | sunset | night
    var season: String = "auto"     // auto (weekday) | spring | summer | autumn | winter
    var koiCount: Int = 5
    var showClock: Bool = true
    var rainOn: Bool = false
    var monoMode: Bool = false
    var minimalistMode: Bool = false
    var musicReactive: Bool = true
    var treeBranch: String = "bottomRight" // none | topRight | topLeft | bottomRight | bottomLeft
    var pondAccent: String = "bridge"      // none | bridge | stones (placed in opposite corner from treeBranch)
    var cloudDensity: CGFloat = 0.90       // 0.30 (clear) .. 1.45 (overcast), driven by Live Weather
    var isPreview: Bool = false
}

struct RGB {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat
    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) {
        self.r = r / 255.0
        self.g = g / 255.0
        self.b = b / 255.0
    }
}

private struct Palette {
    var tod: String
    var bg: RGB
    var waterDeep: RGB
    var stone: RGB
    var clock: RGB
    var water: RGB
    var waterAlpha: CGFloat
    var ripple: RGB
    var shadow: RGB
    var shadowAlpha: CGFloat
    var lotus: RGB
    var lotusVein: RGB
    var flower: RGB
    var white: RGB
    var red: RGB
    var black: RGB
    var gold: RGB
    var fin: RGB
    var finBlack: RGB
    var barbel: RGB
    var turtleShell: RGB
    var turtleRim: RGB
    var turtleSkin: RGB
    var minnow: RGB
    var plant: RGB
    var plantTip: RGB
    var bubble: RGB
    var splash: RGB
    var dragonfly: RGB
    var wing: RGB
    var frog: RGB
    var firefly: RGB
    var moon: RGB
    var leafAutumn: [RGB]
    var leafSpring: [RGB]
    var leafSummer: [RGB]
    var snow: RGB
    var eye: RGB
}

private struct Vec2 {
    var x: CGFloat
    var y: CGFloat
}

private struct RenderNode {
    var x: CGFloat
    var y: CGFloat
    var nx: CGFloat
    var ny: CGFloat
}

private struct SpineSeg {
    var ax: CGFloat
    var ay: CGFloat
    var abx: CGFloat
    var aby: CGFloat
    var invLenSq: CGFloat
    var anx: CGFloat
    var any: CGFloat
    var dnx: CGFloat
    var dny: CGFloat
}

private struct BarbelNode {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
}

private enum KoiVariety: CaseIterable {
    case showa, utsuri, sanke, ogon, kumonryu
    case gemini, claude, trashEater

    static let pondVarieties: [KoiVariety] = [.showa, .utsuri, .sanke, .ogon, .kumonryu]
}

private struct TrashCrumb {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var ch: Character
    var life: CGFloat
}

private struct Koi {
    var variety: KoiVariety
    var seed: CGFloat
    var baseScale: CGFloat
    var scale: CGFloat
    var z: CGFloat
    var targetZ: CGFloat
    var zTimer: CGFloat
    var segLen: CGFloat
    var N: Int
    var nodes: [Vec2]
    var renderNodes: [RenderNode]
    var segs: [SpineSeg]
    var barbels: [[BarbelNode]]
    var barbelSegLen: CGFloat
    var angle: CGFloat
    var turnVel: CGFloat
    var targetX: CGFloat
    var targetY: CGFloat
    var phase: CGFloat
    var baseSpeed: CGFloat
    var speed: CGFloat
    var turnRate: CGFloat
    var tailTimer: CGFloat
    var wanderTimer: CGFloat
    var breaching: Bool
    var breachProgress: CGFloat
    var breachCooldown: CGFloat
    var breachSplashTick: CGFloat
    var breachDir: CGFloat = 1.0
    var breachLaunched: Bool = false
    var hasEntered: Bool
    var leaving: Bool
    var agentId: String? = nil
    var parentAgentId: String? = nil
    var formationSlot: Int = 0
    var agentState: AgentState? = nil
    var isSubagent: Bool = false
    var isTrashEater: Bool = false
    var errorFlash: CGFloat = 0
    var stateRippleTimer: CGFloat = 0
    var trashTarget: CGPoint? = nil
    var trashEating: Bool = false
}

private struct Turtle {
    var x: CGFloat
    var y: CGFloat
    var angle: CGFloat
    var targetX: CGFloat
    var targetY: CGFloat
    var z: CGFloat
    var targetZ: CGFloat
    var zTimer: CGFloat
    var scale: CGFloat
    var speed: CGFloat
    var turnRate: CGFloat
    var phase: CGFloat
    var headYaw: CGFloat
    var wanderTimer: CGFloat
}

private struct Minnow {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var angle: CGFloat
    var z: CGFloat
    var phase: CGFloat
    var nodes: [Vec2]
    var boost: CGFloat
}

private struct Dragonfly {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat
    var angle: CGFloat
    var targetX: CGFloat
    var targetY: CGFloat
    var perched: Bool
    var perchPadIdx: Int
    var stateTimer: CGFloat
    var wingPhase: CGFloat
}

private enum FrogState {
    case perched
    case leaping
    case swimming
    case climbing
}

private struct Frog {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat
    var angle: CGFloat
    var padIdx: Int
    var state: FrogState
    var targetPadIdx: Int
    var swimPhase: CGFloat
    var restTimer: CGFloat
    var jumpStart: CGPoint = .zero
    var jumpEnd: CGPoint = .zero
    var jumpProgress: CGFloat = 0
    var speed: CGFloat = 0
    var lookAngle: CGFloat = 0.55
    var lookTimer: CGFloat = 2.0
}

private struct LotusPad {
    var x: CGFloat
    var y: CGFloat
    var r: CGFloat
    var notchAngle: CGFloat
    var flower: Bool
    var phase: CGFloat
}

private struct PlantFrond {
    var ang: CGFloat
    var len: CGFloat
    var bend: CGFloat
}

private struct PondPlant {
    var x: CGFloat
    var y: CGFloat
    var r: CGFloat
    var phase: CGFloat
    var fronds: [PlantFrond]
    var bubbleTimer: CGFloat
}

private struct Ripple {
    var x: CGFloat
    var y: CGFloat
    var r: CGFloat
    var maxR: CGFloat
    var alpha: CGFloat
}

private struct Bubble {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat
    var vz: CGFloat
    var wigglePhase: CGFloat
    var wiggleAmp: CGFloat
}

private struct Splash {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var vz: CGFloat
    var big: Bool
}

private struct Leaf {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var rot: CGFloat
    var rotSpd: CGFloat
    var tumble: CGFloat
    var tumbleSpd: CGFloat
    var swayPhase: CGFloat
    var colorIdx: Int
    var size: CGFloat
    var maple: Bool
    var isSnow: Bool
    var floating: Bool
    var age: CGFloat
    var maxAge: CGFloat
}

private struct Firefly {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var phase: CGFloat
    var blinkSpd: CGFloat
}

private enum SampleHit {
    case eye(glint: Bool, rim: Bool, depthZ: CGFloat)
    case barbel(u: CGFloat, ang: CGFloat, variety: KoiVariety, depthZ: CGFloat)
    case body(shade: CGFloat, pigment: Int, isDorsal: Bool, isScaleEdge: Bool, isGill: Bool, depthZ: CGFloat)
    case fin(density: CGFloat, dark: Bool, spine: Bool, depthZ: CGFloat)
    case turtleShell(shade: CGFloat, rim: Bool, depthZ: CGFloat)
    case turtleSkin(shade: CGFloat, depthZ: CGFloat)
    case minnow(t: CGFloat, depthZ: CGFloat)
    case frog(part: Int, shade: CGFloat, depthZ: CGFloat)
    case shadow(alpha: CGFloat)
}

private struct ActorBox {
    var kind: Int // 0 = koi, 1 = turtle, 2 = minnow
    var index: Int
    var z: CGFloat
    var shX: CGFloat
    var shY: CGFloat
    var minC: Int
    var maxC: Int
    var minR: Int
    var maxR: Int
}

final class PondEngine {
    var config = SaverConfig()

    private var width: CGFloat = 1280
    private var height: CGFloat = 800
    private var cellW: CGFloat = 6.2
    private var cellH: CGFloat = 10.4
    private var fontSize: CGFloat = 10.4
    private var cols: Int = 180
    private var rows: Int = 75

    private var ctFont: CTFont!
    private var cgFont: CGFont!
    private var glyphCache: [Character: CGGlyph] = [:]

    private let shadeRamp: [Character] = Array(" .,:;i1tfLCG08#%@W")
    private let scaleRamp: [Character] = Array(" .,:;coO08@#")
    private let finRamp: [Character] = Array(" .,:~-=+*#")
    private let stoneRamp: [Character] = Array(" .,:;oO")
    private let leafBladeRamp: [Character] = Array(" .:+*#%@")

    private let digits: [Character: [String]] = [
        "0": ["01110","10001","10011","10101","11001","10001","01110"],
        "1": ["00100","01100","00100","00100","00100","00100","01110"],
        "2": ["01110","10001","00001","00110","01000","10000","11111"],
        "3": ["01110","10001","00001","00110","00001","10001","01110"],
        "4": ["00010","00110","01010","10010","11111","00010","00010"],
        "5": ["11111","10000","11110","00001","00001","10001","01110"],
        "6": ["00110","01000","10000","11110","10001","10001","01110"],
        "7": ["11111","00001","00010","00100","01000","01000","01000"],
        "8": ["01110","10001","10001","01110","10001","10001","01110"],
        "9": ["01110","10001","10001","01111","00001","00010","01100"],
        ":": ["00000","00100","00100","00000","00100","00100","00000"]
    ]

    private var fishes: [Koi] = []
    private var turtle: Turtle?
    private var minnows: [Minnow] = []
    private var dragonfly: Dragonfly?
    private var frog: Frog?
    private var lotusPads: [LotusPad] = []
    private var plants: [PondPlant] = []
    private var stoneMap: [CGFloat] = []
    private var ripples: [Ripple] = []
    private var bubbles: [Bubble] = []
    private var splashes: [Splash] = []
    private var leaves: [Leaf] = []
    private var fireflies: [Firefly] = []
    private var stars: [(x: CGFloat, y: CGFloat, phase: CGFloat, spd: CGFloat)] = []
    private var trashCrumbs: [TrashCrumb] = []
    private var pendingTrashBite: (() -> Void)? = nil
    private var agentsActive: Bool = false
    private var isMusicPlaying: Bool = false
    private var audioBass: CGFloat = 0
    private var beatEnergy: CGFloat = 0
    private var beatSide: CGFloat = 1.0
    private var beatNod: CGFloat = 0
    private var musicHold: CGFloat = 0
    private var beatCounter: Int = 0
    private var musicNoteCooldown: CGFloat = 0
    // Phase-locked BPM rhythm tracker for smooth, steady head turns
    private var estimatedBeatInterval: CGFloat = 0.55 // ~109 BPM default until locked
    private var rhythmTimer: CGFloat = 0
    private var lastRealBeatTime: CGFloat = -10
    private var lastRhythmFlipTime: CGFloat = -10

    private var time: CGFloat = 0
    private var rainTimer: CGFloat = 0
    private var leafSpawnTimer: CGFloat = 1.6
    private var patternSeed: CGFloat = CGFloat.random(in: 1...99)
    private var initialized = false

    // Performance caches (reused across frames for zero heap churn & low CPU!)
    private var rippleChGrid: [UInt8] = []
    private var rippleAlphaGrid: [CGFloat] = []
    private var rippleDirtyIndices: [Int] = []
    private var cloudGrid: [CGFloat] = []
    private var cloudFrameCounter: Int = 0
    private var lotusFrameCache: [(x: CGFloat, y: CGFloat, r: CGFloat, r2: CGFloat, notch: CGFloat, flower: Bool)] = []
    private var batchGlyphs: [UInt32: [CGGlyph]] = [:]
    private var batchPositions: [UInt32: [CGPoint]] = [:]
    private var batchKeys: [UInt32] = []

    // Pre-rasterized overhanging corner tree branch (rebuilt ONLY on resize/season/corner change -> ~0.1ms/frame!)
    private struct BranchCell {
        let col: Int
        let row: Int
        let ch: Character
        let kind: UInt8 // 0 = bark, 1 = bark highlight, 2 = foliage/petal, 3 = bright blossom/snow
        let colorIdx: Int
        let swayWeight: CGFloat
    }
    private var branchCells: [BranchCell] = []
    private var branchShadowCells: [(col: Int, row: Int, ch: Character, swayWeight: CGFloat)] = []
    private var branchTipPoints: [CGPoint] = []
    private var branchCacheKey: String = ""

    // Pre-rasterized top-down Zen Garden Accent: Wooden Bridge or Stepping Stones (Tobi-ishi) -> ~0.06ms/frame!
    private struct AccentCell {
        let col: Int
        let row: Int
        let ch: Character
        let kind: UInt8 // Bridge: 0=plank dark, 1=plank light, 2=rail, 3=post | Stones: 4=stone dark, 5=stone top, 6=moss
    }
    private var accentCells: [AccentCell] = []
    private var accentShadowCells: [(col: Int, row: Int, ch: Character)] = []
    private var accentCacheKey: String = ""

    // Visible falling raindrops (lightweight: max ~18 drops -> ~0.02ms/frame!)
    private struct RainDrop {
        var x: CGFloat
        var y: CGFloat
        var z: CGFloat // falls from ~2.2 down to 1.0 (water surface)
        var vx: CGFloat
        var vy: CGFloat
        var vz: CGFloat
    }
    private var rainDrops: [RainDrop] = []

    init() {
        setupFont(size: 10.4)
    }

    func updateAudio(bass: CGFloat, beatHit: CGFloat, playing: Bool) {
        isMusicPlaying = playing
        audioBass = bass
        if config.musicReactive && beatHit > 0.1 {
            // Update tempo tracker (BPM inter-beat interval) from real bass hits
            let delta = time - lastRealBeatTime
            if delta >= 0.36 && delta <= 0.85 {
                // Direct quarter-note beat interval (70–166 BPM)
                estimatedBeatInterval = estimatedBeatInterval * 0.72 + delta * 0.28
            } else if delta > 0.85 && delta <= 1.65 {
                // Missed one beat (2-beat gap): halve to keep true BPM locked
                let half = delta * 0.5
                estimatedBeatInterval = estimatedBeatInterval * 0.82 + half * 0.18
            }
            lastRealBeatTime = time

            // Phase-lock the rhythm clock onto the real beat without double-flipping
            let sinceFlip = time - lastRhythmFlipTime
            if sinceFlip >= estimatedBeatInterval * 0.58 {
                beatSide = -beatSide
                lastRhythmFlipTime = time
                rhythmTimer = 0
            } else if sinceFlip < estimatedBeatInterval * 0.30 {
                // Just flipped slightly early — pull phase gently back into alignment
                rhythmTimer = 0
            }

            beatCounter += 1
            beatEnergy = max(beatEnergy, min(1.0, beatHit))
            musicHold = 1.0

            // Big expanding bass ripples radiating outward from the lotus pads (nenúfares)!
            if !config.minimalistMode && !lotusPads.isEmpty {
                for (idx, lp) in lotusPads.enumerated() {
                    if beatHit > 0.62 || (idx % 2 == beatCounter % 2) {
                        let ox = sin(time * 0.55 + lp.phase) * 2.5
                        let oy = cos(time * 0.45 + lp.phase) * 2.0
                        ripples.append(Ripple(
                            x: lp.x + ox,
                            y: lp.y + oy,
                            r: lp.r * 0.88,
                            maxR: lp.r + 74 + beatHit * 56,
                            alpha: min(0.95, 0.62 + beatHit * 0.34)
                        ))
                    }
                }
            }

            // Subtle musical note & Koi ripple (especially in Minimalist mode)
            if let f = fishes.first(where: { !$0.leaving }), let head = f.renderNodes.first {
                if config.minimalistMode {
                    ripples.append(Ripple(x: head.x, y: head.y, r: 6, maxR: (54 + beatHit * 44) * f.scale, alpha: 0.58 + beatHit * 0.32))
                }
                if beatHit > 0.65 && musicNoteCooldown <= 0 {
                    trashCrumbs.append(TrashCrumb(
                        x: head.x + CGFloat.random(in: -14...14),
                        y: head.y + CGFloat.random(in: -14...14),
                        vx: CGFloat.random(in: -10...10),
                        vy: CGFloat.random(in: -20 ... -10),
                        ch: "♪",
                        life: 1.25
                    ))
                    musicNoteCooldown = 0.75
                }
            }
        }
    }

    private func setupFont(size: CGFloat) {
        fontSize = size
        ctFont = CTFontCreateWithName("Menlo-Regular" as CFString, size, nil)
        cgFont = CTFontCopyGraphicsFont(ctFont, nil)
        glyphCache.removeAll()

        let chars = " .,:;i1tfLCG08#%@WcoO~-=+*()<>/'°·|\\^✦♪"
        for ch in chars {
            var unichar = Array(String(ch).utf16)[0]
            var glyph: CGGlyph = 0
            if CTFontGetGlyphsForCharacters(ctFont, &unichar, &glyph, 1) {
                glyphCache[ch] = glyph
            }
        }
    }

    func resize(to size: CGSize) {
        let w = max(160, size.width)
        let h = max(100, size.height)
        if initialized && abs(w - width) < 2 && abs(h - height) < 2 { return }
        width = w
        height = h

        if width < 480 {
            cellW = 3.2; cellH = 5.4; setupFont(size: 5.5)
        } else if width > 1550 {
            cellW = 6.8; cellH = 11.4; setupFont(size: 11.4)
        } else {
            cellW = 5.6; cellH = 9.4; setupFont(size: 9.4)
        }

        cols = max(24, Int(width / cellW))
        rows = max(16, Int(height / cellH))

        initLotus()
        initPlants()
        buildStoneMap()
        if !initialized {
            initEcosystem()
            initialized = true
        } else {
            initFireflies()
        }
    }

    func applyConfig(_ newConfig: SaverConfig) {
        let countChanged = newConfig.koiCount != config.koiCount
        let seasonChanged = newConfig.season != config.season
        config = newConfig
        if initialized && countChanged {
            initEcosystem()
        }
        if initialized && seasonChanged {
            leaves.removeAll()
            spawnLeaf(forceVisible: true)
        }
    }

    private func screenScale() -> CGFloat {
        return max(0.32, min(1.38, min(width / 1150.0, height / 720.0)))
    }

    private func hash2(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
        let s = sin(x * 127.1 + y * 311.7) * 43758.5453123
        return s - floor(s)
    }

    private func valueNoise(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
        let ix = floor(x), iy = floor(y)
        let fx = x - ix, fy = y - iy
        let ux = fx * fx * (3 - 2 * fx)
        let uy = fy * fy * (3 - 2 * fy)
        let a = hash2(ix, iy), b = hash2(ix + 1, iy)
        let c = hash2(ix, iy + 1), d = hash2(ix + 1, iy + 1)
        return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy
    }

    private func fbm(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
        return valueNoise(x, y) * 0.60 +
               valueNoise(x * 2.15 + 13.7, y * 2.15 - 7.3) * 0.28 +
               valueNoise(x * 4.4 - 5.1, y * 4.4 + 19.2) * 0.12
    }

    private func normalizeAngle(_ a: CGFloat) -> CGFloat {
        var x = a
        while x > .pi { x -= .pi * 2 }
        while x < -.pi { x += .pi * 2 }
        return x
    }

    private func activeTimeOfDay() -> String {
        if config.timeMode != "auto" { return config.timeMode }
        let hr = Calendar.current.component(.hour, from: Date())
        if hr >= 6 && hr < 13 { return "day" }
        if hr >= 13 && hr < 17 { return "afternoon" }
        if hr >= 17 && hr < 20 { return "sunset" }
        return "night"
    }

    private func activeSeason() -> String {
        if config.season != "auto" { return config.season }
        // Rotate seasons by day of the week: Mon/Tue=Spring, Wed/Thu=Summer, Fri/Sat=Autumn, Sun=Winter
        let wd = Calendar.current.component(.weekday, from: Date()) // 1=Sun, 2=Mon..7=Sat
        switch wd {
        case 2, 3: return "spring"
        case 4, 5: return "summer"
        case 6, 7: return "autumn"
        default:   return "winter"
        }
    }

    private func currentPalette() -> Palette {
        let tod = activeTimeOfDay()
        if config.monoMode {
            return Palette(
                tod: tod, bg: RGB(8, 11, 16), waterDeep: RGB(16, 22, 32), stone: RGB(44, 52, 66), clock: RGB(54, 66, 82),
                water: RGB(148, 163, 184), waterAlpha: 0.14, ripple: RGB(208, 218, 232), shadow: RGB(0, 0, 0), shadowAlpha: 0.68,
                lotus: RGB(78, 90, 104), lotusVein: RGB(118, 134, 150), flower: RGB(222, 230, 240),
                white: RGB(236, 242, 250), red: RGB(168, 180, 196), black: RGB(56, 66, 80), gold: RGB(214, 222, 232),
                fin: RGB(146, 160, 178), finBlack: RGB(62, 72, 86), barbel: RGB(232, 240, 248),
                turtleShell: RGB(148, 162, 178), turtleRim: RGB(198, 210, 224), turtleSkin: RGB(122, 136, 152),
                minnow: RGB(212, 222, 236), plant: RGB(68, 82, 92), plantTip: RGB(112, 130, 144),
                bubble: RGB(214, 230, 244), splash: RGB(246, 250, 255),
                dragonfly: RGB(226, 236, 248), wing: RGB(152, 168, 188), frog: RGB(172, 186, 198),
                firefly: RGB(248, 252, 255), moon: RGB(195, 210, 228),
                leafAutumn: [RGB(198,210,224), RGB(164,176,192), RGB(224,232,242)],
                leafSpring: [RGB(212,222,236), RGB(184,196,212), RGB(232,240,248)],
                leafSummer: [RGB(154,168,182), RGB(184,198,212), RGB(134,148,164)],
                snow: RGB(238, 244, 252), eye: RGB(3, 5, 8)
            )
        }
        if tod == "afternoon" {
            // Warm sun-drenched afternoon pond: deep golden-teal water with honey-warm caustics
            return Palette(
                tod: tod, bg: RGB(10, 28, 28), waterDeep: RGB(18, 50, 48), stone: RGB(48, 76, 68), clock: RGB(72, 108, 92),
                water: RGB(214, 198, 134), waterAlpha: 0.23, ripple: RGB(250, 236, 186), shadow: RGB(4, 10, 12), shadowAlpha: 0.66,
                lotus: RGB(54, 124, 68), lotusVein: RGB(96, 174, 98), flower: RGB(255, 206, 212),
                white: RGB(252, 246, 232), red: RGB(248, 82, 36), black: RGB(24, 30, 34), gold: RGB(255, 206, 62),
                fin: RGB(236, 238, 224), finBlack: RGB(36, 42, 46), barbel: RGB(252, 240, 216),
                turtleShell: RGB(82, 122, 64), turtleRim: RGB(196, 168, 88), turtleSkin: RGB(98, 132, 76),
                minnow: RGB(224, 236, 218), plant: RGB(40, 102, 62), plantTip: RGB(86, 168, 96),
                bubble: RGB(242, 248, 224), splash: RGB(255, 252, 236),
                dragonfly: RGB(96, 228, 232), wing: RGB(246, 244, 220), frog: RGB(96, 182, 76),
                firefly: RGB(255, 244, 132), moon: RGB(255, 238, 196),
                leafAutumn: [RGB(244,92,42), RGB(254,186,48), RGB(218,54,44)],
                leafSpring: [RGB(255,192,212), RGB(255,224,234), RGB(246,154,186)],
                leafSummer: [RGB(76,172,82), RGB(108,200,98), RGB(58,146,72)],
                snow: RGB(248, 246, 240), eye: RGB(5, 10, 10)
            )
        }
        if tod == "sunset" {
            return Palette(
                tod: tod, bg: RGB(18, 16, 26), waterDeep: RGB(30, 24, 40), stone: RGB(54, 42, 54), clock: RGB(78, 58, 70),
                water: RGB(235, 148, 86), waterAlpha: 0.22, ripple: RGB(255, 206, 148), shadow: RGB(8, 5, 14), shadowAlpha: 0.68,
                lotus: RGB(54, 96, 62), lotusVein: RGB(98, 142, 88), flower: RGB(255, 192, 196),
                white: RGB(252, 238, 222), red: RGB(248, 82, 42), black: RGB(24, 24, 34), gold: RGB(255, 196, 66),
                fin: RGB(236, 218, 208), finBlack: RGB(38, 36, 48), barbel: RGB(252, 232, 210),
                turtleShell: RGB(82, 108, 62), turtleRim: RGB(192, 152, 86), turtleSkin: RGB(96, 120, 74),
                minnow: RGB(235, 206, 184), plant: RGB(46, 84, 58), plantTip: RGB(88, 138, 86),
                bubble: RGB(255, 224, 192), splash: RGB(255, 238, 216),
                dragonfly: RGB(120, 224, 238), wing: RGB(255, 224, 190), frog: RGB(96, 162, 74),
                firefly: RGB(255, 228, 108), moon: RGB(255, 214, 158),
                leafAutumn: [RGB(242,88,46), RGB(252,174,52), RGB(214,54,48)],
                leafSpring: [RGB(255,184,208), RGB(255,216,228), RGB(244,148,184)],
                leafSummer: [RGB(72,158,84), RGB(96,184,96), RGB(56,134,72)],
                snow: RGB(245, 236, 248), eye: RGB(8, 6, 12)
            )
        }
        if tod == "night" {
            return Palette(
                tod: tod, bg: RGB(4, 11, 22), waterDeep: RGB(8, 22, 42), stone: RGB(20, 42, 68), clock: RGB(38, 68, 98),
                water: RGB(92, 152, 220), waterAlpha: 0.20, ripple: RGB(176, 220, 255), shadow: RGB(1, 4, 10), shadowAlpha: 0.74,
                lotus: RGB(26, 76, 64), lotusVein: RGB(52, 114, 92), flower: RGB(224, 198, 232),
                white: RGB(222, 236, 252), red: RGB(224, 72, 52), black: RGB(16, 24, 38), gold: RGB(234, 186, 78),
                fin: RGB(184, 216, 242), finBlack: RGB(24, 34, 52), barbel: RGB(216, 232, 248),
                turtleShell: RGB(50, 88, 72), turtleRim: RGB(134, 134, 96), turtleSkin: RGB(62, 102, 82),
                minnow: RGB(168, 212, 248), plant: RGB(20, 66, 62), plantTip: RGB(46, 112, 96),
                bubble: RGB(186, 232, 255), splash: RGB(224, 244, 255),
                dragonfly: RGB(110, 222, 252), wing: RGB(192, 226, 252), frog: RGB(68, 138, 86),
                firefly: RGB(244, 255, 118), moon: RGB(216, 234, 255),
                leafAutumn: [RGB(204,84,64), RGB(222,158,68), RGB(178,56,64)],
                leafSpring: [RGB(234,176,208), RGB(242,208,232), RGB(214,142,188)],
                leafSummer: [RGB(52,126,86), RGB(74,152,102), RGB(40,104,76)],
                snow: RGB(226, 240, 255), eye: RGB(2, 5, 12)
            )
        }
        return Palette(
            tod: tod, bg: RGB(6, 26, 32), waterDeep: RGB(10, 44, 54), stone: RGB(28, 72, 78), clock: RGB(44, 96, 102),
            water: RGB(84, 178, 188), waterAlpha: 0.22, ripple: RGB(182, 244, 250), shadow: RGB(1, 8, 12), shadowAlpha: 0.65,
            lotus: RGB(42, 116, 72), lotusVein: RGB(78, 164, 102), flower: RGB(252, 200, 218),
            white: RGB(248, 244, 238), red: RGB(246, 74, 34), black: RGB(22, 28, 36), gold: RGB(250, 196, 54),
            fin: RGB(220, 236, 238), finBlack: RGB(32, 40, 50), barbel: RGB(246, 238, 222),
            turtleShell: RGB(72, 116, 66), turtleRim: RGB(176, 154, 88), turtleSkin: RGB(88, 126, 78),
            minnow: RGB(182, 232, 244), plant: RGB(30, 94, 66), plantTip: RGB(72, 158, 104),
            bubble: RGB(204, 248, 255), splash: RGB(238, 254, 255),
            dragonfly: RGB(66, 224, 242), wing: RGB(216, 246, 255), frog: RGB(84, 174, 78),
            firefly: RGB(248, 255, 130), moon: RGB(220, 240, 255),
            leafAutumn: [RGB(236,84,42), RGB(248,176,46), RGB(208,48,44)],
            leafSpring: [RGB(252,184,210), RGB(255,216,232), RGB(242,146,184)],
            leafSummer: [RGB(68,164,84), RGB(96,192,100), RGB(52,138,72)],
            snow: RGB(240, 248, 255), eye: RGB(3, 8, 11)
        )
    }

    private func initLotus() {
        let s = screenScale()
        lotusPads = [
            LotusPad(x: width * 0.13, y: height * 0.21, r: 74 * s, notchAngle: 0.62, flower: true, phase: 0.2),
            LotusPad(x: width * 0.87, y: height * 0.78, r: 80 * s, notchAngle: -2.35, flower: false, phase: 1.7),
            LotusPad(x: width * 0.83, y: height * 0.18, r: 56 * s, notchAngle: 2.35, flower: true, phase: 3.1),
            LotusPad(x: width * 0.18, y: height * 0.82, r: 60 * s, notchAngle: -0.75, flower: false, phase: 4.4)
        ]
    }

    private func initPlants() {
        let s = screenScale()
        let specs: [(CGFloat, CGFloat, Int, CGFloat, CGFloat)] = [
            (width * 0.24, height * 0.74, 7, 46 * s, 0.4),
            (width * 0.46, height * 0.15, 6, 40 * s, 1.8),
            (width * 0.74, height * 0.45, 7, 46 * s, 3.2),
            (width * 0.30, height * 0.35, 6, 38 * s, 4.5),
            (width * 0.62, height * 0.86, 7, 44 * s, 5.7)
        ]
        plants = specs.enumerated().map { idx, sp in
            var fronds: [PlantFrond] = []
            for f in 0..<sp.2 {
                let base = (CGFloat(f) / CGFloat(sp.2)) * .pi * 2 + hash2(CGFloat(idx) * 3.1, CGFloat(f) * 2.7) * 0.45
                let len = sp.3 * (0.68 + hash2(CGFloat(idx) * 5.3, CGFloat(f) * 4.1) * 0.45)
                let bend = (hash2(CGFloat(idx), CGFloat(f)) - 0.5) * 0.5
                fronds.append(PlantFrond(ang: base, len: len, bend: bend))
            }
            return PondPlant(x: sp.0, y: sp.1, r: sp.3, phase: sp.4, fronds: fronds, bubbleTimer: CGFloat.random(in: 0.4...1.8))
        }
    }

    private func initFireflies() {
        fireflies = (0..<16).map { _ in
            Firefly(
                x: CGFloat.random(in: 0...width), y: CGFloat.random(in: 0...height),
                vx: CGFloat.random(in: -9...9), vy: CGFloat.random(in: -9...9),
                phase: CGFloat.random(in: 0...(2 * .pi)), blinkSpd: CGFloat.random(in: 1.4...3.0)
            )
        }
        stars = (0..<42).map { i in
            let fi = CGFloat(i)
            return (
                x: hash2(fi * 4.7, 9.1) * width,
                y: hash2(fi * 8.3, 2.7) * height,
                phase: hash2(fi * 1.9, 5.3) * 2 * .pi,
                spd: 1.2 + hash2(fi * 6.1, 3.7) * 2.2
            )
        }
    }

    private func buildStoneMap() {
        stoneMap = Array(repeating: 0, count: cols * rows)
        let s = screenScale()
        var stones: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = []
        for i in 0..<50 {
            let fi = CGFloat(i)
            let sx = hash2(fi * 3.7, 1.1) * width
            let sy = hash2(fi * 5.3, 2.9) * height
            let rx = (20 + hash2(fi * 7.1, 4.3) * 44) * s
            let ry = rx * (0.58 + hash2(fi * 2.3, 8.7) * 0.38)
            let ang = hash2(fi * 9.1, 6.2) * .pi
            let tone = 0.55 + hash2(fi * 4.9, 3.3) * 0.45
            stones.append((sx, sy, rx, ry, cos(ang), sin(ang), tone))
        }
        for r in 0..<rows {
            let py = (CGFloat(r) + 0.5) * cellH
            for c in 0..<cols {
                let px = (CGFloat(c) + 0.5) * cellW
                var best: CGFloat = 0
                for st in stones {
                    let dx = px - st.0, dy = py - st.1
                    if abs(dx) > st.2 + 2 || abs(dy) > st.2 + 2 { continue }
                    let lx = (dx * st.4 + dy * st.5) / st.2
                    let ly = (-dx * st.5 + dy * st.4) / st.3
                    let d2 = lx * lx + ly * ly
                    if d2 < 1.0 {
                        let z = sqrt(1.0 - d2)
                        let lit = max(0.12, (z * 0.65 - lx * 0.25 - ly * 0.28) * st.6)
                        if lit > best { best = lit }
                    }
                }
                stoneMap[r * cols + c] = best
            }
        }
    }

    private func bodyHalfWidth(_ t: CGFloat, _ scale: CGFloat) -> CGFloat {
        if t < 0 || t > 0.76 { return 0 }
        let u = t / 0.76
        let w: CGFloat
        if u < 0.08 {
            w = 0.44 * pow(sin((u / 0.08) * (.pi / 2)), 0.55)
        } else if u < 0.30 {
            w = 0.44 + 0.56 * sin(((u - 0.08) / 0.22) * (.pi / 2))
        } else {
            w = 0.115 + 0.885 * pow(1.0 - (u - 0.30) / 0.70, 1.52)
        }
        let eyeBulge = exp(-pow((t - 0.082) / 0.018, 2)) * 0.075
        return (w + eyeBulge) * 26.5 * scale
    }

    private func createKoi(variety: KoiVariety, seed: CGFloat, x: CGFloat, y: CGFloat, angle: CGFloat, scale: CGFloat, z: CGFloat, speed: CGFloat, phase: CGFloat, turnRate: CGFloat) -> Koi {
        let N = 28
        let segLen = 9.4 * scale
        var nodes: [Vec2] = []
        var renderNodes: [RenderNode] = []
        for i in 0..<N {
            let nx = x - cos(angle) * CGFloat(i) * segLen
            let ny = y - sin(angle) * CGFloat(i) * segLen
            nodes.append(Vec2(x: nx, y: ny))
            renderNodes.append(RenderNode(x: nx, y: ny, nx: 0, ny: 0))
        }
        let segs = Array(repeating: SpineSeg(ax: 0, ay: 0, abx: 1, aby: 0, invLenSq: 1, anx: 0, any: 1, dnx: 0, dny: 0), count: N - 1)
        let bSegLen = 5.2 * scale
        func makeBarbel(_ side: CGFloat) -> [BarbelNode] {
            let initAng = angle + side * 1.15
            return (0..<7).map { i in
                BarbelNode(x: x + cos(initAng) * CGFloat(i) * bSegLen, y: y + sin(initAng) * CGFloat(i) * bSegLen, vx: 0, vy: 0)
            }
        }
        return Koi(
            variety: variety, seed: seed, baseScale: scale, scale: scale,
            z: z, targetZ: z, zTimer: CGFloat.random(in: 2...6),
            segLen: segLen, N: N, nodes: nodes, renderNodes: renderNodes, segs: segs,
            barbels: [makeBarbel(-1), makeBarbel(1)], barbelSegLen: bSegLen,
            angle: angle, turnVel: 0,
            targetX: x + cos(angle) * 180, targetY: y + sin(angle) * 180,
            phase: phase, baseSpeed: speed, speed: speed, turnRate: turnRate,
            tailTimer: 0.5, wanderTimer: 2.5,
            breaching: false, breachProgress: 0, breachCooldown: CGFloat.random(in: 6...16), breachSplashTick: 0,
            hasEntered: true, leaving: false
        )
    }

    private func spawnKoiFromEdge(forcedVariety: KoiVariety? = nil, scaleMult: CGFloat = 1.0, forcedZ: CGFloat? = nil) -> Koi {
        let s = screenScale()
        let edge = Int.random(in: 0..<4)
        let variety = forcedVariety ?? (KoiVariety.pondVarieties.randomElement() ?? .showa)
        let scale = CGFloat.random(in: 1.38...1.90) * s * scaleMult
        let z = forcedZ ?? CGFloat.random(in: 0.22...0.92)
        let off = 95 * scale
        var x: CGFloat = 0, y: CGFloat = 0, angle: CGFloat = 0
        switch edge {
        case 0: x = -off; y = height * CGFloat.random(in: 0.18...0.82); angle = CGFloat.random(in: -0.28...0.28)
        case 1: x = width + off; y = height * CGFloat.random(in: 0.18...0.82); angle = .pi + CGFloat.random(in: -0.28...0.28)
        case 2: x = width * CGFloat.random(in: 0.18...0.82); y = -off; angle = .pi * 0.5 + CGFloat.random(in: -0.28...0.28)
        default: x = width * CGFloat.random(in: 0.18...0.82); y = height + off; angle = -.pi * 0.5 + CGFloat.random(in: -0.28...0.28)
        }
        var koi = createKoi(variety: variety, seed: CGFloat.random(in: 0...100), x: x, y: y, angle: angle, scale: scale, z: z, speed: CGFloat.random(in: 48...66) * s, phase: CGFloat.random(in: 0...(2 * .pi)), turnRate: CGFloat.random(in: 1.15...1.5))
        koi.targetX = width * CGFloat.random(in: 0.22...0.78)
        koi.targetY = height * CGFloat.random(in: 0.22...0.78)
        koi.wanderTimer = CGFloat.random(in: 4.5...8.0)
        koi.hasEntered = false
        return koi
    }

    // MARK: - Desktop Interactive & Useful Fish APIs

    func onClick(x: CGFloat, y: CGFloat) {
        let s = screenScale()
        ripples.append(Ripple(x: x, y: y, r: 3 * s, maxR: 96 * s, alpha: 0.88))
        ripples.append(Ripple(x: x, y: y, r: 1 * s, maxR: 54 * s, alpha: 0.62))
        if let idx = fishes.firstIndex(where: { $0.agentId == nil && !$0.isTrashEater }) {
            fishes[idx].leaving = false
            fishes[idx].targetX = max(60, min(width - 60, x))
            fishes[idx].targetY = max(60, min(height - 60, y))
            fishes[idx].targetZ = 0.94
            fishes[idx].wanderTimer = 4.5
        }
        for i in 0..<minnows.count {
            let dx = minnows[i].x - x, dy = minnows[i].y - y
            let d = max(1, hypot(dx, dy))
            if d < 150 * s {
                minnows[i].vx += (dx / d) * 160
                minnows[i].vy += (dy / d) * 160
                minnows[i].boost = 1.0
            }
        }
    }

    func syncAgents(_ activeAgents: [AgentDescriptor]) {
        let activeIds = Set(activeAgents.map { $0.id })
        let hasLiveAgents = activeAgents.contains { $0.state != .done }
        agentsActive = hasLiveAgents

        // When AI agents enter, gently send ambient pond Koi off-screen to keep the pond spacious
        if hasLiveAgents {
            for i in 0..<fishes.count where fishes[i].agentId == nil && !fishes[i].isTrashEater && !fishes[i].leaving {
                fishes[i].leaving = true
                let exitEdge = Int.random(in: 0..<4)
                let far = 440 * fishes[i].scale
                switch exitEdge {
                case 0: fishes[i].targetX = -far; fishes[i].targetY = CGFloat.random(in: 0...height)
                case 1: fishes[i].targetX = width + far; fishes[i].targetY = CGFloat.random(in: 0...height)
                case 2: fishes[i].targetX = CGFloat.random(in: 0...width); fishes[i].targetY = -far
                default: fishes[i].targetX = CGFloat.random(in: 0...width); fishes[i].targetY = height + far
                }
            }
        } else {
            // Agents finished — bring ambient pond Koi back in smoothly from the edges!
            // Count ALL ambient Koi (including ones currently leaving) so cycling Koi never exceed koiCount
            let ambientCount = fishes.filter { $0.agentId == nil && !$0.isTrashEater }.count
            let targetAmbient = max(1, min(8, config.koiCount))
            if ambientCount < targetAmbient {
                for _ in 0..<(targetAmbient - ambientCount) {
                    fishes.append(spawnKoiFromEdge())
                }
            }
        }

        // Mark removed or .done agents for triumphant breach + exit
        for i in 0..<fishes.count {
            guard let aid = fishes[i].agentId else { continue }
            if !activeIds.contains(aid) && !fishes[i].leaving {
                triggerAgentDeparture(&fishes[i])
            }
        }

        // Update existing or spawn newly active agent Koi
        for ag in activeAgents {
            if let idx = fishes.firstIndex(where: { $0.agentId == ag.id }) {
                let prevState = fishes[idx].agentState
                fishes[idx].agentState = ag.state
                fishes[idx].parentAgentId = ag.parentId
                fishes[idx].formationSlot = ag.formationSlot
                if ag.state == .done && !fishes[idx].leaving {
                    triggerAgentDeparture(&fishes[idx])
                } else if ag.state == .error && prevState != .error {
                    fishes[idx].errorFlash = 1.0
                    let head = fishes[idx].renderNodes[0]
                    ripples.append(Ripple(x: head.x, y: head.y, r: 4, maxR: 65, alpha: 0.92))
                }
            } else if ag.state != .done {
                let variety: KoiVariety = (ag.model == .gemini) ? .gemini : .claude
                let scaleMult: CGFloat = ag.isSubagent ? 0.68 : 1.12
                var koi = spawnKoiFromEdge(forcedVariety: variety, scaleMult: scaleMult, forcedZ: ag.isSubagent ? 0.78 : 0.92)
                koi.agentId = ag.id
                koi.parentAgentId = ag.parentId
                koi.formationSlot = ag.formationSlot
                koi.agentState = ag.state
                koi.isSubagent = ag.isSubagent
                fishes.append(koi)
            }
        }
    }

    private func triggerAgentDeparture(_ fish: inout Koi) {
        fish.leaving = true
        fish.agentState = .done
        if !fish.breaching {
            fish.breaching = true
            fish.breachProgress = 0
            fish.breachSplashTick = 0
            let pt = fish.renderNodes[min(2, fish.N - 1)]
            spawnSplashBurst(x: pt.x, y: pt.y, count: 16, power: 1.15)
        }
        let exitEdge = Int.random(in: 0..<4)
        let far = 460 * fish.scale
        switch exitEdge {
        case 0: fish.targetX = -far; fish.targetY = CGFloat.random(in: 0...height)
        case 1: fish.targetX = width + far; fish.targetY = CGFloat.random(in: 0...height)
        case 2: fish.targetX = CGFloat.random(in: 0...width); fish.targetY = -far
        default: fish.targetX = CGFloat.random(in: 0...width); fish.targetY = height + far
        }
    }

    /// Curious visual visit when files are dropped in ~/.Trash (never deletes anything).
    func triggerTrashVisit(at point: CGPoint) {
        ensureTrashEaterKoi(near: point, eating: false)
        spawnTrashCrumbs(at: point, count: 5)
    }

    /// Active feeding frenzy triggered by user ("Feed Trash to Koi"): gobbles crumbs then calls onBite to empty Trash.
    func triggerFeedTrash(at point: CGPoint, onBite: @escaping () -> Void) {
        pendingTrashBite = onBite
        ensureTrashEaterKoi(near: point, eating: true)
        spawnTrashCrumbs(at: point, count: 14)
    }

    private func ensureTrashEaterKoi(near point: CGPoint, eating: Bool) {
        if let idx = fishes.firstIndex(where: { $0.isTrashEater }) {
            fishes[idx].leaving = false
            fishes[idx].trashTarget = point
            fishes[idx].trashEating = eating
            fishes[idx].targetX = point.x
            fishes[idx].targetY = point.y
            fishes[idx].targetZ = 0.96
            fishes[idx].wanderTimer = 8.0
        } else {
            var koi = spawnKoiFromEdge(forcedVariety: .trashEater, scaleMult: 1.16, forcedZ: 0.92)
            koi.isTrashEater = true
            koi.trashTarget = point
            koi.trashEating = eating
            koi.targetX = point.x
            koi.targetY = point.y
            koi.wanderTimer = 8.0
            fishes.append(koi)
        }
    }

    private func spawnTrashCrumbs(at point: CGPoint, count: Int) {
        let glyphs: [Character] = ["#", "%", "+", "@", "*", "~"]
        for _ in 0..<count {
            trashCrumbs.append(TrashCrumb(
                x: point.x + CGFloat.random(in: -34...34),
                y: point.y + CGFloat.random(in: -28...28),
                vx: CGFloat.random(in: -14...14),
                vy: CGFloat.random(in: -14...14),
                ch: glyphs.randomElement() ?? "#",
                life: CGFloat.random(in: 5.5...8.5)
            ))
        }
        ripples.append(Ripple(x: point.x, y: point.y, r: 3, maxR: 52, alpha: 0.72))
    }

    private func initEcosystem() {
        let s = screenScale()
        let count = max(1, min(8, config.koiCount))
        let presets: [(KoiVariety, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (.showa, 0.36, 0.48, -0.12, 1.84, 0.90, 52),
            (.utsuri, 0.66, 0.30, .pi * 0.85, 1.56, 0.54, 58),
            (.ogon, 0.52, 0.74, -.pi * 0.72, 1.38, 0.24, 46),
            (.sanke, 0.22, 0.26, 0.4, 1.50, 0.72, 50),
            (.kumonryu, 0.78, 0.66, -2.4, 1.44, 0.38, 54),
            (.showa, 0.16, 0.68, -0.45, 1.32, 0.62, 55),
            (.ogon, 0.84, 0.24, 2.55, 1.42, 0.44, 49),
            (.sanke, 0.48, 0.20, 1.15, 1.36, 0.80, 53)
        ]
        fishes = (0..<count).map { i in
            let p = presets[i % presets.count]
            return createKoi(variety: p.0, seed: patternSeed + CGFloat(i) * 13.7, x: width * p.1, y: height * p.2, angle: p.3, scale: p.4 * s, z: p.5, speed: p.6 * s, phase: CGFloat(i) * 1.9, turnRate: 1.2 + CGFloat(i % 3) * 0.12)
        }
        turtle = Turtle(x: width * 0.70, y: height * 0.65, angle: -2.4, targetX: width * 0.35, targetY: height * 0.35, z: 0.38, targetZ: 0.44, zTimer: 4, scale: 1.54 * s, speed: 22 * s, turnRate: 0.55, phase: 0, headYaw: 0, wanderTimer: 5.0)

        let cx = width * 0.28, cy = height * 0.70
        minnows = (0..<6).map { _ in
            let ang = -0.3 + CGFloat.random(in: -0.2...0.2)
            let mx = cx + CGFloat.random(in: -35...35), my = cy + CGFloat.random(in: -25...25)
            let segs = (0..<6).map { k in Vec2(x: mx - cos(ang) * CGFloat(k) * 4.8 * s, y: my - sin(ang) * CGFloat(k) * 4.8 * s) }
            return Minnow(x: mx, y: my, vx: cos(ang) * 62 * s, vy: sin(ang) * 62 * s, angle: ang, z: CGFloat.random(in: 0.78...0.96), phase: CGFloat.random(in: 0...(2 * .pi)), nodes: segs, boost: 0)
        }
        dragonfly = Dragonfly(x: width * 0.2, y: height * 0.25, z: 1.75, angle: 0.3, targetX: width * 0.7, targetY: height * 0.3, perched: false, perchPadIdx: -1, stateTimer: 3.5, wingPhase: 0)
        let pad0 = lotusPads.first ?? LotusPad(x: width * 0.13, y: height * 0.21, r: 50, notchAngle: 0.6, flower: true, phase: 0)
        frog = Frog(x: pad0.x + 12, y: pad0.y + 8, z: 1.03, angle: 0.55, padIdx: 0, state: .perched, targetPadIdx: 0, swimPhase: 0, restTimer: 5.5)
        initFireflies()
        leaves.removeAll()
        spawnLeaf(forceVisible: true)
    }

    private func spawnLeaf(forceVisible: Bool) {
        let s = screenScale()
        let actSeason = activeSeason()
        let isWinter = actSeason == "winter"

        let startX: CGFloat
        let startY: CGFloat
        let startZ: CGFloat
        var vx: CGFloat
        var vy: CGFloat

        if config.treeBranch != "none" && !config.minimalistMode && !branchTipPoints.isEmpty && CGFloat.random(in: 0...1) < 0.78 {
            // Detach petal/leaf gently from a blossom/foliage cluster on the overhanging tree branch
            let tip = branchTipPoints[Int.random(in: 0..<branchTipPoints.count)]
            startX = tip.x + CGFloat.random(in: -14...14) * s
            startY = tip.y + CGFloat.random(in: -12...12) * s
            startZ = CGFloat.random(in: 1.78...2.05)
            // Gentle inward breeze drift away from the branch corner (peels off smoothly via age ramp!)
            let dirX: CGFloat = (config.treeBranch == "topRight" || config.treeBranch == "bottomRight") ? -1.0 : 1.0
            let dirY: CGFloat = (config.treeBranch == "bottomRight" || config.treeBranch == "bottomLeft") ? -0.35 : 0.65
            vx = (dirX * CGFloat.random(in: 14...30) + CGFloat.random(in: -6...6)) * s
            vy = (dirY * CGFloat.random(in: 10...22) + CGFloat.random(in: -5...5)) * s
        } else {
            let fromTop = Bool.random()
            startX = fromTop ? CGFloat.random(in: 0...(width * 0.85)) : -52 * s
            startY = fromTop ? -52 * s : CGFloat.random(in: 0...(height * 0.78))
            startZ = forceVisible ? 2.15 : CGFloat.random(in: 2.15...2.55)
            vx = ((isWinter ? 18 : 34) + CGFloat.random(in: 0...22)) * s
            vy = ((isWinter ? 20 : 22) + CGFloat.random(in: 0...18)) * s
        }

        leaves.append(Leaf(
            x: startX, y: startY,
            z: startZ,
            vx: vx, vy: vy,
            rot: CGFloat.random(in: 0...(2 * .pi)), rotSpd: CGFloat.random(in: -0.75...0.75),
            tumble: CGFloat.random(in: 0...(2 * .pi)), tumbleSpd: CGFloat.random(in: 1.8...3.1),
            swayPhase: CGFloat.random(in: 0...(2 * .pi)), colorIdx: Int.random(in: 0..<3),
            size: (isWinter ? CGFloat.random(in: 12...18) : CGFloat.random(in: 20...30)) * s,
            maple: CGFloat.random(in: 0...1) > 0.25, isSnow: isWinter,
            floating: false, age: 0, maxAge: isWinter ? 0.2 : CGFloat.random(in: 34...50)
        ))
    }

    private func spawnSplashBurst(x: CGFloat, y: CGFloat, count: Int, power: CGFloat) {
        let s = screenScale()
        for _ in 0..<count {
            let ang = CGFloat.random(in: 0...(2 * .pi))
            let spd = CGFloat.random(in: 28...104) * power * s
            splashes.append(Splash(
                x: x + CGFloat.random(in: -8...8) * s, y: y + CGFloat.random(in: -8...8) * s, z: 1.02,
                vx: cos(ang) * spd, vy: sin(ang) * spd, vz: CGFloat.random(in: 1.2...2.7) * power,
                big: Bool.random()
            ))
        }
        ripples.append(Ripple(x: x, y: y, r: 5 * s, maxR: 86 * power * s, alpha: 0.94))
        ripples.append(Ripple(x: x, y: y, r: 1 * s, maxR: 52 * power * s, alpha: 0.74))
    }

    // MARK: - Step Simulation

    func step(dt rawDt: CGFloat) {
        let dt = min(0.05, max(0.001, rawDt))
        time += dt

        // Tempo-locked rhythm clock: keeps Koi heads turning Left <-> Right in steady BPM rhythm
        musicNoteCooldown = max(0, musicNoteCooldown - dt)
        if config.musicReactive && isMusicPlaying && (time - lastRealBeatTime) < 2.8 {
            beatEnergy *= exp(-4.8 * dt)
            rhythmTimer += dt
            // Slight 22ms predictive lead compensates for CoreAudio + display pipeline latency
            let nextBeatAt = max(0.32, estimatedBeatInterval - 0.022)
            if rhythmTimer >= nextBeatAt {
                rhythmTimer -= estimatedBeatInterval
                beatSide = -beatSide
                lastRhythmFlipTime = time
                musicHold = 1.0
            }
            musicHold = max(0, musicHold - dt * 0.45)
            let targetNod = beatSide * min(1.0, musicHold * 1.35)
            beatNod += (targetNod - beatNod) * min(1.0, dt * 48.0)
        } else {
            beatEnergy = 0
            musicHold = 0
            rhythmTimer = 0
            beatNod *= exp(-8.0 * dt)
        }

        // Snapshot parent agent positions BEFORE inout mutation to avoid Swift exclusive-access crash!
        var parentLookup: [String: (x: CGFloat, y: CGFloat, angle: CGFloat, z: CGFloat, scale: CGFloat, speed: CGFloat)] = [:]
        for f in fishes {
            if let aid = f.agentId, !f.isSubagent, let h = f.nodes.first {
                parentLookup[aid] = (h.x, h.y, f.angle, f.z, f.scale, f.speed)
            }
        }

        var fIdx = fishes.count - 1
        while fIdx >= 0 {
            let pInfo = fishes[fIdx].parentAgentId.flatMap { parentLookup[$0] }
            updateKoi(&fishes[fIdx], dt: dt, parentInfo: pInfo)
            if fishes[fIdx].leaving {
                let padOut = 110 * fishes[fIdx].scale
                let allOut = fishes[fIdx].renderNodes.allSatisfy { rn in
                    rn.x <= -padOut || rn.x >= width + padOut || rn.y <= -padOut || rn.y >= height + padOut
                }
                if allOut {
                    let totalAmbient = fishes.filter { $0.agentId == nil && !$0.isTrashEater }.count
                    if fishes[fIdx].agentId != nil || fishes[fIdx].isTrashEater || agentsActive || totalAmbient > config.koiCount {
                        fishes.remove(at: fIdx)
                    } else {
                        fishes[fIdx] = spawnKoiFromEdge()
                    }
                }
            }
            fIdx -= 1
        }

        // Update floating Trash crumbs (drawn into Trash-Eater Koi's mouth!)
        let trashHead = fishes.first(where: { $0.isTrashEater })?.renderNodes.first
        var cIdx = trashCrumbs.count - 1
        while cIdx >= 0 {
            trashCrumbs[cIdx].life -= dt
            trashCrumbs[cIdx].x += trashCrumbs[cIdx].vx * dt
            trashCrumbs[cIdx].y += trashCrumbs[cIdx].vy * dt
            trashCrumbs[cIdx].vx *= exp(-2.2 * dt)
            trashCrumbs[cIdx].vy *= exp(-2.2 * dt)
            if let th = trashHead {
                let dx = th.x - trashCrumbs[cIdx].x, dy = th.y - trashCrumbs[cIdx].y
                let d = hypot(dx, dy)
                if d < 120 {
                    trashCrumbs[cIdx].x += (dx / max(1, d)) * 130 * dt
                    trashCrumbs[cIdx].y += (dy / max(1, d)) * 130 * dt
                }
                if d < 26 {
                    bubbles.append(Bubble(x: th.x, y: th.y, z: 0.72, vz: 0.45, wigglePhase: 0, wiggleAmp: 4))
                    trashCrumbs.remove(at: cIdx)
                    cIdx -= 1
                    continue
                }
            }
            if trashCrumbs[cIdx].life <= 0 { trashCrumbs.remove(at: cIdx) }
            cIdx -= 1
        }

        if !config.minimalistMode {
            if turtle != nil { updateTurtle(&turtle!, dt: dt) }
            updateMinnows(dt: dt)
            if dragonfly != nil { updateDragonfly(&dragonfly!, dt: dt) }
            if frog != nil { updateFrog(&frog!, dt: dt) }
            updatePlantsAndBubbles(dt: dt)
            updateSplashesAndLeaves(dt: dt)
        } else {
            // Still animate bubbles & splashes in minimalist mode
            updateSplashesAndLeaves(dt: dt)
            var bIdx = bubbles.count - 1
            while bIdx >= 0 {
                bubbles[bIdx].z += bubbles[bIdx].vz * dt
                if bubbles[bIdx].z >= 1.0 {
                    ripples.append(Ripple(x: bubbles[bIdx].x, y: bubbles[bIdx].y, r: 2, maxR: 22, alpha: 0.64))
                    bubbles.remove(at: bIdx)
                }
                bIdx -= 1
            }
        }

        if config.rainOn {
            rainTimer -= dt
            if rainTimer <= 0 && rainDrops.count < 20 {
                let s = screenScale()
                let landX = CGFloat.random(in: 30...max(31, width - 30))
                let landY = CGFloat.random(in: 30...max(31, height - 30))
                let fallTime: CGFloat = CGFloat.random(in: 0.34...0.52)
                let vx: CGFloat = -68 * s
                let vy: CGFloat = 240 * s
                rainDrops.append(RainDrop(
                    x: landX - vx * fallTime,
                    y: landY - vy * fallTime,
                    z: 1.0 + fallTime * 2.4,
                    vx: vx, vy: vy, vz: -2.4
                ))
                rainTimer = CGFloat.random(in: 0.08...0.22)
            }
        }
        var rdIdx = rainDrops.count - 1
        while rdIdx >= 0 {
            rainDrops[rdIdx].x += rainDrops[rdIdx].vx * dt
            rainDrops[rdIdx].y += rainDrops[rdIdx].vy * dt
            rainDrops[rdIdx].z += rainDrops[rdIdx].vz * dt
            if rainDrops[rdIdx].z <= 1.0 {
                let rd = rainDrops[rdIdx]
                if rd.x >= 0 && rd.x <= width && rd.y >= 0 && rd.y <= height {
                    ripples.append(Ripple(x: rd.x, y: rd.y, r: 2, maxR: CGFloat.random(in: 28...58), alpha: 0.68))
                    splashes.append(Splash(x: rd.x, y: rd.y, z: 1.02, vx: CGFloat.random(in: -14...14), vy: CGFloat.random(in: -12...12), vz: CGFloat.random(in: 0.8...1.5), big: false))
                }
                rainDrops.remove(at: rdIdx)
            }
            rdIdx -= 1
        }

        var idx = ripples.count - 1
        while idx >= 0 {
            ripples[idx].r += dt * 48
            if ripples[idx].r >= ripples[idx].maxR { ripples.remove(at: idx) }
            idx -= 1
        }
    }

    private func updateKoi(_ fish: inout Koi, dt: CGFloat, parentInfo: (x: CGFloat, y: CGFloat, angle: CGFloat, z: CGFloat, scale: CGFloat, speed: CGFloat)?) {
        if !fish.breaching {
            fish.breachCooldown -= dt
            if fish.breachCooldown <= 0 && fish.z > 0.68 && !fish.leaving {
                let h = fish.nodes[0]
                if h.x > width * 0.14 && h.x < width * 0.86 && h.y > height * 0.14 && h.y < height * 0.86 {
                    fish.breaching = true
                    fish.breachProgress = 0
                    fish.breachSplashTick = 0
                    fish.breachLaunched = false
                    fish.breachDir = Bool.random() ? 1.0 : -1.0
                    fish.breachCooldown = CGFloat.random(in: 10...22)
                    // Subtle preparation tremor ripple as the Koi coils to jump
                    ripples.append(Ripple(x: h.x, y: h.y, r: 4, maxR: 34 * fish.scale, alpha: 0.62))
                } else {
                    fish.breachCooldown = 3.0
                }
            }
        }

        var breachAirArc: CGFloat = 0
        var breachPitchTilt: CGFloat = 0
        var breachPrep: Bool = false

        if fish.breaching {
            fish.breachProgress += dt / 1.72
            let p = min(1.0, fish.breachProgress)

            if p < 0.24 {
                // Stage 1: Preparation coil & dip just beneath the surface
                breachPrep = true
                let prepT = p / 0.24
                fish.z = 0.88 - sin(prepT * .pi) * 0.16
            } else if p < 0.86 {
                // Stage 2: Explosive launch, pitched-up climb, C-curve mid-air arch, and head-first dive!
                let airP = (p - 0.24) / 0.62
                breachAirArc = sin(airP * .pi)
                breachPitchTilt = abs(cos(airP * .pi)) // steepest tilt at launch & dive entry
                fish.z = 1.0 + breachAirArc * 0.68

                if !fish.breachLaunched {
                    fish.breachLaunched = true
                    let pt = fish.renderNodes[min(2, fish.N - 1)]
                    spawnSplashBurst(x: pt.x, y: pt.y, count: 18, power: 1.25)
                }

                // Trailing airborne sparkling water droplets shaking off fins & tail!
                fish.breachSplashTick -= dt
                if fish.breachSplashTick <= 0 {
                    let s = screenScale()
                    let nodeIdx = min(fish.N - 1, max(1, Int((1.0 - airP * 0.5) * CGFloat(fish.N - 2))))
                    let pt = fish.renderNodes[nodeIdx]
                    for _ in 0..<5 {
                        let ang = CGFloat.random(in: 0...(2 * .pi))
                        let spd = CGFloat.random(in: 22...76) * s
                        splashes.append(Splash(
                            x: pt.x + CGFloat.random(in: -8...8) * s,
                            y: pt.y + CGFloat.random(in: -8...8) * s,
                            z: max(1.04, fish.z - 0.06),
                            vx: cos(ang) * spd, vy: sin(ang) * spd,
                            vz: CGFloat.random(in: 0.6...2.1),
                            big: Bool.random()
                        ))
                    }
                    fish.breachSplashTick = 0.075
                }
            } else {
                // Stage 3: Head-first splashdown with massive water burst & triple concentric ripples!
                fish.breaching = false
                fish.breachProgress = 0
                fish.breachLaunched = false
                fish.z = 0.86
                fish.targetZ = CGFloat.random(in: 0.48...0.82)
                let headPt = fish.renderNodes[min(2, fish.N - 1)]
                let midPt = fish.renderNodes[fish.N / 2]
                spawnSplashBurst(x: headPt.x, y: headPt.y, count: 28, power: 1.48)
                spawnSplashBurst(x: midPt.x, y: midPt.y, count: 10, power: 0.95)
                ripples.append(Ripple(x: headPt.x, y: headPt.y, r: 8 * fish.scale, maxR: 135 * fish.scale, alpha: 0.96))
            }
        } else {
            fish.zTimer -= dt
            if fish.zTimer <= 0 { fish.targetZ = CGFloat.random(in: 0.20...0.96); fish.zTimer = CGFloat.random(in: 4...9) }
            fish.z += (fish.targetZ - fish.z) * min(1.0, dt * 0.55)
        }

        let breachBoost: CGFloat = fish.z > 1.0 ? (fish.z - 1.0) * 0.44 : 0
        fish.scale = fish.baseScale * (0.86 + min(1.0, fish.z) * 0.18 + breachBoost)
        fish.segLen = 9.4 * fish.scale
        fish.barbelSegLen = 5.2 * fish.scale

        fish.wanderTimer -= dt
        fish.errorFlash = max(0, fish.errorFlash - dt * 1.4)
        fish.stateRippleTimer -= dt
        let head = fish.nodes[0]
        if head.x > 40 && head.x < width - 40 && head.y > 40 && head.y < height - 40 { fish.hasEntered = true }

        // Trash-Eater Koi arrival logic
        if fish.isTrashEater, let tPt = fish.trashTarget, !fish.leaving {
            fish.targetX = tPt.x
            fish.targetY = tPt.y
            fish.targetZ = 0.96
            if hypot(tPt.x - head.x, tPt.y - head.y) < 52 {
                spawnSplashBurst(x: tPt.x, y: tPt.y, count: fish.trashEating ? 14 : 5, power: fish.trashEating ? 0.95 : 0.55)
                if fish.trashEating {
                    let cb = pendingTrashBite
                    pendingTrashBite = nil
                    cb?()
                }
                fish.trashTarget = nil
                fish.trashEating = false
                fish.leaving = true
                fish.targetX = -420 * fish.scale
                fish.targetY = height * 0.45
            }
        } else if fish.isSubagent, let parent = parentInfo, !fish.leaving {
            // Subagents swim smoothly in V-formation escort behind their parent Agent Koi!
            let pTx = cos(parent.angle), pTy = sin(parent.angle)
            let pNx = -pTy, pNy = pTx
            let side: CGFloat = (fish.formationSlot % 2 == 0) ? -1.0 : 1.0
            let rank = CGFloat((fish.formationSlot / 2) + 1)
            let backDist = (115.0 + rank * 75.0) * parent.scale
            let sideDist = (72.0 + rank * 42.0) * parent.scale
            fish.targetX = parent.x - pTx * backDist + pNx * (side * sideDist)
            fish.targetY = parent.y - pTy * backDist + pNy * (side * sideDist)
            fish.targetZ = max(0.35, parent.z - 0.08)
        } else if let st = fish.agentState, !fish.leaving {
            // Reactive AI Agent Koi behaviors (always wide, graceful paths — never coiling!)
            func pickWideTarget() {
                var tx = CGFloat.random(in: width * 0.16...max(width * 0.17, width * 0.84))
                var ty = CGFloat.random(in: height * 0.16...max(height * 0.17, height * 0.84))
                // Ensure waypoint is far enough away so the Koi never loops in a tight knot
                if hypot(tx - head.x, ty - head.y) < 260 {
                    tx = head.x < width * 0.5 ? width * 0.78 : width * 0.22
                    ty = head.y < height * 0.5 ? height * 0.75 : height * 0.25
                }
                fish.targetX = tx
                fish.targetY = ty
            }

            switch st {
            case .thinking:
                fish.targetZ = 0.68
                if fish.stateRippleTimer <= 0 {
                    bubbles.append(Bubble(x: head.x, y: head.y, z: 0.65, vz: 0.35, wigglePhase: 0, wiggleAmp: 5))
                    fish.stateRippleTimer = CGFloat.random(in: 1.0...1.8)
                }
                if hypot(fish.targetX - head.x, fish.targetY - head.y) < 160 || fish.wanderTimer <= 0 {
                    let orbitAng = time * 0.38 + fish.seed
                    fish.targetX = width * 0.5 + cos(orbitAng) * width * 0.30
                    fish.targetY = height * 0.5 + sin(orbitAng) * height * 0.26
                    fish.wanderTimer = 3.2
                }
            case .editing:
                fish.targetZ = 0.90
                if fish.stateRippleTimer <= 0 {
                    ripples.append(Ripple(x: head.x, y: head.y, r: 3, maxR: 38 * fish.scale, alpha: 0.48))
                    fish.stateRippleTimer = 0.60
                }
                if hypot(fish.targetX - head.x, fish.targetY - head.y) < 160 || fish.wanderTimer <= 0 {
                    pickWideTarget()
                    fish.wanderTimer = 3.6
                }
            case .waiting:
                fish.targetZ = 0.96
                if hypot(fish.targetX - head.x, fish.targetY - head.y) < 160 || fish.wanderTimer <= 0 {
                    fish.targetX = width * (head.x < width * 0.5 ? 0.68 : 0.32)
                    fish.targetY = height * 0.70
                    fish.wanderTimer = 4.0
                }
                if fish.stateRippleTimer <= 0 {
                    ripples.append(Ripple(x: head.x, y: head.y, r: 4, maxR: 62, alpha: 0.72))
                    fish.stateRippleTimer = 1.25
                }
            case .error:
                fish.targetZ = 0.95
                if hypot(fish.targetX - head.x, fish.targetY - head.y) < 160 || fish.wanderTimer <= 0 {
                    pickWideTarget()
                    fish.wanderTimer = 3.0
                }
                if fish.stateRippleTimer <= 0 {
                    ripples.append(Ripple(x: head.x, y: head.y, r: 4, maxR: 72, alpha: 0.88))
                    fish.stateRippleTimer = 0.75
                }
            case .done:
                break
            }
        } else if !fish.leaving && (hypot(fish.targetX - head.x, fish.targetY - head.y) < 110 || fish.wanderTimer <= 0) {
            if fish.hasEntered && CGFloat.random(in: 0...1) < 0.35 {
                fish.leaving = true
                let exitEdge = Int.random(in: 0..<4)
                let far = 440 * fish.scale
                switch exitEdge {
                case 0: fish.targetX = -far; fish.targetY = CGFloat.random(in: 0...height)
                case 1: fish.targetX = width + far; fish.targetY = CGFloat.random(in: 0...height)
                case 2: fish.targetX = CGFloat.random(in: 0...width); fish.targetY = -far
                default: fish.targetX = CGFloat.random(in: 0...width); fish.targetY = height + far
                }
            } else {
                fish.targetX = CGFloat.random(in: 35...max(36, width - 35))
                fish.targetY = CGFloat.random(in: 35...max(36, height - 35))
                fish.wanderTimer = CGFloat.random(in: 3.6...7.8)
            }
        }

        let desiredAngle = atan2(fish.targetY - head.y, fish.targetX - head.x)
        let diff = normalizeAngle(desiredAngle - fish.angle)
        // Cap turnRate smoothly so spine never coils into a tight pretzel!
        let maxTurn = min(1.18, fish.turnRate) * dt
        let deltaAngle = max(-maxTurn, min(maxTurn, diff))
        fish.angle += deltaAngle
        fish.turnVel = deltaAngle / dt

        let turnEffort = min(1.0, abs(diff) * 0.9)
        let stateSpeedMult: CGFloat = {
            if fish.isTrashEater && fish.trashTarget != nil { return 1.45 }
            if fish.isSubagent, let parent = parentInfo {
                let d = hypot(fish.targetX - head.x, fish.targetY - head.y)
                return d > 180 ? 1.38 : (d < 70 ? 0.72 : (parent.speed / max(1, fish.baseSpeed)))
            }
            switch fish.agentState {
            case .editing: return 1.28
            case .waiting: return 0.78
            case .thinking: return 0.90
            default: return 1.0
            }
        }()
        let surge: CGFloat = breachPrep ? 0.62 : (fish.breaching ? 1.58 : stateSpeedMult)
        let targetSpeed = fish.baseSpeed * surge * (1.0 + turnEffort * 0.22)
        fish.speed += (targetSpeed - fish.speed) * min(1.0, dt * (fish.breaching ? 6.0 : 3.2))
        let phaseRate: CGFloat = breachPrep ? 10.5 : (fish.breaching ? 7.8 : (4.5 + turnEffort * 2.0))
        fish.phase += dt * phaseRate

        fish.nodes[0].x += cos(fish.angle) * fish.speed * dt
        fish.nodes[0].y += sin(fish.angle) * fish.speed * dt

        // Pitch foreshortening: when launching up or diving head-first into the water, spine compresses along travel axis!
        let effSegLen = fish.segLen * (1.0 - breachPitchTilt * 0.24)
        for i in 1..<fish.N {
            let prev = fish.nodes[i - 1], curr = fish.nodes[i]
            let dx = curr.x - prev.x, dy = curr.y - prev.y
            let d = max(0.0001, hypot(dx, dy))
            fish.nodes[i].x = prev.x + (dx / d) * effSegLen
            fish.nodes[i].y = prev.y + (dy / d) * effSegLen
        }

        for i in 0..<fish.N {
            let t = CGFloat(i) / CGFloat(fish.N - 1)
            let prev = fish.nodes[max(0, i - 1)]
            let next = fish.nodes[min(fish.N - 1, i + 1)]
            var tx = prev.x - next.x, ty = prev.y - next.y
            let len = max(0.0001, hypot(tx, ty))
            tx /= len; ty /= len
            let nx = -ty, ny = tx
            let amp = (1.1 + 20.0 * pow(t, 1.95)) * fish.scale * (breachPrep ? 1.35 : 1.0)
            var sway = sin(fish.phase - t * 6.5) * amp
            if breachAirArc > 0.01 {
                // Athletic mid-air C-curve body arch & twist as the Koi leaps through the air!
                sway = sway * 0.35 + fish.breachDir * sin(t * .pi) * breachAirArc * 28.0 * fish.scale
            }
            if config.musicReactive && abs(beatNod) > 0.01 && t < 0.28 {
                // Clean head-only turn (snout to gills) locked 1-to-1 with real beats
                let headFactor = pow(1.0 - (t / 0.28), 1.35)
                sway += beatNod * (16.0 * headFactor * fish.scale)
            }
            fish.renderNodes[i] = RenderNode(x: fish.nodes[i].x + nx * sway, y: fish.nodes[i].y + ny * sway, nx: nx, ny: ny)
        }

        for i in 0..<(fish.N - 1) {
            let a = fish.renderNodes[i], b = fish.renderNodes[i + 1]
            let abx = b.x - a.x, aby = b.y - a.y
            let lenSq = max(0.0001, abx * abx + aby * aby)
            fish.segs[i] = SpineSeg(ax: a.x, ay: a.y, abx: abx, aby: aby, invLenSq: 1.0 / lenSq, anx: a.nx, any: a.ny, dnx: b.nx - a.nx, dny: b.ny - a.ny)
        }

        // Barbel chain physics
        let r0 = fish.renderNodes[0], r1 = fish.renderNodes[1]
        var headTx = r0.x - r1.x, headTy = r0.y - r1.y
        let headLen = max(0.0001, hypot(headTx, headTy))
        headTx /= headLen; headTy /= headLen
        let headNx = -headTy, headNy = headTx
        let snoutEdgeW = bodyHalfWidth(0.025, fish.scale) + 1.6 * fish.scale
        let drag = exp(-5.8 * dt)
        let cheekNode = fish.renderNodes[4]
        let cheekRepelR = bodyHalfWidth(0.13, fish.scale) + 11.5 * fish.scale

        for bIdx in 0..<2 {
            let side: CGFloat = bIdx == 0 ? -1 : 1
            fish.barbels[bIdx][0].x = r0.x - headTx * (1.2 * fish.scale) + headNx * (side * snoutEdgeW)
            fish.barbels[bIdx][0].y = r0.y - headTy * (1.2 * fish.scale) + headNy * (side * snoutEdgeW)
            fish.barbels[bIdx][0].vx = 0; fish.barbels[bIdx][0].vy = 0

            for i in 1..<fish.barbels[bIdx].count {
                let prev = fish.barbels[bIdx][i - 1]
                var curr = fish.barbels[bIdx][i]
                let oldX = curr.x, oldY = curr.y
                let f = CGFloat(i) / CGFloat(fish.barbels[bIdx].count - 1)
                let splayOut = (1.15 - f * 0.55) * 145 * fish.scale
                let forwardAtBase = max(0, 0.45 - f) * 95 * fish.scale
                let backDrag = (f * 66 + fish.speed * 0.22 * f) * fish.scale
                let flutter = sin(fish.phase * 1.5 - CGFloat(i) * 0.72 + CGFloat(bIdx) * 1.9) * (32 * f * fish.scale)
                var fx = headNx * (side * splayOut + flutter) + headTx * (forwardAtBase - backDrag)
                var fy = headNy * (side * splayOut + flutter) + headTy * (forwardAtBase - backDrag)

                let cdx = curr.x - cheekNode.x, cdy = curr.y - cheekNode.y
                let cDist = max(0.001, hypot(cdx, cdy))
                if cDist < cheekRepelR {
                    let push = (1 - cDist / cheekRepelR) * 260 * fish.scale
                    fx += (cdx / cDist) * push; fy += (cdy / cDist) * push
                }

                curr.vx = (curr.vx + fx * dt) * drag
                curr.vy = (curr.vy + fy * dt) * drag
                curr.x += curr.vx * dt; curr.y += curr.vy * dt

                let dx = curr.x - prev.x, dy = curr.y - prev.y
                let d = max(0.0001, hypot(dx, dy))
                curr.x = prev.x + (dx / d) * fish.barbelSegLen
                curr.y = prev.y + (dy / d) * fish.barbelSegLen
                curr.vx = curr.vx * 0.40 + ((curr.x - oldX) / dt) * 0.60
                curr.vy = curr.vy * 0.40 + ((curr.y - oldY) / dt) * 0.60
                fish.barbels[bIdx][i] = curr
            }
        }

        fish.tailTimer -= dt
        if fish.tailTimer <= 0 && fish.z > 0.58 {
            let tail = fish.renderNodes[fish.N - 1]
            ripples.append(Ripple(x: tail.x, y: tail.y, r: 4, maxR: 42 * fish.scale, alpha: 0.24 + min(0.5, (fish.z - 0.58) * 0.7)))
            fish.tailTimer = CGFloat.random(in: 0.65...1.15)
        }
    }

    private func updateTurtle(_ t: inout Turtle, dt: CGFloat) {
        t.zTimer -= dt
        if t.zTimer <= 0 { t.targetZ = CGFloat.random(in: 0.25...0.75); t.zTimer = CGFloat.random(in: 6...11) }
        t.z += (t.targetZ - t.z) * min(1, dt * 0.35)
        t.wanderTimer -= dt
        if hypot(t.targetX - t.x, t.targetY - t.y) < 60 || t.wanderTimer <= 0 {
            t.targetX = CGFloat.random(in: 80...max(81, width - 80))
            t.targetY = CGFloat.random(in: 70...max(71, height - 70))
            t.wanderTimer = CGFloat.random(in: 6...11)
        }
        let diff = normalizeAngle(atan2(t.targetY - t.y, t.targetX - t.x) - t.angle)
        t.angle += max(-t.turnRate * dt, min(t.turnRate * dt, diff))
        t.headYaw = sin(t.phase * 0.45) * 0.16 + max(-0.25, min(0.25, diff * 0.5))
        t.phase += dt * 2.1
        let surge = 0.72 + 0.45 * max(0, sin(t.phase))
        t.x += cos(t.angle) * t.speed * surge * dt
        t.y += sin(t.angle) * t.speed * surge * dt
    }

    private func updateMinnows(dt: CGFloat) {
        let s = screenScale()
        for i in 0..<minnows.count {
            var m = minnows[i]
            var ax: CGFloat = 0, ay: CGFloat = 0, cx: CGFloat = 0, cy: CGFloat = 0, avx: CGFloat = 0, avy: CGFloat = 0
            var count: CGFloat = 0
            for j in 0..<minnows.count where i != j {
                let o = minnows[j]
                let dx = o.x - m.x, dy = o.y - m.y
                let d = max(0.01, hypot(dx, dy))
                if d < 95 * s {
                    cx += o.x; cy += o.y; avx += o.vx; avy += o.vy; count += 1
                    if d < 24 * s { ax -= (dx / d) * 150; ay -= (dy / d) * 150 }
                }
            }
            if count > 0 {
                ax += ((cx / count) - m.x) * 1.4 + ((avx / count) - m.vx) * 1.8
                ay += ((cy / count) - m.y) * 1.4 + ((avy / count) - m.vy) * 1.8
            }
            for k in 0..<fishes.count {
                let kh = fishes[k].renderNodes[0]
                let dx = m.x - kh.x, dy = m.y - kh.y
                let d = max(1, hypot(dx, dy))
                if d < 95 * s { ax += (dx / d) * 260; ay += (dy / d) * 260; m.boost = min(1, m.boost + dt * 3) }
            }
            let pad: CGFloat = 45
            if m.x < pad { ax += 190 } else if m.x > width - pad { ax -= 190 }
            if m.y < pad { ay += 190 } else if m.y > height - pad { ay -= 190 }
            m.vx += ax * dt; m.vy += ay * dt
            m.boost = max(0, m.boost - dt * 1.6)
            let targetSpd = (62 + m.boost * 80) * s
            let spd = max(1, hypot(m.vx, m.vy))
            m.vx = (m.vx / spd) * targetSpd; m.vy = (m.vy / spd) * targetSpd
            m.x += m.vx * dt; m.y += m.vy * dt
            m.angle = atan2(m.vy, m.vx)
            m.phase += dt * (11 + m.boost * 9)
            m.nodes[0] = Vec2(x: m.x, y: m.y)
            for k in 1..<m.nodes.count {
                let prev = m.nodes[k - 1], curr = m.nodes[k]
                let dx = curr.x - prev.x, dy = curr.y - prev.y
                let d = max(0.01, hypot(dx, dy))
                m.nodes[k] = Vec2(x: prev.x + (dx / d) * 4.8 * s, y: prev.y + (dy / d) * 4.8 * s)
            }
            minnows[i] = m
        }
    }

    private func updateDragonfly(_ df: inout Dragonfly, dt: CGFloat) {
        df.wingPhase += dt * (df.perched ? 6 : 42)
        df.stateTimer -= dt
        if df.perched {
            if df.perchPadIdx >= 0 && df.perchPadIdx < lotusPads.count {
                let pad = lotusPads[df.perchPadIdx]
                df.x = pad.x + sin(time * 0.55 + pad.phase) * 2.5 - 10
                df.y = pad.y + cos(time * 0.45 + pad.phase) * 2.0 - 8
                df.z += (1.06 - df.z) * min(1, dt * 6)
            }
            let spooked = fishes.contains { hypot($0.nodes[0].x - df.x, $0.nodes[0].y - df.y) < 110 }
            if df.stateTimer <= 0 || spooked {
                df.perched = false; df.stateTimer = CGFloat.random(in: 4.0...8.5)
                df.targetX = CGFloat.random(in: 80...max(81, width - 80))
                df.targetY = CGFloat.random(in: 80...max(81, height - 80))
                ripples.append(Ripple(x: df.x, y: df.y, r: 2, maxR: 22, alpha: 0.45))
            }
        } else {
            df.z += (1.72 - df.z) * min(1, dt * 2.5)
            let dx = df.targetX - df.x, dy = df.targetY - df.y
            let dist = hypot(dx, dy)
            if dist < 28 {
                if df.stateTimer <= 0 && !lotusPads.isEmpty && Bool.random() {
                    let pIdx = Int.random(in: 0..<lotusPads.count)
                    df.perchPadIdx = pIdx
                    df.targetX = lotusPads[pIdx].x - 10; df.targetY = lotusPads[pIdx].y - 8
                    if hypot(df.targetX - df.x, df.targetY - df.y) < 30 {
                        df.perched = true; df.stateTimer = CGFloat.random(in: 2.8...6.3)
                    }
                } else {
                    df.targetX = CGFloat.random(in: 70...max(71, width - 70))
                    df.targetY = CGFloat.random(in: 70...max(71, height - 70))
                }
            }
            let diff = normalizeAngle(atan2(dy, dx) - df.angle)
            df.angle += max(-4.5 * dt, min(4.5 * dt, diff))
            let spd: CGFloat = dist < 80 ? 68 : 138
            df.x += cos(df.angle) * spd * dt; df.y += sin(df.angle) * spd * dt
        }
    }

    private func updateFrog(_ fr: inout Frog, dt: CGFloat) {
        guard !lotusPads.isEmpty else { return }
        let s = screenScale()

        switch fr.state {
        case .perched:
            let pad = lotusPads[fr.padIdx % lotusPads.count]
            fr.x = pad.x + sin(time * 0.55 + pad.phase) * 2.5 + 10
            fr.y = pad.y + cos(time * 0.45 + pad.phase) * 2.0 + 8
            fr.z = 1.03
            fr.restTimer -= dt
            fr.lookTimer -= dt
            if fr.lookTimer <= 0 {
                fr.lookAngle = fr.angle + CGFloat.random(in: -0.9...0.9)
                fr.lookTimer = CGFloat.random(in: 2.0...4.5)
            }
            // Gently turn head/body while perched
            let lookDiff = normalizeAngle(fr.lookAngle - fr.angle)
            fr.angle += lookDiff * min(1.0, dt * 3.5)

            let startled = fishes.contains { hypot($0.nodes[0].x - fr.x, $0.nodes[0].y - fr.y) < 98 }
            if startled || fr.restTimer <= 0 {
                let nextIdx = (fr.padIdx + Int.random(in: 1..<max(2, lotusPads.count))) % lotusPads.count
                fr.targetPadIdx = nextIdx
                let tPad = lotusPads[nextIdx]
                let aimAng = atan2((tPad.y + 8) - fr.y, (tPad.x + 10) - fr.x)
                fr.angle = aimAng
                // Leap off the lily pad in a realistic arc into open water past the pad's edge!
                let leapDist = max(pad.r + 36 * s, 72 * s)
                fr.jumpStart = CGPoint(x: fr.x, y: fr.y)
                fr.jumpEnd = CGPoint(
                    x: max(30, min(width - 30, fr.x + cos(aimAng) * leapDist)),
                    y: max(30, min(height - 30, fr.y + sin(aimAng) * leapDist))
                )
                fr.jumpProgress = 0
                fr.state = .leaping
                ripples.append(Ripple(x: fr.x, y: fr.y, r: 4, maxR: 26, alpha: 0.48))
            }

        case .leaping:
            fr.jumpProgress += dt * 2.15
            let p = min(1.0, fr.jumpProgress)
            fr.x = fr.jumpStart.x + (fr.jumpEnd.x - fr.jumpStart.x) * p
            fr.y = fr.jumpStart.y + (fr.jumpEnd.y - fr.jumpStart.y) * p
            // Smooth parabolic jump arc above water!
            fr.z = 1.02 + sin(p * .pi) * 0.42
            if p >= 1.0 {
                // Splash down into the water and begin realistic breaststroke swimming!
                fr.state = .swimming
                fr.z = 0.85
                fr.swimPhase = 0.2
                fr.speed = 46 * s
                spawnSplashBurst(x: fr.x, y: fr.y, count: 7, power: 0.58)
            }

        case .swimming:
            let tPad = lotusPads[fr.targetPadIdx % lotusPads.count]
            let goalX = tPad.x + 10, goalY = tPad.y + 8
            let dx = goalX - fr.x, dy = goalY - fr.y
            let dist = hypot(dx, dy)
            let desiredAng = atan2(dy, dx)
            let angDiff = normalizeAngle(desiredAng - fr.angle)
            fr.angle += max(-2.4 * dt, min(2.4 * dt, angDiff))

            // Authentic frog breaststroke: crisp kick pulse followed by smooth water glide!
            let prevSin = sin(fr.swimPhase)
            fr.swimPhase += dt * 4.2
            let curSin = sin(fr.swimPhase)
            let kickPower = max(0, curSin)
            let targetSpd = (18 + 72 * pow(kickPower, 1.4)) * s
            fr.speed += (targetSpd - fr.speed) * min(1.0, dt * (kickPower > 0.2 ? 9.0 : 2.6))
            fr.x += cos(fr.angle) * fr.speed * dt
            fr.y += sin(fr.angle) * fr.speed * dt
            // Gently bob just beneath/at the water surface as it kicks and glides
            fr.z = 0.82 + 0.08 * kickPower

            // Wake ripple on every strong hind-leg kick!
            if prevSin <= 0.85 && curSin > 0.85 {
                let rearX = fr.x - cos(fr.angle) * 14 * s
                let rearY = fr.y - sin(fr.angle) * 14 * s
                ripples.append(Ripple(x: rearX, y: rearY, r: 3, maxR: 28, alpha: 0.48))
            }

            // Reached the edge of the target lily pad -> hop up onto it!
            if dist < tPad.r + 14 * s {
                fr.jumpStart = CGPoint(x: fr.x, y: fr.y)
                fr.jumpEnd = CGPoint(x: goalX, y: goalY)
                fr.jumpProgress = 0
                fr.state = .climbing
                ripples.append(Ripple(x: fr.x, y: fr.y, r: 3, maxR: 26, alpha: 0.54))
            }

        case .climbing:
            fr.jumpProgress += dt * 2.8
            let p = min(1.0, fr.jumpProgress)
            fr.x = fr.jumpStart.x + (fr.jumpEnd.x - fr.jumpStart.x) * p
            fr.y = fr.jumpStart.y + (fr.jumpEnd.y - fr.jumpStart.y) * p
            fr.z = 0.90 + sin(p * .pi) * 0.28 + p * 0.13
            if p >= 1.0 {
                fr.state = .perched
                fr.padIdx = fr.targetPadIdx
                fr.z = 1.03
                fr.restTimer = CGFloat.random(in: 7.5...16.0)
                fr.lookAngle = fr.angle
                fr.lookTimer = CGFloat.random(in: 1.5...3.5)
            }
        }
    }

    private func updatePlantsAndBubbles(dt: CGFloat) {
        for i in 0..<plants.count {
            plants[i].bubbleTimer -= dt
            if plants[i].bubbleTimer <= 0 {
                let pl = plants[i]
                if let fr = pl.fronds.randomElement() {
                    let ang = fr.ang + sin(time * 1.15 + pl.phase) * 0.24
                    let rOff = fr.len * CGFloat.random(in: 0.55...0.95)
                    bubbles.append(Bubble(x: pl.x + cos(ang) * rOff, y: pl.y + sin(ang) * rOff, z: 0.08, vz: CGFloat.random(in: 0.26...0.42), wigglePhase: CGFloat.random(in: 0...(2 * .pi)), wiggleAmp: CGFloat.random(in: 5...11)))
                }
                plants[i].bubbleTimer = CGFloat.random(in: 0.8...2.7)
            }
        }
        var idx = bubbles.count - 1
        while idx >= 0 {
            bubbles[idx].z += bubbles[idx].vz * dt
            bubbles[idx].wigglePhase += dt * 4.5
            bubbles[idx].x += cos(bubbles[idx].wigglePhase) * bubbles[idx].wiggleAmp * dt
            bubbles[idx].y += sin(bubbles[idx].wigglePhase * 0.8) * bubbles[idx].wiggleAmp * dt
            if bubbles[idx].z >= 1.0 {
                ripples.append(Ripple(x: bubbles[idx].x, y: bubbles[idx].y, r: 2, maxR: CGFloat.random(in: 18...30), alpha: 0.64))
                bubbles.remove(at: idx)
            }
            idx -= 1
        }
    }

    private func updateSplashesAndLeaves(dt: CGFloat) {
        let actSeason = activeSeason()
        var sIdx = splashes.count - 1
        while sIdx >= 0 {
            splashes[sIdx].x += splashes[sIdx].vx * dt
            splashes[sIdx].y += splashes[sIdx].vy * dt
            splashes[sIdx].vx *= exp(-1.4 * dt)
            splashes[sIdx].vy *= exp(-1.4 * dt)
            splashes[sIdx].vz -= 4.2 * dt
            splashes[sIdx].z += splashes[sIdx].vz * dt
            if splashes[sIdx].z <= 1.0 && splashes[sIdx].vz < 0 {
                let sp = splashes[sIdx]
                if sp.big || Bool.random() {
                    ripples.append(Ripple(x: sp.x, y: sp.y, r: 1.5, maxR: sp.big ? 24 : 14, alpha: sp.big ? 0.72 : 0.50))
                }
                splashes.remove(at: sIdx)
            }
            sIdx -= 1
        }

        leafSpawnTimer -= dt
        let maxLeaves = actSeason == "winter" ? 12 : (actSeason == "summer" ? 4 : 8)
        let spawnGap: CGFloat = actSeason == "winter" ? 0.55 : (actSeason == "summer" ? 4.5 : 2.1)
        if leafSpawnTimer <= 0 && leaves.count < maxLeaves {
            spawnLeaf(forceVisible: false)
            leafSpawnTimer = spawnGap + CGFloat.random(in: 0...spawnGap)
        }

        var lIdx = leaves.count - 1
        while lIdx >= 0 {
            var lf = leaves[lIdx]
            lf.swayPhase += dt * (lf.floating ? 1.1 : 3.4)
            lf.rot += lf.rotSpd * dt
            if !lf.floating {
                // Natural peel-off acceleration: starts softly from branch tip, then catches the breeze & flutters down
                lf.age += dt
                let peel = min(1.0, lf.age / 0.75)
                let ease = peel * peel * (3.0 - 2.0 * peel)
                lf.z -= dt * (lf.isSnow ? 0.44 : 0.28) * (0.35 + 0.65 * ease)
                lf.tumble += lf.tumbleSpd * (0.45 + 0.55 * ease) * dt
                lf.x += (lf.vx * (0.25 + 0.75 * ease) + sin(lf.swayPhase) * 32 * ease) * dt
                lf.y += (lf.vy * (0.25 + 0.75 * ease) + cos(lf.swayPhase * 0.82) * 16 * ease) * dt
                if lf.z <= 1.0 {
                    lf.z = 1.0; lf.floating = true; lf.age = 0; lf.rotSpd *= 0.18
                    ripples.append(Ripple(x: lf.x, y: lf.y, r: 3, maxR: lf.isSnow ? 20 : 42, alpha: lf.isSnow ? 0.58 : 0.85))
                    if !lf.isSnow { ripples.append(Ripple(x: lf.x, y: lf.y, r: 0.5, maxR: 25, alpha: 0.62)) }
                }
                leaves[lIdx] = lf
            } else {
                lf.age += dt
                lf.x += (lf.vx * 0.42 + sin(lf.swayPhase) * 3.5) * dt
                lf.y += (lf.vy * 0.42 + cos(lf.swayPhase * 0.7) * 2.5) * dt
                if lf.age > lf.maxAge || lf.x < -90 || lf.x > width + 90 || lf.y < -90 || lf.y > height + 90 {
                    leaves.remove(at: lIdx)
                } else {
                    leaves[lIdx] = lf
                }
            }
            lIdx -= 1
        }

        for i in 0..<fireflies.count {
            fireflies[i].phase += dt * fireflies[i].blinkSpd
            fireflies[i].x += (fireflies[i].vx + sin(time * 0.9 + CGFloat(i)) * 10) * dt
            fireflies[i].y += (fireflies[i].vy + cos(time * 0.7 + CGFloat(i) * 1.3) * 10) * dt
            if fireflies[i].x < 10 { fireflies[i].x = width - 10 } else if fireflies[i].x > width - 10 { fireflies[i].x = 10 }
            if fireflies[i].y < 10 { fireflies[i].y = height - 10 } else if fireflies[i].y > height - 10 { fireflies[i].y = 10 }
        }
    }

    // MARK: - Samplers

    private func projectToSpine(_ fish: Koi, _ px: CGFloat, _ py: CGFloat) -> (t: CGFloat, lat: CGFloat, dist: CGFloat, nx: CGFloat, ny: CGFloat) {
        let nSeg = fish.N - 1
        var bestDistSq: CGFloat = .infinity
        var bestIdx = 0
        var bestU: CGFloat = 0
        for i in 0..<nSeg {
            let s = fish.segs[i]
            var u = ((px - s.ax) * s.abx + (py - s.ay) * s.aby) * s.invLenSq
            if u < 0 { u = 0 } else if u > 1 { u = 1 }
            let dx = px - (s.ax + s.abx * u), dy = py - (s.ay + s.aby * u)
            let dSq = dx * dx + dy * dy
            if dSq < bestDistSq { bestDistSq = dSq; bestIdx = i; bestU = u }
        }
        let s = fish.segs[bestIdx]
        let dx = px - (s.ax + s.abx * bestU), dy = py - (s.ay + s.aby * bestU)
        var nx = s.anx + s.dnx * bestU, ny = s.any + s.dny * bestU
        let nLen = max(0.0001, hypot(nx, ny))
        nx /= nLen; ny /= nLen
        return ((CGFloat(bestIdx) + bestU) / CGFloat(nSeg), dx * nx + dy * ny, sqrt(bestDistSq), nx, ny)
    }

    // 0: white, 1: red, 2: black, 3: gold, 4: geminiBlue, 5: geminiViolet, 6: geminiCyan, 7: claudeTerracotta, 8: claudeCream
    private func getPigment(_ fish: Koi, _ t: CGFloat, _ normLat: CGFloat) -> Int {
        if fish.errorFlash > 0.25 { return 1 }
        if fish.variety == .ogon { return 3 }
        let sd = fish.seed
        let n1 = fbm(t * 4.3 + sd, normLat * 1.5 + sd * 0.7)
        let n2 = fbm(t * 5.8 - sd * 1.3, normLat * 1.9 + sd * 1.1)
        let n3 = fbm(t * 8.8 + sd * 2.1, normLat * 2.7 - sd * 0.9)
        switch fish.variety {
        case .showa:
            if n1 > 0.55 { return 2 }
            if n2 > 0.48 { return 1 }
            if n3 > 0.66 && t > 0.14 { return 2 }
            return 0
        case .utsuri:
            return (n1 > 0.48 || (n2 > 0.65 && t > 0.10)) ? 2 : 0
        case .kumonryu:
            return (n1 > 0.62 || (abs(normLat) > 0.64 && n2 > 0.56)) ? 0 : 2
        case .sanke:
            if n3 > 0.66 && t > 0.15 && t < 0.74 { return 2 }
            return n2 > 0.46 ? 1 : 0
        case .ogon:
            return 3
        case .gemini:
            // Crisp 4-pointed Gemini sparkle star logo on the shoulders (t ≈ 0.34, normLat ≈ 0)
            let gx = (t - 0.34) / 0.125
            let gy = normLat / 0.68
            let astroid = pow(abs(gx), 0.58) + pow(abs(gy), 0.58)
            if astroid < 0.88 { return 6 } // Bright cyan-white Gemini 4-point star!
            return (t + n1 * 0.28) < 0.50 ? 4 : 5
        case .claude:
            // Crisp Claude 8-ray sunburst/asterisk star logo on the shoulders (t ≈ 0.34, normLat ≈ 0)
            let cx = (t - 0.34) / 0.12
            let cy = normLat / 0.66
            let cr = hypot(cx, cy)
            if cr < 0.92 {
                let ang = atan2(cy, cx)
                let ray = abs(sin(ang * 4.0)) // 8 radiating arms!
                if cr < 0.24 || ray < 0.22 { return 8 } // Bright warm cream Claude starburst!
            }
            return n1 > 0.32 ? 7 : 8
        case .trashEater:
            // Bold obsidian & bronze-gold Koi
            return n1 > 0.54 ? 3 : 2
        }
    }

    private func sampleKoi(_ fish: Koi, _ px: CGFloat, _ py: CGFloat, shadowOnly: Bool) -> SampleHit? {
        let proj = projectToSpine(fish, px, py)
        let t = proj.t, lat = proj.lat, absLat = abs(lat), s = fish.scale
        if proj.dist > 78 * s { return nil }

        if t >= 0 && t <= 0.76 {
            let bw = bodyHalfWidth(t, s)
            if absLat <= bw {
                if shadowOnly { return .shadow(alpha: 0.78) }
                let normLat = bw > 0.01 ? lat / bw : 0
                let z = sqrt(max(0.02, 1.0 - normLat * normLat))

                let eyeT: CGFloat = 0.082
                let eyeLat = bodyHalfWidth(eyeT, s) * 0.80
                let dEye = hypot((t - eyeT) * 265 * s, absLat - eyeLat)
                if dEye < 3.6 * s {
                    let glint = hypot((t - (eyeT - 0.005)) * 265 * s, absLat - (eyeLat - 0.9 * s)) < 1.25 * s
                    return .eye(glint: glint, rim: dEye > 2.6 * s, depthZ: fish.z)
                }

                var shade = (proj.nx * normLat * 0.9) * -0.50 + (proj.ny * normLat * 0.9) * -0.56 + z * 0.66
                shade = max(0.14, min(1.0, 0.30 + shade * 0.76))
                let caustic = sin(px * 0.08 + time * 1.4 + sin(py * 0.07 - time)) * cos(py * 0.10 + time * 0.9)
                if caustic > 0.55 && z > 0.55 { shade = min(1.0, shade + (caustic - 0.55) * 0.35 * min(1.0, fish.z)) }

                let gillCurve = 0.188 - 0.032 * (1 - normLat * normLat)
                let isGill = abs(t - gillCurve) < 0.0075 && absLat > bw * 0.28
                if isGill { shade *= 0.55 }

                var isScaleEdge = false
                if t > 0.195 && t < 0.74 {
                    let scaleRow = t * 48
                    let stagger: CGFloat = (Int(floor(scaleRow)) % 2 == 0) ? 0 : 0.5
                    let su = scaleRow - floor(scaleRow)
                    let sv = (normLat * 5.0 + 12 + stagger).truncatingRemainder(dividingBy: 1.0)
                    let dScale = hypot(su - 0.5, sv - 0.5)
                    if dScale > 0.37 && dScale < 0.52 { shade = max(0.12, shade - 0.12); isScaleEdge = true }
                    else if dScale < 0.20 { shade = min(1.0, shade + 0.08) }
                }

                var isDorsal = false
                if t >= 0.29 && t <= 0.66 {
                    let df = (t - 0.29) / 0.37
                    let dorsalOffset = sin(fish.phase - t * 7.0 - 1.0) * (4.8 * s * sin(df * .pi))
                    let dorsalThick = (2.4 * s) * (0.4 + 0.6 * sin(df * .pi))
                    if abs(lat - dorsalOffset) < dorsalThick { isDorsal = true; shade = min(1.0, shade + 0.16) }
                    else if abs(lat - (dorsalOffset + 3.0 * s)) < dorsalThick * 0.9 { shade *= 0.78 }
                }

                return .body(shade: shade, pigment: getPigment(fish, t, normLat), isDorsal: isDorsal, isScaleEdge: isScaleEdge, isGill: isGill, depthZ: fish.z)
            }
        }

        // Physics-driven Barbels
        let headNode = fish.renderNodes[0]
        if hypot(px - headNode.x, py - headNode.y) < 76 * s {
            var bestBDistSq: CGFloat = .infinity, bestBU: CGFloat = 0, bestBAng: CGFloat = 0
            for bIdx in 0..<2 {
                let chain = fish.barbels[bIdx]
                for i in 0..<(chain.count - 1) {
                    let a = chain[i], b = chain[i + 1]
                    let abx = b.x - a.x, aby = b.y - a.y
                    let lenSq = max(0.0001, abx * abx + aby * aby)
                    var u = ((px - a.x) * abx + (py - a.y) * aby) / lenSq
                    if u < 0 { u = 0 } else if u > 1 { u = 1 }
                    let dx = px - (a.x + abx * u), dy = py - (a.y + aby * u)
                    let dSq = dx * dx + dy * dy
                    if dSq < bestBDistSq { bestBDistSq = dSq; bestBU = (CGFloat(i) + u) / CGFloat(chain.count - 1); bestBAng = atan2(aby, abx) }
                }
            }
            let thick = (3.1 - bestBU * 1.4) * s
            if bestBDistSq <= thick * thick {
                return shadowOnly ? .shadow(alpha: 0.25 * (1 - bestBU * 0.55)) : .barbel(u: bestBU, ang: bestBAng, variety: fish.variety, depthZ: fish.z)
            }
        }

        // Caudal Fin
        if t >= 0.71 && t <= 1.0 {
            let v = (t - 0.71) / 0.29
            let tailWhip = sin(fish.phase - 6.5 - v * 2.5) * (9.5 * v * v * s)
            let absEff = abs(lat - tailWhip)
            let tailOuter = (3.8 + 31.5 * pow(v, 0.76)) * s
            let notchInner: CGFloat = v > 0.36 ? pow((v - 0.36) / 0.64, 1.15) * 18.0 * s : -1
            if absEff <= tailOuter && absEff >= notchInner {
                if shadowOnly { return .shadow(alpha: 0.32 * (1 - v * 0.55)) }
                let rayFrac = absEff / max(0.01, tailOuter)
                let ray = 0.5 + 0.5 * sin(rayFrac * 26 - v * 3.0)
                let spine = rayFrac > 0.88 && v < 0.78
                let density = spine ? 0.92 : (1 - v * 0.64) * (0.36 + 0.64 * ray)
                let dark = (fish.variety == .showa || fish.variety == .utsuri || fish.variety == .kumonryu) && v < 0.58 && sin(rayFrac * 10 + fish.seed) > 0.52
                return .fin(density: density, dark: dark, spine: spine, depthZ: fish.z)
            }
        }

        // Pectoral Fins
        let turnFlare = max(-0.04, min(0.04, fish.turnVel * 0.025))
        let rowL = sin(fish.phase * 0.60) * 0.022 + turnFlare
        let rowR = sin(fish.phase * 0.60 + 0.38) * 0.022 - turnFlare
        let tStartP = 0.18 + (lat > 0 ? rowL : rowR)
        let tEndP = 0.46 + (lat > 0 ? rowL : rowR)
        if t >= tStartP && t <= tEndP {
            let f = (t - tStartP) / (tEndP - tStartP)
            let bw = bodyHalfWidth(t, s)
            let reach = 35.0 * s * sin(pow(f, 0.58) * .pi)
            let innerCut = f > 0.55 ? bw + ((f - 0.55) / 0.45) * 12 * s : bw * 0.88
            if absLat > innerCut && absLat <= bw + reach {
                if shadowOnly { return .shadow(alpha: 0.30) }
                let distFromBody = (absLat - bw) / max(0.01, reach)
                let ray = 0.5 + 0.5 * sin(f * 22 - distFromBody * 5.2)
                let spine = f < 0.13 && distFromBody < 0.92
                let density = spine ? 0.95 : (1 - distFromBody * 0.62) * (0.38 + 0.62 * ray)
                let dark = (fish.variety == .showa || fish.variety == .utsuri || fish.variety == .kumonryu) && distFromBody < 0.45 && f > 0.10 && f < 0.72
                return .fin(density: density, dark: dark, spine: spine, depthZ: fish.z)
            }
        }

        // Pelvic Fins
        if t >= 0.46 && t <= 0.62 {
            let f = (t - 0.46) / 0.16
            let bw = bodyHalfWidth(t, s)
            let reach = 15.0 * s * sin(pow(f, 0.68) * .pi)
            if absLat > bw * 0.88 && absLat <= bw + reach {
                if shadowOnly { return .shadow(alpha: 0.22) }
                let distFromBody = (absLat - bw) / max(0.01, reach)
                return .fin(density: (1 - distFromBody * 0.68) * 0.65, dark: false, spine: false, depthZ: fish.z)
            }
        }
        return nil
    }

    private func sampleTurtle(_ tr: Turtle, _ px: CGFloat, _ py: CGFloat, shadowOnly: Bool) -> SampleHit? {
        let s = tr.scale * (0.86 + tr.z * 0.18)
        let dx = px - tr.x, dy = py - tr.y
        if dx * dx + dy * dy > (54 * s) * (54 * s) { return nil }
        let c = cos(-tr.angle), sn = sin(-tr.angle)
        let lx = (dx * c - dy * sn) / s, ly = (dx * sn + dy * c) / s

        let sx = lx / 24.5, sy = ly / 19.5, r2 = sx * sx + sy * sy
        if r2 <= 1.0 {
            if shadowOnly { return .shadow(alpha: 0.82) }
            let z = sqrt(max(0.02, 1.0 - r2))
            let rim = r2 > 0.76
            let scuteRing = abs(sqrt(r2) - 0.45) < 0.055
            let scuteSpoke = abs(sin(atan2(ly, lx) * 5)) > 0.93 && r2 > 0.20
            var shade = 0.36 + z * 0.58 - sx * 0.18 - sy * 0.18
            if scuteRing || scuteSpoke { shade *= 0.62 }
            if abs(ly) < 2.0 && abs(lx) < 18 { shade = min(1.0, shade + 0.15) }
            return .turtleShell(shade: max(0.18, min(1, shade)), rim: rim, depthZ: tr.z)
        }

        let hx = lx - 27.5, hy = ly - sin(tr.headYaw) * 6.0
        if (hx * hx) / (9.5 * 9.5) + (hy * hy) / (6.2 * 6.2) <= 1.0 && lx > 20 {
            if shadowOnly { return .shadow(alpha: 0.65) }
            if hypot(hx - 2.5, abs(hy) - 3.6) < 1.8 { return .eye(glint: false, rim: false, depthZ: tr.z) }
            return .turtleSkin(shade: 0.65 - (hx * hx + hy * hy) / 140, depthZ: tr.z)
        }

        let paddleF = sin(tr.phase) * 0.48, paddleB = sin(tr.phase + .pi * 0.7) * 0.42
        let flippers: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (12, -16, -1.15 - paddleF, 13.5, 5.2),
            (12,  16,  1.15 + paddleF, 13.5, 5.2),
            (-14, -14, -2.25 + paddleB, 11.0, 4.5),
            (-14,  14,  2.25 - paddleB, 11.0, 4.5)
        ]
        for fl in flippers {
            let fx = lx - fl.0, fy = ly - fl.1
            let cf = cos(-fl.2), sf = sin(-fl.2)
            let ux = (fx * cf - fy * sf - fl.3 * 0.45) / fl.3
            let uy = (fx * sf + fy * cf) / fl.4
            if ux * ux + uy * uy <= 1.0 {
                return shadowOnly ? .shadow(alpha: 0.45) : .turtleSkin(shade: 0.48 + (1 - (ux * ux + uy * uy)) * 0.35, depthZ: tr.z)
            }
        }
        if lx < -22 && lx > -32 && abs(ly) < (1 - (-lx - 22) / 10) * 3.2 {
            return shadowOnly ? .shadow(alpha: 0.35) : .turtleSkin(shade: 0.42, depthZ: tr.z)
        }
        return nil
    }

    // Detailed top-down Pond Frog: pear-shaped torso, bulging eyes, front arms & folded/kicking hind legs
    private func sampleFrog(_ fr: Frog, _ px: CGFloat, _ py: CGFloat) -> (part: Int, shade: CGFloat)? {
        // part: 0 = skin, 1 = dark spot/ridge, 2 = eye iris, 3 = eye pupil
        let s = 1.32 * screenScale()
        let dx = px - fr.x, dy = py - fr.y
        if dx * dx + dy * dy > (36 * s) * (36 * s) { return nil }
        let c = cos(-fr.angle), sn = sin(-fr.angle)
        let lx = (dx * c - dy * sn) / s
        let ly = (dx * sn + dy * c) / s
        let absY = abs(ly)

        // 1. Bulging Frog Eyes (prominent on top-front sides of head)
        let dEye = hypot(lx - 8.2, absY - 5.4)
        if dEye < 3.1 {
            if dEye < 1.55 { return (3, 1.0) } // Pupil
            return (2, 1.0)                    // Golden/white iris ring
        }

        // 2. Sculpted Pear-Shaped Torso (pointed snout +14, wide back -2, rounded rump -13)
        if lx >= -13.5 && lx <= 14.5 {
            let u = (14.5 - lx) / 28.0 // 0 at snout -> 1 at rump
            let halfW: CGFloat
            if u < 0.28 {
                halfW = 9.5 * pow(sin((u / 0.28) * (.pi / 2)), 0.62)
            } else {
                let r = (u - 0.28) / 0.72
                halfW = 10.6 * sin(pow(1 - r * 0.86, 0.78) * (.pi / 2))
            }
            if absY <= halfW {
                let z = sqrt(max(0.05, 1.0 - pow(absY / max(0.1, halfW), 2)))
                let isStripe = absY < 1.4 && lx < 7 && lx > -11
                let isSpot = hypot(lx + 1.5, absY - 4.8) < 2.4 || hypot(lx + 7.0, absY - 3.6) < 2.1
                let shade = max(0.25, min(1.0, 0.35 + z * 0.62 - (ly / max(1, halfW)) * 0.16))
                return ((isSpot || isStripe) ? 1 : 0, shade)
            }
        }

        // 3. Front Webbed Forearms
        let fAx = lx - 4.2, fAy = absY - 10.5
        if (fAx * fAx) / (5.2 * 5.2) + (fAy * fAy) / (3.2 * 3.2) <= 1.0 {
            return (0, 0.62)
        }

        // 4. Articulated Hind Legs (folded Z-shape when perched, fully extended mid-leap, rhythmic breaststroke kick when swimming!)
        let kick: CGFloat
        switch fr.state {
        case .perched: kick = 0.0
        case .leaping: kick = sin(min(1.0, fr.jumpProgress) * .pi) * 1.15
        case .climbing: kick = (1.0 - min(1.0, fr.jumpProgress)) * 0.75
        case .swimming: kick = pow(max(0, sin(fr.swimPhase)), 0.85) * 1.05
        }
        // Upper thigh
        let thighX = lx - (-6.8 - kick * 4.5)
        let thighY = absY - (10.5 + kick * 2.0)
        let tAng: CGFloat = -0.55 - kick * 0.75
        let tc = cos(-tAng), ts = sin(-tAng)
        let tux = (thighX * tc - thighY * ts) / 8.2
        let tuy = (thighX * ts + thighY * tc) / 4.2
        if tux * tux + tuy * tuy <= 1.0 {
            return (1, 0.58 + (1 - (tux * tux + tuy * tuy)) * 0.3)
        }

        // Lower calf & webbed foot
        let footX = lx - (-11.5 - kick * 13.5)
        let footY = absY - (9.2 + kick * 5.8)
        let fAng: CGFloat = 0.65 - kick * 1.15
        let fc = cos(-fAng), fs = sin(-fAng)
        let fux = (footX * fc - footY * fs) / (7.8 + kick * 3.5)
        let fuy = (footX * fs + footY * fc) / 3.4
        if fux * fux + fuy * fuy <= 1.0 {
            return (0, 0.52 + (1 - (fux * fux + fuy * fuy)) * 0.25)
        }

        return nil
    }

    private func sampleMinnow(_ m: Minnow, _ px: CGFloat, _ py: CGFloat, shadowOnly: Bool) -> SampleHit? {
        let s = screenScale()
        var bestD2: CGFloat = .infinity, bestT: CGFloat = 0
        for i in 0..<(m.nodes.count - 1) {
            let a = m.nodes[i], b = m.nodes[i + 1]
            let abx = b.x - a.x, aby = b.y - a.y
            let lenSq = max(0.001, abx * abx + aby * aby)
            var u = ((px - a.x) * abx + (py - a.y) * aby) / lenSq
            if u < 0 { u = 0 } else if u > 1 { u = 1 }
            let dx = px - (a.x + abx * u), dy = py - (a.y + aby * u)
            let d2 = dx * dx + dy * dy
            if d2 < bestD2 { bestD2 = d2; bestT = (CGFloat(i) + u) / CGFloat(m.nodes.count - 1) }
        }
        let w = (bestT < 0.72 ? sin(pow(bestT / 0.72, 0.7) * .pi) * 3.8 + 0.9 : 3.0 * ((bestT - 0.72) / 0.28)) * s
        if bestD2 <= w * w { return shadowOnly ? .shadow(alpha: 0.35) : .minnow(t: bestT, depthZ: m.z) }
        return nil
    }

    @inline(__always)
    private func sampleLotus(_ px: CGFloat, _ py: CGFloat) -> (flower: Bool, norm: CGFloat, vein: Bool)? {
        for lp in lotusFrameCache {
            let dx = px - lp.x
            if abs(dx) > lp.r { continue }
            let dy = py - lp.y
            if abs(dy) > lp.r { continue }
            let d2 = dx * dx + dy * dy
            if d2 <= lp.r2 {
                let d = sqrt(d2)
                let ang = atan2(dy, dx)
                if abs(normalizeAngle(ang - lp.notch)) < 0.28 { return nil }
                let normR = d / lp.r
                if lp.flower && d < lp.r * 0.24 {
                    let petal = sin(ang * 6) * 0.5 + 0.5
                    if d < lp.r * (0.16 + petal * 0.08) { return (true, d / (lp.r * 0.24), false) }
                }
                let vein = abs(sin(ang * 7)) > 0.94 && normR > 0.18
                return (false, normR, vein)
            }
        }
        return nil
    }

    @inline(__always)
    private func sampleLotusShadow(_ px: CGFloat, _ py: CGFloat) -> Bool {
        for lp in lotusFrameCache {
            let dx = px - (lp.x + 20)
            if abs(dx) > lp.r { continue }
            let dy = py - (lp.y + 18)
            if abs(dy) > lp.r { continue }
            if dx * dx + dy * dy <= lp.r2 { return true }
        }
        return false
    }

    @inline(__always)
    private func samplePlant(_ px: CGFloat, _ py: CGFloat) -> (tip: CGFloat, ch: Character)? {
        for pl in plants {
            let maxR = pl.r + 10
            let dx = px - pl.x
            if abs(dx) > maxR { continue }
            let dy = py - pl.y
            if abs(dy) > maxR { continue }
            let d2 = dx * dx + dy * dy
            if d2 > maxR * maxR { continue }
            if d2 < 25.0 { return (0.15, "%") }
            let sway = sin(time * 1.15 + pl.phase) * 0.24
            for (f, fr) in pl.fronds.enumerated() {
                let ang = fr.ang + sway * (0.6 + 0.4 * sin(CGFloat(f) + time * 0.8))
                let c = cos(-ang), sn = sin(-ang)
                let lx = dx * c - dy * sn, ly = dx * sn + dy * c
                if lx >= 0 && lx <= fr.len {
                    let u = lx / fr.len
                    let curveY = sin(u * .pi) * fr.bend * 13 + sin(u * 4.0 + time * 1.6 + CGFloat(f)) * 2.0 * u
                    let leafW = sin(pow(u, 0.72) * .pi) * 4.2 + 1.0
                    if abs(ly - curveY) <= leafW {
                        let ch: Character = u > 0.78 ? (u > 0.9 ? "·" : "~") : (abs(ly - curveY) < 1.3 ? "=" : (u < 0.35 ? "#" : "+"))
                        return (u, ch)
                    }
                }
            }
        }
        return nil
    }

    private func sampleLeafLocal(_ lf: Leaf, _ lx: CGFloat, _ ly: CGFloat, _ actSeason: String) -> (part: Int, shade: CGFloat)? {
        // part: 0 = blade, 1 = vein, 2 = stem
        if lf.isSnow {
            let r = hypot(lx, ly)
            if r > 1.0 { return nil }
            let arm = abs(sin(atan2(ly, lx) * 3))
            if r < 0.25 || arm < 0.17 { return (r < 0.35 ? 1 : 0, 1.0 - r * 0.35) }
            return nil
        }
        if actSeason == "spring" {
            if lx < -0.95 || lx > 1.0 { return nil }
            let u = (lx + 0.95) / 1.95
            let halfW = sin(pow(u, 0.72) * .pi) * 0.72
            let absY = abs(ly)
            if absY > halfW { return nil }
            if u > 0.76 && absY < (u - 0.76) * 0.95 { return nil }
            let isVein = absY < 0.08 && u > 0.12 && u < 0.74
            return (isVein ? 1 : 0, min(1, 0.55 + (1 - absY / max(0.01, halfW)) * 0.35 + (1 - u) * 0.15))
        }
        if actSeason == "autumn" && lf.maple {
            if lx < -0.08 && lx > -0.78 && abs(ly) < 0.085 { return (2, 0.65) }
            let r = hypot(lx, ly)
            if r > 1.06 { return nil }
            let absA = abs(atan2(ly, lx))
            let l1 = exp(-pow(absA / 0.30, 2)) * 1.02
            let l2 = exp(-pow((absA - 0.92) / 0.28, 2)) * 0.88
            let l3 = exp(-pow((absA - 1.82) / 0.26, 2)) * 0.58
            let palm: CGFloat = absA < 2.15 ? 0.34 : 0.12
            let maxR = max(palm, max(l1, max(l2, l3)))
            if r <= maxR {
                let onVein = (absA < 0.09 && r < 0.86) || (abs(absA - 0.92) < 0.09 && r < 0.74) || (abs(absA - 1.82) < 0.10 && r < 0.48)
                let edgeFade = 1 - pow(r / max(0.01, maxR), 2.2) * 0.42
                return (onVein ? 1 : 0, max(0.28, min(1.0, edgeFade * 0.95 - ly * 0.16)))
            }
            return nil
        }
        if lx < -0.92 && lx > -1.48 && abs(ly) < 0.08 { return (2, 0.62) }
        if lx < -0.95 || lx > 1.0 { return nil }
        let u = (lx + 0.95) / 1.95
        let halfW = sin(pow(u, 0.78) * .pi) * 0.56
        let absY = abs(ly)
        if absY > halfW { return nil }
        let isMidrib = absY < 0.075 && u > 0.05 && u < 0.92
        return (isMidrib ? 1 : 0, max(0.28, min(1.0, 0.50 + (1 - absY / max(0.01, halfW)) * 0.42 - ly * 0.18)))
    }

    private func isClockCell(_ c: Int, _ r: Int, _ chars: [Character]) -> Bool {
        if !config.showClock || config.isPreview || config.minimalistMode { return false }
        let scaleX = cols > 170 ? 3 : (cols > 120 ? 2 : 1)
        let scaleY = rows > 60 ? 3 : (rows > 40 ? 2 : 1)
        let charW = 6 * scaleX
        let totalW = chars.count * charW - scaleX
        let totalH = 7 * scaleY
        let startC = (cols - totalW) / 2
        let startR = (rows - totalH) / 2
        let lc = c - startC, lr = r - startR
        if lc < 0 || lc >= totalW || lr < 0 || lr >= totalH { return false }
        let charIdx = lc / charW
        let inCharC = (lc % charW) / scaleX
        let inCharR = lr / scaleY
        if inCharC >= 5 { return false }
        guard let glyph = digits[chars[charIdx]] else { return false }
        let rowStr = glyph[inCharR]
        let idx = rowStr.index(rowStr.startIndex, offsetBy: inCharC)
        return rowStr[idx] == "1"
    }

    // MARK: - Native CoreGraphics Rendering (Color-Batched for Ultra-Low CPU)

    @inline(__always)
    private func drawGlyph(_ ctx: CGContext, _ ch: Character, col: Int, row: Int, r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1.0) {
        guard let glyph = glyphCache[ch] else { return }
        let cr = max(0, min(1, r))
        let cg = max(0, min(1, g))
        let cb = max(0, min(1, b))
        let ca = max(0, min(1, a))
        // Quantize to 5-bit RGB + 4-bit Alpha (32 levels/channel) so thousands of glyphs batch into ~90 CTFontDrawGlyphs calls!
        let r5 = UInt32(cr * 31.0 + 0.5)
        let g5 = UInt32(cg * 31.0 + 0.5)
        let b5 = UInt32(cb * 31.0 + 0.5)
        let a4 = UInt32(ca * 15.0 + 0.5)
        let key = (r5 << 14) | (g5 << 9) | (b5 << 4) | a4

        let x = CGFloat(col) * cellW
        let y = height - CGFloat(row + 1) * cellH + cellH * 0.18
        let pt = CGPoint(x: x, y: y)

        if batchGlyphs[key] == nil {
            batchGlyphs[key] = [glyph]
            batchPositions[key] = [pt]
            batchKeys.append(key)
        } else {
            if batchGlyphs[key]!.isEmpty { batchKeys.append(key) }
            batchGlyphs[key]!.append(glyph)
            batchPositions[key]!.append(pt)
        }
    }

    private func ensureTreeBranchCache(season actSeason: String) {
        let key = "\(config.treeBranch)_\(actSeason)_\(cols)x\(rows)"
        if branchCacheKey == key { return }
        branchCacheKey = key
        branchCells.removeAll(keepingCapacity: true)
        branchShadowCells.removeAll(keepingCapacity: true)
        branchTipPoints.removeAll(keepingCapacity: true)

        guard config.treeBranch != "none", cols > 20, rows > 12 else { return }

        let s = screenScale()
        let spanX = min(width * 0.38, 575 * s)
        let spanY = min(height * 0.40, 395 * s)

        let isRight = (config.treeBranch == "topRight" || config.treeBranch == "bottomRight")
        let isBottom = (config.treeBranch == "bottomRight" || config.treeBranch == "bottomLeft")
        let anchorX: CGFloat = isRight ? width + 10 : -10
        let anchorY: CGFloat = isBottom ? height + 10 : -10
        let dirX: CGFloat = isRight ? -1 : 1
        let dirY: CGFloat = isBottom ? -1 : 1

        func toWorld(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            CGPoint(x: anchorX + dirX * u * spanX, y: anchorY + dirY * v * spanY)
        }

        // Deduplicated cell map: key = row * cols + col -> BranchCell
        var cellMap: [Int: BranchCell] = [:]
        var shadowSet = Set<Int>()

        func putCell(px: CGFloat, py: CGFloat, ch: Character, kind: UInt8, colorIdx: Int, sway: CGFloat) {
            let c = Int(px / cellW), r = Int(py / cellH)
            guard c >= 0 && c < cols && r >= 0 && r < rows else { return }
            let idx = r * cols + c
            if let existing = cellMap[idx], existing.kind > kind { return }
            cellMap[idx] = BranchCell(col: c, row: r, ch: ch, kind: kind, colorIdx: colorIdx, swayWeight: sway)
            // High-altitude top-down cast shadow: larger parallax offset (+7 cols, +4 rows) creates instant aerial depth!
            let sc = c + 7, sr = r + 4
            if sc >= 0 && sc < cols && sr >= 0 && sr < rows {
                let sIdx = sr * cols + sc
                if shadowSet.insert(sIdx).inserted {
                    branchShadowCells.append((col: sc, row: sr, ch: kind >= 3 ? "·" : ":", swayWeight: sway))
                }
            }
        }

        // Helper: rasterize a gnarled organic Bezier wood limb with 3-tone bark shading
        func rasterizeWood(p0: CGPoint, p1: CGPoint, p2: CGPoint, rStart: CGFloat, rEnd: CGFloat, swayStart: CGFloat, swayEnd: CGFloat, steps: Int, gnarlSeed: CGFloat) {
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let mt = 1 - t
                var x = mt * mt * p0.x + 2 * mt * t * p1.x + t * t * p2.x
                var y = mt * mt * p0.y + 2 * mt * t * p1.y + t * t * p2.y
                let tx = 2 * mt * (p1.x - p0.x) + 2 * t * (p2.x - p1.x)
                let ty = 2 * mt * (p1.y - p0.y) + 2 * t * (p2.y - p1.y)
                let len = max(0.001, hypot(tx, ty))
                let nx = -ty / len, ny = tx / len

                // Subtle organic gnarl/knot undulation so the wood looks real, not geometric
                let gnarl = (sin(t * 10.5 + gnarlSeed) * 2.6 + cos(t * 21.0 + gnarlSeed * 1.7) * 1.1) * s * (0.4 + 0.6 * t)
                x += nx * gnarl
                y += ny * gnarl

                let rad = (rStart + (rEnd - rStart) * pow(t, 0.85)) * (1.0 + 0.10 * sin(t * 17.0 + gnarlSeed))
                let sway = swayStart + (swayEnd - swayStart) * t

                var ang = atan2(ty, tx).truncatingRemainder(dividingBy: .pi)
                if ang < 0 { ang += .pi }
                let twigCh: Character = (ang < .pi / 8 || ang >= 7 * .pi / 8) ? "=" : (ang < 3 * .pi / 8 ? "\\" : (ang < 5 * .pi / 8 ? "|" : "/"))

                let samples = max(1, Int(ceil(rad / 2.6)))
                for k in -samples...samples {
                    let frac = CGFloat(k) / CGFloat(max(1, samples))
                    let ox = nx * frac * rad
                    let oy = ny * frac * rad
                    let ch: Character
                    let kind: UInt8
                    if rad > 7.0 {
                        // Thick gnarled trunk/bough: sunlit upper edge, grooved center, deep underside
                        if frac < -0.35 { ch = (i % 3 == 0 ? ":" : "="); kind = 1 }
                        else if frac > 0.45 { ch = "@"; kind = 0 }
                        else { ch = (i % 4 == 0 ? "%" : "#"); kind = 0 }
                    } else if rad > 3.2 {
                        ch = frac < -0.2 ? "=" : "#"
                        kind = frac < -0.25 ? 1 : 0
                    } else {
                        ch = twigCh
                        kind = 0
                    }
                    putCell(px: x + ox, py: y + oy, ch: ch, kind: kind, colorIdx: 0, sway: sway)
                }
            }
        }

        // Helper: true TOP-DOWN botanical leaf/blossom canopy (radiating rosettes + 3D crown height shading!)
        // kind: 2 = deep lower shaded foliage, 3 = mid canopy leaves, 4 = sunlit upper crown tips/blossoms
        func addFoliageCluster(center: CGPoint, radius: CGFloat, sway: CGFloat, seed: Int) {
            branchTipPoints.append(center)
            let isWinter = actSeason == "winter"

            // 1. Deep shaded under-canopy base (gives 3D volume when viewed from straight above)
            let baseCount = isWinter ? 6 : 16
            for k in 0..<baseCount {
                let h1 = hash2(CGFloat(seed * 41 + k), 5.1)
                let h2 = hash2(CGFloat(seed * 23 + k), 13.7)
                let ang = h1 * 2.0 * .pi
                let dist = sqrt(h2) * radius * 0.96
                let px = center.x + cos(ang) * dist + 2.5
                let py = center.y + sin(ang) * dist + 2.0
                let ch: Character = isWinter ? "·" : (h1 > 0.5 ? "%" : "#")
                putCell(px: px, py: py, ch: ch, kind: 2, colorIdx: k % 3, sway: sway)
            }

            // 2. Radiating top-down leaf fans / 5-petal sakura rosettes
            let rosetteCount = isWinter ? 3 : 5
            for rIdx in 0..<rosetteCount {
                let rh1 = hash2(CGFloat(seed * 29 + rIdx), 11.3)
                let rh2 = hash2(CGFloat(seed * 17 + rIdx), 27.9)
                let rAng = rh1 * 2.0 * .pi
                let rDist = (rIdx == 0 ? 0.0 : (0.35 + rh2 * 0.45)) * radius
                let rx = center.x + cos(rAng) * rDist
                let ry = center.y + sin(rAng) * rDist
                let petals = actSeason == "spring" ? 5 : 6
                let leafLen = radius * (0.36 + rh2 * 0.22)
                let baseRot = rh1 * .pi

                for p in 0..<petals {
                    let pAng = baseRot + CGFloat(p) * (2.0 * .pi / CGFloat(petals))
                    let steps = isWinter ? 2 : 3
                    for st in 1...steps {
                        let frac = CGFloat(st) / CGFloat(steps)
                        let px = rx + cos(pAng) * leafLen * frac
                        let py = ry + sin(pAng) * leafLen * frac
                        // Top-left side catches overhead sun -> brightest crown highlight (kind 4)
                        let sunlit = (cos(pAng) < 0.25 && sin(pAng) < 0.35) || (rIdx == 0 && st <= 2)
                        let kind: UInt8 = sunlit ? 4 : 3
                        let ch: Character
                        if isWinter {
                            ch = sunlit ? "*" : "+"
                        } else if actSeason == "spring" {
                            ch = sunlit ? (st == 1 ? "@" : "*") : (st == steps ? "·" : "+")
                        } else {
                            ch = sunlit ? (st == 1 ? "*" : "#") : (st == steps ? "+" : "%")
                        }
                        putCell(px: px, py: py, ch: ch, kind: kind, colorIdx: (rIdx + p) % 3, sway: sway)
                    }
                }
            }
        }

        // 1. Sturdy sweeping main bough reaching majestically out over the pond
        rasterizeWood(p0: toWorld(-0.04, 0.06), p1: toWorld(0.40, 0.20), p2: toWorld(0.95, 0.58), rStart: 15.5 * s, rEnd: 2.0 * s, swayStart: 0.0, swayEnd: 1.0, steps: 80, gnarlSeed: 1.2)

        // 2. Four organic secondary limbs forking outward at natural angles
        rasterizeWood(p0: toWorld(0.20, 0.13), p1: toWorld(0.46, 0.02), p2: toWorld(0.86, 0.10), rStart: 7.5 * s, rEnd: 1.5 * s, swayStart: 0.20, swayEnd: 0.95, steps: 46, gnarlSeed: 3.1)
        rasterizeWood(p0: toWorld(0.32, 0.21), p1: toWorld(0.24, 0.54), p2: toWorld(0.36, 0.92), rStart: 7.0 * s, rEnd: 1.5 * s, swayStart: 0.30, swayEnd: 0.95, steps: 46, gnarlSeed: 5.4)
        rasterizeWood(p0: toWorld(0.56, 0.34), p1: toWorld(0.76, 0.22), p2: toWorld(0.98, 0.28), rStart: 5.2 * s, rEnd: 1.3 * s, swayStart: 0.52, swayEnd: 1.0, steps: 34, gnarlSeed: 7.8)
        rasterizeWood(p0: toWorld(0.68, 0.43), p1: toWorld(0.60, 0.68), p2: toWorld(0.70, 0.88), rStart: 4.2 * s, rEnd: 1.2 * s, swayStart: 0.65, swayEnd: 1.0, steps: 30, gnarlSeed: 9.6)

        // 3. Fine tertiary twigs for delicate silhouette detail
        rasterizeWood(p0: toWorld(0.52, 0.07), p1: toWorld(0.64, 0.16), p2: toWorld(0.76, 0.18), rStart: 2.6 * s, rEnd: 1.0 * s, swayStart: 0.55, swayEnd: 0.92, steps: 18, gnarlSeed: 11.2)
        rasterizeWood(p0: toWorld(0.29, 0.52), p1: toWorld(0.16, 0.68), p2: toWorld(0.14, 0.84), rStart: 2.6 * s, rEnd: 1.0 * s, swayStart: 0.50, swayEnd: 0.90, steps: 18, gnarlSeed: 13.7)
        rasterizeWood(p0: toWorld(0.80, 0.49), p1: toWorld(0.92, 0.44), p2: toWorld(1.02, 0.48), rStart: 2.2 * s, rEnd: 1.0 * s, swayStart: 0.80, swayEnd: 1.0, steps: 16, gnarlSeed: 15.1)

        // 4. Lush layered foliage / blossom clusters along every limb & twig tip
        let clusters: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.16, 0.10, 30, 0.18), (0.38, 0.08, 34, 0.38), (0.60, 0.06, 32, 0.62), (0.85, 0.11, 34, 0.95),
            (0.75, 0.19, 28, 0.80), (0.98, 0.28, 32, 1.00), (0.80, 0.28, 30, 0.78),
            (0.28, 0.42, 32, 0.42), (0.15, 0.78, 28, 0.82), (0.34, 0.68, 32, 0.72), (0.38, 0.91, 34, 0.96),
            (0.48, 0.30, 34, 0.48), (0.68, 0.42, 34, 0.68), (0.64, 0.66, 30, 0.82), (0.71, 0.87, 32, 0.98),
            (0.88, 0.54, 34, 0.92), (0.97, 0.60, 32, 1.00), (1.01, 0.48, 26, 1.00)
        ]
        for (idx, cl) in clusters.enumerated() {
            addFoliageCluster(center: toWorld(cl.0, cl.1), radius: cl.2 * s, sway: cl.3, seed: idx + 1)
        }

        branchCells = Array(cellMap.values)
    }

    /// Pre-rasterizes top-down Zen Garden Accent (Japanese Hinoki Wooden Bridge or Mossy River Stones) ONCE on change (~0.08ms/frame!)
    private func ensurePondAccentCache() {
        // Place in opposite bottom corner from treeBranch so it never collides with widgets or the tree!
        let onLeft = (config.treeBranch != "bottomLeft")
        let key = "\(config.pondAccent)_\(onLeft ? "L" : "R")_\(cols)x\(rows)"
        if accentCacheKey == key { return }
        accentCacheKey = key
        accentCells.removeAll(keepingCapacity: true)
        accentShadowCells.removeAll(keepingCapacity: true)

        guard config.pondAccent != "none", cols > 30, rows > 16 else { return }
        let s = screenScale()
        var cellMap: [Int: AccentCell] = [:]
        var shadowSet = Set<Int>()

        // kind legend:
        // Bridge: 0=dark seam/underwood, 1=weathered plank mid, 2=sunlit plank grain, 3=warm cedar rail, 4=dark bronze post cap
        // Stones: 5=wet dark rock base, 6=mid river granite, 7=sunlit flat top stone, 8=dark damp moss, 9=bright lush moss
        func put(px: CGFloat, py: CGFloat, ch: Character, kind: UInt8, shDx: Int, shDy: Int, priority: UInt8? = nil) {
            let c = Int(px / cellW), r = Int(py / cellH)
            guard c >= 0 && c < cols && r >= 0 && r < rows else { return }
            let idx = r * cols + c
            let prio = priority ?? kind
            if let ex = cellMap[idx], ex.kind > prio { return }
            cellMap[idx] = AccentCell(col: c, row: r, ch: ch, kind: kind)
            if shDx != 0 || shDy != 0 {
                let sc = c + shDx, sr = r + shDy
                if sc >= 0 && sc < cols && sr >= 0 && sr < rows {
                    if shadowSet.insert(sr * cols + sc).inserted {
                        accentShadowCells.append((col: sc, row: sr, ch: (kind == 3 || kind == 4 || kind >= 6) ? ":" : "·"))
                    }
                }
            }
        }

        // Helper: organic top-down mossy river stone (works for both big boulders & small surrounding pebbles!)
        func stampRiverStone(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, rot: CGFloat, seed: Int, mossAmt: CGFloat, isPebble: Bool) {
            let cCos = cos(-rot), cSin = sin(-rot)
            let minC = max(0, Int(floor((cx - rx - 8) / cellW))), maxC = min(cols - 1, Int(ceil((cx + rx + 8) / cellW)))
            let minR = max(0, Int(floor((cy - ry - 8) / cellH))), maxR = min(rows - 1, Int(ceil((cy + ry + 8) / cellH)))
            guard minR <= maxR && minC <= maxC else { return }

            for r in minR...maxR {
                let dy = (CGFloat(r) + 0.5) * cellH - cy
                for c in minC...maxC {
                    let dx = (CGFloat(c) + 0.5) * cellW - cx
                    let lx = (dx * cCos - dy * cSin) / rx
                    let ly = (dx * cSin + dy * cCos) / ry
                    let ang = atan2(ly, lx)
                    let edge = 1.0 + 0.13 * sin(ang * 3.0 + CGFloat(seed) * 2.1) + 0.07 * cos(ang * 5.0 - CGFloat(seed))
                    let d = hypot(lx, ly) / edge
                    if d <= 1.0 {
                        let h = hash2(CGFloat(c + seed * 19), CGFloat(r + seed * 7))
                        let nMoss = fbm(CGFloat(c) * 0.24 + CGFloat(seed) * 3.1, CGFloat(r) * 0.24)
                        // Directional top-down lighting (sunlit upper-left face, damp shaded lower-right rim)
                        let light = -lx * 0.45 - ly * 0.45 + (1.0 - d) * 0.65
                        let px = (CGFloat(c) + 0.5) * cellW
                        let py = (CGFloat(r) + 0.5) * cellH

                        // Lush organic moss creeping across damp edges & crevices (especially on shaded/wet sides!)
                        let mossZone = (d > 0.42 && nMoss > (0.64 - mossAmt * 0.24)) || (d > 0.68 && ly > -0.1 && nMoss > (0.52 - mossAmt * 0.20))
                        if !isPebble && mossZone {
                            let isBrightMoss = light > 0.12 || h > 0.62
                            let mCh: Character = isBrightMoss ? (h > 0.55 ? "*" : "+") : (h > 0.5 ? "%" : ":")
                            put(px: px, py: py, ch: mCh, kind: isBrightMoss ? 9 : 8, shDx: 3, shDy: 2)
                        } else if d > 0.80 {
                            // Wet dark granite waterline edge
                            put(px: px, py: py, ch: isPebble ? "o" : (h > 0.5 ? "%" : ":"), kind: 5, shDx: isPebble ? 2 : 3, shDy: isPebble ? 1 : 2)
                        } else if light > 0.36 && !isPebble {
                            // Sunlit weathered granite top face
                            let tCh: Character = h > 0.72 ? "#" : (h > 0.35 ? "=" : ".")
                            put(px: px, py: py, ch: tCh, kind: 7, shDx: 3, shDy: 2)
                        } else {
                            // Mid-tone natural river granite
                            let mCh: Character = isPebble ? (h > 0.45 ? "o" : ".") : (h > 0.62 ? "#" : (h > 0.25 ? "%" : "+"))
                            put(px: px, py: py, ch: mCh, kind: 6, shDx: isPebble ? 2 : 3, shDy: isPebble ? 1 : 2)
                        }
                    }
                }
            }
        }

        if config.pondAccent == "bridge" {
            // Authentic Japanese curved cedar/hinoki wooden footbridge seen 100% TOP-DOWN
            let p0 = onLeft ? CGPoint(x: -18, y: height * 0.68) : CGPoint(x: width + 18, y: height * 0.68)
            let p1 = onLeft ? CGPoint(x: width * 0.16, y: height * 0.81) : CGPoint(x: width * 0.84, y: height * 0.81)
            let p2 = onLeft ? CGPoint(x: width * 0.28, y: height + 18) : CGPoint(x: width * 0.72, y: height + 18)
            let halfW: CGFloat = 40 * s

            // 1. Anchor both ends of the bridge with natural mossy shoreline stones & small pebbles!
            let shoreStones: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, Bool)] = [
                (0.025, 0.63, 24, 18,  0.3, false), (0.055, 0.65, 11, 9, 0.1, true),
                (0.018, 0.75, 22, 16, -0.2, false), (0.048, 0.77, 10, 8, 0.5, true),
                (0.225, 0.96, 24, 18,  0.4, false), (0.195, 0.97, 12, 9, -0.3, true),
                (0.320, 0.96, 20, 15, -0.2, false), (0.345, 0.98, 10, 8,  0.2, true)
            ]
            for (idx, st) in shoreStones.enumerated() {
                let sx = onLeft ? width * st.0 : width * (1.0 - st.0)
                stampRiverStone(cx: sx, cy: height * st.1, rx: st.2 * s, ry: st.3 * s, rot: st.4, seed: 40 + idx, mossAmt: 0.95, isPebble: st.5)
            }

            // 2. Curved wooden plank deck + warm cedar handrails + dark bronze finial posts!
            let steps = 54
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let mt = 1 - t
                let cx = mt * mt * p0.x + 2 * mt * t * p1.x + t * t * p2.x
                let cy = mt * mt * p0.y + 2 * mt * t * p1.y + t * t * p2.y
                let tx = 2 * mt * (p1.x - p0.x) + 2 * t * (p2.x - p1.x)
                let ty = 2 * mt * (p1.y - p0.y) + 2 * t * (p2.y - p1.y)
                let len = max(0.001, hypot(tx, ty))
                let nx = -ty / len, ny = tx / len

                let isSeam = (i % 3 == 0)
                let isPost = (i % 13 == 4)
                let plankIdx = i / 3
                let plankToneLight = (plankIdx % 2 == 0)

                let widthSamples = 18
                for k in -widthSamples...widthSamples {
                    let frac = CGFloat(k) / CGFloat(widthSamples)
                    let px = cx + nx * frac * halfW
                    let py = cy + ny * frac * halfW
                    let absF = abs(frac)

                    if absF > 0.85 {
                        // Warm cedar handrail with dark bronze/black corner post caps (just like the reference photo!)
                        if isPost {
                            put(px: px, py: py, ch: "@", kind: 4, shDx: 6, shDy: 4, priority: 12)
                        } else {
                            let rCh: Character = absF > 0.92 ? "#" : "="
                            put(px: px, py: py, ch: rCh, kind: 3, shDx: 6, shDy: 4, priority: 11)
                        }
                    } else {
                        // Transverse weathered wooden deck planks with dark seams between boards
                        let grain = hash2(CGFloat(plankIdx * 13 + k), CGFloat(i))
                        if isSeam {
                            put(px: px, py: py, ch: "-", kind: 0, shDx: 5, shDy: 3, priority: 10)
                        } else {
                            let isBright = plankToneLight && (grain > 0.35 || absF < 0.35)
                            let pCh: Character = isBright ? (grain > 0.7 ? "#" : "=") : (grain > 0.65 ? "%" : "=")
                            put(px: px, py: py, ch: pCh, kind: isBright ? 2 : 1, shDx: 5, shDy: 3, priority: 10)
                        }
                    }
                }
            }
        } else if config.pondAccent == "stones" {
            // Authentic Japanese mossy stepping stones (Tobi-ishi) surrounded by natural smaller river pebbles!
            let bigStones: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (0.042, 0.74, 38, 27,  0.22),
                (0.118, 0.81, 34, 24, -0.20),
                (0.185, 0.88, 40, 28,  0.28),
                (0.258, 0.95, 34, 24, -0.14)
            ]
            // Smaller river pebbles scattered naturally around the stepping stones
            let pebbles: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (0.018, 0.69, 13, 10,  0.4), (0.078, 0.71, 11, 8, -0.3), (0.024, 0.81, 12, 9,  0.1),
                (0.088, 0.86, 14, 10,  0.5), (0.150, 0.77, 11, 8, -0.4), (0.148, 0.85,  9, 7,  0.2),
                (0.142, 0.93, 13, 10, -0.2), (0.222, 0.84, 12, 9,  0.3), (0.215, 0.94, 10, 8, -0.5),
                (0.288, 0.91, 13,  9,  0.2), (0.305, 0.97, 11, 8, -0.1), (0.062, 0.78,  9, 7,  0.6)
            ]
            for (idx, pb) in pebbles.enumerated() {
                let px = onLeft ? width * pb.0 : width * (1.0 - pb.0)
                stampRiverStone(cx: px, cy: height * pb.1, rx: pb.2 * s, ry: pb.3 * s, rot: pb.4, seed: 100 + idx, mossAmt: 0.5, isPebble: true)
            }
            for (idx, sp) in bigStones.enumerated() {
                let cx = onLeft ? width * sp.0 : width * (1.0 - sp.0)
                stampRiverStone(cx: cx, cy: height * sp.1, rx: sp.2 * s, ry: sp.3 * s, rot: sp.4, seed: 10 + idx, mossAmt: 1.0, isPebble: false)
            }
        }

        accentCells = Array(cellMap.values)
    }

    private func flushGlyphBatches(in ctx: CGContext) {
        for key in batchKeys {
            guard let glyphs = batchGlyphs[key], let positions = batchPositions[key], !glyphs.isEmpty else { continue }
            let r = CGFloat((key >> 14) & 31) / 31.0
            let g = CGFloat((key >> 9) & 31) / 31.0
            let b = CGFloat((key >> 4) & 31) / 31.0
            let a = CGFloat(key & 15) / 15.0
            ctx.setFillColor(red: r, green: g, blue: b, alpha: a)
            CTFontDrawGlyphs(ctFont, glyphs, positions, glyphs.count, ctx)
            batchGlyphs[key]?.removeAll(keepingCapacity: true)
            batchPositions[key]?.removeAll(keepingCapacity: true)
        }
        batchKeys.removeAll(keepingCapacity: true)
    }

    @inline(__always)
    private func drawDepthGlyph(_ ctx: CGContext, _ ch: Character, col: Int, row: Int, rgb: RGB, z: CGFloat, pal: Palette, mult: CGFloat = 1.0, alpha: CGFloat = 1.0) {
        let clampedZ = max(0, min(1, z))
        let breachGlow: CGFloat = z > 1.0 ? 1.0 + (z - 1.0) * 0.72 : 1.0
        let clarity = 0.42 + clampedZ * 0.58
        let r = pal.waterDeep.r * (1 - clarity) + rgb.r * mult * breachGlow * clarity
        let g = pal.waterDeep.g * (1 - clarity) + rgb.g * mult * breachGlow * clarity
        let b = pal.waterDeep.b * (1 - clarity) + rgb.b * mult * breachGlow * clarity
        drawGlyph(ctx, ch, col: col, row: row, r: r, g: g, b: b, a: alpha)
    }

    func draw(in ctx: CGContext, rect: CGRect) {
        resize(to: rect.size)
        let pal = currentPalette()
        let actSeason = activeSeason()

        if config.minimalistMode {
            // Truly transparent over the user's real macOS desktop wallpaper!
            ctx.clear(rect)
        } else {
            ctx.setFillColor(red: pal.bg.r, green: pal.bg.g, blue: pal.bg.b, alpha: 1.0)
            ctx.fill(rect)
        }

        ctx.setFont(cgFont)
        ctx.setFontSize(fontSize)
        ctx.textMatrix = .identity
        ctx.setAllowsFontSmoothing(false)
        ctx.setShouldSmoothFonts(false)

        let now = Date()
        let cal = Calendar.current
        let timeChars = Array(String(format: "%02d:%02d", cal.component(.hour, from: now), cal.component(.minute, from: now)))

        // Precompute lotus pad frame positions once per frame (instead of sin/cos per cell!)
        lotusFrameCache.removeAll(keepingCapacity: true)
        if !config.minimalistMode {
            for lp in lotusPads {
                let ox = sin(time * 0.55 + lp.phase) * 2.5
                let oy = cos(time * 0.45 + lp.phase) * 2.0
                lotusFrameCache.append((lp.x + ox, lp.y + oy, lp.r, lp.r * lp.r, lp.notchAngle, lp.flower))
            }
        }

        // Pre-stamp ripples by walking ONLY each circle's perimeter (~100 steps vs 22,800 cell checks!)
        let gridSize = rows * cols
        if rippleChGrid.count != gridSize {
            rippleChGrid = Array(repeating: 0, count: gridSize)
            rippleAlphaGrid = Array(repeating: 0, count: gridSize)
            rippleDirtyIndices.removeAll(keepingCapacity: true)
        } else {
            for idx in rippleDirtyIndices {
                rippleChGrid[idx] = 0
                rippleAlphaGrid[idx] = 0
            }
            rippleDirtyIndices.removeAll(keepingCapacity: true)
        }
        for rp in ripples {
            let fade = (1 - rp.r / rp.maxR) * rp.alpha
            if fade <= 0.06 { continue }
            let alpha = min(0.95, fade * 1.48)
            let steps = max(24, Int(2.0 * .pi * max(4.0, rp.r) / 4.2))
            let dAng = (2.0 * .pi) / CGFloat(steps)
            for s in 0..<steps {
                let ang = CGFloat(s) * dAng
                let cAng = cos(ang), sAng = sin(ang)
                let rx = rp.x + cAng * rp.r
                let ry = rp.y + sAng * rp.r
                let col = Int(rx / cellW), row = Int(ry / cellH)
                if col >= 0 && col < cols && row >= 0 && row < rows {
                    let idx = row * cols + col
                    if alpha > rippleAlphaGrid[idx] {
                        if rippleChGrid[idx] == 0 { rippleDirtyIndices.append(idx) }
                        let absCos = abs(cAng)
                        rippleChGrid[idx] = absCos > 0.72 ? (cAng > 0 ? 2 : 1) : (fade > 0.28 ? 3 : 4)
                        rippleAlphaGrid[idx] = alpha
                    }
                }
            }
        }

        // Cache drifting sky cloud fbm every 6 frames at 2x2 stride (cuts 96% of fbm CPU cost!)
        let cloudCols = (cols + 1) / 2
        let cloudRows = (rows + 1) / 2
        let cloudSize = cloudCols * cloudRows
        if !config.minimalistMode && pal.tod != "night" {
            if cloudGrid.count != cloudSize || cloudFrameCounter % 6 == 0 {
                if cloudGrid.count != cloudSize { cloudGrid = Array(repeating: 0, count: cloudSize) }
                for cr in 0..<cloudRows {
                    let py = (CGFloat(cr * 2) + 0.5) * cellH
                    let base = cr * cloudCols
                    for cc in 0..<cloudCols {
                        let px = (CGFloat(cc * 2) + 0.5) * cellW
                        cloudGrid[base + cc] = fbm(px * 0.0042 - time * 0.028, py * 0.0052 - time * 0.012)
                    }
                }
            }
            cloudFrameCounter += 1
        }

        // Precompute clock bounding box once per frame
        let clockEnabled = config.showClock && !config.isPreview && !config.minimalistMode
        let clockScaleX = cols > 170 ? 3 : (cols > 120 ? 2 : 1)
        let clockScaleY = rows > 60 ? 3 : (rows > 40 ? 2 : 1)
        let clockTotalW = timeChars.count * 6 * clockScaleX - clockScaleX
        let clockTotalH = 7 * clockScaleY
        let clockStartC = (cols - clockTotalW) / 2
        let clockEndC = clockStartC + clockTotalW
        let clockStartR = (rows - clockTotalH) / 2
        let clockEndR = clockStartR + clockTotalH

        var actors: [ActorBox] = []
        actors.reserveCapacity(fishes.count + minnows.count + 1)

        for i in 0..<fishes.count {
            let fish = fishes[i]
            var minX: CGFloat = .infinity, maxX: CGFloat = -.infinity, minY: CGFloat = .infinity, maxY: CGFloat = -.infinity
            for rn in fish.renderNodes {
                if rn.x < minX { minX = rn.x }; if rn.x > maxX { maxX = rn.x }
                if rn.y < minY { minY = rn.y }; if rn.y > maxY { maxY = rn.y }
            }
            let pad = 88 * fish.scale
            let shX = 6 + min(1.70, fish.z) * 34, shY = 5 + min(1.70, fish.z) * 28
            actors.append(ActorBox(
                kind: 0, index: i, z: fish.z, shX: shX, shY: shY,
                minC: max(0, Int(floor((minX - pad) / cellW))), maxC: min(cols - 1, Int(ceil((maxX + pad + shX) / cellW))),
                minR: max(0, Int(floor((minY - pad) / cellH))), maxR: min(rows - 1, Int(ceil((maxY + pad + shY) / cellH)))
            ))
        }
        if !config.minimalistMode {
            if let tr = turtle {
                let pad = 54 * tr.scale
                let shX = 6 + tr.z * 28, shY = 5 + tr.z * 24
                actors.append(ActorBox(
                    kind: 1, index: 0, z: tr.z, shX: shX, shY: shY,
                    minC: max(0, Int(floor((tr.x - pad) / cellW))), maxC: min(cols - 1, Int(ceil((tr.x + pad + shX) / cellW))),
                    minR: max(0, Int(floor((tr.y - pad) / cellH))), maxR: min(rows - 1, Int(ceil((tr.y + pad + shY) / cellH)))
                ))
            }
            for i in 0..<minnows.count {
                let m = minnows[i]
                let shX = 6 + m.z * 25, shY = 5 + m.z * 22
                actors.append(ActorBox(
                    kind: 2, index: i, z: m.z, shX: shX, shY: shY,
                    minC: max(0, Int(floor((m.x - 36) / cellW))), maxC: min(cols - 1, Int(ceil((m.x + 36 + shX) / cellW))),
                    minR: max(0, Int(floor((m.y - 36) / cellH))), maxR: min(rows - 1, Int(ceil((m.y + 36 + shY) / cellH)))
                ))
            }
            // When swimming IN the water, Z-sort the frog with Koi/turtle so it swims properly UNDER lily pads!
            if let fr = frog, fr.state == .swimming {
                let fPad = 48 * screenScale()
                let shX = 6 + fr.z * 24, shY = 5 + fr.z * 20
                actors.append(ActorBox(
                    kind: 3, index: 0, z: fr.z, shX: shX, shY: shY,
                    minC: max(0, Int(floor((fr.x - fPad) / cellW))), maxC: min(cols - 1, Int(ceil((fr.x + fPad + shX) / cellW))),
                    minR: max(0, Int(floor((fr.y - fPad) / cellH))), maxR: min(rows - 1, Int(ceil((fr.y + fPad + shY) / cellH)))
                ))
            }
        }
        actors.sort { $0.z > $1.z }

        let moonX = width * 0.78, moonY = height * 0.26
        let rippleChars: [Character] = [" ", "(", ")", "~", "·"]
        var rowActors: [ActorBox] = []
        rowActors.reserveCapacity(actors.count)

        for r in 0..<rows {
            let py = (CGFloat(r) + 0.5) * cellH
            let rowOff = r * cols
            let rowWaveSin = sin(CGFloat(r) * 0.23 + time * 0.4)
            let rowWaveCosBase = CGFloat(r) * 0.20 - time * 0.5
            let inClockRow = clockEnabled && r >= clockStartR && r < clockEndR
            let cloudRowOff = (r >> 1) * cloudCols

            // Filter actors intersecting this row once per row (0–2 actors instead of 12 per cell!)
            rowActors.removeAll(keepingCapacity: true)
            for ac in actors where r >= ac.minR && r <= ac.maxR {
                rowActors.append(ac)
            }

            for c in 0..<cols {
                let px = (CGFloat(c) + 0.5) * cellW
                let cellIdx = rowOff + c

                // 0. Lily pads on top of water
                if !config.minimalistMode, let lp = sampleLotus(px, py) {
                    if lp.flower {
                        let m = 1.05 - lp.norm * 0.2
                        drawGlyph(ctx, lp.norm < 0.4 ? "@" : "*", col: c, row: r, r: pal.flower.r * m, g: pal.flower.g * m, b: pal.flower.b * m)
                    } else {
                        let edge = lp.norm > 0.88
                        let rgb = lp.vein ? pal.lotusVein : pal.lotus
                        let m: CGFloat = lp.vein ? 1.0 : (edge ? 0.72 : 0.85 + (1 - lp.norm) * 0.25)
                        let ch: Character = lp.vein ? ":" : (edge ? "+" : (lp.norm < 0.35 ? "%" : "#"))
                        drawGlyph(ctx, ch, col: c, row: r, r: rgb.r * m, g: rgb.g * m, b: rgb.b * m)
                    }
                    continue
                }

                // 1. Ripples (O(1) lookup from pre-stamped perimeter grid!)
                let rCode = Int(rippleChGrid[cellIdx])
                let rippleCh: Character? = rCode > 0 ? rippleChars[rCode] : nil
                let rippleAlpha: CGFloat = rCode > 0 ? rippleAlphaGrid[cellIdx] : 0

                // 2. Z-sorted swimmers & shadows (row-culled actors!)
                var hit: SampleHit? = nil
                var shadowHit: SampleHit? = nil
                for ac in rowActors {
                    if c >= ac.minC && c <= ac.maxC {
                        if hit == nil {
                            if ac.kind == 0 { hit = sampleKoi(fishes[ac.index], px, py, shadowOnly: false) }
                            else if ac.kind == 1, let tr = turtle { hit = sampleTurtle(tr, px, py, shadowOnly: false) }
                            else if ac.kind == 2 { hit = sampleMinnow(minnows[ac.index], px, py, shadowOnly: false) }
                            else if ac.kind == 3, let fr = frog, let fh = sampleFrog(fr, px, py) { hit = .frog(part: fh.part, shade: fh.shade, depthZ: fr.z) }
                            if hit != nil { break }
                        }
                        if shadowHit == nil {
                            if ac.kind == 0 { shadowHit = sampleKoi(fishes[ac.index], px - ac.shX, py - ac.shY, shadowOnly: true) }
                            else if ac.kind == 1, let tr = turtle { shadowHit = sampleTurtle(tr, px - ac.shX, py - ac.shY, shadowOnly: true) }
                            else if ac.kind == 2 { shadowHit = sampleMinnow(minnows[ac.index], px - ac.shX, py - ac.shY, shadowOnly: true) }
                            else if ac.kind == 3, let fr = frog, sampleFrog(fr, px - ac.shX, py - ac.shY) != nil { shadowHit = .shadow(alpha: 0.55) }
                        }
                    }
                }

                if let h = hit {
                    var dz: CGFloat = 0.8
                    switch h {
                    case .eye(let glint, let rim, let depthZ):
                        dz = depthZ
                        if glint { drawGlyph(ctx, "·", col: c, row: r, r: 1, g: 1, b: 1) }
                        else if rim { drawDepthGlyph(ctx, "o", col: c, row: r, rgb: pal.fin, z: depthZ, pal: pal, mult: 0.7) }
                        else { drawGlyph(ctx, "@", col: c, row: r, r: pal.eye.r, g: pal.eye.g, b: pal.eye.b) }
                    case .barbel(let u, let ang, let variety, let depthZ):
                        dz = depthZ
                        let ch: Character
                        if u > 0.84 { ch = "·" }
                        else if u < 0.22 { ch = "=" }
                        else {
                            var a = ang.truncatingRemainder(dividingBy: .pi)
                            if a < 0 { a += .pi }
                            if a < .pi / 8 || a >= 7 * .pi / 8 { ch = "-" }
                            else if a < 3 * .pi / 8 { ch = "\\" }
                            else if a < 5 * .pi / 8 { ch = "|" }
                            else { ch = "/" }
                        }
                        drawDepthGlyph(ctx, ch, col: c, row: r, rgb: variety == .ogon ? pal.gold : pal.barbel, z: depthZ, pal: pal, mult: 1.02, alpha: max(0.42, 0.96 - u * 0.48))
                    case .body(let shade, let pigment, let isDorsal, let isScaleEdge, let isGill, let depthZ):
                        dz = depthZ
                        let ramp = isScaleEdge ? scaleRamp : shadeRamp
                        let idx = max(1, min(ramp.count - 1, Int(shade * CGFloat(ramp.count - 1))))
                        var ch = ramp[idx]
                        if isDorsal { ch = idx > 10 ? "W" : "+" }
                        else if isGill { ch = "(" }
                        let baseRgb: RGB
                        var boost = 0.45 + shade * 0.65
                        switch pigment {
                        case 1: baseRgb = pal.red; boost = 0.50 + shade * 0.62
                        case 2: baseRgb = pal.black; boost = 0.70 + shade * 1.50; ch = shade > 0.80 ? "#" : (isScaleEdge ? ":" : "%")
                        case 3: baseRgb = pal.gold; boost = 0.50 + shade * 0.68
                        case 4: baseRgb = config.monoMode ? pal.white : RGB(66, 146, 255); boost = 0.58 + shade * 0.68
                        case 5: baseRgb = config.monoMode ? pal.fin : RGB(154, 108, 255); boost = 0.58 + shade * 0.68
                        case 6: baseRgb = config.monoMode ? pal.white : RGB(115, 246, 255); boost = 0.85 + shade * 0.45; ch = "*"
                        case 7: baseRgb = config.monoMode ? pal.red : RGB(224, 118, 76); boost = 0.55 + shade * 0.65
                        case 8: baseRgb = config.monoMode ? pal.white : RGB(248, 232, 208); boost = 0.52 + shade * 0.62
                        default: baseRgb = pal.white
                        }
                        drawDepthGlyph(ctx, ch, col: c, row: r, rgb: baseRgb, z: depthZ, pal: pal, mult: boost)
                    case .fin(let density, let dark, let spine, let depthZ):
                        dz = depthZ
                        let idx = max(1, min(finRamp.count - 1, Int(density * CGFloat(finRamp.count))))
                        let ch: Character = spine ? "=" : finRamp[idx]
                        if ch != " " {
                            drawDepthGlyph(ctx, ch, col: c, row: r, rgb: dark ? pal.finBlack : pal.fin, z: depthZ, pal: pal, mult: spine ? 1.05 : 0.9, alpha: min(0.95, 0.32 + density * 0.65))
                        }
                    case .turtleShell(let shade, let rim, let depthZ):
                        dz = depthZ
                        let idx = max(1, min(shadeRamp.count - 1, Int(shade * CGFloat(shadeRamp.count - 1))))
                        drawDepthGlyph(ctx, rim ? "=" : shadeRamp[idx], col: c, row: r, rgb: rim ? pal.turtleRim : pal.turtleShell, z: depthZ, pal: pal, mult: 0.65 + shade * 0.55)
                    case .turtleSkin(let shade, let depthZ):
                        dz = depthZ
                        drawDepthGlyph(ctx, shade > 0.6 ? "+" : ":", col: c, row: r, rgb: pal.turtleSkin, z: depthZ, pal: pal, mult: 0.6 + shade * 0.5)
                    case .minnow(let t, let depthZ):
                        dz = depthZ
                        drawDepthGlyph(ctx, t < 0.25 ? "o" : (t < 0.72 ? "=" : "~"), col: c, row: r, rgb: pal.minnow, z: depthZ, pal: pal, mult: 1.0, alpha: t > 0.72 ? 0.65 : 0.92)
                    case .frog(let part, let shade, let depthZ):
                        dz = depthZ
                        switch part {
                        case 3:
                            drawDepthGlyph(ctx, "@", col: c, row: r, rgb: pal.eye, z: depthZ, pal: pal, mult: 1.0)
                        case 2:
                            drawDepthGlyph(ctx, "o", col: c, row: r, rgb: pal.gold, z: depthZ, pal: pal, mult: 1.05)
                        case 1:
                            let m = 0.55 + shade * 0.45
                            drawDepthGlyph(ctx, shade > 0.65 ? "#" : "%", col: c, row: r, rgb: RGB(pal.frog.r * 255 * 0.72, pal.frog.g * 255 * 0.88, pal.frog.b * 255 * 0.72), z: depthZ, pal: pal, mult: m)
                        default:
                            let idx = max(2, min(shadeRamp.count - 1, Int(shade * CGFloat(shadeRamp.count - 1))))
                            drawDepthGlyph(ctx, shadeRamp[idx], col: c, row: r, rgb: pal.frog, z: depthZ, pal: pal, mult: 0.72 + shade * 0.48)
                        }
                    case .shadow: break
                    }
                    if let rCh = rippleCh, rippleAlpha > 0.32 && dz <= 1.0 {
                        drawGlyph(ctx, rCh, col: c, row: r, r: pal.ripple.r, g: pal.ripple.g, b: pal.ripple.b, a: rippleAlpha * 0.45)
                    }
                    continue
                }

                // 3. Shadows on pond bed
                if let sh = shadowHit {
                    var isDense = false
                    if case .shadow(let a) = sh, a > 0.5 { isDense = true }
                    drawGlyph(ctx, isDense ? ":" : "·", col: c, row: r, r: pal.shadow.r, g: pal.shadow.g, b: pal.shadow.b, a: pal.shadowAlpha)
                    continue
                }
                if !config.minimalistMode && sampleLotusShadow(px, py) {
                    drawGlyph(ctx, "·", col: c, row: r, r: pal.shadow.r, g: pal.shadow.g, b: pal.shadow.b, a: pal.shadowAlpha)
                    continue
                }

                // 4. Ripples
                if let rCh = rippleCh {
                    drawGlyph(ctx, rCh, col: c, row: r, r: pal.ripple.r, g: pal.ripple.g, b: pal.ripple.b, a: rippleAlpha)
                    continue
                }

                // 5. Submerged oxygenating plants
                if !config.minimalistMode, let plHit = samplePlant(px, py) {
                    drawDepthGlyph(ctx, plHit.ch, col: c, row: r, rgb: plHit.tip > 0.55 ? pal.plantTip : pal.plant, z: 0.16 + plHit.tip * 0.24, pal: pal, mult: 0.82 + plHit.tip * 0.35)
                    continue
                }

                // 6. Submerged stone clock (clearer, luminous carved look)
                if inClockRow && c >= clockStartC && c < clockEndC && isClockCell(c, r, timeChars) {
                    let shimmer = 1.65 + 0.35 * sin(CGFloat(c) * 0.18 + time * 1.1)
                    drawGlyph(ctx, "#", col: c, row: r, r: min(1, pal.clock.r * shimmer), g: min(1, pal.clock.g * shimmer), b: min(1, pal.clock.b * shimmer), a: 0.88)
                    continue
                }

                if config.minimalistMode { continue }

                // 7. Sun / Moon reflection & stones & caustics
                let wave = sin(CGFloat(c) * 0.14 + time * 0.75 + rowWaveSin) *
                           cos(rowWaveCosBase + CGFloat(c) * 0.05)

                if pal.tod == "night" {
                    // Luminous silver-cyan Moon reflection + shimmering vertical water trail
                    let mdx = (px - moonX) * 0.85, mdy = (py - moonY) * 1.05
                    if abs(mdx) < 76 && abs(mdy) < 115 {
                        let md = hypot(mdx, mdy)
                        if md < 54 + wave * 10 {
                            let core = md < 22
                            let mAlpha = min(0.88, (1 - md / 66) * (core ? 0.85 : 0.56) + max(0, wave) * 0.24)
                            if mAlpha > 0.10 {
                                let mCh: Character = md < 14 ? "O" : (md < 26 ? "@" : (md < 40 ? "~" : "·"))
                                drawGlyph(ctx, mCh, col: c, row: r, r: pal.moon.r, g: pal.moon.g, b: pal.moon.b, a: mAlpha)
                                continue
                            }
                        } else if mdy > 30 && mdy < 110 && abs(mdx) < (42 - (mdy - 30) * 0.25) + wave * 12 {
                            // Gentle rippling moonbeam bars on the water below the moon
                            if wave > 0.22 {
                                let trailA = max(0, (1.0 - (mdy - 30) / 85.0)) * 0.52
                                drawGlyph(ctx, wave > 0.58 ? "=" : "~", col: c, row: r, r: pal.moon.r, g: pal.moon.g, b: pal.moon.b, a: trailA)
                                continue
                            }
                        }
                    }
                } else {
                    // Shimmering Sun reflection (pale warm gold at Day, glowing amber-orange at Sunset/Afternoon)
                    let sunX = pal.tod == "sunset" ? width * 0.26 : width * 0.74
                    let sunY = pal.tod == "sunset" ? height * 0.28 : height * 0.24
                    let sdx = (px - sunX) * 0.85, sdy = (py - sunY) * 1.0
                    if abs(sdx) < 88 && abs(sdy) < 125 {
                        let sd = hypot(sdx, sdy)
                        let sunRgb = pal.tod == "sunset" ? RGB(255, 178, 92) : RGB(255, 246, 198)
                        if sd < 58 + wave * 12 {
                            let sAlpha = min(0.76, (1 - sd / 70) * (sd < 24 ? 0.72 : 0.44) + max(0, wave) * 0.22)
                            if sAlpha > 0.08 {
                                let sCh: Character = sd < 16 ? "@" : (sd < 30 ? "*" : (sd < 46 ? "~" : "·"))
                                drawGlyph(ctx, sCh, col: c, row: r, r: sunRgb.r, g: sunRgb.g, b: sunRgb.b, a: sAlpha)
                                continue
                            }
                        } else if sdy > 32 && sdy < 120 && abs(sdx) < (48 - (sdy - 32) * 0.22) + wave * 14 {
                            if wave > 0.18 {
                                let trailA = max(0, (1.0 - (sdy - 32) / 92.0)) * (pal.tod == "sunset" ? 0.55 : 0.42)
                                drawGlyph(ctx, wave > 0.55 ? "=" : "~", col: c, row: r, r: sunRgb.r, g: sunRgb.g, b: sunRgb.b, a: trailA)
                                continue
                            }
                        }
                    }
                }

                let stVal = stoneMap[cellIdx]
                if stVal > 0.15 {
                    let causticBoost: CGFloat = wave > 0.55 ? (wave - 0.55) * 0.75 : 0
                    let sIdx = max(1, min(stoneRamp.count - 1, Int((stVal + causticBoost * 0.4) * CGFloat(stoneRamp.count - 1))))
                    let m = 0.55 + stVal * 0.65 + causticBoost * 0.6
                    drawGlyph(ctx, stoneRamp[sIdx], col: c, row: r, r: pal.stone.r * m, g: pal.stone.g * m, b: pal.stone.b * m)
                    continue
                }

                if wave > 0.78 {
                    drawGlyph(ctx, wave > 0.91 ? "~" : "·", col: c, row: r, r: pal.water.r, g: pal.water.g, b: pal.water.b, a: pal.waterAlpha)
                    continue
                }

                // 8. Clearer drifting sky cloud reflections on open water (scaled by Live Weather cloudDensity!)
                if pal.tod != "night" {
                    let cloud = cloudGrid[cloudRowOff + (c >> 1)]
                    let cloudThresh = max(0.46, 0.72 - config.cloudDensity * 0.16)
                    if cloud > cloudThresh {
                        let excess = (cloud - cloudThresh) / max(0.15, 1.0 - cloudThresh)
                        let cAlpha = min(0.48, excess * 0.58 * min(1.25, config.cloudDensity))
                        let cRgb = pal.tod == "sunset" ? RGB(248, 196, 172) : pal.white
                        let cCh: Character = excess > 0.62 ? "=" : (excess > 0.28 ? "~" : "·")
                        drawGlyph(ctx, cCh, col: c, row: r, r: cRgb.r, g: cRgb.g, b: cRgb.b, a: cAlpha)
                    }
                }
            }
        }

        // Twinkling reflected stars on open water at Night (crisp & clearly visible!)
        if !config.minimalistMode && pal.tod == "night" {
            for st in stars {
                if sampleLotus(st.x, st.y) != nil { continue }
                let twinkle = sin(time * st.spd + st.phase)
                if twinkle > -0.05 {
                    let wx = st.x + sin(time * 1.4 + st.phase) * 2.2
                    let sc = Int(wx / cellW), sr = Int(st.y / cellH)
                    if sc >= 0 && sc < cols && sr >= 0 && sr < rows {
                        let ch: Character = twinkle > 0.70 ? "*" : (twinkle > 0.30 ? "+" : "·")
                        let sAlpha = min(0.92, (twinkle + 0.18) * 0.82)
                        drawGlyph(ctx, ch, col: sc, row: sr, r: min(1, pal.moon.r * 1.1), g: min(1, pal.moon.g * 1.1), b: min(1, pal.moon.b * 1.1), a: sAlpha)
                    }
                }
            }
        }

        // Rising oxygen bubbles
        for b in bubbles {
            if sampleLotus(b.x, b.y) != nil { continue }
            let bc = Int(b.x / cellW), br = Int(b.y / cellH)
            if bc >= 0 && bc < cols && br >= 0 && br < rows {
                let ch: Character = b.z < 0.35 ? "·" : (b.z < 0.65 ? "°" : (b.z < 0.88 ? "o" : "O"))
                drawDepthGlyph(ctx, ch, col: bc, row: br, rgb: pal.bubble, z: b.z, pal: pal, mult: 1.08, alpha: 0.34 + b.z * 0.64)
            }
        }

        // Perched / Leaping / Climbing Frog (ABOVE lily pads, BELOW elevated leaves & tree branch!)
        if !config.minimalistMode, let fr = frog, fr.state != .swimming {
            let h = max(0, fr.z - 1.0)
            let shOffX: CGFloat = 5 + h * 34
            let shOffY: CGFloat = 4 + h * 28
            let fPad = 48 * screenScale()
            let fMinC = max(0, Int(floor((fr.x - fPad) / cellW)))
            let fMaxC = min(cols - 1, Int(ceil((fr.x + fPad + shOffX) / cellW)))
            let fMinR = max(0, Int(floor((fr.y - fPad) / cellH)))
            let fMaxR = min(rows - 1, Int(ceil((fr.y + fPad + shOffY) / cellH)))
            if fMinR <= fMaxR && fMinC <= fMaxC {
                for r in fMinR...fMaxR {
                    let py = (CGFloat(r) + 0.5) * cellH
                    for c in fMinC...fMaxC {
                        let px = (CGFloat(c) + 0.5) * cellW
                        if let fh = sampleFrog(fr, px, py) {
                            switch fh.part {
                            case 3: // Pupil
                                drawGlyph(ctx, "@", col: c, row: r, r: pal.eye.r, g: pal.eye.g, b: pal.eye.b)
                            case 2: // Golden/white iris
                                drawGlyph(ctx, "o", col: c, row: r, r: pal.gold.r * 1.05, g: pal.gold.g * 1.05, b: pal.gold.b * 1.05)
                            case 1: // Dark emerald spot / thigh / stripe
                                let m = 0.55 + fh.shade * 0.45
                                drawGlyph(ctx, fh.shade > 0.65 ? "#" : "%", col: c, row: r, r: pal.frog.r * m * 0.72, g: pal.frog.g * m * 0.88, b: pal.frog.b * m * 0.72)
                            default: // Frog skin
                                let idx = max(2, min(shadeRamp.count - 1, Int(fh.shade * CGFloat(shadeRamp.count - 1))))
                                let m = 0.72 + fh.shade * 0.48
                                drawGlyph(ctx, shadeRamp[idx], col: c, row: r, r: pal.frog.r * m, g: pal.frog.g * m, b: pal.frog.b * m)
                            }
                        } else if sampleFrog(fr, px - shOffX, py - shOffY) != nil {
                            drawGlyph(ctx, h > 0.14 ? "·" : ":", col: c, row: r, r: pal.shadow.r, g: pal.shadow.g, b: pal.shadow.b, a: pal.shadowAlpha * max(0.38, 0.78 - h * 0.65))
                        }
                    }
                }
            }
        }

        // Botanical Leaves / Sakura / Snow
        let leafPal = actSeason == "spring" ? pal.leafSpring : (actSeason == "summer" ? pal.leafSummer : pal.leafAutumn)
        for lf in (config.minimalistMode ? [] : leaves) {
            let h = max(0, lf.z - 1.0)
            let fadeIn: CGFloat = lf.floating ? 1.0 : min(1.0, lf.age / 0.45)
            let fadeOut: CGFloat = fadeIn * ((lf.floating && lf.age > lf.maxAge - 3) ? max(0, (lf.maxAge - lf.age) / 3) : 1)
            let drawR = lf.size * (1.0 + h * 0.52)
            let tiltY: CGFloat = lf.floating ? 1.0 : (0.58 + 0.42 * abs(cos(lf.tumble)))
            let cCos = cos(-lf.rot), cSin = sin(-lf.rot)
            let colRgb = leafPal[lf.colorIdx % leafPal.count]
            let bright = (0.94 + h * 0.22) * (0.85 + tiltY * 0.18)
            let pad = drawR * 1.55

            if !lf.isSnow {
                let shOffX = 14 + h * 38, shOffY = 12 + h * 32
                let sMinC = max(0, Int(floor((lf.x + shOffX - pad) / cellW)))
                let sMaxC = min(cols - 1, Int(ceil((lf.x + shOffX + pad) / cellW)))
                let sMinR = max(0, Int(floor((lf.y + shOffY - pad) / cellH)))
                let sMaxR = min(rows - 1, Int(ceil((lf.y + shOffY + pad) / cellH)))
                if sMinR <= sMaxR && sMinC <= sMaxC {
                    let shA = fadeOut * max(0.28, 0.72 - h * 0.25)
                    for r in sMinR...sMaxR {
                        let py = (CGFloat(r) + 0.5) * cellH - (lf.y + shOffY)
                        for c in sMinC...sMaxC {
                            let px = (CGFloat(c) + 0.5) * cellW - (lf.x + shOffX)
                            let lx = (px * cCos - py * cSin) / drawR
                            let ly = (px * cSin + py * cCos) / (drawR * tiltY)
                            if sampleLeafLocal(lf, lx, ly, actSeason) != nil {
                                drawGlyph(ctx, h < 0.28 ? ":" : "·", col: c, row: r, r: pal.shadow.r, g: pal.shadow.g, b: pal.shadow.b, a: shA)
                            }
                        }
                    }
                }
            }

            let minC = max(0, Int(floor((lf.x - pad) / cellW))), maxC = min(cols - 1, Int(ceil((lf.x + pad) / cellW)))
            let minR = max(0, Int(floor((lf.y - pad) / cellH))), maxR = min(rows - 1, Int(ceil((lf.y + pad) / cellH)))
            if minR <= maxR && minC <= maxC {
                for r in minR...maxR {
                    let py = (CGFloat(r) + 0.5) * cellH - lf.y
                    for c in minC...maxC {
                        let px = (CGFloat(c) + 0.5) * cellW - lf.x
                        let lx = (px * cCos - py * cSin) / drawR
                        let ly = (px * cSin + py * cCos) / (drawR * tiltY)
                        guard let hit = sampleLeafLocal(lf, lx, ly, actSeason) else { continue }
                        if lf.isSnow {
                            drawGlyph(ctx, hit.part == 1 ? "*" : "+", col: c, row: r, r: pal.snow.r, g: pal.snow.g, b: pal.snow.b, a: fadeOut * (0.68 + h * 0.28))
                        } else if hit.part == 2 {
                            var a = lf.rot.truncatingRemainder(dividingBy: .pi); if a < 0 { a += .pi }
                            let sCh: Character = (a < .pi / 8 || a >= 7 * .pi / 8) ? "-" : (a < 3 * .pi / 8 ? "\\" : (a < 5 * .pi / 8 ? "|" : "/"))
                            let m = bright * 0.62
                            drawGlyph(ctx, sCh, col: c, row: r, r: colRgb.r * m, g: colRgb.g * m, b: colRgb.b * m, a: fadeOut * 0.92)
                        } else if hit.part == 1 {
                            let m = bright * 1.28
                            drawGlyph(ctx, "=", col: c, row: r, r: colRgb.r * m, g: colRgb.g * m, b: colRgb.b * m, a: fadeOut * 0.98)
                        } else {
                            let idx = max(2, min(leafBladeRamp.count - 1, Int(hit.shade * CGFloat(leafBladeRamp.count - 1))))
                            let m = bright * (0.68 + hit.shade * 0.42)
                            drawGlyph(ctx, leafBladeRamp[idx], col: c, row: r, r: colRgb.r * m, g: colRgb.g * m, b: colRgb.b * m, a: fadeOut * 0.96)
                        }
                    }
                }
            }
        }

        // Visible falling raindrops (angled silver-blue streaks descending into surface ripples)
        for rd in rainDrops {
            let rc = Int(rd.x / cellW), rr = Int(rd.y / cellH)
            let h = max(0, rd.z - 1.0)
            let dropA = min(0.88, 0.45 + (1.0 - min(1.0, h * 0.6)) * 0.45)
            if rc >= 0 && rc < cols && rr >= 0 && rr < rows {
                drawGlyph(ctx, "/", col: rc, row: rr, r: pal.splash.r, g: pal.splash.g, b: pal.splash.b, a: dropA)
            }
            if rc + 1 >= 0 && rc + 1 < cols && rr - 1 >= 0 && rr - 1 < rows {
                drawGlyph(ctx, "'", col: rc + 1, row: rr - 1, r: pal.ripple.r, g: pal.ripple.g, b: pal.ripple.b, a: dropA * 0.62)
            }
        }

        // Splash droplets
        for sp in splashes {
            let sc = Int(sp.x / cellW), sr = Int(sp.y / cellH)
            if sc >= 0 && sc < cols && sr >= 0 && sr < rows {
                let h = max(0, sp.z - 1.0)
                let ch: Character = h > 0.32 ? (sp.big ? "*" : "°") : (h > 0.14 ? "o" : "'")
                drawGlyph(ctx, ch, col: sc, row: sr, r: pal.splash.r, g: pal.splash.g, b: pal.splash.b, a: min(1, 0.58 + h * 1.4))
            }
        }

        // Trash crumbs floating toward Trash-Eater Koi
        for cr in trashCrumbs {
            let cc = Int(cr.x / cellW), crRow = Int(cr.y / cellH)
            if cc >= 0 && cc < cols && crRow >= 0 && crRow < rows {
                drawGlyph(ctx, cr.ch, col: cc, row: crRow, r: pal.gold.r, g: pal.gold.g, b: pal.gold.b, a: min(1.0, cr.life * 0.4))
            }
        }

        // Dragonfly
        if !config.minimalistMode, let df = dragonfly {
            let h = max(0, df.z - 1.0)
            let shC = Int((df.x + 14 + h * 36) / cellW), shR = Int((df.y + 12 + h * 30) / cellH)
            if shC >= 1 && shC < cols - 1 && shR >= 1 && shR < rows - 1 {
                drawGlyph(ctx, "+", col: shC, row: shR, r: pal.shadow.r, g: pal.shadow.g, b: pal.shadow.b, a: pal.shadowAlpha)
            }
            let dc = Int(df.x / cellW), dr = Int(df.y / cellH)
            if dc >= 3 && dc < cols - 3 && dr >= 3 && dr < rows - 3 {
                let tx = cos(df.angle), ty = sin(df.angle), nx = -ty, ny = tx
                drawGlyph(ctx, "o", col: Int(round(CGFloat(dc) + tx)), row: Int(round(CGFloat(dr) + ty)), r: pal.dragonfly.r * 1.15, g: pal.dragonfly.g * 1.15, b: pal.dragonfly.b * 1.15)
                drawGlyph(ctx, "#", col: dc, row: dr, r: pal.dragonfly.r * 1.15, g: pal.dragonfly.g * 1.15, b: pal.dragonfly.b * 1.15)
                drawGlyph(ctx, "=", col: Int(round(CGFloat(dc) - tx)), row: Int(round(CGFloat(dr) - ty)), r: pal.dragonfly.r, g: pal.dragonfly.g, b: pal.dragonfly.b)
                drawGlyph(ctx, ":", col: Int(round(CGFloat(dc) - tx * 2)), row: Int(round(CGFloat(dr) - ty * 2)), r: pal.dragonfly.r * 0.85, g: pal.dragonfly.g * 0.85, b: pal.dragonfly.b * 0.85)
                let flutter: CGFloat = sin(df.wingPhase) > 0 ? 1 : 0.65
                let wa = 0.55 + flutter * 0.35
                let w1 = round(1.6 + flutter * 0.8)
                drawGlyph(ctx, "~", col: Int(round(CGFloat(dc) + nx * w1)), row: Int(round(CGFloat(dr) + ny * w1)), r: pal.wing.r, g: pal.wing.g, b: pal.wing.b, a: wa)
                drawGlyph(ctx, "~", col: Int(round(CGFloat(dc) - nx * w1)), row: Int(round(CGFloat(dr) - ny * w1)), r: pal.wing.r, g: pal.wing.g, b: pal.wing.b, a: wa)
                drawGlyph(ctx, "-", col: Int(round(CGFloat(dc) + nx)), row: Int(round(CGFloat(dr) + ny)), r: pal.wing.r, g: pal.wing.g, b: pal.wing.b, a: wa)
                drawGlyph(ctx, "-", col: Int(round(CGFloat(dc) - nx)), row: Int(round(CGFloat(dr) - ny)), r: pal.wing.r, g: pal.wing.g, b: pal.wing.b, a: wa)
            }
        }

        // Fireflies at night/sunset
        if !config.minimalistMode && (pal.tod == "night" || pal.tod == "sunset") {
            let mult: CGFloat = pal.tod == "night" ? 1.0 : 0.45
            for ff in fireflies {
                let glow = max(0, sin(ff.phase))
                if glow > 0.15 {
                    let fc = Int(ff.x / cellW), fr = Int(ff.y / cellH)
                    if fc >= 0 && fc < cols && fr >= 0 && fr < rows {
                        drawGlyph(ctx, glow > 0.72 ? "*" : "·", col: fc, row: fr, r: pal.firefly.r, g: pal.firefly.g, b: pal.firefly.b, a: glow * mult)
                    }
                }
            }
        }

        // Pre-rasterized top-down Zen Garden Accent (Japanese Hinoki Bridge or Mossy River Stones — Koi swim underneath!)
        if !config.minimalistMode && config.pondAccent != "none" {
            ensurePondAccentCache()
            // Natural weathered cedar/hinoki wood & river granite palette inspired by Kyoto garden ponds
            let woodSeam   = config.monoMode ? pal.shadow : RGB(56, 40, 30)
            let woodMid    = config.monoMode ? pal.stone  : RGB(126, 94, 68)
            let woodSun    = config.monoMode ? pal.ripple : RGB(168, 128, 92)
            let cedarRail  = config.monoMode ? pal.white  : RGB(182, 124, 74) // Warm natural hinoki handrail
            let bronzePost = config.monoMode ? pal.shadow : RGB(46, 38, 34)   // Dark bronze finial cap
            let stoneWet   = config.monoMode ? pal.shadow : RGB(68, 76, 74)
            let stoneMid   = config.monoMode ? pal.stone  : RGB(114, 122, 118)
            let stoneTop   = config.monoMode ? pal.ripple : RGB(158, 166, 158)
            let mossDark   = config.monoMode ? pal.lotus  : RGB(66, 116, 62)
            let mossBright = config.monoMode ? pal.lotusVein : RGB(118, 174, 86)

            for sh in accentShadowCells {
                drawGlyph(ctx, sh.ch, col: sh.col, row: sh.row, r: pal.shadow.r, g: pal.shadow.g, b: pal.shadow.b, a: pal.shadowAlpha * 0.86)
            }
            for ac in accentCells {
                switch ac.kind {
                case 0: drawGlyph(ctx, ac.ch, col: ac.col, row: ac.row, r: woodSeam.r,   g: woodSeam.g,   b: woodSeam.b,   a: 0.96)
                case 1: drawGlyph(ctx, ac.ch, col: ac.col, row: ac.row, r: woodMid.r,    g: woodMid.g,    b: woodMid.b,    a: 0.97)
                case 2: drawGlyph(ctx, ac.ch, col: ac.col, row: ac.row, r: woodSun.r,    g: woodSun.g,    b: woodSun.b,    a: 0.98)
                case 3: drawGlyph(ctx, ac.ch, col: ac.col, row: ac.row, r: cedarRail.r,  g: cedarRail.g,  b: cedarRail.b,  a: 0.99)
                case 4: drawGlyph(ctx, ac.ch, col: ac.col, row: ac.row, r: bronzePost.r, g: bronzePost.g, b: bronzePost.b, a: 0.99)
                case 5: drawGlyph(ctx, ac.ch, col: ac.col, row: ac.row, r: stoneWet.r,   g: stoneWet.g,   b: stoneWet.b,   a: 0.95)
                case 6: drawGlyph(ctx, ac.ch, col: ac.col, row: ac.row, r: stoneMid.r,   g: stoneMid.g,   b: stoneMid.b,   a: 0.96)
                case 7: drawGlyph(ctx, ac.ch, col: ac.col, row: ac.row, r: stoneTop.r,   g: stoneTop.g,   b: stoneTop.b,   a: 0.98)
                case 8: drawGlyph(ctx, ac.ch, col: ac.col, row: ac.row, r: mossDark.r,   g: mossDark.g,   b: mossDark.b,   a: 0.96)
                default: drawGlyph(ctx, ac.ch, col: ac.col, row: ac.row, r: mossBright.r, g: mossBright.g, b: mossBright.b, a: 0.98)
                }
            }
        }

        // Overhanging corner tree branch + soft cast shadow (pre-rasterized -> ~0.1ms/frame!)
        if !config.minimalistMode && config.treeBranch != "none" {
            ensureTreeBranchCache(season: actSeason)
            let breeze = sin(time * 0.85) * 1.15
            let barkDark = config.monoMode ? pal.stone : RGB(78, 56, 44)
            let barkLight = config.monoMode ? pal.ripple : RGB(118, 86, 66)
            let branchPal = actSeason == "spring" ? pal.leafSpring : (actSeason == "summer" ? pal.leafSummer : pal.leafAutumn)
            let isWinter = actSeason == "winter"

            // 1. Cast shadow on pond water below
            for sh in branchShadowCells {
                let sc = sh.col + Int(round(breeze * sh.swayWeight))
                if sc >= 0 && sc < cols {
                    drawGlyph(ctx, sh.ch, col: sc, row: sh.row, r: pal.shadow.r, g: pal.shadow.g, b: pal.shadow.b, a: pal.shadowAlpha * 0.82)
                }
            }
            // 2. Branch wood & 3-tier top-down foliage/blossom canopy
            for bc in branchCells {
                let cc = bc.col + Int(round(breeze * bc.swayWeight))
                guard cc >= 0 && cc < cols else { continue }
                switch bc.kind {
                case 0: // Deep bark
                    drawGlyph(ctx, bc.ch, col: cc, row: bc.row, r: barkDark.r, g: barkDark.g, b: barkDark.b, a: 0.96)
                case 1: // Top-ridge sunlit bark
                    drawGlyph(ctx, bc.ch, col: cc, row: bc.row, r: barkLight.r, g: barkLight.g, b: barkLight.b, a: 0.96)
                case 2: // Lower shaded under-canopy (creates 3D top-down depth!)
                    let rgb = isWinter ? pal.snow : branchPal[bc.colorIdx % branchPal.count]
                    drawGlyph(ctx, bc.ch, col: cc, row: bc.row, r: rgb.r * 0.56, g: rgb.g * 0.56, b: rgb.b * 0.56, a: 0.92)
                case 3: // Mid-crown foliage
                    let rgb = isWinter ? pal.snow : branchPal[bc.colorIdx % branchPal.count]
                    drawGlyph(ctx, bc.ch, col: cc, row: bc.row, r: rgb.r * 0.88, g: rgb.g * 0.88, b: rgb.b * 0.88, a: 0.95)
                default: // Upper sunlit crown tips & blossoms
                    let rgb = isWinter ? pal.snow : branchPal[bc.colorIdx % branchPal.count]
                    drawGlyph(ctx, bc.ch, col: cc, row: bc.row, r: min(1, rgb.r * 1.22), g: min(1, rgb.g * 1.22), b: min(1, rgb.b * 1.22), a: 0.99)
                }
            }
        }

        // Flush all color-batched glyphs in ~90 CTFontDrawGlyphs calls instead of 10,000+!
        flushGlyphBatches(in: ctx)
    }
}
