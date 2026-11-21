import AppKit
import Foundation
import ServiceManagement

@main
final class ASCIIKoiDesktopApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let wallpaper = DesktopWallpaperManager()
    private let agentMonitor = AgentMonitor()
    private let trashMonitor = TrashMonitor()
    private let musicMonitor = MusicMonitor()
    private let nowPlayingMonitor = NowPlayingMonitor()
    private let weatherMonitor = WeatherMonitor()

    private var statusMenuItem: NSMenuItem!
    private var agentsMenuItem: NSMenuItem!
    private var musicMenuItem: NSMenuItem!
    private var weatherMenuItem: NSMenuItem!
    private var rainMenuItem: NSMenuItem!
    private var vicePreviewMenuItem: NSMenuItem!
    private var feedTrashMenuItem: NSMenuItem!
    private var pauseMenuItem: NSMenuItem!

    private var config = SaverConfig()
    private var liveWeatherEnabled: Bool = true
    private var manualViceCityPreview: Bool = false
    private var songTriggersViceCity: Bool = false

    static func main() {
        let app = NSApplication.shared
        let delegate = ASCIIKoiDesktopApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // Menu bar only (no Dock icon)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadPreferences()
        setupStatusBar()

        wallpaper.config = config
        wallpaper.onStatusChanged = { [weak self] running, autoPaused in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.wallpaper.manuallyPaused {
                    self.statusMenuItem.title = "Status: Paused (Manual)"
                } else if autoPaused {
                    self.statusMenuItem.title = "Status: Auto-Paused (Fullscreen)"
                } else if running {
                    if self.wallpaper.isLowPowerActive {
                        let fps = self.wallpaper.batteryPercent <= 25 ? 14 : 16
                        self.statusMenuItem.title = "Status: Active · Low Power (\(fps) FPS · \(self.wallpaper.batteryPercent)%)"
                    } else {
                        self.statusMenuItem.title = "Status: Active (Desktop)"
                    }
                }
            }
        }
        wallpaper.start()

        agentMonitor.onAgentsChanged = { [weak self] agents in
            guard let self = self else { return }
            self.wallpaper.syncAgents(agents)
            if agents.isEmpty {
                self.agentsMenuItem.title = "AI Agents: Idle"
            } else {
                let gCount = agents.filter { $0.model == .gemini }.count
                let cCount = agents.filter { $0.model == .claude }.count
                var parts: [String] = []
                if gCount > 0 { parts.append("Gemini ×\(gCount)") }
                if cCount > 0 { parts.append("Claude ×\(cCount)") }
                self.agentsMenuItem.title = "AI Agents: " + parts.joined(separator: ", ")
            }
        }
        agentMonitor.start()

        trashMonitor.onCountChanged = { [weak self] count in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.feedTrashMenuItem.title = count > 0 ? "Feed Trash to Koi (\(count) items)…" : "Feed Trash to Koi (Empty)"
                self.feedTrashMenuItem.isEnabled = count > 0
            }
        }
        trashMonitor.onNewTrashItems = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Curious visual visit only — never auto-deletes!
                self.wallpaper.triggerTrashVisit { size in
                    self.trashMonitor.dockTrashPoint(in: size)
                }
            }
        }
        trashMonitor.start()

        wallpaper.audioFrameProvider = { [weak self] in
            guard let frame = self?.musicMonitor.consumeAudioFrame() else { return (0, 0, false, []) }
            return (frame.bass, frame.beatHit, frame.playing, frame.spectrum)
        }
        musicMonitor.onStatusChanged = { [weak self] _, detail in
            self?.musicMenuItem.title = detail
        }
        if config.musicReactive {
            musicMonitor.start()
        } else {
            musicMenuItem.title = "Music: Off"
        }

        nowPlayingMonitor.isSystemAudioPlaying = { [weak self] in
            self?.musicMonitor.isAudioActiveNow()
        }
        nowPlayingMonitor.onTrackChanged = { [weak self] track in
            guard let self = self else { return }
            self.songTriggersViceCity = track.isGTA6
            self.syncViceCityState()
            if track.isGTA6 {
                let label = track.title.isEmpty ? "GTA VI" : track.title
                self.musicMenuItem.title = "Music: 🌴 Vice City · \(label)"
            } else if track.isPlaying && !track.title.isEmpty {
                self.musicMenuItem.title = "Music: ♪ \(track.title)"
            } else if self.config.musicReactive {
                self.musicMenuItem.title = "Music: Real-Time Beat Sync ♪"
            }
        }
        nowPlayingMonitor.start()

        weatherMonitor.onWeatherUpdated = { [weak self] st in
            guard let self = self else { return }
            self.weatherMenuItem.title = st.summary
            if self.liveWeatherEnabled {
                self.config.cloudDensity = st.cloudDensity
                self.config.rainOn = st.isRaining
                self.rainMenuItem?.state = st.isRaining ? .on : .off
                self.wallpaper.config = self.config
            }
        }
        if liveWeatherEnabled {
            weatherMonitor.start()
        } else {
            weatherMenuItem.title = "Weather: Manual"
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        nowPlayingMonitor.stop()
        weatherMonitor.stop()
        musicMonitor.stop()
        agentMonitor.stop()
        trashMonitor.stop()
        wallpaper.stop()
    }

    // MARK: - Preferences

    private func loadPreferences() {
        let d = UserDefaults.standard
        config.timeMode = d.string(forKey: "timeMode") ?? "auto"
        config.season = d.string(forKey: "season") ?? "auto"
        let kc = d.integer(forKey: "koiCount")
        config.koiCount = kc > 0 ? max(2, min(8, kc)) : 5
        config.showClock = d.object(forKey: "showClock") == nil ? true : d.bool(forKey: "showClock")
        config.rainOn = d.bool(forKey: "rainOn")
        config.monoMode = d.bool(forKey: "monoMode")
        config.minimalistMode = d.bool(forKey: "minimalistMode")
        config.musicReactive = d.object(forKey: "musicReactive") == nil ? true : d.bool(forKey: "musicReactive")
        config.treeBranch = d.string(forKey: "treeBranch") ?? "bottomRight"
        liveWeatherEnabled = d.object(forKey: "liveWeather") == nil ? true : d.bool(forKey: "liveWeather")
        wallpaper.autoLowPowerOnBattery = d.object(forKey: "autoLowPower") == nil ? true : d.bool(forKey: "autoLowPower")
        wallpaper.desktopClicksEnabled = d.object(forKey: "desktopClicks") == nil ? true : d.bool(forKey: "desktopClicks")
    }

    private func savePreferences() {
        let d = UserDefaults.standard
        d.set(config.timeMode, forKey: "timeMode")
        d.set(config.season, forKey: "season")
        d.set(config.koiCount, forKey: "koiCount")
        d.set(config.showClock, forKey: "showClock")
        d.set(config.rainOn, forKey: "rainOn")
        d.set(config.monoMode, forKey: "monoMode")
        d.set(config.minimalistMode, forKey: "minimalistMode")
        d.set(config.musicReactive, forKey: "musicReactive")
        d.set(config.treeBranch, forKey: "treeBranch")
        d.set(liveWeatherEnabled, forKey: "liveWeather")
        d.set(wallpaper.autoLowPowerOnBattery, forKey: "autoLowPower")
        d.set(wallpaper.desktopClicksEnabled, forKey: "desktopClicks")
        wallpaper.config = config
    }

    // MARK: - Menu Bar UI

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.title = "><((°>"
            btn.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
            btn.toolTip = "ASCII Koi Desktop"
        }

        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "Status: Active (Desktop)", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        agentsMenuItem = NSMenuItem(title: "AI Agents: Idle", action: nil, keyEquivalent: "")
        agentsMenuItem.isEnabled = false
        menu.addItem(agentsMenuItem)

        musicMenuItem = NSMenuItem(title: "Music: Idle", action: nil, keyEquivalent: "")
        musicMenuItem.isEnabled = false
        menu.addItem(musicMenuItem)

        weatherMenuItem = NSMenuItem(title: "Weather: Checking…", action: nil, keyEquivalent: "")
        weatherMenuItem.isEnabled = false
        menu.addItem(weatherMenuItem)

        menu.addItem(.separator())

        feedTrashMenuItem = NSMenuItem(title: "Feed Trash to Koi (Empty)", action: #selector(feedTrashClicked), keyEquivalent: "t")
        feedTrashMenuItem.keyEquivalentModifierMask = [.option, .command]
        feedTrashMenuItem.target = self
        menu.addItem(feedTrashMenuItem)

        pauseMenuItem = NSMenuItem(title: "Pause Wallpaper", action: #selector(togglePause), keyEquivalent: "p")
        pauseMenuItem.target = self
        menu.addItem(pauseMenuItem)

        menu.addItem(.separator())

        // AI Agent Demo Submenu
        let aiSub = NSMenu()
        let demoG = NSMenuItem(title: "Toggle Gemini Koi (+ Subagents)", action: #selector(toggleDemoGemini), keyEquivalent: "")
        demoG.target = self
        aiSub.addItem(demoG)
        let demoC = NSMenuItem(title: "Toggle Claude Koi (+ Subagents)", action: #selector(toggleDemoClaude), keyEquivalent: "")
        demoC.target = self
        aiSub.addItem(demoC)
        let cycleS = NSMenuItem(title: "Cycle Agent State (Thinking → Editing → Waiting → Error)", action: #selector(cycleAgentState), keyEquivalent: "")
        cycleS.target = self
        aiSub.addItem(cycleS)
        let clearD = NSMenuItem(title: "Finish All Demo Agents (Jump & Exit)", action: #selector(clearDemos), keyEquivalent: "")
        clearD.target = self
        aiSub.addItem(clearD)
        let aiItem = NSMenuItem(title: "AI Agent Koi (Test)", action: nil, keyEquivalent: "")
        aiItem.submenu = aiSub
        menu.addItem(aiItem)

        // Time of Day Submenu
        let timeSub = NSMenu()
        for (title, val) in [("Automatic (System Clock)", "auto"), ("Morning / Day", "day"), ("Afternoon (Warm Sun)", "afternoon"), ("Sunset", "sunset"), ("Night (Fireflies & Stars)", "night")] {
            let item = NSMenuItem(title: title, action: #selector(selectTimeMode(_:)), keyEquivalent: "")
            item.representedObject = val
            item.state = (config.timeMode == val) ? .on : .off
            item.target = self
            timeSub.addItem(item)
        }
        let timeItem = NSMenuItem(title: "Time of Day", action: nil, keyEquivalent: "")
        timeItem.submenu = timeSub
        menu.addItem(timeItem)

        // Season Submenu
        let seasonSub = NSMenu()
        for (title, val) in [("Automatic (Day of Week)", "auto"), ("Spring (Sakura)", "spring"), ("Summer", "summer"), ("Autumn (Maple Leaves)", "autumn"), ("Winter (Snow)", "winter")] {
            let item = NSMenuItem(title: title, action: #selector(selectSeason(_:)), keyEquivalent: "")
            item.representedObject = val
            item.state = (config.season == val) ? .on : .off
            item.target = self
            seasonSub.addItem(item)
        }
        let seasonItem = NSMenuItem(title: "Season", action: nil, keyEquivalent: "")
        seasonItem.submenu = seasonSub
        menu.addItem(seasonItem)

        // Koi Count Submenu
        let koiSub = NSMenu()
        for n in 2...8 {
            let item = NSMenuItem(title: "\(n) Ambient Koi", action: #selector(selectKoiCount(_:)), keyEquivalent: "")
            item.tag = n
            item.state = (config.koiCount == n) ? .on : .off
            item.target = self
            koiSub.addItem(item)
        }
        let koiItem = NSMenuItem(title: "Ambient Koi Count", action: nil, keyEquivalent: "")
        koiItem.submenu = koiSub
        menu.addItem(koiItem)

        // Overhanging Tree Branch Submenu
        let branchSub = NSMenu()
        for (title, val) in [
            ("Off", "none"),
            ("Bottom-Right Corner", "bottomRight"),
            ("Top-Right Corner", "topRight"),
            ("Top-Left Corner", "topLeft"),
            ("Bottom-Left Corner", "bottomLeft")
        ] {
            let item = NSMenuItem(title: title, action: #selector(selectTreeBranch(_:)), keyEquivalent: "")
            item.representedObject = val
            item.state = (config.treeBranch == val) ? .on : .off
            item.target = self
            branchSub.addItem(item)
        }
        let branchItem = NSMenuItem(title: "Tree Branch", action: nil, keyEquivalent: "")
        branchItem.submenu = branchSub
        menu.addItem(branchItem)

        menu.addItem(.separator())

        // Toggles
        @discardableResult
        func addToggle(_ title: String, isOn: Bool, action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.state = isOn ? .on : .off
            item.target = self
            menu.addItem(item)
            return item
        }
        addToggle("Minimalist Mode (Transparent over Wallpaper)", isOn: config.minimalistMode, action: #selector(toggleMinimalist(_:)))
        addToggle("Music Reactive ♪", isOn: config.musicReactive, action: #selector(toggleMusicReactive(_:)))
        vicePreviewMenuItem = addToggle("Preview Vice City Mode 🌴 (GTA VI)", isOn: manualViceCityPreview, action: #selector(toggleViceCityPreview(_:)))
        addToggle("Live Weather Sync (Auto Rain & Clouds)", isOn: liveWeatherEnabled, action: #selector(toggleLiveWeather(_:)))
        addToggle("Auto Low Power on Battery (14–16 FPS)", isOn: wallpaper.autoLowPowerOnBattery, action: #selector(toggleAutoLowPower(_:)))
        addToggle("Submerged Stone Clock", isOn: config.showClock, action: #selector(toggleClock(_:)))
        rainMenuItem = addToggle("Gentle Rain", isOn: config.rainOn, action: #selector(toggleRain(_:)))
        addToggle("Pure ASCII Mode (Monochrome)", isOn: config.monoMode, action: #selector(toggleMono(_:)))
        addToggle("Desktop Click Ripples", isOn: wallpaper.desktopClicksEnabled, action: #selector(toggleDesktopClicks(_:)))
        addToggle("Launch at Login", isOn: SMAppService.mainApp.status == .enabled, action: #selector(toggleLaunchAtLogin(_:)))

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit ASCII Koi Desktop", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Menu Actions

    @objc private func feedTrashClicked() {
        let count = trashMonitor.countTrashItems()
        guard count > 0 else { return }

        let alert = NSAlert()
        alert.messageText = "Feed Trash to Koi?"
        alert.informativeText = "The Trash-Eater Koi will swim to your Dock and permanently empty \(count) item(s) from the Trash."
        alert.addButton(withTitle: "Feed & Empty Trash")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            wallpaper.triggerFeedTrash(dockPointProvider: { size in
                self.trashMonitor.dockTrashPoint(in: size)
            }, onBite: {
                self.trashMonitor.emptyTrashSafely { _ in }
            })
        }
    }

    @objc private func togglePause() {
        wallpaper.manuallyPaused.toggle()
        pauseMenuItem.title = wallpaper.manuallyPaused ? "Resume Wallpaper" : "Pause Wallpaper"
    }

    @objc private func toggleDemoGemini() {
        agentMonitor.toggleDemo(model: .gemini, state: .editing, withSubagents: true)
    }

    @objc private func toggleDemoClaude() {
        agentMonitor.toggleDemo(model: .claude, state: .thinking, withSubagents: true)
    }

    @objc private func cycleAgentState() {
        agentMonitor.cycleDemoStates()
    }

    @objc private func clearDemos() {
        agentMonitor.clearDemos()
    }

    @objc private func selectTimeMode(_ sender: NSMenuItem) {
        guard let val = sender.representedObject as? String else { return }
        config.timeMode = val
        sender.menu?.items.forEach { $0.state = ($0 == sender) ? .on : .off }
        savePreferences()
    }

    @objc private func selectSeason(_ sender: NSMenuItem) {
        guard let val = sender.representedObject as? String else { return }
        config.season = val
        sender.menu?.items.forEach { $0.state = ($0 == sender) ? .on : .off }
        savePreferences()
    }

    @objc private func selectKoiCount(_ sender: NSMenuItem) {
        config.koiCount = sender.tag
        sender.menu?.items.forEach { $0.state = ($0 == sender) ? .on : .off }
        savePreferences()
    }

    @objc private func selectTreeBranch(_ sender: NSMenuItem) {
        guard let val = sender.representedObject as? String else { return }
        config.treeBranch = val
        sender.menu?.items.forEach {
            if $0.action == #selector(selectTreeBranch(_:)) {
                $0.state = ($0 == sender) ? .on : .off
            }
        }
        savePreferences()
    }

    private func syncViceCityState() {
        let shouldEnable = manualViceCityPreview || songTriggersViceCity
        if config.viceCityMode != shouldEnable {
            config.viceCityMode = shouldEnable
            wallpaper.config = config
        }
    }

    @objc private func toggleViceCityPreview(_ sender: NSMenuItem) {
        manualViceCityPreview.toggle()
        sender.state = manualViceCityPreview ? .on : .off
        syncViceCityState()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled {
                try svc.unregister()
                sender.state = .off
            } else {
                try svc.register()
                sender.state = .on
            }
        } catch {
            sender.state = (svc.status == .enabled) ? .on : .off
        }
    }

    @objc private func toggleLiveWeather(_ sender: NSMenuItem) {
        liveWeatherEnabled.toggle()
        sender.state = liveWeatherEnabled ? .on : .off
        if liveWeatherEnabled {
            weatherMonitor.start()
        } else {
            weatherMonitor.stop()
            weatherMenuItem.title = "Weather: Manual"
            config.cloudDensity = 0.90
        }
        savePreferences()
    }

    @objc private func toggleAutoLowPower(_ sender: NSMenuItem) {
        wallpaper.autoLowPowerOnBattery.toggle()
        sender.state = wallpaper.autoLowPowerOnBattery ? .on : .off
        savePreferences()
    }

    @objc private func toggleMinimalist(_ sender: NSMenuItem) {
        config.minimalistMode.toggle()
        sender.state = config.minimalistMode ? .on : .off
        savePreferences()
    }

    @objc private func toggleMusicReactive(_ sender: NSMenuItem) {
        config.musicReactive.toggle()
        sender.state = config.musicReactive ? .on : .off
        if config.musicReactive { musicMonitor.start() } else { musicMonitor.stop() }
        savePreferences()
    }

    @objc private func toggleClock(_ sender: NSMenuItem) {
        config.showClock.toggle()
        sender.state = config.showClock ? .on : .off
        savePreferences()
    }

    @objc private func toggleRain(_ sender: NSMenuItem) {
        config.rainOn.toggle()
        sender.state = config.rainOn ? .on : .off
        savePreferences()
    }

    @objc private func toggleMono(_ sender: NSMenuItem) {
        config.monoMode.toggle()
        sender.state = config.monoMode ? .on : .off
        savePreferences()
    }

    @objc private func toggleDesktopClicks(_ sender: NSMenuItem) {
        wallpaper.desktopClicksEnabled.toggle()
        sender.state = wallpaper.desktopClicksEnabled ? .on : .off
        savePreferences()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
