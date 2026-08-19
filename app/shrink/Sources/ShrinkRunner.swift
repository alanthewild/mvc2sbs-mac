// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Alan Wild
import Foundation
import Combine
import AppKit

/// Drives mkvshrink. All the decisions live in the script; this builds
/// arguments, reads the plan it writes, and parses the @@ events it emits.
///
/// The two phases are the script's own: `--plan` writes a reviewable TSV and
/// changes nothing, `--apply` carries out an edited one. The GUI exists to make
/// the middle step bearable, so it never bypasses the plan.
final class ShrinkController: ObservableObject {

    static weak var shared: ShrinkController?

    @Published var rows: [PlanRow] = []
    @Published var header: [String] = []
    @Published var scanning = false
    @Published var running = false
    @Published var stage = ""
    @Published var currentFile = ""
    @Published var currentPct: Double = 0
    @Published var sweepIndex = 0
    @Published var sweepTotal = 0
    @Published var elapsed: TimeInterval = 0
    @Published var eta: TimeInterval = 0
    @Published var speed = ""
    @Published var message = ""
    @Published var log = ""
    @Published var consoleVisible = false
    @Published var toolWarning = ""
    @Published var lastSummary = ""
    /// Warnings are counted, not displayed. mkvshrink's are whole paragraphs
    /// explaining why a file was rejected, and a status bar can show about a
    /// third of one, which is worse than showing none.
    @Published var noteCount = 0
    @Published var scannedFolders: [String] = []

    private var process: Process?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var planPath: URL?

    init() {
        ShrinkController.shared = self
        refreshToolWarning()
    }

    // MARK: - Tools

    func refreshToolWarning() {
        var missing: [String] = []
        for t in ["mkvshrink", "ffmpeg", "ffprobe", "mkvmerge", "mkvpropedit", "mkvextract"]
        where Tools.find(t) == nil {
            missing.append(t)
        }
        if missing.isEmpty {
            toolWarning = ""
        } else if missing == ["mkvshrink"] {
            toolWarning = "mkvshrink not found. Install it with install-mac3d.sh, "
                + "or set its path in Tools."
        } else {
            toolWarning = "Not found: " + missing.joined(separator: ", ")
                + ". Install with: brew install ffmpeg mkvtoolnix"
        }
    }

    func appendLog(_ s: String) {
        log.append(s)
        // A sweep of a thousand files produces a lot of output.
        if log.count > 400_000 { log = String(log.suffix(200_000)) }
    }

    // MARK: - Planning

    /// Scan folders and build a plan. This probe-encodes each candidate, so it
    /// is minutes per file rather than seconds, and it changes nothing on disk.
    func scan(paths: [String], settings: ShrinkSettings) {
        guard !scanning, !running, let tool = Tools.find("mkvshrink") else { return }
        let plan = FileManager.default.temporaryDirectory
            .appendingPathComponent("mkvshrink-plan-\(UUID().uuidString).tsv")
        planPath = plan
        scannedFolders = paths
        rows = []
        header = []
        scanning = true
        stage = "planning"
        noteCount = 0
        message = ""
        lastSummary = ""

        var args = ["--machine", "--plan", plan.path]
        args += settings.arguments
        args += paths
        launch(tool: tool, args: args) { [weak self] ok in
            guard let self = self else { return }
            self.scanning = false
            self.stage = ""
            guard ok, let text = try? String(contentsOf: plan, encoding: .utf8) else {
                if self.message.isEmpty {
                    self.message = "The scan did not produce a plan. See the console."
                }
                return
            }
            let parsed = PlanFile.parse(text)
            self.header = parsed.header
            self.rows = parsed.rows
            if parsed.rows.isEmpty {
                self.message = "Nothing to do: no file in those folders passed the gates."
            }
        }
    }

