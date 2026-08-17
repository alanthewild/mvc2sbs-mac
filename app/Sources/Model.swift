// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Alan Wild
import Foundation
import Combine

// MARK: - Options that map directly onto mvc2sbs flags

enum Layout: String, CaseIterable, Identifiable, Codable {
    case fsbs, hsbs, ftab, htab
    var id: String { rawValue }

    var title: String {
        switch self {
        case .fsbs: return "Full SBS  (3840x1080)"
        case .hsbs: return "Half SBS  (1920x1080)"
        case .ftab: return "Full Top/Bottom  (1920x2160)"
        case .htab: return "Half Top/Bottom  (1920x1080)"
        }
    }

    var note: String {
        switch self {
        case .fsbs: return "1:1, nothing resampled. Matches BD3D2MK3D."
        case .hsbs: return "Half horizontal resolution per eye."
        case .ftab: return "1:1, stacked instead of side by side."
        case .htab: return "Half vertical resolution per eye."
        }
    }
}

enum EncoderKind: String, CaseIterable, Identifiable, Codable {
    case x264, x265, videotoolbox
    var id: String { rawValue }

    var title: String {
        switch self {
        case .x264: return "H.264 / x264"
        case .x265: return "H.265 / x265"
        case .videotoolbox: return "H.265 VideoToolbox"
        }
    }

    var note: String {
        switch self {
        case .x264: return "Same encoder as BD3D2MK3D. Widest compatibility, and roughly four times the size of HEVC for the same quality."
        case .x265: return "Smaller files, slower."
        case .videotoolbox: return "Apple media engine. Measured at quality 62 it matched x265 CRF 20 slow on both PSNR and SSIM, 8% larger, 27 times faster."
        }
    }
}

struct QualityPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let crf: Int
    let detail: String

    static let all: [QualityPreset] = [
        QualityPreset(id: "archive", name: "Archive", crf: 16,
                      detail: "CRF 16. Near transparent, but still a re-encode rather than a copy of the source. This is what BD3D2MK3D users normally pick."),
        QualityPreset(id: "high", name: "High", crf: 18,
                      detail: "CRF 18. Roughly 20% smaller than CRF 16. Slightly more grain smoothing and a little more banding risk in dark scenes."),
        QualityPreset(id: "medium", name: "Medium", crf: 20,
                      detail: "CRF 20. Visibly lossy on grain and dark gradients. Fine for casual viewing, not for archiving.")
    ]
}

struct JobSettings: Codable, Equatable {
    /// Bumped whenever the recommended defaults change. A saved blob carries the
    /// number it was written with, so the app can tell that someone's settings
    /// predate a recommendation without silently overwriting their choices.
    /// 1: x264, CRF 16, 8-bit, dark tuning on. The original guesses.
    /// 2: VideoToolbox quality 62, 10-bit, dark tuning off. All measured.
    static let currentSchema = 2

    var schema: Int = JobSettings.currentSchema

    /// The measured recommendations, keeping where the file is going.
    ///
    /// Destination and name describe this job, not the encoding advice, so
    /// resetting the video settings must not silently move someone's output.
    static func recommended(from old: JobSettings) -> JobSettings {
        var fresh = JobSettings()
        fresh.outputFolder = old.outputFolder
        fresh.outputName = old.outputName
        return fresh
    }


    var crf: Int = 20               // only used by x264 and x265
    var preset: String = "slow"
    var layout: Layout = .fsbs
    var encoder: EncoderKind = .videotoolbox
    var outputFolder: String = ""       // empty means alongside the source
    var outputName: String = ""         // empty means derived from the source
    var tempFolder: String = ""         // empty means alongside the output
    var audioTracks: [Int] = []         // empty means keep all
    var subTracks: [Int] = []           // empty means keep all
    var dropAudio: Bool = false
    var dropSubs: Bool = false
    var dropChapters: Bool = false
    var maxRate: Int = 0            // Mbps, 0 means no cap
    var swapEyes: Bool = false
    var vtQuality: Int = 62         // VideoToolbox only, 1 to 100
    var singleThread: Bool = false
    var tenBit: Bool = true
    var flatSubs: Bool = false
    var subDepth: Int = 0
    var subBrightness: Double = 1.0
    var subColour: String = "source"
    var subOpacity: Double = 1.0
    var darkTuning: Bool = false    // measured worthless at 10-bit
    var extraArgs: String = ""

    /// True when the saved settings were written before the current
    /// recommendations, so the app can offer to update rather than assume.
    var predatesCurrentAdvice: Bool { schema < JobSettings.currentSchema }

    static let presets = ["ultrafast", "superfast", "veryfast", "faster",
                          "fast", "medium", "slow", "slower", "veryslow"]

