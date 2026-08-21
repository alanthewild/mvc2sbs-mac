// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Alan Wild
import Foundation
import Combine

// MARK: - Settings

enum ShrinkCodec: String, CaseIterable, Identifiable, Codable {
    case vt, x265
    var id: String { rawValue }

    var title: String {
        switch self {
        case .vt: return "H.265 VideoToolbox"
        case .x265: return "H.265 / x265"
        }
    }

    var note: String {
        switch self {
        case .vt: return "Apple media engine, about 7.6x realtime at 1080p on an M1 Pro. Quality 62 sits on the knee of the curve."
        case .x265: return "Marginally smaller and marginally worse than VideoToolbox 62, for twenty-five times the encode time."
        }
    }
}

/// What happens to the original once every check has passed.
enum ReplacePolicy: String, CaseIterable, Identifiable, Codable {
    case keep, folder, insitu
    var id: String { rawValue }

    var title: String {
        switch self {
        case .keep: return "Keep originals"
        case .folder: return "Move to _replaced"
        case .insitu: return "Replace in place"
        }
    }

    /// Only two of the three have a flag. The _replaced folder is the script's
    /// default, so asking for it means passing nothing.
    var flags: [String] {
        switch self {
        case .keep: return ["--keep-originals"]
        case .folder: return []
        case .insitu: return ["--in-situ"]
        }
    }

    var note: String {
        switch self {
        case .keep: return "Writes alongside and never touches the source. Nothing is reclaimed until you delete the originals yourself, which is the point."
        case .folder: return "The original moves into a _replaced folder after every check passes. Reversible, and disk comes back when you empty it."
        case .insitu: return "The original is replaced by rename. Least disk needed, nothing to undo. Marked untested on real media in the tool's own status notes."
        }
    }
}

struct ShrinkSettings: Codable, Equatable {
    var codec: ShrinkCodec = .vt
    var vtQuality: Int = 62
    var crf: Int = 20
    var preset: String = "slow"
    var tenBit: Bool = true

    var minSavingPct: Int = 10
    var minSizeGB: Int = 5
    var minPSNR: Int = 40

    var audioLangs: String = "eng,en"
    var subLangs: String = "eng,en,und"
    var keepForced: Bool = true
    var keepCommentary: Bool = true
    var keepAllTracks: Bool = false

    var replace: ReplacePolicy = .keep
    var recurse: Bool = true
    var skipHEVC: Bool = true
    var tempFolder: String = ""
    var probeCount: Int = 3
    var probeLen: Int = 20

    static let presets = ["ultrafast", "superfast", "veryfast", "faster",
                          "fast", "medium", "slow", "slower", "veryslow"]

    init() {}

    /// Same reasoning as JobSettings in the other app: Swift's synthesised
    /// decoder throws on a missing key even where the property has a default,
    /// so adding one setting would silently wipe everything anyone had saved.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func b(_ k: CodingKeys, _ d: Bool) -> Bool { (try? c.decode(Bool.self, forKey: k)) ?? d }
        func i(_ k: CodingKeys, _ d: Int) -> Int { (try? c.decode(Int.self, forKey: k)) ?? d }
        func s(_ k: CodingKeys, _ d: String) -> String { (try? c.decode(String.self, forKey: k)) ?? d }

        codec = (try? c.decode(ShrinkCodec.self, forKey: .codec)) ?? .vt
        vtQuality = i(.vtQuality, 62)
        crf = i(.crf, 20)
        preset = s(.preset, "slow")
        tenBit = b(.tenBit, true)
        minSavingPct = i(.minSavingPct, 10)
        minSizeGB = i(.minSizeGB, 5)
        minPSNR = i(.minPSNR, 40)
        audioLangs = s(.audioLangs, "eng,en")
        subLangs = s(.subLangs, "eng,en,und")
        keepForced = b(.keepForced, true)
        keepCommentary = b(.keepCommentary, true)
        keepAllTracks = b(.keepAllTracks, false)
        replace = (try? c.decode(ReplacePolicy.self, forKey: .replace)) ?? .keep
        recurse = b(.recurse, true)
        skipHEVC = b(.skipHEVC, true)
        tempFolder = s(.tempFolder, "")
        probeCount = i(.probeCount, 3)
        probeLen = i(.probeLen, 20)
    }

    /// The flags that describe these settings, shared by planning and applying
    /// so a plan cannot be built under one set of rules and carried out under
    /// another.
    var arguments: [String] {
        var a: [String] = []
        // VideoToolbox is the default and has no flag of its own, so the
        // encoder is chosen by whether --x265 is present.
        switch codec {
        case .vt:
            a += ["--vt-quality", String(vtQuality)]
        case .x265:
            a += ["--x265", "--crf", String(crf), "--preset", preset]
        }
        // Same again: 10-bit is the default, and only its absence has a flag.
        if !tenBit { a.append("--8bit") }
        a += ["--min-saving", String(minSavingPct)]
        a += ["--min-size", String(minSizeGB) + "G"]
        a += ["--min-psnr", String(minPSNR)]
        a += ["--audio-langs", audioLangs]
        a += ["--sub-langs", subLangs]
        if !keepForced { a.append("--no-forced") }
        if !keepCommentary { a.append("--no-commentary") }
        if keepAllTracks { a.append("--keep-all-tracks") }
        if !skipHEVC { a.append("--no-skip-hevc") }
        if !recurse { a.append("--no-recurse") }
        a += replace.flags
        if !tempFolder.isEmpty { a += ["--temp", tempFolder] }
        a += ["--probes", String(probeCount)]
        a += ["--probe-len", String(probeLen)]
        return a
    }
}

