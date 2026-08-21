// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Alan Wild
import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Root

struct ShrinkContentView: View {
    @EnvironmentObject var ctl: ShrinkController
    @EnvironmentObject var defaults: ShrinkDefaults
    @State private var showSettings = false
    @State private var showHelp = false
    @State private var sort: PlanSort = .saving
    @State private var ascending = false
    @State private var confirmApply = false
    @State private var trackRow: PlanRow?
    @State private var onlyRow: PlanRow?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if !ctl.toolWarning.isEmpty {
                ShrinkWarningStrip(text: ctl.toolWarning) { ctl.refreshToolWarning() }
            }
            // What happens to the originals, on screen at all times rather
            // than three clicks away in Settings. It is the one setting whose
            // wrong value is not recoverable, and the one most likely to be
            // remembered wrong: a sweep that reclaimed nothing and a sweep
            // that replaced twenty-five films look identical until it is over.
            ShrinkPolicyBanner(policy: defaults.settings.replace) { showSettings = true }
            Divider()
            if ctl.rows.isEmpty {
                emptyState
            } else {
                PlanHeaderRow(sort: $sort, ascending: $ascending)
                Divider()
                List(sortedRows) { row in
                    PlanRowView(row: row, enabled: editable,
                                onTracks: { trackRow = row })
                        .contextMenu { rowMenu(row) }
                }
                .listStyle(.inset)
            }
            Divider()
            ShrinkStatusBar()
        }
        .frame(minWidth: 1180, minHeight: 720)
        .sheet(isPresented: $showSettings) { ShrinkSettingsSheet() }
        .sheet(isPresented: $showHelp) { ShrinkHelpSheet() }
        .sheet(isPresented: $ctl.consoleVisible) { ShrinkConsoleSheet() }
        .sheet(item: $trackRow) { row in
            TrackSheet(row: row)
        }
        .confirmationDialog(applyQuestion,
                            isPresented: $confirmApply, titleVisibility: .visible) {
            Button("Yes", role: .destructive) {
                ctl.apply(settings: defaults.settings, order: sortedRows, only: onlyRow)
                onlyRow = nil
            }
            Button("No", role: .cancel) { onlyRow = nil }
        } message: {
            Text(applyDetail)
        }
    }

    private var editable: Bool { !ctl.running && !ctl.scanning }

    private var applyQuestion: String {
        if let r = onlyRow { return "Re-encode \(r.name)?" }
        return "Re-encode \(ctl.selectedCount) file(s)?"
    }

    // MARK: - Per row menu
    //
    // Everything here works on the order on screen, not the order in the plan.
    // "From here down" means what it looks like it means, whichever column the
    // table is sorted by.

    @ViewBuilder
    private func rowMenu(_ row: PlanRow) -> some View {
        Button("Shrink only this one") {
            onlyRow = row
            confirmApply = true
        }
        .disabled(!editable || row.action == "skip")

        Divider()

        Button("Edit tracks to keep") { trackRow = row }
            .disabled(!editable)

        Menu("Set action") {
            ForEach(["shrink", "strip", "skip"], id: \.self) { a in
                Button(a) { row.action = a }
            }
        }
        .disabled(!editable)

        Divider()

        Button("Untick from here down") { setInclude(false, from: row) }
            .disabled(!editable)
        Button("Tick from here down") { setInclude(true, from: row) }
            .disabled(!editable)
        Button("Untick everything above") { setIncludeAbove(false, from: row) }
            .disabled(!editable)

        Divider()

        Menu("Set action from here down") {
            ForEach(["shrink", "strip", "skip"], id: \.self) { a in
                Button(a) { setAction(a, from: row) }
            }
        }
        .disabled(!editable)

        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: row.path)])
        }
    }

    private func setInclude(_ on: Bool, from row: PlanRow) {
        let list = sortedRows
        guard let i = list.firstIndex(where: { $0.id == row.id }) else { return }
        for r in list[i...] { r.include = on }
    }

    private func setIncludeAbove(_ on: Bool, from row: PlanRow) {
        let list = sortedRows
        guard let i = list.firstIndex(where: { $0.id == row.id }) else { return }
        for r in list[..<i] { r.include = on }
    }

    private func setAction(_ a: String, from row: PlanRow) {
        let list = sortedRows
        guard let i = list.firstIndex(where: { $0.id == row.id }) else { return }
        for r in list[i...] { r.action = a }
    }

    private var applyDetail: String {
        let reclaim = ShrinkController.humanMB(ctl.selectedReclaimMB)
        switch defaults.settings.replace {
        case .keep:
            return "About \(reclaim) of predicted saving. Originals are left "
                + "exactly where they are, so nothing is reclaimed until you "
                + "delete them yourself."
        case .folder:
            return "About \(reclaim) of predicted saving. Each original moves "
                + "into a _replaced folder once every check has passed."
        case .insitu:
            return "About \(reclaim) of predicted saving. Each original is "
                + "REPLACED once every check has passed. This mode is recorded "
                + "as untested on real media."
        }
    }

    private var sortedRows: [PlanRow] {
        let sorted = ctl.rows.sorted { sort.less($0, $1) }
        return ascending ? sorted : sorted.reversed()
    }

    private var toolbar: some View {
        HStack(spacing: 20) {
            ShrinkToolButton(title: "Scan", symbol: "folder.badge.questionmark", tint: .secondary,
                             help: "Choose folders and build a plan. Probes every candidate and changes nothing",
                             enabled: !ctl.running && !ctl.scanning) { chooseFolders() }
            ShrinkToolButton(title: "Rescan", symbol: "arrow.clockwise", tint: .secondary,
                             help: "Plan the same folders again with the current settings",
                             enabled: !ctl.running && !ctl.scanning && !ctl.scannedFolders.isEmpty) {
                ctl.scan(paths: ctl.scannedFolders, settings: defaults.settings)
            }
            ShrinkToolButton(title: "Start", symbol: "play", tint: .green,
                             help: "Carry out the ticked rows",
                             enabled: !ctl.running && !ctl.scanning && ctl.selectedCount > 0) {
                confirmApply = true
            }
            ShrinkToolButton(title: "Stop", symbol: "stop", tint: .red,
                             help: "Stop after the current file",
                             enabled: ctl.running || ctl.scanning) { ctl.stop() }

            Divider().frame(height: 34)

            ShrinkToolButton(title: "All", symbol: "checkmark.square", tint: .cyan,
                             help: "Tick every row",
                             enabled: !ctl.rows.isEmpty && !ctl.running) {
                for r in ctl.rows { r.include = true }
            }
            ShrinkToolButton(title: "None", symbol: "square", tint: .cyan,
                             help: "Untick every row",
                             enabled: !ctl.rows.isEmpty && !ctl.running) {
                for r in ctl.rows { r.include = false }
            }
            // Bulk action. Twenty-five rows is too many to change one at a
            // time, and the whole point of a plan is that you can disagree
            // with it wholesale.
            Menu {
                ForEach(["shrink", "strip", "skip"], id: \.self) { a in
                    Button("Set ticked rows to \(a)") {
                        for r in ctl.rows where r.include { r.action = a }
                    }
                }
                Divider()
                Button("Untick rows the rules skipped") {
                    for r in ctl.rows where r.action == "skip" { r.include = false }
                }
                Button("Untick rows under 10% saving") {
                    for r in ctl.rows where r.savePct < 10 { r.include = false }
                }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 22, weight: .light))
                        .frame(height: 26)
                    Text("Bulk").font(.system(size: 11))
                }
                .foregroundColor(editable && !ctl.rows.isEmpty
                                 ? Color.cyan : Color.secondary.opacity(0.4))
                .frame(minWidth: 54)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!editable || ctl.rows.isEmpty)
            .help("Change the action on every ticked row at once")

            ShrinkToolButton(title: "Save Plan", symbol: "square.and.arrow.down", tint: .cyan,
                             help: "Write the ticked rows as a TSV you can keep, edit by hand, or run with mkvshrink --apply",
                             enabled: !ctl.rows.isEmpty) { savePlan() }
            ShrinkToolButton(title: "Load Plan", symbol: "square.and.arrow.up", tint: .cyan,
                             help: "Open a plan saved earlier. Every row is re-checked against the file before anything is done to it",
                             enabled: editable) { loadPlan() }

            Spacer()

            ShrinkToolButton(title: "Console", symbol: "terminal", tint: .teal,
                             help: "Everything mkvshrink printed") { ctl.consoleVisible = true }
            ShrinkToolButton(title: "Settings", symbol: "gearshape", tint: .cyan,
                             help: "Encoder, gates, track rules and what happens to originals") {
                showSettings = true
            }
            ShrinkToolButton(title: "Help", symbol: "questionmark.circle", tint: .secondary,
                             help: "What this does and how to read a plan") { showHelp = true }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: ctl.scanning ? "hourglass" : "internaldrive")
                .font(.system(size: 60, weight: .ultraLight))
                .foregroundColor(.accentColor)
            if ctl.scanning {
                Text("Planning").font(.headline)
                Text("Metadata cannot predict how much HEVC will win, because that depends on how tightly the source was already encoded. So each candidate gets a few short sample windows cut out and encoded for real, and the saving is measured rather than guessed.")
                    .font(.caption).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520)
                Text("That is why this takes minutes per file. Nothing on disk is being changed, and you can stop at any point.")
                    .font(.caption).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520)
                Text("Every probe window is printed as it is measured. Open the Console to watch it per file.")
                    .font(.caption).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520)
                ProgressView().progressViewStyle(.linear).frame(width: 320)
                if ctl.noteCount > 0 {
                    Button {
                        ctl.consoleVisible = true
                    } label: {
                        Label("\(ctl.noteCount) note\(ctl.noteCount == 1 ? "" : "s") so far, open the Console to read them",
                              systemImage: "text.alignleft")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                    .padding(.top, 4)
                }
            } else {
                Text("Scan a folder to build a plan").font(.headline)
                Text("Nothing is changed until you review the plan and press Start. A plan saved earlier can be opened with Load Plan.")
                    .font(.caption).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
                if !ctl.message.isEmpty {
                    Text(ctl.message).font(.callout)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                        .padding(.top, 6)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Scan"
        if panel.runModal() == .OK {
            ctl.scan(paths: panel.urls.map { $0.path }, settings: defaults.settings)
        }
    }

    private func loadPlan() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.tabSeparatedText, UTType.plainText]
        panel.prompt = "Load"
        if panel.runModal() == .OK, let url = panel.url {
            ctl.loadPlan(url: url)
        }
    }

    private func savePlan() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "plan.tsv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = PlanFile.write(header: ctl.header, rows: ctl.rows)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - The plan table

