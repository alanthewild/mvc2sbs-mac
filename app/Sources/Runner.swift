// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Alan Wild
import Foundation
import Combine
import AppKit

/// Owns the queue and drives mvc2sbs. All the conversion logic lives in the
/// shell script, which is tested. This class only builds arguments, parses the
/// @@ status lines and the FFmpeg progress file, and reports state.
final class QueueController: ObservableObject {

    /// So the app delegate can stop a running job before the app quits.
    static weak var shared: QueueController?

    @Published var jobs: [Job] = []
    @Published var selectedJobID: UUID? = nil
    @Published var isRunning = false
    @Published var runAll = false
    @Published var consoleVisible = false
    /// Driven from the toolbar, presented by whichever settings form is on
    /// screen. The button sits with Console and Tools; the sheet belongs to the
    /// settings it edits.
    @Published var advancedVisible = false
    @Published var toolWarning: String = ""
    @Published var toolWarningIsAdvisory = false

    private var process: Process?
    private var runningJob: Job?
    private var runningMode: RunMode = .convert
    private var progressFile: URL?
    private var progressTimer: Timer?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()

    var selectedJob: Job? {
        guard let id = selectedJobID else { return nil }
        return jobs.first { $0.id == id }
    }

    init() {
        refreshToolWarning()
        QueueController.shared = self
    }

    func refreshToolWarning() {
        let brew = "brew install " + Tools.missingFormulae.joined(separator: " ")

        if !Tools.missingBundled.isEmpty {
            // These ship inside the app, so their absence means a bad build.
            toolWarningIsAdvisory = false
            toolWarning = "Not found: \(Tools.missingBundled.joined(separator: ", ")). "
                + "Rebuild the app with build-app.sh, or set the paths in Settings."
        } else if !Tools.missingRequired.isEmpty {
            toolWarningIsAdvisory = false
            toolWarning = "FFmpeg not found. Install it with: \(brew)"
        } else if !Tools.missingRequiredMux.isEmpty {
            // Not advisory. Without mkvmerge the output is muxed by FFmpeg, and
            // an FFmpeg-muxed file is refused outright by Jellyfin on a Shield.
            toolWarningIsAdvisory = false
            toolWarning = "\(Tools.missingRequiredMux.joined(separator: " and ")) not found. "
                + "Without MKVToolNix the output is muxed by FFmpeg, which some "
                + "players refuse to play at all, and it will carry no chapters "
                + "and no record of the settings used. Install it with: \(brew)"
        } else if let m = Tools.versionMismatch {
            toolWarningIsAdvisory = false
            toolWarning = Tools.bundleIsStale
                ? "The copy of mvc2sbs inside this app is \(m.app), but \(m.tool) is "
                  + "installed on your system. The app uses its own copy, so it is "
                  + "running the older one. Rebuild with build-app.sh --install."
                : "The copy of mvc2sbs inside this app is \(m.app) and the one "
                  + "installed on your system is \(m.tool). They should match. "
                  + "Rebuild with build-app.sh --install."
        } else if !Tools.missingOptional.isEmpty {
            // Optional, but silently dropping the 3D flag is worse than saying so.
            toolWarningIsAdvisory = true
            toolWarning = "mkvpropedit not found, so the output will not be tagged "
                + "with the 3D StereoMode flag and players will not switch to 3D "
                + "on their own. Install it with: \(brew)"
        } else {
            toolWarning = ""
            toolWarningIsAdvisory = false
        }
    }