    init() {}

    /// Swift's synthesised decoder throws on a missing key even when the
    /// property has a default value, so every new setting would wipe the saved
    /// defaults of everyone upgrading. Decode each key if present, fall back to
    /// the default if not.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func b(_ k: CodingKeys, _ d: Bool) -> Bool { (try? c.decode(Bool.self, forKey: k)) ?? d }
        func i(_ k: CodingKeys, _ d: Int) -> Int { (try? c.decode(Int.self, forKey: k)) ?? d }
        func s(_ k: CodingKeys, _ d: String) -> String { (try? c.decode(String.self, forKey: k)) ?? d }
        func f(_ k: CodingKeys, _ d: Double) -> Double { (try? c.decode(Double.self, forKey: k)) ?? d }

        schema = i(.schema, 1)   // absent means it predates the schema field
        crf = i(.crf, 20)
        preset = s(.preset, "slow")
        layout = (try? c.decode(Layout.self, forKey: .layout)) ?? .fsbs
        encoder = (try? c.decode(EncoderKind.self, forKey: .encoder)) ?? .videotoolbox
        outputFolder = s(.outputFolder, "")
        outputName = s(.outputName, "")
        tempFolder = s(.tempFolder, "")
        audioTracks = (try? c.decode([Int].self, forKey: .audioTracks)) ?? []
        subTracks = (try? c.decode([Int].self, forKey: .subTracks)) ?? []
        dropAudio = b(.dropAudio, false)
        dropSubs = b(.dropSubs, false)
        dropChapters = b(.dropChapters, false)
        maxRate = i(.maxRate, 0)
        swapEyes = b(.swapEyes, false)
        vtQuality = i(.vtQuality, 62)
        singleThread = b(.singleThread, false)
        tenBit = b(.tenBit, true)
        flatSubs = b(.flatSubs, false)
        subDepth = i(.subDepth, 0)
        subBrightness = f(.subBrightness, 1.0)
        subColour = s(.subColour, "source")
        subOpacity = f(.subOpacity, 1.0)
        darkTuning = b(.darkTuning, false)
        extraArgs = s(.extraArgs, "")
    }
}

// MARK: - What ffprobe tells us about a source file

struct TrackInfo: Identifiable, Hashable {
    let id: String           // stable identity for SwiftUI
    let typeIndex: Int       // index within its own type: a:0, a:1, s:0 ...
    let kind: String         // "audio" or "subtitle"
    let codec: String
    let language: String
    let channels: Int
    let channelLayout: String
    let sampleRate: Int
    let profile: String

    /// Short, readable codec name. Raw FFmpeg names like hdmv_pgs_subtitle are
    /// too long for a column and tell you nothing you did not already know.
    var codecLabel: String {
        switch codec {
        case "hdmv_pgs_subtitle": return "PGS"
        case "dvd_subtitle":      return "VobSub"
        case "subrip":            return "SRT"
        case "ass", "ssa":        return "ASS"
        case "truehd":            return profile.isEmpty ? "TrueHD" : "TrueHD \(profile)"
        case "eac3":              return "E-AC3"
        case "ac3":               return "AC3"
        case "dts":               return profile.isEmpty ? "DTS" : profile
        case "flac":              return "FLAC"
        case "pcm_bluray":        return "LPCM"
        default:                  return codec.uppercased()
        }
    }

    /// Detail for the right hand column. Subtitles have nothing to add beyond
    /// the codec, so returning it again just printed it twice.
    var summary: String {
        guard kind == "audio" else { return "" }
        var bits: [String] = []
        if sampleRate > 0 { bits.append("\(sampleRate / 1000) kHz") }
        if channels > 0 { bits.append("\(channels) ch") }
        if !channelLayout.isEmpty { bits.append(channelLayout) }
        return bits.joined(separator: ", ")
    }
}

struct SourceInfo {
    var width: Int = 0
    var height: Int = 0
    var fps: Double = 0
    var duration: Double = 0
    var videoCodec: String = ""
    var audio: [TrackInfo] = []
    var subs: [TrackInfo] = []

    var resolutionText: String { width > 0 ? "\(width)x\(height)" : "unknown" }

    var durationText: String {
        guard duration > 0 else { return "--:--:--" }
        let t = Int(duration.rounded())
        return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }

    var codecText: String {
        guard width > 0 else { return "" }
        return String(format: "%@ %.2f fps", videoCodec.uppercased(), fps)
    }

    var estimatedFrames: Int { Int(duration * fps) }

    /// What the frame becomes for a given layout. The decoder always hands back
    /// a full width side-by-side frame; the half layouts scale it afterwards.
    func outputSize(for layout: Layout) -> String {
        guard width > 0 else { return "" }
        switch layout {
        case .fsbs: return "\(width * 2)x\(height)"
        case .hsbs: return "\(width)x\(height)"
        case .ftab: return "\(width)x\(height * 2)"
        case .htab: return "\(width)x\(height)"
        }
    }
}