struct PlanHeaderRow: View {
    @Binding var sort: PlanSort
    @Binding var ascending: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text("").frame(width: 30)
            heading("File", .name, width: nil)
            heading("Action", .action, width: 90)
            heading("Tracks", nil, width: 66)
            heading("Save", .saving, width: 70)
            heading("Size", .size, width: 84)
            heading("After", .sizeAfter, width: 84)
            heading("PSNR", .psnr, width: 62)
            heading("Risk", .risk, width: 56)
            heading("Reason", .reason, width: 190)
        }
        .font(.caption).bold()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func heading(_ title: String, _ key: PlanSort?, width: CGFloat?) -> some View {
        let isActive = key != nil && key == sort
        Button {
            guard let k = key else { return }
            if sort == k { ascending.toggle() } else { sort = k; ascending = false }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                if isActive {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                }
            }
            .foregroundColor(isActive ? .accentColor : .secondary)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(key == nil)
    }
}

struct PlanRowView: View {
    @ObservedObject var row: PlanRow
    let enabled: Bool
    var onTracks: () -> Void = {}

    private var trackSummary: String {
        func count(_ s: String) -> String {
            let t = s.trimmingCharacters(in: .whitespaces)
            if t == "none" || t == "-" || t.isEmpty { return "0" }
            if t == "all" { return "all" }
            return String(t.split(separator: ",").count)
        }
        return "\(count(row.audio))a \(count(row.subs))s"
    }

