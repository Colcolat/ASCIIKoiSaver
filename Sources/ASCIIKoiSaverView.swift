import AppKit
import QuartzCore
import ScreenSaver

@objc(ASCIIKoiSaverView)
final class ASCIIKoiSaverView: ScreenSaverView {
    private static let moduleName = "com.jj.ASCIIKoiSaver"

    private let engine = PondEngine()
    private var lastTimestamp: CFTimeInterval = 0
    private var configPanel: NSPanel?

    // Options sheet controls
    private var timePopup: NSPopUpButton?
    private var seasonPopup: NSPopUpButton?
    private var koiCountPopup: NSPopUpButton?
    private var clockCheckbox: NSButton?
    private var rainCheckbox: NSButton?
    private var monoCheckbox: NSButton?

    private var defaults: ScreenSaverDefaults? {
        ScreenSaverDefaults(forModuleWithName: Self.moduleName)
    }

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        registerDefaultSettings()
        animationTimeInterval = 1.0 / 30.0
        engine.resize(to: bounds.size)
        applySavedConfig()
    }

    private func registerDefaultSettings() {
        defaults?.register(defaults: [
            "timeMode": "auto",
            "season": "auto",
            "koiCount": 3,
            "showClock": true,
            "rainOn": false,
            "monoMode": false
        ])
    }

    private func applySavedConfig() {
        let d = defaults
        var cfg = SaverConfig()
        cfg.timeMode = d?.string(forKey: "timeMode") ?? "auto"
        cfg.season = d?.string(forKey: "season") ?? "auto"
        let kc = d?.integer(forKey: "koiCount") ?? 3
        cfg.koiCount = max(2, min(5, kc == 0 ? 3 : kc))
        cfg.showClock = d?.bool(forKey: "showClock") ?? true
        cfg.rainOn = d?.bool(forKey: "rainOn") ?? false
        cfg.monoMode = d?.bool(forKey: "monoMode") ?? false
        cfg.isPreview = isPreview
        engine.applyConfig(cfg)
    }

    override func startAnimation() {
        super.startAnimation()
        lastTimestamp = CACurrentMediaTime()
        applySavedConfig()
    }

    override func animateOneFrame() {
        let now = CACurrentMediaTime()
        let dt = lastTimestamp > 0 ? CGFloat(now - lastTimestamp) : (1.0 / 30.0)
        lastTimestamp = now
        engine.resize(to: bounds.size)
        engine.step(dt: dt)
        setNeedsDisplay(bounds)
    }

    override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        engine.draw(in: ctx, rect: bounds)
    }

    // MARK: - Native macOS Options Sheet (English)

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        if let existing = configPanel {
            syncControlsFromDefaults()
            return existing
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "ASCII Koi Pond Options"
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.hidesOnDeactivate = false
        panel.contentMinSize = NSSize(width: 390, height: 280)
        panel.contentMaxSize = NSSize(width: 390, height: 280)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 390, height: 280))
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = content
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: 390),
            content.heightAnchor.constraint(equalToConstant: 280)
        ])

        func makeLabel(_ text: String, frame: NSRect) -> NSTextField {
            let lbl = NSTextField(labelWithString: text)
            lbl.frame = frame
            lbl.alignment = .right
            lbl.font = .systemFont(ofSize: 13)
            return lbl
        }

        // Time of Day
        content.addSubview(makeLabel("Time of Day:", frame: NSRect(x: 20, y: 226, width: 120, height: 22)))
        let tPop = NSPopUpButton(frame: NSRect(x: 150, y: 222, width: 215, height: 26), pullsDown: false)
        tPop.addItems(withTitles: ["Automatic (System Clock)", "Day", "Sunset", "Night (Fireflies)"])
        content.addSubview(tPop)
        timePopup = tPop

        // Season
        content.addSubview(makeLabel("Season:", frame: NSRect(x: 20, y: 188, width: 120, height: 22)))
        let sPop = NSPopUpButton(frame: NSRect(x: 150, y: 184, width: 215, height: 26), pullsDown: false)
        sPop.addItems(withTitles: ["Automatic (Calendar)", "Spring (Sakura)", "Summer", "Autumn (Maple Leaves)", "Winter (Snow)"])
        content.addSubview(sPop)
        seasonPopup = sPop

        // Koi Count
        content.addSubview(makeLabel("Koi Count:", frame: NSRect(x: 20, y: 150, width: 120, height: 22)))
        let kPop = NSPopUpButton(frame: NSRect(x: 150, y: 146, width: 215, height: 26), pullsDown: false)
        kPop.addItems(withTitles: ["2 Koi", "3 Koi", "4 Koi", "5 Koi"])
        content.addSubview(kPop)
        koiCountPopup = kPop

        // Checkboxes
        let cBox = NSButton(checkboxWithTitle: "Show submerged stone clock", target: nil, action: nil)
        cBox.frame = NSRect(x: 150, y: 112, width: 220, height: 22)
        content.addSubview(cBox)
        clockCheckbox = cBox

        let rBox = NSButton(checkboxWithTitle: "Enable gentle rain", target: nil, action: nil)
        rBox.frame = NSRect(x: 150, y: 84, width: 220, height: 22)
        content.addSubview(rBox)
        rainCheckbox = rBox

        let mBox = NSButton(checkboxWithTitle: "Pure ASCII mode (monochrome)", target: nil, action: nil)
        mBox.frame = NSRect(x: 150, y: 56, width: 220, height: 22)
        content.addSubview(mBox)
        monoCheckbox = mBox

        // Buttons
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelOptions))
        cancelBtn.frame = NSRect(x: 192, y: 16, width: 88, height: 30)
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1b}"
        content.addSubview(cancelBtn)

        let okBtn = NSButton(title: "OK", target: self, action: #selector(saveOptions))
        okBtn.frame = NSRect(x: 286, y: 16, width: 88, height: 30)
        okBtn.bezelStyle = .rounded
        okBtn.keyEquivalent = "\r"
        content.addSubview(okBtn)

        configPanel = panel
        syncControlsFromDefaults()
        return panel
    }

    private func syncControlsFromDefaults() {
        let d = defaults
        let timeValues = ["auto", "day", "sunset", "night"]
        let tVal = d?.string(forKey: "timeMode") ?? "auto"
        timePopup?.selectItem(at: timeValues.firstIndex(of: tVal) ?? 0)

        let seasonValues = ["auto", "spring", "summer", "autumn", "winter"]
        let sVal = d?.string(forKey: "season") ?? "auto"
        seasonPopup?.selectItem(at: seasonValues.firstIndex(of: sVal) ?? 0)

        let koiCount = max(2, min(5, d?.integer(forKey: "koiCount") ?? 3))
        koiCountPopup?.selectItem(at: koiCount - 2)

        clockCheckbox?.state = (d?.bool(forKey: "showClock") ?? true) ? .on : .off
        rainCheckbox?.state = (d?.bool(forKey: "rainOn") ?? false) ? .on : .off
        monoCheckbox?.state = (d?.bool(forKey: "monoMode") ?? false) ? .on : .off
    }

    @objc private func saveOptions() {
        let timeValues = ["auto", "day", "sunset", "night"]
        let seasonValues = ["auto", "spring", "summer", "autumn", "winter"]

        if let d = defaults {
            let tIdx = timePopup?.indexOfSelectedItem ?? 0
            let sIdx = seasonPopup?.indexOfSelectedItem ?? 0
            let kIdx = koiCountPopup?.indexOfSelectedItem ?? 1

            d.set(timeValues[max(0, min(timeValues.count - 1, tIdx))], forKey: "timeMode")
            d.set(seasonValues[max(0, min(seasonValues.count - 1, sIdx))], forKey: "season")
            d.set(kIdx + 2, forKey: "koiCount")
            d.set(clockCheckbox?.state == .on, forKey: "showClock")
            d.set(rainCheckbox?.state == .on, forKey: "rainOn")
            d.set(monoCheckbox?.state == .on, forKey: "monoMode")
            d.synchronize()
        }

        applySavedConfig()
        dismissSheet()
    }

    @objc private func cancelOptions() {
        dismissSheet()
    }

    private func dismissSheet() {
        guard let panel = configPanel else { return }
        if let parent = panel.sheetParent {
            parent.endSheet(panel)
        } else {
            NSApp.endSheet(panel)
        }
        panel.orderOut(nil)
    }
}
