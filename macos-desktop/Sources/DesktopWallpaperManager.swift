import AppKit
import CoreGraphics
import IOKit.ps
import QuartzCore

private final class DesktopPondView: NSView {
    let engine = PondEngine()

    override var isOpaque: Bool { !engine.config.minimalistMode }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        engine.draw(in: ctx, rect: bounds)
    }
}

final class DesktopWallpaperManager {
    private var windows: [NSWindow] = []
    private var views: [DesktopPondView] = []
    private var renderTimer: Timer?
    private var currentFPS: Double = 24.0
    private var visibilityTimer: Timer?
    private var batteryTimer: Timer?
    private var clickMonitor: Any?
    private var lastTimestamp: CFTimeInterval = 0

    var autoLowPowerOnBattery: Bool = true {
        didSet { checkBatteryState() }
    }
    private(set) var isOnBattery: Bool = false
    private(set) var batteryPercent: Int = 100
    var isLowPowerActive: Bool { autoLowPowerOnBattery && isOnBattery }

    var config = SaverConfig() {
        didSet {
            for (win, v) in zip(windows, views) {
                v.engine.applyConfig(config)
                win.isOpaque = !config.minimalistMode
                win.backgroundColor = config.minimalistMode
                    ? .clear
                    : NSColor(calibratedRed: 0.02, green: 0.08, blue: 0.10, alpha: 1.0)
                win.invalidateShadow()
                v.needsDisplay = true
            }
        }
    }

    var audioFrameProvider: (() -> (bass: CGFloat, beatHit: CGFloat, playing: Bool))?

    var desktopClicksEnabled: Bool = true
    var manuallyPaused: Bool = false {
        didSet { updateTimerState() }
    }
    private(set) var isAutoPaused: Bool = false
    private var isScreenLocked: Bool = false

    var onStatusChanged: ((_ running: Bool, _ autoPaused: Bool) -> Void)?

    func start() {
        rebuildWindows()
        registerObservers()
        startClickMonitor()

        visibilityTimer?.invalidate()
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            self?.checkVisibility()
        }
        checkVisibility()