    private var riskColour: Color {
        if row.risk < 0 { return .secondary }
        if row.risk >= 40 { return .red }
        if row.risk >= 25 { return .orange }
        return .secondary
    }

    private var stateColour: Color {
        switch row.state {
        case "done": return .green
        case "failed", "missing": return .red
        case "stopped": return .orange
        case "running", "encode", "verify", "strip", "mux", "replace":
            return .accentColor
        default: return .secondary
        }
    }

    /// The stage words come from the script, where they are event names. A
    /// person reading a table wants to know what is happening to their film.
    private var stateLabel: String {
        switch row.state {
        case "done":     return row.finishedLine
        case "failed":   return "Failed. The original is untouched, see the Console"
        case "missing":  return "Not where the plan says it is"
        case "encode", "running": return "Encoding the video"
        case "strip":    return "Remuxing, no re-encode"
        case "mux":      return "Copying audio, subtitles and chapters"
        case "verify":   return "Checking the output before touching the original"
        case "replace":  return replaceLabel
        case "waiting":  return "Waiting"
        case "stopped":  return "Stopped before it finished. The original is untouched"
        default:         return row.state
        }
    }

    /// The last step says what it is about to do, which is the one moment the
    /// answer differs by setting: in place is the only one that touches the
    /// original file itself.
    private var replaceLabel: String {
        switch row.landed {
        case "kept":     return "Writing the new file"
        case "moved":    return "Moving the original to _replaced"
        case "replaced": return "Replacing the original"
        default:         return "Putting the finished file in place"
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                Toggle("", isOn: $row.include)
                    .labelsHidden()
                    .disabled(!enabled)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(row.name).lineLimit(1).truncationMode(.middle)
                    Text(row.folder)
                        .font(.caption2).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.head)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Picker("", selection: $row.action) {
                    Text("shrink").tag("shrink")
                    Text("strip").tag("strip")
                    Text("skip").tag("skip")
                }
                .labelsHidden()
                .frame(width: 90)
                .disabled(!enabled)

                // The plan's track columns are IDs, which say nothing about
                // what is in them. The button opens the file's real track list
                // so a Japanese track on a Japanese film can be put back.
                Button(action: onTracks) {
                    Text(trackSummary)
                        .lineLimit(1)
                        .foregroundColor(row.dropsAudioLang ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 66, alignment: .leading)
                .disabled(!enabled)
                .help(row.dropsAudioLang
                      ? "Every track in one audio language is being dropped. Click to review."
                      : "Choose which audio and subtitle tracks to keep")

                Text(row.savePct > 0 ? String(format: "%.1f%%", row.savePct) : "-")
                    .frame(width: 70, alignment: .leading)
                    .foregroundColor(row.savePct >= 30 ? .green : .primary)
                Text(ShrinkController.humanMB(row.sizeMB))
                    .frame(width: 84, alignment: .leading)
                Text(ShrinkController.humanMB(row.predMB))
                    .frame(width: 84, alignment: .leading)
                    .foregroundColor(.secondary)
                Text(row.psnr > 0 ? String(format: "%.1f", row.psnr) : "-")
                    .frame(width: 62, alignment: .leading)
                    .foregroundColor(row.psnr > 0 && row.psnr < 40 ? .orange : .primary)
                // Share of sampled frames both dark and low contrast. High is
                // not a verdict, it is a reason to watch the result.
                Text(row.risk >= 0 ? String(format: "%.0f%%", row.risk) : "-")
                    .frame(width: 56, alignment: .leading)
                    .foregroundColor(riskColour)
                    .help("Banding risk: how much of this film is both dark and low contrast. Blade Runner 2049 measured 44% and was visibly damaged; Princess Mononoke measured 25% and was clean.")
                Text(row.reason.isEmpty ? "-" : row.reason)
                    .frame(width: 190, alignment: .leading)
                    .lineLimit(1).truncationMode(.tail)
                    .foregroundColor(row.hi10p ? .accentColor : .secondary)
                    .help(row.hi10p
                          ? "10-bit H.264. No consumer hardware decoder takes this profile, so it transcodes on playback whatever its size. Worth converting at any saving, including none.\n\n" + row.reason
                          : row.reason)
            }
            .font(.system(size: 12))

            if !row.state.isEmpty && row.state != "not selected" {
                HStack(spacing: 8) {
                    if row.state == "done" {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2).foregroundColor(.green)
                    }
                    Text(stateLabel).font(.caption2).foregroundColor(stateColour)
                        .lineLimit(1).truncationMode(.middle)
                    if row.progress > 0 && row.progress < 1 {
                        ProgressView(value: row.progress).frame(width: 160)
                    }
                    Spacer()
                }
                .padding(.leading, 30)
            }
        }
        .padding(.vertical, 2)
        .opacity(row.include ? 1 : 0.45)
    }
}

