import CoreGraphics
import Foundation

struct NowPlayingTrack {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var source: String = ""
    var isPlaying: Bool = false
    var isGTA6: Bool = false
}

/// Lightweight multi-source song recognizer for Spotify, Apple Music, and Web Browsers (Safari/Chrome/Arc/Brave/Edge/Firefox).
/// - Spotify & Apple Music: 0% CPU event-driven via DistributedNotificationCenter.
/// - Browsers (YouTube / YouTube Music / Spotify Web): scans all open tabs + window titles every 2.5s in background.
final class NowPlayingMonitor {
    var onTrackChanged: ((NowPlayingTrack) -> Void)?
    /// Optional provider returning whether real-time system audio is currently active (so pausing YouTube fades out Vice City mode!)
    var isSystemAudioPlaying: (() -> Bool?)?

    private var current = NowPlayingTrack()
    private var nativeAppPlaying = false
    private var browserTimer: Timer?
    private let bgQueue = DispatchQueue(label: "com.jj.ASCIIKoiDesktop.nowPlaying", qos: .utility)

    // Complete tracklist for Grand Theft Auto VI: The Album (2026) + official GTA 6 Trailer songs
    private static let gta6TitleMatches: [String] = [
        // Grand Theft Auto VI: The Album (2026) — Sides A–D
        "starting from zero",
        "that's it",
        "ahh yea",
        "rhyno",
        "sexy magic",
        "flower in a hurricane",
        "go easy",
        "last thing you need",
        "suzuki",
        "macacoa 2000",
        "dance with me",
        "count up",
        "let's rock",
        "wakin up flex",
        "ikyfl",
        "don't chart",
        "power trip",
        "blood in your eyes",
        "fast emotion",
        "sweet like candy",
        "only one",
        "sandunguea",
        "trdwfe",
        "all again",
        "crazy for you",
        "largate",
        "lárgate",
        "no me busques",
        "bright lights, big city",
        "stone kold krazy luuv",
        // Official GTA 6 Trailer 1 & Trailer 2 classics
        "love is a long road",
        "hot together",
        "everybody have fun tonight",
        "talkin' to myself again",
        "child support",
        "thunder island"
    ]

    // Short/ambiguous titles that require an artist match from the album so random songs don't false-trigger
    private static let gta6PairMatches: [(title: String, artist: String)] = [
        ("x", "jhayco"),
        ("bigger", "burna boy"),
        ("tf?", "don toliver"),
        ("gma", "jt")
    ]

    private static let gta6Keywords: [String] = [
        "grand theft auto vi",
        "grand theft auto 6",
        "gta 6",
        "gta vi",
        "gta6",
        "gtavi",
        "vice city"
    ]

    func start() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(
            self,
            selector: #selector(spotifyStateChanged(_:)),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil
        )
        dnc.addObserver(
            self,
            selector: #selector(appleMusicStateChanged(_:)),
            name: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil
        )

        // Initial check for already-playing native app or browser tab
        pollOnceInBackground()