        batteryTimer?.invalidate()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in
            self?.checkBatteryState()
        }
        batteryTimer?.tolerance = 5.0
        checkBatteryState()
    }

    func stop() {
        renderTimer?.invalidate(); renderTimer = nil
        visibilityTimer?.invalidate(); visibilityTimer = nil
        batteryTimer?.invalidate(); batteryTimer = nil
        if let mon = clickMonitor { NSEvent.removeMonitor(mon); clickMonitor = nil }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
    }

    func syncAgents(_ agents: [AgentDescriptor]) {
        for v in views { v.engine.syncAgents(agents) }
    }

    func triggerTrashVisit(dockPointProvider: (CGSize) -> CGPoint) {
        guard let mainView = views.first else { return }
        mainView.engine.triggerTrashVisit(at: dockPointProvider(mainView.bounds.size))
    }

    func triggerFeedTrash(dockPointProvider: (CGSize) -> CGPoint, onBite: @escaping () -> Void) {
        guard let mainView = views.first else { onBite(); return }
        mainView.engine.triggerFeedTrash(at: dockPointProvider(mainView.bounds.size), onBite: onBite)
    }

    // MARK: - Desktop Windows

    private func rebuildWindows() {
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        views.removeAll()

        let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        for screen in NSScreen.screens {
            let win = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.setFrame(screen.frame, display: true)
            win.level = desktopLevel
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            win.ignoresMouseEvents = true
            win.isOpaque = !config.minimalistMode
            win.hasShadow = false
            win.backgroundColor = config.minimalistMode
                ? .clear
                : NSColor(calibratedRed: 0.02, green: 0.08, blue: 0.10, alpha: 1.0)
            win.isReleasedWhenClosed = false

            let pondView = DesktopPondView(frame: NSRect(origin: .zero, size: screen.frame.size))
            pondView.autoresizingMask = [.width, .height]
            pondView.engine.resize(to: screen.frame.size)
            pondView.engine.applyConfig(config)
            win.contentView = pondView
            win.orderBack(nil)

            windows.append(win)
            views.append(pondView)
        }
    }

    // MARK: - Fullscreen & Occlusion Detection (0% CPU when hidden)

    private func registerObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(self, selector: #selector(handleEnvironmentChange), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(handleEnvironmentChange), name: NSWorkspace.didActivateApplicationNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenChange), name: NSApplication.didChangeScreenParametersNotification, object: nil)

        let dist = DistributedNotificationCenter.default()
        dist.addObserver(self, selector: #selector(handleScreenLocked), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dist.addObserver(self, selector: #selector(handleScreenUnlocked), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func handleEnvironmentChange() {
        checkVisibility()
    }

    @objc private func handleScreenChange() {
        rebuildWindows()
        checkVisibility()
    }

    @objc private func handleScreenLocked() {
        isScreenLocked = true
        updateTimerState()
    }

    @objc private func handleScreenUnlocked() {
        isScreenLocked = false
        checkVisibility()
    }

    private func checkVisibility() {
        if isScreenLocked {
            isAutoPaused = true
            updateTimerState()
            return
        }

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        // Inspect visible normal-layer windows across all screens
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            isAutoPaused = false
            updateTimerState()
            return
        }

        let myPid = ProcessInfo.processInfo.processIdentifier
        let primaryHeight = screens.first?.frame.height ?? 900

        var visibleWindowRects: [CGRect] = []
        for info in infoList {
            let layer = (info[kCGWindowLayer as String] as? Int) ?? 0
            if layer != 0 { continue } // Normal app windows & fullscreen spaces live on layer 0
            let ownerPid = (info[kCGWindowOwnerPID as String] as? Int32) ?? 0
            if ownerPid == myPid { continue }
            let alpha = (info[kCGWindowAlpha as String] as? Double) ?? 1.0
            if alpha < 0.85 { continue }
            let owner = (info[kCGWindowOwnerName as String] as? String) ?? ""
            if owner == "Dock" || owner == "Window Server" || owner == "Wallpaper" { continue }

            if let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
               let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
               rect.width > 100 && rect.height > 100 {
                visibleWindowRects.append(rect)
            }
        }

        // Check if EVERY display is covered (>=94% area) by a fullscreen or maximized window
        var allScreensCovered = true
        for screen in screens {
            // Convert NSScreen frame (bottom-left origin) to CGWindow coords (top-left origin)
            let cgScreenRect = CGRect(
                x: screen.frame.minX,
                y: primaryHeight - screen.frame.maxY,
                width: screen.frame.width,
                height: screen.frame.height
            )
            let screenArea = cgScreenRect.width * cgScreenRect.height
            var covered = false
            for wr in visibleWindowRects {
                let inter = cgScreenRect.intersection(wr)
                if !inter.isNull && (inter.width * inter.height) >= screenArea * 0.94 {
                    covered = true
                    break
                }
            }
            if !covered {
                allScreensCovered = false
                break
            }
        }

        isAutoPaused = allScreensCovered
        updateTimerState()
    }

    private func updateTimerState() {
        let shouldRun = !manuallyPaused && !isAutoPaused && !isScreenLocked
        if shouldRun {
            if renderTimer == nil {
                lastTimestamp = CACurrentMediaTime()
                startRenderTimer(fps: currentFPS)
            }
        } else {
            renderTimer?.invalidate()
            renderTimer = nil
        }
        onStatusChanged?(shouldRun, isAutoPaused)
    }

    private func checkBatteryState() {
        var onBat = false
        var pct = 100
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for src in sources {
                if let desc = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any] {
                    if let state = desc[kIOPSPowerSourceStateKey as String] as? String {
                        onBat = (state == kIOPSBatteryPowerValue as String)
                    }
                    if let cur = desc[kIOPSCurrentCapacityKey as String] as? Int,
                       let cap = desc[kIOPSMaxCapacityKey as String] as? Int, cap > 0 {
                        pct = max(0, min(100, Int(Double(cur) / Double(cap) * 100.0)))
                    }
                    break
                }
            }
        }
        let changed = (onBat != isOnBattery) || (pct != batteryPercent)
        isOnBattery = onBat
        batteryPercent = pct
        if changed {
            let running = !manuallyPaused && !isAutoPaused && !isScreenLocked
            onStatusChanged?(running, isAutoPaused)
        }
    }

    private func startRenderTimer(fps: Double) {
        renderTimer?.invalidate()
        currentFPS = fps
        let interval = 1.0 / fps
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Larger tolerance in Low Power lets Apple Silicon coalesce frames onto Efficiency cores
        timer.tolerance = fps <= 16.0 ? 0.014 : (fps <= 25.0 ? 0.005 : 0.001)
        renderTimer = timer
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = lastTimestamp > 0 ? CGFloat(now - lastTimestamp) : CGFloat(1.0 / currentFPS)
        lastTimestamp = now
        let audio = audioFrameProvider?() ?? (bass: 0, beatHit: 0, playing: false)

        // Adaptive FPS: ultra-cool Low Power on battery (14–16 FPS), 24 FPS AC idle, 36 FPS AC music
        let desiredFPS: Double
        if isLowPowerActive {
            if batteryPercent <= 25 {
                desiredFPS = 14.0
            } else {
                desiredFPS = (config.musicReactive && audio.playing) ? 24.0 : 16.0
            }
        } else {
            desiredFPS = (config.musicReactive && audio.playing) ? 36.0 : 24.0
        }
        if desiredFPS != currentFPS {
            startRenderTimer(fps: desiredFPS)
        }

        for v in views {
            v.engine.updateAudio(bass: audio.bass, beatHit: audio.beatHit, playing: audio.playing)
            v.engine.step(dt: dt)
            v.needsDisplay = true
        }
    }

    // MARK: - Passive Desktop Click Ripples (Finder only)

    private func startClickMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self = self, self.desktopClicksEnabled, !self.manuallyPaused, !self.isAutoPaused else { return }
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return }
            let loc = NSEvent.mouseLocation
            for (win, view) in zip(self.windows, self.views) {
                if win.frame.contains(loc) {
                    let localX = loc.x - win.frame.minX
                    let localY = win.frame.maxY - loc.y // Top-down pond coords
                    view.engine.onClick(x: localX, y: localY)
                    break
                }
            }
        }
    }
}