    /// Open a plan written earlier, by this app or by the script.
    ///
    /// A plan is minutes per file to produce, so it is worth keeping and worth
    /// being able to come back to. What it is not is a promise: mkvshrink
    /// re-probes every row as it applies it and refuses any file that is no
    /// longer the size or the segment the plan measured. The rows are shown
    /// here as they were written, and the ones whose files have gone are
    /// counted, so an old plan is obviously old before Start is pressed.
    func loadPlan(url: URL) {
        guard !scanning, !running else { return }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            message = "Could not read \(url.lastPathComponent)."
            return
        }
        let parsed = PlanFile.parse(text)
        guard !parsed.rows.isEmpty else {
            message = "\(url.lastPathComponent) has no plan rows in it."
            return
        }
        header = parsed.header
        rows = parsed.rows
        planPath = url
        scannedFolders = []
        lastSummary = ""
        noteCount = 0
        let missing = parsed.rows.filter {
            !FileManager.default.fileExists(atPath: $0.path)
        }
        for r in missing { r.include = false; r.state = "missing" }
        message = missing.isEmpty ? ""
            : "\(missing.count) file(s) in this plan are no longer where it says. "
              + "Those rows are unticked."
        appendLog("$ loaded plan \(url.path): \(parsed.rows.count) row(s)\n")
    }

    // MARK: - Applying

    /// Write the reviewed plan back and carry it out.
    ///
    /// `only` runs one row and leaves every tick where it is, which is the
    /// difference between trying a setting on one film and committing to a
    /// sweep of twenty-five.
    func apply(settings: ShrinkSettings, only: PlanRow? = nil) {
        guard !scanning, !running, let tool = Tools.find("mkvshrink") else { return }
        let included = only.map { [$0] } ?? rows.filter { $0.include }
        guard !included.isEmpty else {
            message = "Nothing is ticked."
            return
        }
        let plan = FileManager.default.temporaryDirectory
            .appendingPathComponent("mkvshrink-apply-\(UUID().uuidString).tsv")
        let text = PlanFile.write(header: header, rows: included, all: true)
        do {
            try text.write(to: plan, atomically: true, encoding: .utf8)
        } catch {
            message = "Could not write the plan: \(error.localizedDescription)"
            return
        }
        planPath = plan
        let queued = Set(included.map { $0.id })
        for r in rows {
            r.state = queued.contains(r.id) ? "waiting" : "not selected"
            r.progress = 0
            r.savedPct = ""
        }
        running = true
        stage = "starting"
        noteCount = 0
        message = ""
        lastSummary = ""
        sweepIndex = 0
        sweepTotal = included.count

        var args = ["--machine", "--apply", plan.path]
        args += settings.arguments
        launch(tool: tool, args: args) { [weak self] _ in
            guard let self = self else { return }
            self.running = false
            self.stage = ""
            self.currentFile = ""
            self.currentPct = 0
            for r in self.rows where r.state == "waiting" || r.state == "running" {
                r.state = ""
            }
        }
    }

    // MARK: - Tracks

    /// Ask mkvshrink what tracks a file has. Synchronous on purpose: it is two
    /// probes of one file and the sheet has nothing to show until it answers.
    /// The same rules the plan was built under are passed in, so the "kept by
    /// the rules" column in the sheet is the truth rather than a second guess.
    func tracks(for row: PlanRow, settings: ShrinkSettings) -> [TrackInfo] {
        guard let tool = Tools.find("mkvshrink") else { return [] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = ["--tracks", row.path] + settings.arguments
        p.environment = Tools.environment()
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
        } catch {
            return []
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return TrackInfo.parse(String(data: data, encoding: .utf8) ?? "")
    }

    func stop() {
        guard let p = process, p.isRunning else { return }
        stage = "stopping"
        p.terminate()
    }

    // MARK: - Process plumbing

    private func launch(tool: String, args: [String], done: @escaping (Bool) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.environment = Tools.environment()

        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        stdoutBuffer = Data()
        stderrBuffer = Data()

        appendLog("$ " + ([tool] + args).joined(separator: " ") + "\n")

        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            DispatchQueue.main.async { self?.consumeStdout(d) }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            DispatchQueue.main.async { self?.consumeStderr(d) }
        }

        p.terminationHandler = { [weak self] proc in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                self?.process = nil
                done(proc.terminationStatus == 0)
            }
        }

        do {
            try p.run()
            process = p
        } catch {
            message = "Could not start mkvshrink: \(error.localizedDescription)"
            scanning = false
            running = false
            done(false)
        }
    }

    private func consumeStdout(_ d: Data) {
        stdoutBuffer.append(d)
        while let nl = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = String(data: stdoutBuffer[..<nl], encoding: .utf8) ?? ""
            stdoutBuffer.removeSubrange(...nl)
            handleEvent(line)
        }
    }

    private func consumeStderr(_ d: Data) {
        stderrBuffer.append(d)
        while let nl = stderrBuffer.firstIndex(of: 0x0A) {
            let line = String(data: stderrBuffer[..<nl], encoding: .utf8) ?? ""
            stderrBuffer.removeSubrange(...nl)
            appendLog(strippingColour(line) + "\n")
        }
    }

    private func strippingColour(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "",
                               options: .regularExpression)
    }

    private func row(forPath p: String) -> PlanRow? {
        rows.first { $0.path == p }
    }

    /// The @@ events mkvshrink emits under --machine. The console shows the
    /// same information as prose, so neither view owns it.
    private func handleEvent(_ line: String) {
        guard line.hasPrefix("@@") else {
            if !line.isEmpty { appendLog(line + "\n") }
            return
        }
        appendLog(line + "\n")
        let body = String(line.dropFirst(2))
        let key = body.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        let rest = body.dropFirst(key.count).trimmingCharacters(in: .whitespaces)

        // key=value events
        var kv: [String: String] = [:]
        for pair in rest.split(separator: " ") where pair.contains("=") {
            let bits = pair.split(separator: "=", maxSplits: 1)
            if bits.count == 2 { kv[String(bits[0])] = String(bits[1]) }
        }

        switch key {
        case "version":
            appendLog("")
        case "stage":
            let parts = rest.split(separator: " ", maxSplits: 1).map(String.init)
            stage = parts.first ?? ""
            if parts.count > 1 {
                currentFile = (parts[1] as NSString).lastPathComponent
                row(forPath: parts[1])?.state = stage
            }
        case "progress":
            if let f = kv["file"] { currentFile = f }
            currentPct = Double(kv["pct"] ?? "") ?? currentPct
            speed = kv["speed"].map { $0 + "x" } ?? speed
            eta = Double(kv["eta"] ?? "") ?? eta
            elapsed = Double(kv["elapsed"] ?? "") ?? elapsed
            if let r = rows.first(where: { $0.name == currentFile || $0.path.hasSuffix(currentFile) }) {
                r.progress = currentPct / 100.0
                r.state = "running"
            }
        case "sweep":
            sweepIndex = Int(kv["index"] ?? "") ?? sweepIndex
            sweepTotal = Int(kv["total"] ?? "") ?? sweepTotal
            elapsed = Double(kv["elapsed"] ?? "") ?? elapsed
        case "done":
            let parts = rest.split(separator: " ").map(String.init)
            if let path = parts.first {
                let r = row(forPath: path)
                    ?? rows.first { path.hasSuffix($0.name) }
                r?.state = "done"
                r?.progress = 1
                if parts.count > 1 { r?.savedPct = parts[1] }
            }
        case "failed":
            let path = rest.trimmingCharacters(in: .whitespaces)
            let r = row(forPath: path) ?? rows.first { path.hasSuffix($0.name) }
            r?.state = "failed"
        case "summary":
            let parts = rest.split(separator: " ").map(String.init)
            if parts.count >= 3 {
                lastSummary = "\(parts[0]) processed, \(parts[1]) skipped, \(parts[2]) failed"
            }
        case "warn":
            noteCount += 1
        case "error":
            message = rest
        default:
            break
        }
    }

    // MARK: - Totals for the status bar

    var selectedCount: Int { rows.filter { $0.include }.count }

    var selectedReclaimMB: Double {
        rows.filter { $0.include }.reduce(0) { $0 + max(0, $1.sizeMB - $1.predMB) }
    }

    static func humanMB(_ mb: Double) -> String {
        if mb >= 1_048_576 { return String(format: "%.2f TB", mb / 1_048_576) }
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }

    static func clock(_ t: TimeInterval) -> String {
        guard t.isFinite, t > 0 else { return "--:--:--" }
        let s = Int(t.rounded())
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}

/// Saved settings, in the app's own defaults domain.
final class ShrinkDefaults: ObservableObject {
    static let key = "shrinkSettings"

    @Published var settings: ShrinkSettings {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: ShrinkDefaults.key),
           let s = try? JSONDecoder().decode(ShrinkSettings.self, from: data) {
            settings = s
        } else {
            settings = ShrinkSettings()
        }
    }

    func resetToRecommended() {
        settings = ShrinkSettings()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: ShrinkDefaults.key)
        }
    }
}