        browserTimer?.invalidate()
        browserTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            guard let self = self, !self.nativeAppPlaying else { return }
            self.pollBrowserTabsInBackground()
        }
        browserTimer?.tolerance = 0.5
    }

    func stop() {
        DistributedNotificationCenter.default().removeObserver(self)
        browserTimer?.invalidate()
        browserTimer = nil
    }

    @objc private func spotifyStateChanged(_ note: Notification) {
        guard let info = note.userInfo else { return }
        let state = (info["Player State"] as? String ?? "").lowercased()
        let playing = (state == "playing")
        let title = info["Name"] as? String ?? ""
        let artist = info["Artist"] as? String ?? ""
        let album = info["Album"] as? String ?? ""
        nativeAppPlaying = playing
        updateTrack(title: title, artist: artist, album: album, source: "Spotify", isPlaying: playing)
    }

    @objc private func appleMusicStateChanged(_ note: Notification) {
        guard let info = note.userInfo else { return }
        let state = (info["Player State"] as? String ?? "").lowercased()
        let playing = (state == "playing")
        let title = info["Name"] as? String ?? ""
        let artist = info["Artist"] as? String ?? ""
        let album = info["Album"] as? String ?? ""
        nativeAppPlaying = playing
        updateTrack(title: title, artist: artist, album: album, source: "Apple Music", isPlaying: playing)
    }

    private func pollOnceInBackground() {
        bgQueue.async { [weak self] in
            guard let self = self else { return }
            // Check Spotify if running
            if let sp = self.runAppleScript("""
                if application "Spotify" is running then
                    tell application "Spotify"
                        if player state is playing then
                            return (name of current track) & "||" & (artist of current track) & "||" & (album of current track)
                        end if
                    end tell
                end if
                return ""
                """), !sp.isEmpty {
                let parts = sp.components(separatedBy: "||")
                if parts.count >= 3 {
                    self.nativeAppPlaying = true
                    self.updateTrack(title: parts[0], artist: parts[1], album: parts[2], source: "Spotify", isPlaying: true)
                    return
                }
            }
            // Check Apple Music if running
            if let am = self.runAppleScript("""
                if application "Music" is running then
                    tell application "Music"
                        if player state is playing then
                            return (name of current track) & "||" & (artist of current track) & "||" & (album of current track)
                        end if
                    end tell
                end if
                return ""
                """), !am.isEmpty {
                let parts = am.components(separatedBy: "||")
                if parts.count >= 3 {
                    self.nativeAppPlaying = true
                    self.updateTrack(title: parts[0], artist: parts[1], album: parts[2], source: "Apple Music", isPlaying: true)
                    return
                }
            }
            self.pollBrowserTabsInBackground()
        }
    }

    private func pollBrowserTabsInBackground() {
        bgQueue.async { [weak self] in
            guard let self = self else { return }

            // Collect candidate (source, tabTitle) from ALL tabs of running browsers (including background tabs!)
            var candidates: [(source: String, title: String)] = []

            let script = """
            set results to {}
            if application "Safari" is running then
                try
                    tell application "Safari"
                        repeat with w in windows
                            repeat with t in tabs of w
                                set end of results to ("Safari||" & (name of t))
                            end repeat
                        end repeat
                    end tell
                end try
            end if
            if application "Google Chrome" is running then
                try
                    tell application "Google Chrome"
                        repeat with w in windows
                            repeat with t in tabs of w
                                set end of results to ("Chrome||" & (title of t))
                            end repeat
                        end repeat
                    end tell
                end try
            end if
            if application "Arc" is running then
                try
                    tell application "Arc"
                        repeat with w in windows
                            repeat with t in tabs of w
                                set end of results to ("Arc||" & (title of t))
                            end repeat
                        end repeat
                    end tell
                end try
            end if
            if application "Brave Browser" is running then
                try
                    tell application "Brave Browser"
                        repeat with w in windows
                            repeat with t in tabs of w
                                set end of results to ("Brave||" & (title of t))
                            end repeat
                        end repeat
                    end tell
                end try
            end if
            if application "Microsoft Edge" is running then
                try
                    tell application "Microsoft Edge"
                        repeat with w in windows
                            repeat with t in tabs of w
                                set end of results to ("Edge||" & (title of t))
                            end repeat
                        end repeat
                    end tell
                end try
            end if
            set AppleScript's text item delimiters to linefeed
            return results as text
            """

            if let res = self.runAppleScript(script), !res.isEmpty {
                for line in res.components(separatedBy: .newlines) {
                    let parts = line.components(separatedBy: "||")
                    if parts.count >= 2 {
                        let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                        if !title.isEmpty {
                            candidates.append((parts[0], title))
                        }
                    }
                }
            }

            // Also inspect visible browser window titles via CGWindowList (works with ZERO Automation permission & supports Firefox/Zen/Opera!)
            if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
                let browserNames = ["Safari", "Google Chrome", "Arc", "Brave Browser", "Microsoft Edge", "Firefox", "Opera", "Vivaldi", "Zen"]
                for w in list {
                    guard let owner = w[kCGWindowOwnerName as String] as? String,
                          let name = w[kCGWindowName as String] as? String,
                          !name.isEmpty,
                          browserNames.contains(where: { owner.localizedCaseInsensitiveContains($0) }) else { continue }
                    candidates.append((owner, name))
                }
            }

            // 1. Highest priority: any browser tab matching GTA 6 / Vice City!
            var chosen: (source: String, title: String)? = nil
            for cand in candidates {
                if Self.matchesGTA6(title: cand.title, artist: "", album: "") {
                    chosen = cand
                    break
                }
            }
            // 2. Otherwise pick any active music/video streaming tab (YouTube, YouTube Music, Spotify Web, SoundCloud)
            if chosen == nil {
                for cand in candidates {
                    let low = cand.title.lowercased()
                    if low.contains("youtube") || low.contains("spotify") || low.contains("soundcloud") || low.contains("apple music") {
                        chosen = cand
                        break
                    }
                }
            }

            if let match = chosen {
                let cleanTitle = match.title
                    .replacingOccurrences(of: " - YouTube Music", with: "")
                    .replacingOccurrences(of: " - YouTube", with: "")
                    .replacingOccurrences(of: " – Spotify", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // If real-time audio monitor is active and receiving audio, respect play/pause state!
                let audioPlaying = self.isSystemAudioPlaying?() ?? true
                self.updateTrack(title: cleanTitle, artist: "", album: "", source: match.source, isPlaying: audioPlaying)
                return
            }

            if !self.nativeAppPlaying && self.current.isPlaying && self.current.source != "Spotify" && self.current.source != "Apple Music" {
                self.updateTrack(title: "", artist: "", album: "", source: "", isPlaying: false)
            }
        }
    }

    private func runAppleScript(_ source: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            // Drain stdout BEFORE waitUntilExit to prevent any pipe deadlock
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func updateTrack(title: String, artist: String, album: String, source: String, isPlaying: Bool) {
        let isGTA = isPlaying && Self.matchesGTA6(title: title, artist: artist, album: album)
        let next = NowPlayingTrack(title: title, artist: artist, album: album, source: source, isPlaying: isPlaying, isGTA6: isGTA)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if next.title != self.current.title || next.isPlaying != self.current.isPlaying || next.isGTA6 != self.current.isGTA6 {
                self.current = next
                self.onTrackChanged?(next)
            }
        }
    }

    static func matchesGTA6(title: String, artist: String, album: String) -> Bool {
        let t = title.lowercased()
        let a = artist.lowercased()
        let al = album.lowercased()
        let combined = "\(t) \(a) \(al)"

        for kw in gta6Keywords where combined.contains(kw) {
            return true
        }
        for track in gta6TitleMatches where t.contains(track) {
            return true
        }
        for pair in gta6PairMatches {
            if (t == pair.title || t.hasPrefix(pair.title + " ") || t.contains(" \(pair.title) ")) && combined.contains(pair.artist) {
                return true
            }
        }
        return false
    }
}
