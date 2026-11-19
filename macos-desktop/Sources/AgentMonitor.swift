import Foundation

/// Monitors local AI agents & subagents from:
/// 1) Hook JSON file at ~/.ascii-koi/agents.json
/// 2) Active Antigravity sessions/subagents in ~/.gemini/antigravity/brain/
/// 3) Running CLI processes (claude, gemini, codex)
final class AgentMonitor {
    private struct HookEntry: Codable {
        var id: String
        var model: String
        var state: String
        var subagents: Int?
    }

    var onAgentsChanged: (([AgentDescriptor]) -> Void)?
    private var timer: Timer?
    private var manualDemos: [AgentDescriptor] = []
    private var lastReported: [AgentDescriptor] = []

    private let hookFileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ascii-koi")
        return dir.appendingPathComponent("agents.json")
    }()

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.2, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Demo / Test Triggers from Menu Bar

    func toggleDemo(model: AgentModel, state: AgentState, withSubagents: Bool = false) {
        let mainId = "demo-\(model.rawValue)"
        if manualDemos.contains(where: { $0.id == mainId }) {
            // Transition to done so the Koi performs its triumphant jump and swims away!
            manualDemos.removeAll { $0.id == mainId || $0.id.hasPrefix("\(mainId)-sub-") }
        } else {
            manualDemos.append(AgentDescriptor(id: mainId, model: model, state: state, isSubagent: false))
            if withSubagents {
                manualDemos.append(AgentDescriptor(id: "\(mainId)-sub-1", model: model, state: .thinking, isSubagent: true))
                manualDemos.append(AgentDescriptor(id: "\(mainId)-sub-2", model: model, state: .editing, isSubagent: true))
            }
        }
        poll()
    }

    func cycleDemoStates() {
        let order: [AgentState] = [.thinking, .editing, .waiting, .error]
        for i in 0..<manualDemos.count {
            let cur = manualDemos[i].state
            let nextIdx = ((order.firstIndex(of: cur) ?? 0) + 1) % order.count
            manualDemos[i].state = order[nextIdx]
        }
        poll()
    }

    func clearDemos() {
        manualDemos.removeAll()
        poll()
    }

    // MARK: - Polling

    private func poll() {
        var detected: [AgentDescriptor] = manualDemos

        // 1. Hook JSON file (~/.ascii-koi/agents.json)
        if let data = try? Data(contentsOf: hookFileURL),
           let entries = try? JSONDecoder().decode([HookEntry].self, from: data) {
            for e in entries {
                let model: AgentModel = e.model.lowercased().contains("claude") ? .claude : .gemini
                let state = AgentState(rawValue: e.state.lowercased()) ?? .thinking
                detected.append(AgentDescriptor(id: "hook-\(e.id)", model: model, state: state, isSubagent: false))
                let subs = max(0, min(4, e.subagents ?? 0))
                for s in 0..<subs {
                    detected.append(AgentDescriptor(id: "hook-\(e.id)-sub-\(s)", model: model, state: .thinking, isSubagent: true))
                }
            }
        }

        // 2. Passive CLI process detection (claude / gemini)
        let runningProcs = detectRunningCLIs()
        for (idx, model) in runningProcs.enumerated() {
            detected.append(AgentDescriptor(id: "cli-\(model.rawValue)-\(idx)", model: model, state: .editing, isSubagent: idx > 0))
        }

        // 3. Passive Antigravity brain transcript activity (modified in last 14 seconds)
        let activeBrains = detectRecentAntigravityActivity()
        for idx in 0..<activeBrains {
            detected.append(AgentDescriptor(
                id: "agy-brain-\(idx)",
                model: .gemini,
                state: idx == 0 ? .thinking : .editing,
                isSubagent: idx > 0
            ))
        }

        if detected != lastReported {
            lastReported = detected
            DispatchQueue.main.async { [weak self] in
                self?.onAgentsChanged?(detected)
            }
        }
    }

    private func detectRunningCLIs() -> [AgentModel] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-eo", "comm"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return [] }
        task.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var found: [AgentModel] = []
        for line in out.split(separator: "\n") {
            let name = URL(fileURLWithPath: String(line).trimmingCharacters(in: .whitespaces)).lastPathComponent.lowercased()
            if name == "claude" { found.append(.claude) }
            else if name == "gemini" { found.append(.gemini) }
        }
        return Array(found.prefix(3))
    }

    private func detectRecentAntigravityActivity() -> Int {
        let brainDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity/brain")
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: brainDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return 0 }

        let cutoff = Date().addingTimeInterval(-14)
        var recentCount = 0
        for folder in folders {
            let logFile = folder.appendingPathComponent(".system_generated/logs/transcript.jsonl")
            if let vals = try? logFile.resourceValues(forKeys: [.contentModificationDateKey]),
               let mod = vals.contentModificationDate, mod > cutoff {
                recentCount += 1
            }
        }
        return min(recentCount, 3)
    }
}
