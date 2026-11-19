import AppKit
import Foundation

/// Monitors ~/.Trash item count, detects macOS Dock orientation for Trash coordinates,
/// and provides a safe explicit empty-trash helper triggered only by user action.
final class TrashMonitor {
    var onNewTrashItems: ((Int) -> Void)?
    var onCountChanged: ((Int) -> Void)?

    private(set) var itemCount: Int = 0
    private var timer: Timer?

    private let trashURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")

    func start() {
        itemCount = countTrashItems()
        onCountChanged?(itemCount)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let current = countTrashItems()
        if current != itemCount {
            let increased = current > itemCount
            itemCount = current
            onCountChanged?(current)
            if increased {
                onNewTrashItems?(current)
            }
        }
    }

    func countTrashItems() -> Int {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: trashURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return 0 }
        return items.count
    }

    /// Computes the approximate screen coordinate (top-down pond space) of the Trash icon on the Dock.
    func dockTrashPoint(in size: CGSize) -> CGPoint {
        let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
        let orientation = dockDefaults?.string(forKey: "orientation") ?? "bottom"
        switch orientation {
        case "left":
            return CGPoint(x: 56, y: size.height - 64)
        case "right":
            return CGPoint(x: size.width - 56, y: size.height - 64)
        default: // bottom (Trash is on the bottom-right side of the Dock)
            return CGPoint(x: size.width * 0.78, y: size.height - 56)
        }
    }

    /// Safely empties ~/.Trash via Finder AppleScript (only invoked on explicit user "Feed Trash" action).
    func emptyTrashSafely(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let script = NSAppleScript(source: "tell application \"Finder\" to empty trash")
            var err: NSDictionary?
            script?.executeAndReturnError(&err)
            let ok = (err == nil)
            DispatchQueue.main.async {
                self.itemCount = self.countTrashItems()
                self.onCountChanged?(self.itemCount)
                completion(ok)
            }
        }
    }
}
