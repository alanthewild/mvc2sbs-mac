// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Alan Wild
import SwiftUI
import AppKit

struct ShrinkSettingsSheet: View {
    @EnvironmentObject var defaults: ShrinkDefaults
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    private var s: ShrinkSettings { defaults.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings").font(.title3)
                Spacer()
                Button("Reset to Defaults") { confirmReset = true }
                    .buttonStyle(.bordered)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Encoder") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Picker("", selection: $defaults.settings.codec) {
                                    ForEach(ShrinkCodec.allCases) { Text($0.title).tag($0) }
                                }
                                .labelsHidden().fixedSize()
                                Toggle("10-bit", isOn: $defaults.settings.tenBit)
                                Spacer()
                            }
                            Text(s.codec.note).font(.caption).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            if s.codec == .vt {
                                HStack {
                                    Text("Quality").frame(width: 70, alignment: .leading)
                                    Stepper(value: $defaults.settings.vtQuality, in: 1...100) {
                                        Text("\(s.vtQuality)")
                                    }
                                    Spacer()
                                }
                                Text(qualityNote).font(.caption).foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                HStack {
                                    Text("CRF").frame(width: 70, alignment: .leading)
                                    Stepper(value: $defaults.settings.crf, in: 0...35) {
                                        Text("\(s.crf)")
                                    }
                                    Picker("", selection: $defaults.settings.preset) {
                                        ForEach(ShrinkSettings.presets, id: \.self) { Text($0).tag($0) }
                                    }.labelsHidden().fixedSize()
                                    Spacer()
                                }
                            }
                            Text("10-bit costs nothing in size or speed and is the better answer to banding. Leave it on.")
                                .font(.caption).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                    }

                    GroupBox("Which files are worth it") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Min size").frame(width: 110, alignment: .leading)
                                Stepper(value: $defaults.settings.minSizeGB, in: 0...100) {
                                    Text("\(s.minSizeGB) GB")
                                }
                                Spacer()
                            }
                            Text("A small file is usually small because it was already encoded at a low bitrate, so re-encoding inflates it. This gate is cheap and runs before any probe.")
                                .font(.caption).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack {
                                Text("Min saving").frame(width: 110, alignment: .leading)
                                Stepper(value: $defaults.settings.minSavingPct, in: 0...90) {
                                    Text("\(s.minSavingPct)%")
                                }
                                Spacer()
                            }
                            Text("Measured against a free lossless remux rather than against doing nothing, so this is what the re-encode adds on top of simply dropping tracks.")
                                .font(.caption).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack {
                                Text("Min PSNR").frame(width: 110, alignment: .leading)
                                Stepper(value: $defaults.settings.minPSNR, in: 0...60) {
                                    Text("\(s.minPSNR) dB")
                                }
                                Spacer()
                            }
                            Text("PSNR did not predict what the eye saw in three cases out of four: the only real failure scored higher than a film that was fine. Treat this as a weak filter, and consider setting it to 0 and judging by eye.")
                                .font(.caption).foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack {
                                Text("Probes").frame(width: 110, alignment: .leading)
                                Stepper(value: $defaults.settings.probeCount, in: 1...8) {
                                    Text("\(s.probeCount)")
                                }
                                Text("of").foregroundColor(.secondary)
                                Stepper(value: $defaults.settings.probeLen, in: 5...120) {
                                    Text("\(s.probeLen)s")
                                }
                                Spacer()
                            }
                            Text("The reported PSNR is the worst window, not the mean, so more windows is a stronger claim rather than a smoother one.")
                                .font(.caption).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Toggle("Skip files that are already HEVC", isOn: $defaults.settings.skipHEVC)
                            Toggle("Look in subfolders", isOn: $defaults.settings.recurse)
                        }
                        .padding(8)
                    }

                    GroupBox("Tracks to keep") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Audio").frame(width: 70, alignment: .leading)
                                TextField("eng,en", text: $defaults.settings.audioLangs)
                            }
                            HStack {
                                Text("Subtitles").frame(width: 70, alignment: .leading)
                                TextField("eng,en,und", text: $defaults.settings.subLangs)
                            }
                            Toggle("Keep forced subtitles in any language", isOn: $defaults.settings.keepForced)
                            Toggle("Keep commentary tracks", isOn: $defaults.settings.keepCommentary)
                            Toggle("Keep everything, drop nothing", isOn: $defaults.settings.keepAllTracks)

                            Text("The first audio track is always kept whatever its language. That covers a foreign film only when the original language comes first: on a release that puts an English dub at track 1 and the original at track 4, the original is dropped. Any language that loses every track is reported in the plan's reason column as drops-audio, so read that column before starting.")
                                .font(.caption).foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                    }

                    GroupBox("Originals") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("", selection: $defaults.settings.replace) {
                                ForEach(ReplacePolicy.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.radioGroup)
                            .labelsHidden()
                            Text(s.replace.note).font(.caption)
                                .foregroundColor(s.replace == .insitu ? .orange : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("This app defaults to keeping originals, which differs from the command line tool, where the default is the _replaced folder.")
                                .font(.caption).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            ShrinkFolderRow(label: "Scratch", path: $defaults.settings.tempFolder,
                                            placeholder: "Automatic: beside the output")
                            Text("Put this on a local disk if the library is on a NAS. The finished file is copied onto the destination filesystem and size checked before anything is renamed, so a scratch disk cannot leave a partial file where an original used to be.")
                                .font(.caption).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                    }

                    GroupBox("What will be run") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("mkvshrink " + s.arguments.joined(separator: " "))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Shown because a GUI that hides its command line is harder to trust and harder to debug.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        .padding(8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(minWidth: 720, idealWidth: 800, minHeight: 560, idealHeight: 760)
        .confirmationDialog("Reset every setting to the defaults?",
                            isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Yes", role: .destructive) { defaults.resetToRecommended() }
            Button("No", role: .cancel) {}
        } message: {
            Text("VideoToolbox quality 62, 10-bit, 5 GB minimum, 10% minimum saving, keep originals.")
        }
    }

    private var qualityNote: String {
        switch s.vtQuality {
        case 0...54: return "Below the useful range. Small files, visible loss."
        case 55...58: return "Below the knee. Measurably softer than x265 CRF 20."
        case 59...66: return "The useful range. 62 sits on the knee of the curve."
        default: return "Above the useful range. 65 was already better than x265 CRF 20, and the curve is flat above it."
        }
    }
}