    /// Flip the StereoMode flag on a finished file. No re-encode: this changes
    /// how a player reads the two halves, not the picture.
    func swapEyes(on job: Job) {
        guard !job.outputPath.isEmpty,
              let mkvpropedit = Tools.find("mkvpropedit") else { return }
        // 1 and 3 are left-eye-first, 11 and 2 are their right-eye-first pairs.
        let target = (job.settings.layout == .ftab || job.settings.layout == .htab) ? "2" : "11"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: mkvpropedit)
        proc.environment = Tools.environment()
        proc.arguments = [job.outputPath, "--edit", "track:v1", "--set", "stereo-mode=\(target)"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return }
        proc.waitUntilExit()
        if proc.terminationStatus == 0 {
            job.eyeCheck = "fixed"
            job.message = "StereoMode set to \(target). Check it on your display."
            job.appendLog("Set stereo-mode=\(target) on \(job.outputPath)\n")
        } else {
            job.message = "Could not set the StereoMode flag."
        }
    }

    // MARK: - Queue management

    func add(urls: [URL], defaults: JobSettings) {
        for url in urls where !jobs.contains(where: { $0.sourceURL == url }) {
            let job = Job(sourceURL: url, settings: defaults)
            jobs.append(job)
            if selectedJobID == nil { selectedJobID = job.id }
            probe(job)
        }
    }

    func remove(_ job: Job) {
        guard job !== runningJob else { return }
        jobs.removeAll { $0.id == job.id }
        if selectedJobID == job.id { selectedJobID = jobs.first?.id }
    }

    func clearFinished() {
        jobs.removeAll { $0.state == .succeeded || $0.state == .cancelled }
        if let id = selectedJobID, !jobs.contains(where: { $0.id == id }) {
            selectedJobID = jobs.first?.id
        }
    }

    private func probe(_ job: Job) {
        job.state = .probing
        DispatchQueue.global(qos: .userInitiated).async {
            let info = Probe.run(url: job.sourceURL)
            DispatchQueue.main.async {
                if let info = info {
                    job.info = info
                    job.totalFrames = info.estimatedFrames
                    if job.settings.audioTracks.isEmpty {
                        job.settings.audioTracks = info.audio.map { $0.typeIndex }
                    }
                    if job.settings.subTracks.isEmpty {
                        job.settings.subTracks = info.subs.map { $0.typeIndex }
                    }
                } else {
                    job.message = "ffprobe could not read this file"
                }
                job.state = .queued
            }
        }
    }

    // MARK: - Running

    func start(_ job: Job? = nil, all: Bool = false, mode: RunMode = .convert) {
        guard !isRunning else { return }
        runAll = all && mode == .convert
        let target = job ?? jobs.first { $0.state == .queued || $0.state == .failed }
        guard let next = target else { return }
        launch(next, mode: mode)
    }

    func stop() {
        guard let proc = process, proc.isRunning else { return }
        runAll = false
        runningJob?.state = .stopping
        runningJob?.stage = "stopping"
        // mvc2sbs traps SIGTERM and takes the whole pipeline down with it.
        proc.terminate()
    }

    private func startNextIfWanted() {
        guard runAll else { return }
        if let next = jobs.first(where: { $0.state == .queued }) {
            launch(next, mode: .convert)
        } else {
            runAll = false
        }
    }

    private func launch(_ job: Job, mode: RunMode) {
        guard let tool = Tools.find("mvc2sbs") else {
            refreshToolWarning()
            job.state = .failed
            job.message = "mvc2sbs not found"
            return
        }

        runningMode = mode
        job.state = .running
        job.stage = mode == .preview ? "preview" : "starting"
        job.psnr = ""
        job.previewImagePath = ""
        job.currentFrame = 0
        job.fps = 0
        job.speed = ""
        job.message = ""
        job.lengthCheck = ""
        job.startedAt = Date()
        job.finishedAt = nil

        let progressURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mvc2sbs-\(job.id.uuidString).progress")
        FileManager.default.createFile(atPath: progressURL.path, contents: nil)
        progressFile = progressURL

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tool)
        proc.arguments = arguments(for: job, progress: progressURL, mode: mode)
        proc.environment = Tools.environment()
        proc.currentDirectoryURL = job.sourceURL.deletingLastPathComponent()

        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        stdoutBuffer = Data()
        stderrBuffer = Data()

        job.appendLog("$ \(tool) \(proc.arguments!.joined(separator: " "))\n\n")

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.consumeStdout(data, job: job) }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.consumeStderr(data, job: job) }
        }

        proc.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                self?.finish(job, status: finished.terminationStatus)
            }
        }

        do {
            try proc.run()
        } catch {
            job.state = .failed
            job.message = "could not launch mvc2sbs: \(error.localizedDescription)"
            return
        }

        process = proc
        runningJob = job
        isRunning = true

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            job.tick &+= 1          // keeps the clock in the status bar moving
            self?.pollProgress(job)
        }
    }

    private func finish(_ job: Job, status: Int32) {
        progressTimer?.invalidate()
        progressTimer = nil
        if let file = progressFile { try? FileManager.default.removeItem(at: file) }
        progressFile = nil
        process = nil
        runningJob = nil
        isRunning = false
        job.finishedAt = Date()

        let mode = runningMode
        runningMode = .convert

        switch status {
        case 0:
            if mode == .convert {
                job.state = .succeeded
                job.stage = "done"
                job.currentFrame = job.totalFrames
            } else {
                // A preview or smoke test must leave the job ready to convert.
                job.state = .queued
                job.stage = mode == .preview ? "preview done" : "test done"
                job.currentFrame = 0
                if mode == .preview, !job.previewImagePath.isEmpty {
                    NSWorkspace.shared.open(URL(fileURLWithPath: job.previewImagePath))
                }
            }
        case 130, 143, -15:
            job.state = .cancelled
            job.stage = "cancelled"
        default:
            job.state = .failed
            job.stage = "failed"
            if job.message.isEmpty { job.message = "mvc2sbs exited \(status)" }
        }

        startNextIfWanted()
    }

    // MARK: - Argument building

    func arguments(for job: Job, progress: URL?, mode: RunMode = .convert) -> [String] {
        var args: [String] = ["--machine"]
        let s = job.settings
        switch mode {
        case .preview:   args.append("--preview")
        case .smokeTest: args += ["--limit", "60"]
        case .convert:   break
        }

        args += ["-q", String(s.crf)]
        args += ["-p", s.preset]
        args += ["--layout", s.layout.rawValue]

        switch s.encoder {
        case .x264: break
        case .x265: args.append("--x265")
        case .videotoolbox:
            args.append("--vt")
            args += ["--vt-quality", String(s.vtQuality)]
        }

        if s.singleThread { args.append("--single-thread") }
        if s.tenBit { args.append("--10bit") }
        if s.darkTuning { args.append("--dark") }
        if s.flatSubs { args.append("--flat-subs") }
        else {
            if s.subDepth != 0 { args += ["--sub-depth", String(s.subDepth)] }
            if s.subBrightness != 1.0 {
                args += ["--sub-brightness", String(format: "%.2f", s.subBrightness)]
            }
            if s.subColour != "source" { args += ["--sub-colour", s.subColour] }
            if s.subOpacity != 1.0 {
                args += ["--sub-opacity", String(format: "%.2f", s.subOpacity)]
            }
        }
        if !s.tempFolder.isEmpty { args += ["--temp", s.tempFolder] }
        if let progress = progress { args += ["--progress", progress.path] }

        // Audio and subtitle selection. Empty selection means drop the type
        // entirely; a selection equal to everything is left implicit.
        if s.dropAudio || (job.info.audio.isEmpty == false && s.audioTracks.isEmpty) {
            args.append("--no-audio")
        } else if !s.audioTracks.isEmpty, s.audioTracks.count < job.info.audio.count {
            args += ["--audio-tracks", s.audioTracks.sorted().map(String.init).joined(separator: ",")]
        }

        if s.dropSubs || (job.info.subs.isEmpty == false && s.subTracks.isEmpty) {
            args.append("--no-subs")
        } else if !s.subTracks.isEmpty, s.subTracks.count < job.info.subs.count {
            args += ["--sub-tracks", s.subTracks.sorted().map(String.init).joined(separator: ",")]
        }

        if s.dropChapters { args.append("--no-chapters") }
        if s.maxRate > 0 { args += ["--maxrate", String(s.maxRate)] }
        if s.swapEyes { args.append("--swap-eyes") }

        if !s.extraArgs.isEmpty {
            args += ["--extra", s.extraArgs]
        }

        args += ["-o", outputURL(for: job).path]
        args.append(job.sourceURL.path)
        return args
    }

    func outputURL(for job: Job) -> URL {
        let s = job.settings
        let folder = s.outputFolder.isEmpty
            ? job.sourceURL.deletingLastPathComponent()
            : URL(fileURLWithPath: s.outputFolder)
        let name = s.outputName.isEmpty
            ? "\(job.cleanName).3D-\(s.layout.rawValue).mkv"
            : s.outputName
        return folder.appendingPathComponent(name)
    }

    // MARK: - Output parsing

    /// Split a growing byte buffer into complete lines. Uses Foundation's
    /// Data.range(of:) and rebuilds the buffer rather than assuming zero based
    /// indices, which do not survive removeSubrange on a slice.
    private func takeLines(_ buffer: inout Data) -> [String] {
        var lines: [String] = []
        let newline = Data([0x0A])
        while let r = buffer.range(of: newline) {
            let lineData = buffer.subdata(in: buffer.startIndex..<r.lowerBound)
            buffer = Data(buffer[r.upperBound...])
            if let line = String(data: lineData, encoding: .utf8) { lines.append(line) }
        }
        return lines
    }

    private func consumeStdout(_ data: Data, job: Job) {
        stdoutBuffer.append(data)
        for line in takeLines(&stdoutBuffer) { handleStatus(line, job: job) }
    }

    private func consumeStderr(_ data: Data, job: Job) {
        stderrBuffer.append(data)
        for line in takeLines(&stderrBuffer) { job.appendLog(line + "\n") }
    }

    private func handleStatus(_ line: String, job: Job) {
        guard line.hasPrefix("@@") else { return }
        let parts = line.dropFirst(2).split(separator: " ", maxSplits: 1).map(String.init)
        guard let key = parts.first else { return }
        let value = parts.count > 1 ? parts[1] : ""

        switch key {
        case "stage":
            job.stage = value
        case "totalframes":
            if let n = Int(value), n > 0 { job.totalFrames = n }
        case "mvc":
            job.mvcConfirmed = (value == "yes")
        case "decoder":
            job.decoderSize = value.replacingOccurrences(of: " ", with: "x")
        case "done":
            job.outputPath = value
        case "psnr":
            job.psnr = value
        case "preview":
            job.previewImagePath = value
        case "length":
            job.lengthCheck = value
            if value.hasPrefix("drift") {
                job.message = "Length check failed. Video and audio may be out of sync."
            }
        case "eyes":
            job.eyeCheck = value
            if value.hasPrefix("inverted") {
                job.message = "Depth reads inverted. The file plays normally but "
                    + "may be uncomfortable to watch. Fixable without re-encoding."
            }
        case "startup":
            job.startupCheck = value
            if value.hasPrefix("bad") {
                job.message = "The output does not decode from the start. Sound will "
                    + "play and the picture will stay black. Re-run the encode."
            }
        case "cues":
            if value == "missing" {
                job.message = "The output has no index, so the mux never finished. "
                    + "The encode was interrupted. Re-run it."
            }
        case "subsync":
            job.subCheck = value
            if value.hasPrefix("drift") {
                job.message = "The subtitle track is offset from where it should be. "
                    + "See the console for how far."
            }
        case "remux":
            if value.hasPrefix("failed") {
                job.message = "mkvmerge could not write the final file, so FFmpeg's "
                    + "mux was kept. It plays in VLC but a Shield may refuse it. "
                    + "The console has what mkvmerge said and how to fix it without "
                    + "re-encoding."
            }
        case "chapters":
            job.chapterCheck = value
            if value.hasPrefix("bad") {
                job.message = "Chapters run past the end of the file. Some players "
                    + "show a black screen and play no audio. See the console for the fix."
            }
        case "error":
            job.message = value
        case "warn":
            job.appendLog("WARN \(value)\n")
        default:
            break
        }
    }

    /// FFmpeg writes key=value blocks to the progress file once a second. Read
    /// only the tail: over a three hour encode the file grows to a megabyte or
    /// so and re-reading all of it twice a second would be silly.
    private func pollProgress(_ job: Job) {
        guard job.stage == "encode", let url = progressFile else { return }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 4096
        let start = size > window ? size - window : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return }

        for line in text.split(separator: "\n") {
            let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            let value = pair[1].trimmingCharacters(in: .whitespaces)
            switch pair[0] {
            case "frame":   if let n = Int(value) { job.currentFrame = n }
            case "fps":     if let f = Double(value) { job.fps = f }
            case "speed":   job.speed = value
            case "out_time_us":
                if let us = Double(value) { job.outTimeSeconds = us / 1_000_000 }
            default: break
            }
        }
    }
}

/// Global defaults applied to newly added jobs, persisted between launches.
final class DefaultsStore: ObservableObject {
    @Published var settings: JobSettings {
        didSet { save() }
    }

    private static let key = "defaultJobSettings"

    init() {
        if let data = UserDefaults.standard.data(forKey: DefaultsStore.key),
           let decoded = try? JSONDecoder().decode(JobSettings.self, from: data) {
            settings = decoded
        } else {
            settings = JobSettings()
        }
    }

    /// Back to the recommended settings, which is the only reliable way out of
    /// a saved blob written by an older version. Deleting the plist by hand
    /// works too, but nobody should have to know that.
    func resetToRecommended() {
        settings = JobSettings()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: DefaultsStore.key)
        }
    }
}