// MARK: - A single conversion

/// What a launch is for. Preview and smoke tests reuse the whole pipeline but
/// must not leave the job looking like a finished conversion.
enum RunMode {
    case convert, preview, smokeTest
}

enum JobState: String {
    case queued, probing, running, stopping, succeeded, failed, cancelled

    var label: String {
        switch self {
        case .queued: return "Queued"
        case .probing: return "Reading"
        case .running: return "Converting"
        case .stopping: return "Stopping"
        case .succeeded: return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

final class Job: ObservableObject, Identifiable {
    let id = UUID()
    let sourceURL: URL

    @Published var settings: JobSettings
    @Published var info = SourceInfo()
    @Published var state: JobState = .queued
    @Published var stage: String = ""
    @Published var mvcConfirmed: Bool? = nil
    @Published var decoderSize: String = ""

    @Published var totalFrames: Int = 0
    @Published var currentFrame: Int = 0
    @Published var fps: Double = 0
    @Published var speed: String = ""
    @Published var outTimeSeconds: Double = 0

    @Published var startedAt: Date? = nil
    @Published var finishedAt: Date? = nil
    @Published var outputPath: String = ""
    @Published var lengthCheck: String = ""
    @Published var chapterCheck: String = ""
    @Published var startupCheck: String = ""
    /// "ok SRC OUT" or "drift SRC OUT DELTA" from the post-encode subtitle check.
    @Published var subCheck: String = ""
    /// "ok +/-N", "inverted +/-N" or "unknown" from the post-encode eye check.
    @Published var eyeCheck: String = ""
    @Published var psnr: String = ""
    @Published var previewImagePath: String = ""
    @Published var message: String = ""
    @Published var log: String = ""

    /// Bumped on a timer while the job runs. Elapsed and remaining are computed
    /// from the clock, not from stored state, so without something publishing
    /// they would sit frozen between progress updates.
    @Published var tick: Int = 0

    init(sourceURL: URL, settings: JobSettings) {
        self.sourceURL = sourceURL
        self.settings = settings
    }

    var displayName: String { sourceURL.deletingPathExtension().lastPathComponent }

    /// Rip tools leave markers like ".3D.MVC" on the filename. They describe the
    /// source, not the output, so they are dropped from the suggested name.
    var cleanName: String {
        // Strip 3D and MVC markers wherever they appear, not only at the end.
        // "Avatar- Fire and Ash (2025).3D.MVC.Disc 1" carries them in the
        // middle, and a suffix-only rule left them in place.
        //
        // Only tokens delimited by . - or _ are removed, never by a space, so a
        // film actually called "Spy Kids 3D" keeps its name.
        let pattern = "[._-](?:3D[._-]MVC|MVC[._-]3D|3D-MVC|MVC|3D)(?=[._-]|$)"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return displayName
        }
        var name = displayName
        var previous = ""
        while previous != name {
            previous = name
            name = re.stringByReplacingMatches(
                in: name,
                range: NSRange(name.startIndex..., in: name),
                withTemplate: "")
        }
        // Removing a token can leave "..", which is not a name anyone wants.
        if let collapse = try? NSRegularExpression(pattern: "[._-]{2,}") {
            name = collapse.stringByReplacingMatches(
                in: name,
                range: NSRange(name.startIndex..., in: name),
                withTemplate: ".")
        }
        let trimmed = name.trimmingCharacters(in: CharacterSet(charactersIn: " ._-"))
        return trimmed.isEmpty ? displayName : trimmed
    }

    /// Only the encode stage has meaningful frame based progress. Extraction is
    /// reported separately because it has no frame count of its own.
    var fraction: Double {
        guard totalFrames > 0, currentFrame > 0 else { return 0 }
        return min(1.0, Double(currentFrame) / Double(totalFrames))
    }

    var elapsed: TimeInterval {
        guard let s = startedAt else { return 0 }
        return (finishedAt ?? Date()).timeIntervalSince(s)
    }

    var remaining: TimeInterval? {
        guard state == .running, fps > 0, totalFrames > currentFrame else { return nil }
        return Double(totalFrames - currentFrame) / fps
    }

    func appendLog(_ text: String) {
        log.append(text)
        // Keep memory bounded on a multi hour encode.
        if log.count > 400_000 { log = String(log.suffix(200_000)) }
    }

    static func timeText(_ t: TimeInterval?) -> String {
        guard let t = t, t.isFinite, t >= 0 else { return "--:--:--" }
        let s = Int(t.rounded())
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}