// MARK: - A row of the plan

/// One line of the plan TSV.
///
/// A class rather than a struct because the table edits it in place: ticking a
/// row, or changing its action, has to be visible to the list without copying
/// the whole plan back and forth.
final class PlanRow: ObservableObject, Identifiable {
    let id = UUID()

    @Published var include: Bool
    @Published var action: String       // shrink | strip | skip
    @Published var audio: String
    @Published var subs: String

    let savePct: Double
    let psnr: Double
    let ssim: Double
    /// Banding risk, as a percentage of sampled frames that are both dark and
    /// low contrast. Negative means the plan did not carry one.
    let risk: Double
    let sizeMB: Double
    let predMB: Double
    let uid: String
    let path: String
    let reason: String

    /// Set while this file is being worked on, and afterwards to say how it
    /// went. The plan is the log as well as the plan.
    @Published var state: String = ""
    @Published var progress: Double = 0
    @Published var savedPct: String = ""
    /// How the finished file landed: kept, moved or replaced. Reported by
    /// mkvshrink rather than read from the current settings, because the
    /// setting can be changed while a queue is running and the row should say
    /// what happened to that file, not what would happen to the next one.
    @Published var landed: String = ""

    /// What the row says once it is finished. The state word alone said
    /// "verify", which was the last stage that emitted an event, so a
    /// completed file looked like one stuck mid-check.
    var finishedLine: String {
        var s = "Finished"
        if let pct = Double(savedPct), pct > 0 {
            s += String(format: ", %.1f%% smaller", pct)
        }
        switch landed {
        case "kept":     s += ", written beside the original as \(baseName).shrunk.mkv"
        case "moved":    s += ", original moved to _replaced"
        case "replaced": s += ", original replaced in place"
        default: break
        }
        return s
    }

    /// The file name without its extension, for the .shrunk.mkv line.
    var baseName: String {
        (name as NSString).deletingPathExtension
    }

    var name: String { (path as NSString).lastPathComponent }
    var folder: String { (path as NSString).deletingLastPathComponent }

    /// mkvshrink puts "drops-audio:jpn" in the reason column when a language
    /// loses every one of its tracks. That is the one selection mistake the ID
    /// columns cannot show and that nothing can undo once the original is
    /// gone, so it is flagged rather than left in a string.
    var dropsAudioLang: Bool { reason.contains("drops-audio:") }

    /// 10-bit H.264, which no consumer hardware decoder will take. The gates
    /// here measure bytes, and this file's problem is not bytes: it transcodes
    /// on playback whatever its size, so converting it is worth doing at any
    /// saving. Worth pointing at rather than leaving in a reason string.
    var hi10p: Bool { reason.contains("hi10p") }

    /// The languages in question, for the sheet's warning line. Read to the
    /// end of the string rather than to the next comma: the marker is written
    /// last precisely because the language list it carries is comma separated
    /// too.
    var droppedAudioLangs: String {
        guard let r = reason.range(of: "drops-audio:") else { return "" }
        return String(reason[r.upperBound...])
    }

    init(action: String, audio: String, subs: String, savePct: Double,
         psnr: Double, ssim: Double = 0, risk: Double = -1,
         sizeMB: Double, predMB: Double, uid: String,
         path: String, reason: String) {
        self.action = action
        self.audio = audio
        self.subs = subs
        self.savePct = savePct
        self.psnr = psnr
        self.ssim = ssim
        self.risk = risk
        self.sizeMB = sizeMB
        self.predMB = predMB
        self.uid = uid
        self.path = path
        self.reason = reason
        // Anything the rules decided to skip starts unticked. Everything else
        // starts ticked, because the rules exist to be believed by default.
        self.include = action != "skip"
    }

    /// The row as mkvshrink will read it back. The order here is the order of
    /// the header mkvshrink writes, and the script reads by position, so these
    /// two have to move together. test_shrink_gui.py checks that they have.
    var tsv: String {
        [action, audio, subs,
         String(format: "%.1f", savePct),
         psnr > 0 ? String(format: "%.2f", psnr) : "-",
         ssim > 0 ? String(format: "%.4f", ssim) : "-",
         risk >= 0 ? String(format: "%.0f", risk) : "-",
         String(format: "%.0f", sizeMB),
         String(format: "%.0f", predMB),
         uid, path, reason].joined(separator: "\t")
    }
}