struct ShrinkFolderRow: View {
    let label: String
    @Binding var path: String
    var placeholder: String = ""

    var body: some View {
        HStack {
            Text(label).frame(width: 70, alignment: .leading)
            TextField(placeholder, text: $path)
            Button("Choose\u{2026}") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                if panel.runModal() == .OK, let u = panel.url { path = u.path }
            }
            if !path.isEmpty {
                Button("Clear") { path = "" }
            }
        }
    }
}

// MARK: - Help

struct ShrinkHelpSection: Identifiable, Hashable {
    let title: String
    let rows: [ShrinkHelpRow]
    var id: String { title }

    static func == (a: ShrinkHelpSection, b: ShrinkHelpSection) -> Bool { a.title == b.title }
    func hash(into h: inout Hasher) { h.combine(title) }
}

struct ShrinkHelpRow: Identifiable, Hashable {
    let heading: String
    let body: String
    var id: String { heading }
}

let shrinkHelpSections: [ShrinkHelpSection] = [
    ShrinkHelpSection(title: "What this does", rows: [
        ShrinkHelpRow(heading: "The job", body: "Re-encodes existing H.264 films to HEVC to reclaim disk, and drops the audio and subtitle tracks you will never play. It is a library sweeper, not a converter: point it at a folder and it works out which files are worth the time."),
        ShrinkHelpRow(heading: "Only video is re-encoded", body: "Audio and subtitles are stream copied straight out of the source by mkvmerge, never through FFmpeg. That is what preserves their language, name, forced and commentary flags without anything forming an opinion about them."),
        ShrinkHelpRow(heading: "The original is the last thing touched", body: "Length, startup, seek index and chapter bounds are all checked on the new file first. Only then is the original moved or replaced, and by default this app does not touch it at all."),
        ShrinkHelpRow(heading: "It inherits the 3D tool's rules", body: "Mux with MKVToolNix and never FFmpeg, never let FFmpeg write chapters, preserve StereoMode and display dimensions. Some of the files you point it at will be side-by-side conversions, so those rules are not optional."),
    ]),
    ShrinkHelpSection(title: "How the plan is made", rows: [
        ShrinkHelpRow(heading: "Scan is the expensive half", body: "Pressing Scan does not read metadata and fill in a table. It cuts pieces out of every candidate and encodes them for real, which is why it takes minutes per file rather than seconds. Nothing on disk is changed by any of it, and you can stop at any point."),
        ShrinkHelpRow(heading: "Why it has to encode to find out", body: "How much HEVC wins depends on how tightly the source was already encoded, and nothing in the file says that. Two 28 GB Blu-ray rips can differ by forty points of saving. A prediction from bitrate and resolution would be a guess dressed up as a number, so it is measured instead."),
        ShrinkHelpRow(heading: "The gates come first, cheapest first", body: "Under the minimum size, skipped without probing: a small file is small because it was already encoded at a low bitrate, so re-encoding inflates it. Already HEVC becomes strip rather than shrink, since the tracks may still be worth hundreds of megabytes and that is a remux, not an encode. HDR and interlaced are skipped as untested paths. Only what survives all of that costs any probe time. Every one of these thresholds is a default you can change in Settings, and none of them is a law: they are where the time is best spent on a large library."),
        ShrinkHelpRow(heading: "Three windows, 20 seconds each", body: "Cut at 20%, 45% and 70% of the running time. The body of the film, because the opening is the cheapest minute of most films and the credits are cheaper still, and a sample of those predicts a saving no real scene will deliver. Both are settable: --probes and --probe-len."),
        ShrinkHelpRow(heading: "Cut by seeking, not by reading", body: "ffmpeg seeks to the mark; mkvmerge would read the source from byte zero and discard everything outside the window, which on a 56 GB remux is 39 GB across the network before a single frame is encoded, on a file it may then decide to skip. The cut is a stream copy, so it starts at the keyframe at or before the mark and is often a little longer than asked for. That changes nothing: each window is measured against the encode of that same window."),
        ShrinkHelpRow(heading: "What each window is measured on", body: "Its bytes against the encode's bytes, which is the ratio. PSNR and SSIM of the encode against that same cut, frame by frame, paired by position rather than timestamp: a copy and a re-encode disagree in the millisecond after rounding, and matching on timestamps compares frame N with frame N-1 and reports 27 dB on content that is really 43."),
        ShrinkHelpRow(heading: "What survives the arithmetic", body: "The ratio is the byte total across every window, so a big scene counts more than a small one. PSNR is the worst window, not the average: a file that holds up twice and falls apart once is a file that falls apart. SSIM the same. The saving is that ratio applied to the video track, then compared against what a free lossless remux would have reclaimed anyway."),
        ShrinkHelpRow(heading: "The checks on the probe itself", body: "A window that comes back shorter than asked for is discarded, because its ratio is measured against a fragment and three windows averaged together hide it. An encode that stops early is discarded too: fewer frames means fewer bytes and an excellent score on the frames that did encode, which reads as a spectacular saving and is the most dangerous thing a probe can report. If the windows disagree by more than three times, that is said out loud, because the total cannot show that one of them was a still or a near black scene."),
        ShrinkHelpRow(heading: "Then the banding risk", body: "Twenty-four frames sampled across the film, measuring how much of it is both dark and low in contrast. Seeks only, no encoding. Only for files something would be done to."),
    ]),
    ShrinkHelpSection(title: "Reading a plan", rows: [
        ShrinkHelpRow(heading: "Save", body: "Predicted saving, measured against a free lossless remux rather than against doing nothing. Accuracy is about plus or minus 10 points: Akira predicted 51.9% and delivered 55.7%, GoodFellas predicted 67.0% and delivered 57.8%. Good enough to decide whether to encode, not good enough to promise a number."),
        ShrinkHelpRow(heading: "PSNR", body: "Treat it as a weak signal. Across five films it did not predict what the eye saw, and the only real failure scored higher than a film that was fine. Low PSNR on grainy content just means the grain differs, which is invisible. PSNR is also nearly blind to banding, because the error is small and spread across a large flat area, which is exactly what an average hides. Casino Royale is the closest thing to a hit: it probed at 38.8 dB, below the floor, and forcing it through saved 48% and looked right everywhere except two almost entirely black scenes at the start, which crushed. The floor was pointing at something real and was over-cautious about it."),
        ShrinkHelpRow(heading: "Reason", body: "Why a file was skipped, or what will be lost. Read it before starting. A reason of drops-audio:jpn means every Japanese track would be dropped, which on a Japanese film is the original language."),
        ShrinkHelpRow(heading: "hi10p in the reason", body: "10-bit H.264, which anime releases use constantly and no consumer hardware decoder will take. Measured on the Shield this project is tested against: refused outright, profile not supported, and transcoded. HEVC Main 10 plays. That makes converting one of these worth doing at any saving, including none, which is the opposite of every other rule here. If a gate skipped it, the gate was measuring bytes and this file's problem is not bytes."),
        ShrinkHelpRow(heading: "Sort by saving", body: "The rows the rules got wrong cluster together. Sorting by saving puts the big wins and the obvious mistakes at opposite ends, which is faster than reading 1587 rows in file order."),
        ShrinkHelpRow(heading: "Risk", body: "The share of sampled frames that are both dark and low in contrast, which is the condition banding needs. This is the one number that has matched what the eye saw: Blade Runner 2049 measured 44% and was visibly damaged, Princess Mononoke measured 25% and was clean, A Silent Voice measured 5%. It is a reason to watch the result, not a verdict. Turn the measurement off with --no-risk if a sweep needs to be quicker."),
        ShrinkHelpRow(heading: "Tracks", body: "How many audio and subtitle tracks survive, and a button to change that. The plan carries track IDs, which say nothing about what is in them, so this reads the file and shows the language, codec, name and flags of each one, along with what the rules decided and why. This is where you put the Japanese track back on a Japanese film."),
        ShrinkHelpRow(heading: "Action", body: "shrink re-encodes the video and drops tracks. strip only drops tracks, which is lossless and takes a minute. skip leaves the file alone. Change it per row if you disagree with the rules, or for a whole run of rows with the right click menu."),
        ShrinkHelpRow(heading: "Right click a row", body: "Shrink only that one without touching any other tick, edit its tracks, set the action, or tick and untick everything from that row down. Down means down the screen, in whatever order the table is sorted, so sort first and then cut."),
        ShrinkHelpRow(heading: "The order of the work", body: "Top to bottom, in whatever order the table is sorted when you press Start. Sort by saving and the biggest wins happen first, which matters on a queue of twenty-five films you may stop halfway through. The status bar says so while a queue is selected."),
        ShrinkHelpRow(heading: "The two ETAs", body: "The first is this file. Batch is the whole queue, worked out from how long this run has taken so far per gigabyte, so it needs a minute or so of a real encode before it means anything. A strip row is a remux and finishes in a minute where a shrink row of the same size takes twenty, so a mixed queue drifts."),
    ]),
    ShrinkHelpSection(title: "Plans as files", rows: [
        ShrinkHelpRow(heading: "Save Plan", body: "Writes the ticked rows as a TSV. A plan costs minutes per file to produce, so it is worth keeping. The same file runs from a terminal with mkvshrink --apply."),
        ShrinkHelpRow(heading: "Load Plan", body: "Opens one back. Rows whose files have moved are unticked and marked missing before anything starts."),
        ShrinkHelpRow(heading: "A plan is not a promise", body: "Every row is re-probed as it is applied, and a file that is no longer the size the plan measured, or no longer carries the segment UID it recorded, is left alone and reported. Track IDs shift once a file has been remuxed, so applying a stale row would keep the wrong tracks and say nothing about it."),
    ]),
    ShrinkHelpSection(title: "What it cannot tell you", rows: [
        ShrinkHelpRow(heading: "Where the quality boundary sits", body: "Unknown, honestly. Sweep animation freely. Treat dark live action as a decision rather than a default, and keep the originals where you are unsure. A film with dark, narrow gradients is the case that bands, because those gradients had no headroom left in 8-bit."),
        ShrinkHelpRow(heading: "Whether the original language survives", body: "The rules keep every whitelisted language plus the first audio track. That covers a foreign film only when the original language comes first. On a release that puts the English dub at track 1 and the Japanese at track 4, the original is neither whitelisted nor first. No metadata reliably identifies a film's original language and FlagOriginal is set on virtually nothing, so no rule fixes this in general."),
        ShrinkHelpRow(heading: "What to do about it", body: "The tool names the loss rather than hiding it. Any language that loses every one of its tracks is written into the reason column as drops-audio:jpn, and that row's Tracks cell turns orange. Click it and the file's real track list opens, with the language, codec, name, flags and size of every track and what the rules decided about each. Tick the one you want back and it is kept, whatever the language whitelist says. That is a per file decision and it does not change the rules for anything else. To change the rules instead, add the language in Settings: --audio-langs eng,en,jpn."),
        ShrinkHelpRow(heading: "So review before an unattended sweep", body: "For a library with mixed languages, planning and reviewing is not optional. A direct run with no plan can still drop an original language, and once the original file is gone that audio is not recoverable."),
        ShrinkHelpRow(heading: "What has not been tested", body: "Replace in place has never been run on real media. Neither has the strip-only path on an already-HEVC file, nor anything carrying 3D side-by-side geometry. See docs/mkvshrink-status.md in the repository, which is deliberately honest about this."),
    ]),
    ShrinkHelpSection(title: "Settings worth knowing", rows: [
        ShrinkHelpRow(heading: "VideoToolbox quality 62", body: "Measured as the right default. It sits on the knee of the curve and above 65 is waste. x265 CRF 20 is marginally smaller and marginally worse for twenty-five times the encode time."),
        ShrinkHelpRow(heading: "One media engine", body: "Encoding is media engine bound, roughly 7.6x realtime at 1080p on an M1 Pro. There is one engine, so running two encodes at once splits it and gains nothing. Serial processing is deliberate."),
        ShrinkHelpRow(heading: "Minimum size", body: "A default, not a rule. 5 GB, and the stepper in Settings takes it from 0, which is off, up to 100 GB. Low bitrate web sources inflate rather than shrink, with ratios above 1.0, and this gate catches most of them before any probe time is spent on them. Lower it for a library of 2 GB encodes and expect most of them to be rejected later on their measured ratio instead, which is the same answer for more time. Every gate here works this way: minimum saving, minimum PSNR and the probe count are all yours to move."),
        ShrinkHelpRow(heading: "Track clutter", body: "A file carrying thirty junk subtitle tracks is worth remuxing even when the video is not worth re-encoding, but SRT tracks are text and tiny, so a byte-based gate will never fire on them. Set the action to strip by hand for those."),
    ]),
]

struct ShrinkHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String? = shrinkHelpSections.first?.title

    private var current: ShrinkHelpSection? {
        shrinkHelpSections.first { $0.title == selection } ?? shrinkHelpSections.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MKVShrink").font(.title3)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 12)

            HStack(spacing: 0) {
                List(shrinkHelpSections, selection: $selection) { s in
                    Text(s.title).font(.callout).padding(.vertical, 2)
                }
                .listStyle(.sidebar)
                .frame(width: 210)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let page = current {
                            Text(page.title).font(.title3).bold()
                            ForEach(page.rows) { row in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.heading).font(.callout).bold()
                                    Text(row.body).font(.callout).foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.bottom, 4)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .textSelection(.enabled)
        .frame(minWidth: 760, idealWidth: 900, minHeight: 440, idealHeight: 660)
    }
}
