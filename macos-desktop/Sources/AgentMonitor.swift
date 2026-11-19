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
    private let bgQueue = DispatchQueue(label: "com.jj.ASCIIKoiDesktop.agentMonitor", qos: .utility)
    private let lock = NSLock()
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
        lock.lock()
        let mainId = "demo-\(model.rawValue)"
        if manualDemos.contains(where: { $0.id == mainId }) {
            manualDemos.removeAll { $0.id == mainId || $0.id.hasPrefix("\(mainId)-sub-") }
        } else {
            manualDemos.append(AgentDescriptor(id: mainId, model: model, state: state, isSubagent: false, parentId: nil, formationSlot: 0))
            if withSubagents {
                manualDemos.append(AgentDescriptor(id: "\(mainId)-sub-1", model: model, state: .thinking, isSubagent: true, parentId: mainId, formationSlot: 0))
                manualDemos.append(AgentDescriptor(id: "\(mainId)-sub-2", model: model, state: .editing, isSubagent: true, parentId: mainId, formationSlot: 1))
            }
        }
        lock.unlock()
        poll()
    }

    func cycleDemoStates() {
        lock.lock()
        let order: [AgentState] = [.thinking, .editing, .waiting, .error]
        for i in 0..<manualDemos.count {
            let cur = manualDemos[i].state
            let nextIdx = ((order.firstIndex(of: cur) ?? 0) + 1) % order.count
            manualDemos[i].state = order[nextIdx]
        }
        lock.unlock()
        poll()
    }

    func clearDemos() {
        lock.lock()
        manualDemos.removeAll()
        lock.unlock()
        poll()
    }

    // MARK: - Polling (Always on background queue — never blocks UI!)

    private func poll() {
        bgQueue.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let demosSnapshot = self.manualDemos
            self.lock.unlock()

            var detected: [AgentDescriptor] = demosSnapshot

            // 1. Hook JSON file (~/.ascii-koi/agents.json)
            if let data = try? Data(contentsOf: self.hookFileURL),
               let entries = try? JSONDecoder().decode([HookEntry].self, from: data) {
                for e in entries {
                    let model: AgentModel = e.model.lowercased().contains("claude") ? .claude : .gemini
                    let state = AgentState(rawValue: e.state.lowercased()) ?? .thinking
                    let mainHookId = "hook-\(e.id)"
                    detected.append(AgentDescriptor(id: mainHookId, model: model, state: state, isSubagent: false, parentId: nil, formationSlot: 0))
                    let subs = max(0, min(4, e.subagents ?? 0))
                    for s in 0..<subs {
                        detected.append(AgentDescriptor(id: "\(mainHookId)-sub-\(s)", model: model, state: .thinking, isSubagent: true, parentId: mainHookId, formationSlot: s))
                    }
                }
            }

            // 2. Passive CLI & Antigravity detection (only when not testing demos)
            if demosSnapshot.isEmpty {
                let runningProcs = self.detectRunningCLIs()
                for (idx, model) in runningProcs.enumerated() {
                    let isSub = idx > 0
                    detected.append(AgentDescriptor(
                        id: "cli-\(model.rawValue)-\(idx)",
                        model: model,
                        state: .editing,
                        isSubagent: isSub,
                        parentId: isSub ? "cli-\(model.rawValue)-0" : nil,
                        formationSlot: max(0, idx - 1)
                    ))
                }

                let activeBrains = self.detectRecentAntigravityActivity()
                for idx in 0..<activeBrains {
                    let isSub = idx > 0
                    detected.append(AgentDescriptor(
                        id: "agy-brain-\(idx)",
                        model: .gemini,
                        state: idx == 0 ? .thinking : .editing,
                        isSubagent: isSub,
                        parentId: isSub ? "agy-brain-0" : nil,
                        formationSlot: max(0, idx - 1)
                    ))
                }
            }

            if detected != self.lastReported {
                self.lastReported = detected
                DispatchQueue.main.async { [weak self] in
                    self?.onAgentsChanged?(detected)
                }
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
        // IMPORTANT: Always drain pipe BEFORE waitUntilExit() so large ps output never deadlocks!
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
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
