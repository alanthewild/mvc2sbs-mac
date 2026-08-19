// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Alan Wild
import Foundation

/// Locates the command line tools. A GUI app does not inherit the PATH from
/// your shell, so every lookup has to be explicit.
enum Tools {
    static let searchPaths: [String] = [
        NSHomeDirectory() + "/.local/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin"
    ]

    /// Tools shipped inside the app bundle. Anything here wins over Homebrew,
    /// so the app works on a Mac that has never seen install-mac3d.sh.
    static var bundledDir: String? {
        Bundle.main.resourceURL?.path
    }

    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existing = env["PATH"] ?? ""
        // The bundle goes first so mvc2sbs finds the bundled edge264_test, and
        // so pgs3d.py is picked up from beside mvc2sbs rather than from PATH.
        var parts: [String] = []
        if let dir = bundledDir { parts.append(dir) }
        parts += searchPaths
        parts.append(existing)
        env["PATH"] = parts.joined(separator: ":")
        return env
    }

    /// Honours a user override in defaults first, then the usual locations.
    static func find(_ name: String) -> String? {
        if let override = UserDefaults.standard.string(forKey: "toolPath.\(name)"),
           !override.isEmpty,
           FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        // Inside the bundle first, then Homebrew and friends, then next to the
        // .app itself for a loose drop.
        var candidates = searchPaths.map { $0 + "/" + name }
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent().path + "/" + name)
        if let dir = bundledDir { candidates.insert(dir + "/" + name, at: 0) }
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    static func setOverride(_ name: String, path: String) {
        UserDefaults.standard.set(path, forKey: "toolPath.\(name)")
    }

    /// Where the bundled copy lives, if the build put one there.
    static var bundledTool: String? {
        guard let dir = bundledDir else { return nil }
        let p = dir + "/mvc2sbs"
        return FileManager.default.isExecutableFile(atPath: p) ? p : nil
    }

    /// The first copy on the ordinary search path, ignoring the bundle. This is
    /// the one a terminal would run.
    static var pathTool: String? {
        for dir in searchPaths {
            let p = dir + "/mvc2sbs"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// The version mvc2sbs reports, from the first line of its help output.
    static func toolVersion(at explicit: String? = nil) -> String? {
        guard let path = explicit ?? find("mvc2sbs") else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["--help"]
        proc.environment = environment()
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        // First line looks like "mvc2sbs 3.2"
        for line in text.split(separator: "\n") where line.hasPrefix("mvc2sbs ") {
            return String(line.dropFirst("mvc2sbs ".count))
                .trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// The app's own version, which build-app.sh stamps from the bundled script.
    static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }

    /// A stale bundle is the most confusing failure mode there is, and the
    /// previous version of this check could not see it. It compared the app
    /// version against `find("mvc2sbs")`, and `find` prefers the bundled copy,
    /// while the app version is stamped from that same bundled copy at build
    /// time. It was comparing the bundle against itself and always agreed.
    ///
    /// The comparison that matters is the bundled copy against the one on the
    /// search path, which is what a terminal runs and what gets updated by
    /// install-mac3d.sh.
    static var versionMismatch: (app: String, tool: String)? {
        let bundled = toolVersion(at: bundledTool) ?? appVersion
        guard let onPath = toolVersion(at: pathTool) else { return nil }
        guard bundled != "?", onPath != bundled else { return nil }
        return (bundled, onPath)
    }

    /// True when the bundled copy is older than the one on the search path,
    /// which means a rebuild was missed rather than merely differing.
    static var bundleIsStale: Bool {
        guard let m = versionMismatch else { return false }
        return compareVersions(m.app, m.tool) < 0
    }

    /// Numeric comparison. String ordering puts 3.9 above 3.10.
    static func compareVersions(_ a: String, _ b: String) -> Int {
        let x = a.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let y = b.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        return 0
    }

    /// Ships inside the app bundle. Missing means the build went wrong.
    static var missingBundled: [String] {
        ["mvc2sbs", "edge264_test"].filter { find($0) == nil }
    }

    /// Cannot be bundled and nothing runs without it.
    static var missingRequired: [String] {
        ["ffmpeg", "ffprobe"].filter { find($0) == nil }
    }

    /// mkvmerge is not optional in any meaningful sense. Without it FFmpeg
    /// writes the container, and an FFmpeg-muxed file is refused outright by
    /// Jellyfin on an Nvidia Shield. It also carries no chapters and no record
    /// of what produced it. This used to be unchecked, so the app could fall
    /// back to the broken path without saying anything.
    static var missingRequiredMux: [String] {
        ["mkvmerge", "mkvextract"].filter { find($0) == nil }
    }

    /// Genuinely optional. Without mkvpropedit the output still plays, but it
    /// carries no StereoMode flag, so players will not switch to 3D on their own.
    static var missingOptional: [String] {
        ["mkvpropedit"].filter { find($0) == nil }
    }

    /// Homebrew formula names for whatever is absent.
    static var missingFormulae: [String] {
        var out: [String] = []
        if !missingRequired.isEmpty { out.append("ffmpeg") }
        if !missingOptional.isEmpty || !missingRequiredMux.isEmpty { out.append("mkvtoolnix") }
        return out
    }
}