enum PlanFile {
    /// Parse a plan TSV. Comment lines carry the header and the settings, and
    /// are kept so the file written back is the file that was read.
    static func parse(_ text: String) -> (header: [String], rows: [PlanRow]) {
        var header: [String] = []
        var rows: [PlanRow] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if s.hasPrefix("#") { header.append(s); continue }
            if s.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let f = s.components(separatedBy: "\t")
            // Twelve columns since the ssim and risk columns were added, ten
            // before that. A plan saved by an older build still opens, and
            // reading it with the wrong field list would silently put its size
            // in the ssim column and shift every number after it.
            if f.count >= 12 {
                rows.append(PlanRow(
                    action: f[0], audio: f[1], subs: f[2],
                    savePct: Double(f[3]) ?? 0,
                    psnr: Double(f[4]) ?? 0,
                    ssim: Double(f[5]) ?? 0,
                    risk: Double(f[6]) ?? -1,
                    sizeMB: Double(f[7]) ?? 0,
                    predMB: Double(f[8]) ?? 0,
                    uid: f[9], path: f[10], reason: f[11]))
            } else if f.count >= 10 {
                rows.append(PlanRow(
                    action: f[0], audio: f[1], subs: f[2],
                    savePct: Double(f[3]) ?? 0,
                    psnr: Double(f[4]) ?? 0,
                    ssim: 0, risk: -1,
                    sizeMB: Double(f[5]) ?? 0,
                    predMB: Double(f[6]) ?? 0,
                    uid: f[7], path: f[8], reason: f[9]))
            }
        }
        return (header, rows)
    }

    /// `all` writes every row given rather than only the ticked ones, for the
    /// case where the caller has already decided which rows those are.
    static func write(header: [String], rows: [PlanRow], all: Bool = false) -> String {
        var out = header
        for r in rows where all || r.include {
            out.append(r.tsv)
        }
        return out.joined(separator: "\n") + "\n"
    }
}

// MARK: - Sorting

enum PlanSort: String, CaseIterable, Identifiable {
    case name, action, saving, size, sizeAfter, psnr, risk, reason
    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Name"
        case .action: return "Action"
        case .saving: return "Saving"
        case .size: return "Size"
        case .sizeAfter: return "Size after"
        case .psnr: return "PSNR"
        case .risk: return "Risk"
        case .reason: return "Reason"
        }
    }

    /// Ordering for one key. Ascending, and the header flips it.
    func less(_ a: PlanRow, _ b: PlanRow) -> Bool {
        switch self {
        case .name:
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        case .action:
            return a.action == b.action
                ? a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                : a.action < b.action
        case .saving:    return a.savePct < b.savePct
        case .size:      return a.sizeMB < b.sizeMB
        case .sizeAfter: return a.predMB < b.predMB
        case .psnr:      return a.psnr < b.psnr
        case .risk:      return a.risk < b.risk
        case .reason:    return a.reason < b.reason
        }
    }
}

// MARK: - Tracks

/// One row of `mkvshrink --tracks`, which is the same table the script prints
/// for a human, tab separated. Read on demand for one file rather than carried
/// in the plan: the plan holds the decision, and this is what the decision was
/// made about.
struct TrackInfo: Identifiable, Equatable {
    let id: Int
    let type: String        // video | audio | subtitles
    let lang: String
    let codec: String
    let channels: String
    let flags: String
    let bytes: Double
    let keptByRules: Bool
    let why: String
    let name: String

    var isVideo: Bool { type == "video" }

    /// What the row says about itself, in the order that matters when you are
    /// looking for the Japanese track on a Japanese film.
    var label: String {
        var s = "\(id)  \(lang.uppercased())  \(codec)"
        if !channels.isEmpty && type == "audio" { s += " \(channels)ch" }
        if !name.isEmpty { s += "  \(name)" }
        if !flags.isEmpty { s += "  [\(flags)]" }
        return s
    }

    static func parse(_ text: String) -> [TrackInfo] {
        var out: [TrackInfo] = []
        for line in text.split(separator: "\n") {
            if line.hasPrefix("#") { continue }
            let f = line.components(separatedBy: "\t")
            guard f.count >= 8, let id = Int(f[0]) else { continue }
            out.append(TrackInfo(
                id: id, type: f[1], lang: f[2], codec: f[3], channels: f[4],
                flags: f[5], bytes: Double(f[6]) ?? 0, keptByRules: f[7] == "1",
                why: f.count > 8 ? f[8] : "",
                name: f.count > 9 ? f[9] : ""))
        }
        return out
    }
}

/// The audio or subs column of a plan row, as a set of IDs.
///
/// "all" and "none" are both legal in the file and both mean something the ID
/// list cannot say on its own, so they are resolved against the tracks the
/// file actually has before anything is ticked.
enum TrackSelection {
    static func ids(from column: String, all: [TrackInfo]) -> Set<Int> {
        let t = column.trimmingCharacters(in: .whitespaces)
        if t == "all" { return Set(all.map { $0.id }) }
        if t == "none" || t == "-" || t.isEmpty { return [] }
        return Set(t.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }

    static func column(_ ids: Set<Int>) -> String {
        ids.isEmpty ? "none" : ids.sorted().map(String.init).joined(separator: ",")
    }
}