// MARK: - Tracks

/// Which tracks survive, for one file.
///
/// The rules keep the first audio track and every whitelisted language, which
/// is right for an English film and wrong for a Japanese one released with the
/// English dub first. That case is not rare and it is not recoverable once the
/// original is gone, so it gets a window rather than a note in the console.
struct TrackSheet: View {
    @ObservedObject var row: PlanRow
    @EnvironmentObject var ctl: ShrinkController
    @EnvironmentObject var defaults: ShrinkDefaults
    @Environment(\.dismiss) private var dismiss

    @State private var tracks: [TrackInfo] = []
    @State private var audioKeep: Set<Int> = []
    @State private var subKeep: Set<Int> = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(row.name).font(.headline).lineLimit(1).truncationMode(.middle)
            Text("Ticked tracks are kept. Everything else is dropped, and that is not reversible once the original is gone.")
                .font(.caption).foregroundColor(.secondary)

            if row.dropsAudioLang {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text("Every audio track in \(row.droppedAudioLangs) is being dropped. If one of those is the language this film was made in, tick it.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(Color.orange.opacity(0.14))
            }

            if !loaded {
                HStack { Spacer(); ProgressView(); Spacer() }.frame(height: 120)
            } else if tracks.isEmpty {
                Text("Could not read the tracks. The file may have moved.")
                    .foregroundColor(.orange)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        section("Audio", type: "audio", keep: $audioKeep)
                        section("Subtitles", type: "subtitles", keep: $subKeep)
                    }
                }
                .frame(maxHeight: 380)
            }

            HStack {
                Button("All") {
                    audioKeep = Set(ids("audio")); subKeep = Set(ids("subtitles"))
                }
                Button("What the rules chose") { resetToRules() }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Keep these") {
                    row.audio = TrackSelection.column(audioKeep)
                    row.subs = TrackSelection.column(subKeep)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 720)
        .onAppear(perform: load)
    }

    private func ids(_ type: String) -> [Int] {
        tracks.filter { $0.type == type }.map { $0.id }
    }

    private func load() {
        guard !loaded else { return }
        let found = ctl.tracks(for: row, settings: defaults.settings)
        tracks = found
        audioKeep = TrackSelection.ids(from: row.audio, all: found.filter { $0.type == "audio" })
        subKeep = TrackSelection.ids(from: row.subs, all: found.filter { $0.type == "subtitles" })
        loaded = true
    }

    private func resetToRules() {
        audioKeep = Set(tracks.filter { $0.type == "audio" && $0.keptByRules }.map { $0.id })
        subKeep = Set(tracks.filter { $0.type == "subtitles" && $0.keptByRules }.map { $0.id })
    }

    @ViewBuilder
    private func section(_ title: String, type: String, keep: Binding<Set<Int>>) -> some View {
        let list = tracks.filter { $0.type == type }
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline).bold()
                ForEach(list) { t in
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(
                            get: { keep.wrappedValue.contains(t.id) },
                            set: { on in
                                if on { keep.wrappedValue.insert(t.id) }
                                else { keep.wrappedValue.remove(t.id) }
                            }))
                            .labelsHidden()
                        Text(t.label).font(.system(size: 12))
                        Spacer()
                        if t.bytes > 0 {
                            Text(ShrinkController.humanMB(t.bytes / 1_048_576))
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Text(t.keptByRules ? "rules: \(t.why)" : "rules: drop")
                            .font(.caption)
                            .foregroundColor(t.keptByRules ? .secondary : .orange)
                            .frame(width: 120, alignment: .trailing)
                    }
                }
            }
        }
    }
}

