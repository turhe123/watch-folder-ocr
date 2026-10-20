import AppKit
import ServiceManagement
import SwiftUI

/// Central state: owns the watch rules, polls folders every 3 seconds, feeds a serial
/// OCR queue and keeps the processing log.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var rules: [WatchRule] = [] {
        didSet { rulesChanged(from: oldValue) }
    }
    @Published var isPaused = UserDefaults.standard.bool(forKey: "paused") {
        didSet {
            UserDefaults.standard.set(isPaused, forKey: "paused")
            pump()
        }
    }
    @Published private(set) var log: [LogEntry] = []
    @Published private(set) var currentFile: String?
    @Published private(set) var batchDone = 0
    @Published private(set) var batchTotal = 0
    @Published private(set) var unavailableRules: Set<UUID> = []
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginError: String?

    /// Size/date seen on the last scan; a file is processed once two scans agree.
    private struct Snapshot { var size: Int; var modified: Date; var handled: Bool }

    private var snapshots: [String: Snapshot] = [:]
    private var scannedRules: Set<UUID> = []
    private var pending: [(ruleID: UUID, url: URL)] = []
    private var busy = false
    private var scopedURLs: [Data: URL] = [:]
    private var timer: Timer?
    private let workQueue = DispatchQueue(label: "com.turhe123.watchfolderocr.ocr", qos: .utility)
    private static let rulesKey = "watchRules"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.rulesKey),
           let saved = try? JSONDecoder().decode([WatchRule].self, from: data) {
            rules = saved
        }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    var statusLine: String {
        if batchTotal > 0 { return "\(isPaused ? "Paused at" : "Processing") \(min(batchDone + 1, batchTotal)) of \(batchTotal)" }
        return isPaused ? "Paused" : "Idle"
    }

    var isProcessing: Bool { batchTotal > 0 && !isPaused }

    // MARK: Rules

    func addRule() -> UUID? {
        guard let url = chooseFolder(prompt: "Watch Folder"), let bookmark = Bookmarks.make(for: url) else { return nil }
        let rule = WatchRule(inputBookmark: bookmark, inputPath: url.path)
        rules.append(rule)
        return rule.id
    }

    func removeRule(_ id: UUID) {
        rules.removeAll { $0.id == id }
    }

    func chooseOutputFolder(for id: UUID) {
        guard let url = chooseFolder(prompt: "Use as Output"), let bookmark = Bookmarks.make(for: url),
              let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].outputBookmark = bookmark
        rules[index].outputPath = url.path
    }

    private func chooseFolder(prompt: String) -> URL? {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func rulesChanged(from old: [WatchRule]) {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: Self.rulesKey)
        }
        // Disabled or edited-input rules re-baseline so existing files are not suddenly processed.
        for rule in rules {
            let previous = old.first { $0.id == rule.id }
            if !rule.enabled || previous?.inputBookmark != rule.inputBookmark { scannedRules.remove(rule.id) }
        }
        let inUse = Set(rules.flatMap { [$0.inputBookmark, $0.outputBookmark].compactMap { $0 } })
        for (data, url) in scopedURLs where !inUse.contains(data) {
            url.stopAccessingSecurityScopedResource()
            scopedURLs[data] = nil
        }
    }

    private func resolve(_ bookmark: Data) -> URL? {
        if let url = scopedURLs[bookmark] { return url }
        guard let url = Bookmarks.resolve(bookmark) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        scopedURLs[bookmark] = url
        return url
    }

    // MARK: Watching

    private func candidates(for rule: WatchRule) -> [(url: URL, size: Int, modified: Date)]? {
        guard let dir = resolve(rule.inputBookmark),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]) else { return nil }
        let suffix = rule.effectiveSuffix
        return urls.compactMap { url in
            guard OCRProcessor.isSupported(url),
                  suffix.isEmpty || !url.deletingPathExtension().lastPathComponent.hasSuffix(suffix),
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
    }

    private func tick() {
        var present = Set<String>()
        var unavailable = Set<UUID>()
        for rule in rules where rule.enabled {
            guard let files = candidates(for: rule) else {
                unavailable.insert(rule.id)
                scannedRules.remove(rule.id)
                continue
            }
            let baseline = !scannedRules.contains(rule.id)
            for file in files {
                let key = file.url.path
                present.insert(key)
                guard var snap = snapshots[key] else {
                    snapshots[key] = Snapshot(size: file.size, modified: file.modified, handled: baseline)
                    continue
                }
                guard !snap.handled else { continue }
                if snap.size == file.size && snap.modified == file.modified && file.size > 0 {
                    snap.handled = true
                    enqueue(file.url, rule: rule.id)
                } else {
                    snap.size = file.size
                    snap.modified = file.modified
                }
                snapshots[key] = snap
            }
            scannedRules.insert(rule.id)
        }
        snapshots = snapshots.filter { present.contains($0.key) }
        if unavailable != unavailableRules { unavailableRules = unavailable }
    }

    /// Queues every eligible file already in the folder(s) that has no output yet.
    func processNow(ruleID: UUID? = nil) {
        for rule in rules where rule.enabled && (ruleID == nil || rule.id == ruleID) {
            for file in candidates(for: rule) ?? [] {
                if let job = makeJob(file.url, rule: rule), FileManager.default.fileExists(atPath: job.output.path) {
                    continue
                }
                snapshots[file.url.path] = Snapshot(size: file.size, modified: file.modified, handled: true)
                enqueue(file.url, rule: rule.id)
            }
        }
    }

    // MARK: Processing

    private func enqueue(_ url: URL, rule: UUID) {
        guard !pending.contains(where: { $0.url == url }) else { return }
        pending.append((rule, url))
        batchTotal += 1
        pump()
    }

    private func makeJob(_ url: URL, rule: WatchRule) -> OCRJob? {
        let outputDir: URL
        switch rule.outputMode {
        case .sameFolder:
            outputDir = url.deletingLastPathComponent()
        case .separateFolder:
            guard let bookmark = rule.outputBookmark, let dir = resolve(bookmark) else { return nil }
            outputDir = dir
        }
        let base = url.deletingPathExtension().lastPathComponent + rule.effectiveSuffix
        return OCRJob(input: url,
                      output: outputDir.appendingPathComponent(base).appendingPathExtension("pdf"),
                      textOutput: rule.writeTextFile ? outputDir.appendingPathComponent(base).appendingPathExtension("txt") : nil,
                      languages: rule.languages, accurate: rule.accurate,
                      force: rule.forceOCR, deleteOriginal: rule.deleteOriginal)
    }

    private func pump() {
        while !busy && !isPaused && !pending.isEmpty {
            let item = pending.removeFirst()
            guard let rule = rules.first(where: { $0.id == item.ruleID }),
                  let job = makeJob(item.url, rule: rule) else {
                record(item.url.lastPathComponent, .failed("Output folder unavailable"), duration: 0)
                continue
            }
            busy = true
            currentFile = item.url.lastPathComponent
            workQueue.async {
                let start = Date()
                let outcome = autoreleasepool { OCRProcessor.process(job) }
                let duration = Date().timeIntervalSince(start)
                Task { @MainActor in
                    self.busy = false
                    self.currentFile = nil
                    self.record(item.url.lastPathComponent, outcome, duration: duration)
                    self.pump()
                }
            }
        }
        if pending.isEmpty && !busy {
            batchDone = 0
            batchTotal = 0
        }
    }

    private func record(_ name: String, _ outcome: OCROutcome, duration: TimeInterval) {
        let entry: LogEntry
        switch outcome {
        case .success(let pages):
            entry = LogEntry(name: name, pages: pages, duration: duration, outcome: .success, message: "Done")
        case .skipped(let reason, let pages):
            entry = LogEntry(name: name, pages: pages, duration: duration, outcome: .skipped, message: "Skipped: \(reason)")
        case .failed(let reason):
            entry = LogEntry(name: name, pages: 0, duration: duration, outcome: .failed, message: "Error: \(reason)")
        }
        log.insert(entry, at: 0)
        if log.count > 500 { log.removeLast(log.count - 500) }
        batchDone += 1
    }

    func clearLog() { log.removeAll() }

    // MARK: Launch at login

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Could not change login item: \(error.localizedDescription). You can manage it in System Settings › General › Login Items."
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    static func openDonationPage() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }
}