// MARK: - Status bar

struct ShrinkStatusBar: View {
    @EnvironmentObject var ctl: ShrinkController

    var body: some View {
        HStack(spacing: 16) {
            if ctl.running {
                // The index counts files that have finished, so the one being
                // worked on is index + 1. Reporting "0 of 8" while the first
                // file encodes is arithmetically true and reads as stuck.
                Text("\(min(ctl.sweepIndex + 1, max(1, ctl.sweepTotal))) of \(ctl.sweepTotal)")
                Text(ctl.currentFile).lineLimit(1).truncationMode(.middle)
                if ctl.currentPct > 0 {
                    ProgressView(value: ctl.currentPct / 100).frame(width: 140)
                    Text(String(format: "%.0f%%", ctl.currentPct))
                }
                if !ctl.speed.isEmpty { Text(ctl.speed).foregroundColor(.secondary) }
                Text("ETA " + ShrinkController.clock(ctl.eta)).foregroundColor(.secondary)
                    .help("This file")
                Text("Batch " + (ctl.batchETA > 0
                                 ? ShrinkController.clock(ctl.batchETA) : "--:--:--"))
                    .foregroundColor(.secondary)
                    .help("The whole queue, from how long this run has taken so far per gigabyte. A strip row is a remux and finishes in a minute where a shrink row of the same size takes twenty, so a mixed queue drifts.")
            } else if ctl.scanning {
                Text("Planning. Nothing on disk is being changed.")
            } else if !ctl.lastSummary.isEmpty {
                Text(ctl.lastSummary)
            } else if ctl.rows.isEmpty {
                Text("No plan").foregroundColor(.secondary)
            } else {
                Text("\(ctl.selectedCount) of \(ctl.rows.count) selected")
                Text("about " + ShrinkController.humanMB(ctl.selectedReclaimMB) + " to reclaim")
                    .foregroundColor(.green)
                if ctl.selectedCount > 1 {
                    Text("processed top to bottom in the order shown")
                        .foregroundColor(.secondary)
                        .help("Sort the table before starting and the work follows that order. Sorting by saving does the biggest wins first.")
                }
            }
            Spacer()
            // Never the warning text itself. mkvshrink explains its decisions
            // in paragraphs, and a third of a paragraph is not information.
            if ctl.noteCount > 0 {
                Button {
                    ctl.consoleVisible = true
                } label: {
                    Text("\(ctl.noteCount) note\(ctl.noteCount == 1 ? "" : "s") in the Console")
                        .foregroundColor(.orange)
                }
                .buttonStyle(.link)
            }
            if !ctl.message.isEmpty {
                Text(ctl.message).foregroundColor(.red)
                    .lineLimit(1).truncationMode(.tail)
                    .help(ctl.message)
            }
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }
}

// MARK: - Shared furniture
// Deliberately its own copy rather than shared with MVC2SBS. These are twenty
// lines each, and the alternative is refactoring a working app that cannot be
// compiled here to prove the refactor was safe.

struct ShrinkToolButton: View {
    let title: String
    let symbol: String
    var tint: Color = .accentColor
    var help: String = ""
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .light))
                    .frame(height: 26)
                Text(title).font(.system(size: 11))
            }
            .foregroundColor(enabled ? tint : Color.secondary.opacity(0.4))
            .frame(minWidth: 54)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}

/// The originals policy, stated in the window.
struct ShrinkPolicyBanner: View {
    let policy: ReplacePolicy
    let onSettings: () -> Void

    private var tint: Color {
        switch policy {
        case .keep: return .blue
        case .folder: return .orange
        case .insitu: return .red
        }
    }

    private var symbol: String {
        switch policy {
        case .keep: return "lock.shield"
        case .folder: return "arrow.right.doc.on.clipboard"
        case .insitu: return "exclamationmark.octagon.fill"
        }
    }

    private var headline: String {
        switch policy {
        case .keep: return "KEEPING ORIGINALS"
        case .folder: return "ORIGINALS MOVE TO _replaced"
        case .insitu: return "ORIGINALS ARE REPLACED IN PLACE"
        }
    }

    /// Says where the files go, not just what happens to them. Both of these
    /// are questions with an exact answer, and both were being answered by
    /// going and looking in the folder afterwards.
    private var detail: String {
        switch policy {
        case .keep:
            return "The new file is written beside the original as NAME.shrunk.mkv. Nothing is reclaimed until you delete the originals yourself."
        case .folder:
            return "The new file takes the original's name, and the original moves to a _replaced folder beside it, once every check passes."
        case .insitu:
            return "The original is replaced by rename and there is nothing to undo. Recorded as untested on real media."
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundColor(tint)
            Text(headline).font(.system(size: 13, weight: .bold)).foregroundColor(tint)
            Text(detail).font(.caption).foregroundColor(.secondary)
                .lineLimit(1).truncationMode(.tail)
                .help(detail)
            Spacer()
            Button("Change in Settings", action: onSettings)
                .buttonStyle(.link)
                .font(.caption)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.15))
    }
}

struct ShrinkWarningStrip: View {
    let text: String
    let onRecheck: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Re-check", action: onRecheck)
        }
        .padding(10)
        .background(Color.orange.opacity(0.14))
    }
}

struct ShrinkConsoleSheet: View {
    @EnvironmentObject var ctl: ShrinkController
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Console").font(.headline)
                Spacer()
                Button("Save...") { save() }
                    .disabled(ctl.log.isEmpty)
                Button("Clear") { confirmClear = true }
                    .disabled(ctl.log.isEmpty)
                Button("Log folder") {
                    try? FileManager.default.createDirectory(
                        atPath: ShrinkController.logDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(URL(fileURLWithPath: ShrinkController.logDir))
                }
                Button("Close") { ctl.consoleVisible = false }
            }
            ShrinkLogView(text: ctl.log)
                .background(Color.black.opacity(0.25))
            Text("Every run also writes its own log to " + ShrinkController.logDir)
                .font(.caption).foregroundColor(.secondary)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(width: 900, height: 560)
        .confirmationDialog("Clear the console?", isPresented: $confirmClear,
                            titleVisibility: .visible) {
            Button("Clear", role: .destructive) { ctl.clearLog() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only empties the window. The log file for each run is kept on disk.")
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "mkvshrink.log"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? ctl.log.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Same reasoning as the console in MVC2SBS: SwiftUI's Text lays out the whole
/// string in one pass and builds selection geometry for every glyph of it, so a
/// sweep's worth of log freezes the window.
struct ShrinkLogView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = false
        tv.drawsBackground = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.textContainerInset = NSSize(width: 6, height: 6)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string == text { return }
        let atBottom = scroll.contentView.bounds.maxY >= (tv.frame.height - 40)
        tv.string = text
        if atBottom { tv.scrollToEndOfDocument(nil) }
    }
}
