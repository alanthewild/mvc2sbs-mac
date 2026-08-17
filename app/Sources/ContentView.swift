// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Alan Wild
import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var queue: QueueController
    @EnvironmentObject var defaults: DefaultsStore
    @State private var showSettings = false

    var body: some View {
        // Both halves of this window are flexible, so left to itself SwiftUI
        // split the space by how much content each happened to hold: the track
        // panel took half the window with nothing loaded and a third with a
        // file selected. Measure the window instead, so the split is the same
        // whatever is on screen.
        GeometryReader { win in
            VStack(spacing: 0) {
                ToolbarBar(showSettings: $showSettings)
                Divider()
                if !queue.toolWarning.isEmpty {
                    WarningStrip(text: queue.toolWarning,
                                 advisory: queue.toolWarningIsAdvisory,
                                 onRecheck: { queue.refreshToolWarning() })
                }
                // The drop zone needs enough room to be an obvious target and
                // no more. The settings panel is where the work happens, so it
                // gets the other two thirds.
                HStack(spacing: 0) {
                    DropZone()
                        .frame(width: max(300, win.size.width / 3))
                    Divider()
                    RightPanel()
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
                Divider()
                BottomPanel()
                    .frame(height: max(220, win.size.height * 0.28))
                    .sheet(isPresented: $queue.consoleVisible) { ConsoleSheet() }
                Divider()
                StatusBar()
            }
        }
        .frame(minWidth: 1140, minHeight: 860)
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            queue.refreshToolWarning()
        }
    }
}

/// A draggable divider. The visible line stays one pixel; the part you can
/// grab is ten, because a one pixel target is a test of aim rather than a
/// control. Double click puts it back to a third.
struct SplitHandle: View {
    let onDrag: (CGFloat) -> Void
    let onEnd: () -> Void
    let onReset: () -> Void

    @State private var hovering = false

    var body: some View {
        ZStack {
            // A plain Divider is a hairline at the system separator colour,
            // which on a dark background against an empty panel is invisible.
            // An explicit rule plus a grip says both "the column ends here"
            // and "you can drag this".
            Rectangle()
                .fill(Color.primary.opacity(0.22))
                .frame(width: 1)
            Capsule()
                .fill(Color.primary.opacity(hovering ? 0.8 : 0.4))
                .frame(width: 4, height: 30)
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
        }
        .frame(width: 11)
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { onDrag($0.translation.width) }
                .onEnded { _ in onEnd() }
        )
        .simultaneousGesture(TapGesture(count: 2).onEnded { onReset() })
        .help("Drag to resize. Double click to reset")
    }
}

// MARK: - Toolbar

struct ToolbarBar: View {
    @EnvironmentObject var queue: QueueController
    @EnvironmentObject var defaults: DefaultsStore
    @Binding var showSettings: Bool
    @State private var showHelp = false

    var body: some View {
        HStack(spacing: 20) {
            ToolButton(title: "Open", symbol: "doc", tint: .secondary, help: "Add MakeMKV 3D MKV files to the queue") { openFiles() }
            ToolButton(title: "Remove", symbol: "eject", tint: .purple, help: "Take the selected file out of the queue",
                       enabled: queue.selectedJob != nil && !queue.isRunning) {
                if let job = queue.selectedJob { queue.remove(job) }
            }
            ToolButton(title: "Start", symbol: "play", tint: .green, help: "Convert the selected file",
                       enabled: queue.selectedJob != nil && !queue.isRunning) {
                if let job = queue.selectedJob { queue.start(job) }
            }
            ToolButton(title: "Start All", symbol: "forward", tint: .green, help: "Work through the whole queue one at a time",
                       enabled: !queue.isRunning && !queue.jobs.isEmpty) {
                queue.start(all: true)
            }
            ToolButton(title: "Stop", symbol: "stop", tint: .red, help: "Stop the running conversion and delete its scratch file",
                       enabled: queue.isRunning) { queue.stop() }
            ToolButton(title: "Preview", symbol: "eye", tint: .orange, help: "Decode one frame, measure the left/right difference and open it. Proves the 3D actually decoded before you commit hours",
                       enabled: queue.selectedJob != nil && !queue.isRunning) {
                if let job = queue.selectedJob { queue.start(job, mode: .preview) }
            }
            ToolButton(title: "Test 60s", symbol: "timer", tint: .orange, help: "Encode the first minute only. Checks quality, size and speed cheaply",
                       enabled: queue.selectedJob != nil && !queue.isRunning) {
                if let job = queue.selectedJob { queue.start(job, mode: .smokeTest) }
            }

            Spacer()

            ToolButton(title: "Console", symbol: "terminal", tint: .teal, help: "Full log for the selected job") {
                queue.consoleVisible = true
            }
            ToolButton(title: "Advanced", symbol: "slider.horizontal.3", tint: .cyan,
                       help: "Banding controls, 3D subtitle depth, scratch folder and raw FFmpeg arguments") {
                queue.advancedVisible = true
            }
            ToolButton(title: "Tools", symbol: "gearshape", tint: .cyan, help: "Where the app looks for mvc2sbs, FFmpeg and FFprobe") {
                showSettings = true
            }
            ToolButton(title: "Help", symbol: "questionmark.circle", tint: .secondary,
                       help: "What each control does, and what this app is actually doing") {
                showHelp = true
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .sheet(isPresented: $showHelp) { HelpSheet() }
    }

    private func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "mkv") ?? .movie]
        if panel.runModal() == .OK {
            queue.add(urls: panel.urls, defaults: defaults.settings)
        }
    }
}

struct ToolButton: View {
    // Declaration order IS the memberwise initialiser order, and every call
    // site passes help before enabled, so keep them in that order here.
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

/// One page of the help. The title is the identity: it is what the index shows
/// and what selection is keyed on, so two pages may not share one.
struct HelpSection: Identifiable, Hashable {
    let title: String
    let rows: [HelpRow]
    var id: String { title }

    static func == (a: HelpSection, b: HelpSection) -> Bool { a.title == b.title }
    func hash(into h: inout Hasher) { h.combine(title) }
}

struct HelpRow: Identifiable, Hashable {
    let heading: String
    let body: String
    var id: String { heading }
}

/// Written as a plain list so the index and the page are the same data. The
/// help used to be one long scroll, which meant finding anything was a matter
/// of remembering roughly how far down it lived.
let helpSections: [HelpSection] = [
    HelpSection(title: "What MVC2SBS is", rows: [
        HelpRow(heading: "The problem it solves", body: "A 3D Blu-ray stores two camera views inside one H.264 stream using MVC, an extension almost nothing on a Mac can decode. Ripping the disc with MakeMKV gives you a file that plays flat, in one eye, on everything you own. Converting it to Full side-by-side gives you a file any 3D player understands."),
        HelpRow(heading: "What it replaces", body: "The BD3D2MK3D step of that workflow, which is Windows only. Same job, native on macOS, no virtual machine."),
        HelpRow(heading: "The pipeline", body: "Extract the MVC elementary stream, decode both views with edge264, lay them out side by side, rebuild the subtitles to match, re-encode the video, and mux the result with MKVToolNix. Roughly 25 to 50 minutes for a feature on Apple silicon."),
        HelpRow(heading: "What is not re-encoded", body: "Audio is copied bit for bit. Subtitle bitmaps are copied too, only repositioned. Chapters are carried across. Only the video is re-encoded, and that is unavoidable: the two views have to become one frame."),
        HelpRow(heading: "What it is not", body: "Not a lossless copy, and not a player. It produces a file; what you watch it on is up to you."),
    ]),
    HelpSection(title: "What is in the box", rows: [
        HelpRow(heading: "mvc2sbs", body: "The converter. A shell script that drives ffmpeg, edge264 and MKVToolNix, checks its own output when it finishes, and writes a log of every run. Everything the app does, it does by running this. It works on its own from a terminal, and the app shows you the exact command it used.\n$ mvc2sbs --help"),
        HelpRow(heading: "mkvdiff", body: "The diagnostic tool, and the reason most of the faults in this project were found rather than guessed at. Point it at a file that plays and a file that does not and it marks every field they disagree on. It also has modes for eye order, subtitles, brightness, bitrate, keyframes, quality comparison, and rebuilding a broken container without re-encoding.\n$ mkvdiff --help"),
        HelpRow(heading: "pgs3d.py", body: "The subtitle rebuilder. Blu-ray subtitles are bitmaps authored for a 1920 wide frame, so on a 3840 wide side-by-side frame they land in the left eye only. This splices a second copy into the same bitmap at the right offset, at the level of the compression runs, so no pixel is decoded or re-encoded. It can also shift subtitle depth, and recolour or dim them."),
        HelpRow(heading: "subs3d", body: "Adds subtitles to a side-by-side film that has none. A player draws an ordinary subtitle once across the whole frame, so on an SBS file each eye gets half the sentence. This takes an SRT or an existing ASS and writes both a PGS bitmap track and a text ASS track, each line placed twice, once per eye, with a depth control. --mux puts them in the file with mkvmerge and nothing is re-encoded.\n$ subs3d dialogue.srt --depth 20 --mux movie.mkv"),
        HelpRow(heading: "Why two subtitle formats", body: "No single one plays everywhere, so the file carries both and the player picks. PGS is bitmaps, the Blu-ray format: the typeface is baked in, it needs no font on the player, and it direct plays on a Shield. That is how a disc gives you a custom typeface for something like the Na'\u{2019}vi dialogue in Avatar. ASS is text: small, restylable, correct in VLC, mpv, Kodi and Infuse, but ExoPlayer's support is partial so Jellyfin may ignore the positioning. Use --format pgs or --format ass to write just one."),
        HelpRow(heading: "edge264", body: "The MVC decoder, built from source by the install script. It is the piece that makes any of this possible on a Mac, and it is not mine. See Credits."),
        HelpRow(heading: "Where they live", body: "The app ships all of these inside its bundle, so it needs nothing installed to run. install-mac3d.sh also puts the scripts in ~/.local/bin so you can use them from a terminal on files the app never touched."),
    ]),
    HelpSection(title: "What the app adds", rows: [
        HelpRow(heading: "A queue", body: "Drop files in, set the options once, start it. Jobs run one at a time, because two at once only makes both slower."),
        HelpRow(heading: "Sensible defaults", body: "Full SBS, VideoToolbox, 10-bit, quality 62, 3D subtitles on. Every one of those was measured rather than assumed, and Reset to Defaults puts them back."),
        HelpRow(heading: "Progress that means something", body: "Frames done, real speed, and time remaining computed from the clock rather than from the encoder's estimate."),
        HelpRow(heading: "Checks when it finishes", body: "Length against the source, whether the file decodes from its first frame, whether the seek index is present, whether chapters run past the end, whether the subtitles kept their timing, and which eye is which. If the depth reads inverted it offers to flip the flag, which takes a second and no re-encoding."),
        HelpRow(heading: "The console", body: "The full log of the run, selectable and saveable, plus a button to the log folder. Nothing is hidden from you: it is the same output the script would print in a terminal."),
    ]),
    HelpSection(title: "Toolbar", rows: [
        HelpRow(heading: "Preview", body: "Decodes a single frame, writes it as a PNG, and measures the difference between the two halves. Identical halves mean the second view did not decode. Worth running before any long encode."),
        HelpRow(heading: "Test 60s", body: "Encodes the first minute. Tells you the real speed, the size per minute, and whether audio and subtitles land correctly, in about two minutes."),
        HelpRow(heading: "Start All", body: "Runs the queue one job at a time. Running two at once just makes both slower."),
        HelpRow(heading: "Stop", body: "Sends a stop signal, waits for the encoder to finish writing, then removes the scratch file. A stopped job leaves no usable output."),
    ]),
    HelpSection(title: "Which encoder", rows: [
        HelpRow(heading: "Measured, not assumed", body: "One minute of a demanding scene at 3840x1080, each compared against a common near-lossless reference. x265 CRF 20 slow: 178 MB, 46.16 dB, 6m47. VideoToolbox quality 62: 192 MB, 46.45 dB, 15 seconds. VideoToolbox quality 65: 235 MB, 46.88 dB. x264 CRF 16 for the same footage is roughly four times the size of the x265 file."),
        HelpRow(heading: "VideoToolbox", body: "Runs on the Apple media engine, so a feature takes around 25 minutes rather than most of a day. Quality 62 is the match for x265 CRF 20. It is not a CRF scale and higher is better, which is the opposite of CRF."),
        HelpRow(heading: "x265", body: "Smaller at the low end of the quality range, and its psychovisual tuning spends bits on detail that looks right rather than detail that scores well, which PSNR cannot see. If you can tell the two apart on your own display, this is why."),
        HelpRow(heading: "x264", body: "Widest compatibility and by far the largest files. Worth it only if something in your chain will not take HEVC."),
    ]),
    HelpSection(title: "Quality", rows: [
        HelpRow(heading: "None of these is a copy", body: "Every setting here re-encodes the video. CRF 16 is very close to invisible, but it is not the source. Only CRF 0 is lossless, and that produces hundreds of GB for a feature."),
        HelpRow(heading: "CRF 20 is enough with HEVC", body: "Measured on the busiest minute of a film: CRF 18 and CRF 20 sat 46.5 dB apart, which is below what a display can show, and CRF 18 cost 2.8 GB more per feature. The old advice here was CRF 16, which came from x264 and is wasteful with x265."),
        HelpRow(heading: "CRF", body: "Lower means better quality and a bigger file. 16 to 18 is the archival range. Each step of 1 changes the file size by roughly 11%."),
        HelpRow(heading: "Preset", body: "How hard the encoder works. A slower preset gives a smaller file at the same quality, not a better looking one."),
    ]),
    HelpSection(title: "Format", rows: [
        HelpRow(heading: "Full SBS", body: "3840x1080. Both eyes at their original 1920x1080, nothing resampled. This is what BD3D2MK3D produces and what most 3D players expect."),
        HelpRow(heading: "Half layouts", body: "Squeeze each eye to half resolution so the frame stays 1080p. Smaller and more compatible, but it throws away half the horizontal detail and rules out 3D subtitles."),
    ]),
    HelpSection(title: "Advanced Video Settings", rows: [
        HelpRow(heading: "Dark gradient tuning", body: "Blu-ray masters hide banding with fine dither, and banding appears when an encoder quantises it away. Measured on a dithered dark ramp, this is worth 5 to 8 points of dither retention at 8-bit and essentially nothing at 10-bit, where it costs 20 to 40% more bits for no measurable gain. Leave it on at 8-bit, turn it off at 10-bit."),
        HelpRow(heading: "10-bit", body: "The strongest defence against added banding, and it costs nothing in size. Both measured on a 2017 Shield: HEVC Main 10 at 3840x1080 direct plays, from x265 and from VideoToolbox. H.264 High 10 does not, and Jellyfin reports \"the video codec's profile is not supported\" and transcodes it, which also mangles the aspect ratio. So pair 10-bit with x265 or VideoToolbox, never x264. Build a 60 second clip and try it on your own player before committing hours."),
        HelpRow(heading: "3D subtitles", body: "PGS subtitles are authored for a 1920 wide frame, so copied unchanged they sit in the left eye only. This duplicates each one into both eyes. The bitmaps are untouched."),
        HelpRow(heading: "Subtitle depth", body: "Disparity between the two copies. 0 places them at screen depth. Positive brings them towards you, which helps when objects pop out in front of the screen."),
        HelpRow(heading: "Scratch folder", body: "The decoded stream is written to disk first, roughly the size of the source video, so 25 to 45 GB. Keep it on local storage, never on a network volume."),
    ]),
    HelpSection(title: "Checking a finished file", rows: [
        HelpRow(heading: "Everything at once", body: "Prints the fields a hardware player actually cares about: codec, profile, level, colour tags, aspect, StereoMode, display dimensions, chapters, cues, and which build of this tool made it. Given two files it marks every field that differs, which is usually where the fault is.\n$ mkvdiff FILE\nmkvdiff GOOD.mkv SUSPECT.mkv"),
        HelpRow(heading: "Checked automatically", body: "Every full side-by-side encode is checked for eye order when it finishes, which takes about two seconds. If it reads inverted the app offers to flip the flag. It reports rather than corrects: the estimate is a heuristic about how a scene was composed, and silently inverting a film that was right is worse than leaving one that is wrong, because you would have no reason to look."),
        HelpRow(heading: "Depth feels wrong", body: "Measures horizontal disparity between the two halves and reads the StereoMode flag. Films keep most of the frame behind the screen plane, so a correct pair measures negative. The fix changes how a player reads the halves rather than touching a pixel, and a Shield honours it. Rebuilding the frame with Swap left and right is only for players that ignore the flag.\n$ mkvdiff --eyes FILE\nmkvpropedit FILE --edit track:v1 --set stereo-mode=11"),
        HelpRow(heading: "Sound but no picture", body: "Decodes the head of the file and reports where the first video packet, first audio packet and first keyframe actually are. A large gap between the audio and video start means the picture is not missing, it simply has not begun.\n$ mkvdiff --start FILE"),
        HelpRow(heading: "Made by an older version", body: "Rebuilds the container with MKVToolNix, strips the chapter end times FFmpeg writes, and restores StereoMode and display dimensions. Nothing is re-encoded, so a three hour film takes minutes. Files needing it show writing_app as Lavf, or YES for chapters_ordered_hint.\n$ mkvdiff FILE | grep -E \"writing_app|ordered_hint\"\nmkvdiff --repair FILE"),
        HelpRow(heading: "A black opening", body: "Reports average picture brightness at ten timestamps. Run it against the source as well: if both are black at the same places, the film simply opens on black.\n$ mkvdiff --luma SOURCE.mkv OUTPUT.mkv"),
        HelpRow(heading: "Bitrate", body: "Samples across the film and reports the worst second. Useful for finding the most demanding scene to test with, though note that expensive means bitrate, which can be grain in the dark rather than motion.\n$ mkvdiff --peak FILE"),
        HelpRow(heading: "Keyframes", body: "Reports keyframe placement, picture types and frame sizes at the head of a file.\n$ mkvdiff --gop FILE"),
        HelpRow(heading: "Which build made it", body: "Every output since 3.5 carries its version and settings. mkvdiff FILE shows them as mvc2sbs.version and mvc2sbs.settings. Comparing two files of unknown provenance produces confident conclusions about the wrong variable."),
    ]),
    HelpSection(title: "Comparing settings properly", rows: [
        HelpRow(heading: "Cut one clip first", body: "Cut once, then encode that clip with each setting. Every encode then starts on the identical frame. Seeking snaps to a keyframe, so two runs can begin on different frames and still produce a confident-looking number.\n$ mkvmerge -o clip.mkv --split parts:00:26:30-00:27:30 SOURCE.mkv"),
        HelpRow(heading: "Pick the scene deliberately", body: "A film's opening is usually its cheapest minute, and settings that look identical there can diverge badly elsewhere. mkvdiff --peak finds the expensive parts."),
        HelpRow(heading: "Measuring the difference", body: "Reports PSNR and SSIM between two encodes. Above 45 dB a visible difference is very unlikely, so judge on size and time instead.\n$ mkvdiff --quality A.mkv B.mkv"),
        HelpRow(heading: "It does not say which is better", body: "That comparison measures how far apart two files are. Neither of them is the source. To rank encoders, encode a near-lossless reference with CRF 12 and compare each candidate against that, then the numbers are comparable and higher genuinely means closer.\n$ mvc2sbs --x265 --10bit -q 12 -p fast -o ref.mkv clip.mkv\nmkvdiff --quality ref.mkv candidate.mkv"),
        HelpRow(heading: "Test on the real player", body: "A browser player usually transcodes, which hides container faults entirely. Only Direct Play tells you whether a file is good. If a player reports transcoding, the reason it gives is worth reading: \"the video codec's profile is not supported\" is how a Shield refuses H.264 High 10."),
    ]),
    HelpSection(title: "Logs", rows: [
        HelpRow(heading: "Where they go", body: "Every run writes its own log to ~/Library/Logs/mvc2sbs, named for the source and the time it started. Colour codes and the progress redraws are stripped, so it is plain text. The Console window has a button that opens the folder."),
        HelpRow(heading: "Not beside the film", body: "The log deliberately does not go in the output folder. A media library gets scanned, and a stray .log in it is clutter. Use --log FILE if you want one somewhere specific, or --no-log for none."),
        HelpRow(heading: "What to keep", body: "The interesting line is almost never the last one. If a file turns out wrong days later, the log for that run says which build made it, which settings were used, and what every tool in the chain complained about at the time."),
    ]),
    HelpSection(title: "If a finished file will not play", rows: [
        HelpRow(heading: "mkvmerge could not write the final file", body: "The encode is not lost and nothing needs re-encoding. FFmpeg's mux is kept, which plays in VLC but may be refused by a Shield, and it carries no chapters because FFmpeg is never allowed to write them. The console has what mkvmerge said. Free some space, then rebuild the container in minutes, taking the chapters from the original rip.\n$ mkvdiff --repair \"OUTPUT.mkv\" --chapters-from \"SOURCE.mkv\""),
        HelpRow(heading: "Each eye looks tall and narrow in VLC", body: "Nothing is wrong. A Full-SBS file declares display dimensions of 3840x2160, and VLC has no idea it is 3D, so it renders the whole 3840x1080 frame into a 16:9 box and each eye is squeezed to half width. A 3D-aware player reads StereoMode 1, takes each 1920x1080 half and stretches it back to 16:9. Force the aspect to see it undistorted, or just play it on the device you actually watch on.\n$ /Applications/VLC.app/Contents/MacOS/VLC --aspect-ratio=32:9 FILE"),
        HelpRow(heading: "Not enough disk", body: "The remux writes a second complete copy of the film before the first can be deleted, so the destination needs the size of the output free on top of the staging file. The elementary stream is deleted the moment the encode ends to keep the peak down, but a 30 GB output still needs 30 GB free at the remux."),
        HelpRow(heading: "Subtitles only in the left eye on a Shield", body: "Fixed in 3.52; files made before that need a re-encode. PGS lets a display set place several composition objects, so the obvious way to build a 3D subtitle track is to place the same bitmap twice. FFmpeg draws them all, which is why VLC looks correct. ExoPlayer, which is what Jellyfin's Android TV client uses, reads composition object 0 and drops the rest, so the right eye is empty and what you see there is crosstalk. The two copies are now spliced into a single bitmap. Check any file without watching it:\n$ mkvdiff --subs FILE"),
        HelpRow(heading: "Subtitles appear too early", body: "Fixed in 3.50, and checked automatically at the end of every encode. FFmpeg rebased each subtitle file so its own first timestamp became zero, so a film whose first subtitle is 44 seconds in ran its whole subtitle track 44 seconds early. Nothing about the file looked wrong. If the check reports drift, re-run."),
        HelpRow(heading: "Black screen, or no picture until you seek forward", body: "This was a fault in mvc2sbs and is fixed. FFmpeg wrote a chapter end time that Matroska only defines for ordered editions, and players that read it that way built a broken timeline. VLC showed no video window for 47 seconds, Kodi needed a manual skip, and Jellyfin refused the file outright. Chapters are now written by MKVToolNix instead. Files made before this was fixed can be corrected without re-encoding: mkvpropedit \"your file.mkv\" --chapters ''"),
        HelpRow(heading: "It plays in a browser but not on a set-top box", body: "A browser player usually transcodes, so it hides the fault. Only Direct Play tells you whether the file is good."),
        HelpRow(heading: "Muxer", body: "The finished file is written by MKVToolNix rather than FFmpeg. Both produce valid Matroska with identical streams, but Jellyfin on a Shield refuses FFmpeg's and plays MKVToolNix's. This adds a rewrite at the end of every encode, minutes against hours, and needs mkvtoolnix installed."),
        HelpRow(heading: "Wrong aspect ratio", body: "The 3D flag needs mkvtoolnix installed. Without mkvpropedit the output carries no StereoMode and no per-eye display size, so players stretch it to double width."),
    ]),
    HelpSection(title: "Credits", rows: [
        HelpRow(heading: "subs3d", body: "Adds subtitles to a side-by-side film that has none. A player draws an ordinary subtitle once across the whole frame, so on an SBS file each eye gets half the sentence. This takes an SRT or an existing ASS and writes both a PGS bitmap track and a text ASS track, each line placed twice, once per eye, with a depth control. --mux puts them in the file with mkvmerge and nothing is re-encoded.\n$ subs3d dialogue.srt --depth 20 --mux movie.mkv"),
        HelpRow(heading: "Why two subtitle formats", body: "No single one plays everywhere, so the file carries both and the player picks. PGS is bitmaps, the Blu-ray format: the typeface is baked in, it needs no font on the player, and it direct plays on a Shield. That is how a disc gives you a custom typeface for something like the Na'\u{2019}vi dialogue in Avatar. ASS is text: small, restylable, correct in VLC, mpv, Kodi and Infuse, but ExoPlayer's support is partial so Jellyfin may ignore the positioning. Use --format pgs or --format ass to write just one."),
        HelpRow(heading: "edge264", body: "The MVC decoder, and the reason this can exist at all. By Thibault Raffaillac and Celticom/TVLabs, MVC fork by Chris Busillo and Jens Duttke. BSD licensed. [Source](https://github.com/cbusillo/edge264-mvc)"),
        HelpRow(heading: "BD_to_AVP", body: "Chris Busillo's macOS 3D Blu-ray converter for Apple Vision Pro. Its use of edge264 showed this approach was viable. [Source](https://github.com/cbusillo/BD_to_AVP)"),
        HelpRow(heading: "BD3D2MK3D", body: "The Windows tool this replaces, by r0lZ. No code taken from it, but it defined what the output should look like. [Details](https://www.videohelp.com/software/BD3D2MK3D)"),
        HelpRow(heading: "FFmpeg, x264, MKVToolNix", body: "Demuxing, encoding and muxing. Invoked as separate processes, not linked."),
        HelpRow(heading: "Licence", body: "MVC2SBS is MIT licensed. See THIRD-PARTY-NOTICES.md in the repository for the full third party notices. [Project](https://github.com/alanthewild/mvc2sbs-mac)"),
    ]),
    HelpSection(title: "Requirements", rows: [
        HelpRow(heading: "Bundled", body: "mvc2sbs, pgs3d.py and the MVC decoder ship inside the app."),
        HelpRow(heading: "subs3d needs less", body: "Writing a 3D subtitle file needs nothing but python3. ffprobe and mkvmerge are only used by --mux, which puts the result into the movie. The font named in the file has to exist on whatever plays the film, not on this Mac."),
        HelpRow(heading: "External", body: "FFmpeg is required and is not bundled. mkvtoolnix is optional and only supplies the 3D flag on the output. Install both with: brew install ffmpeg mkvtoolnix"),
        HelpRow(heading: "MakeMKV", body: "When ripping, the video track labelled Mpeg4 MVC must be ticked. It is off by default, and without it there is no second view to extract."),
    ]),
]

struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String? = helpSections.first?.title

    private var current: HelpSection? {
        helpSections.first { $0.title == selection } ?? helpSections.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MVC2SBS").font(.title3)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 12)

            HStack(spacing: 0) {
                List(helpSections, selection: $selection) { s in
                    Text(s.title)
                        .font(.callout)
                        .padding(.vertical, 2)
                }
                .listStyle(.sidebar)
                .frame(width: 220)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let page = current {
                            Text(page.title).font(.title3).bold()
                                .padding(.bottom, 2)
                            ForEach(page.rows) { row in
                                rowView(row)
                            }
                        }
                    }
                    // Without a width constraint the content takes its ideal
                    // width, which for long paragraphs is wider than the
                    // window. The text then never wraps, the pane scrolls
                    // sideways instead of down, and the right edge is cut off.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .textSelection(.enabled)
        .frame(minWidth: 780, idealWidth: 940, maxWidth: 1200,
               minHeight: 440, idealHeight: 700, maxHeight: .infinity)
    }

    @ViewBuilder private func rowView(_ row: HelpRow) -> some View {
        let parts = splitCommand(row.body)
        VStack(alignment: .leading, spacing: 4) {
            Text(row.heading).font(.callout).bold()
            Text(.init(parts.0)).font(.callout).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let cmd = parts.1 {
                HStack(alignment: .top, spacing: 8) {
                    Text(cmd)
                        .font(.system(.caption, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cmd, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help("Copy this command")
                }
                .padding(8)
                .background(Color.secondary.opacity(0.10))
                .cornerRadius(5)
            }
        }
        .padding(.bottom, 4)
    }

    /// A row's text may end with "$ " on its own line. Everything after that is
    /// treated as a command: rendered monospaced, selectable, with a copy
    /// button. Commands buried mid-sentence cannot be picked out cleanly, which
    /// rather defeats the point of documenting them.
    private func splitCommand(_ body: String) -> (String, String?) {
        guard let r = body.range(of: "\n$ ") else { return (body, nil) }
        let prose = String(body[body.startIndex..<r.lowerBound])
        let command = String(body[r.upperBound...])
        return (prose, command)
    }
}


struct WarningStrip: View {
    let text: String
    var advisory: Bool = false
    var onRecheck: (() -> Void)? = nil

    private var tint: Color { advisory ? .blue : .yellow }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: advisory ? "info.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(tint)
            Text(text).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let onRecheck = onRecheck {
                Button("Check again", action: onRecheck)
                    .buttonStyle(.bordered)
                    .help("Look for the tools again without restarting")
            }
        }
        .padding(8)
        .background(tint.opacity(0.12))
    }
}

// MARK: - Drop zone

struct DropZone: View {
    @EnvironmentObject var queue: QueueController
    @EnvironmentObject var defaults: DefaultsStore
    @State private var targeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .foregroundColor(targeted ? .accentColor : Color.accentColor.opacity(0.55))
            content
        }
        .padding(18)
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            handleDrop(providers)
        }
    }

    @ViewBuilder private var content: some View {
        if let job = queue.selectedJob {
            VStack(spacing: 10) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 62, weight: .ultraLight))
                    .foregroundColor(.accentColor)
                Text(job.displayName).font(.headline)
                MvcBadge(job: job)
                Text(job.info.codecText).font(.caption).foregroundColor(.secondary)
                EyeCheckStrip(job: job, queue: queue)
            }
            .padding()
        } else {
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 52, weight: .ultraLight))
                    .foregroundColor(.accentColor.opacity(0.8))
                Text("Drop MakeMKV 3D MVC files here").font(.headline)
                Text("or use Open").font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    queue.add(urls: [url], defaults: defaults.settings)
                }
            }
        }
        return accepted
    }
}

struct MvcBadge: View {
    @ObservedObject var job: Job

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundColor(colour)
            Text(text).font(.callout).foregroundColor(.secondary)
        }
    }

    private var symbol: String {
        switch job.mvcConfirmed {
        case .some(true): return "checkmark.circle"
        case .some(false): return "exclamationmark.triangle"
        case .none: return "questionmark.circle"
        }
    }

    private var colour: Color {
        switch job.mvcConfirmed {
        case .some(true): return .green
        case .some(false): return .orange
        case .none: return .secondary
        }
    }

    private var text: String {
        switch job.mvcConfirmed {
        case .some(true):
            let extra = job.psnr.isEmpty ? "" : "  L/R PSNR \(job.psnr) dB"
            return "MVC confirmed \(job.decoderSize)\(extra)"
        case .some(false): return "No MVC found in this file"
        case .none: return "MakeMKV 3D AVC+MVC (unverified until you start)"
        }
    }
}

// MARK: - Right hand settings panel

struct RightPanel: View {
    @EnvironmentObject var queue: QueueController
    @EnvironmentObject var defaults: DefaultsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let job = queue.selectedJob {
                    JobSettingsView(job: job, queue: queue)
                } else {
                    if defaults.settings.predatesCurrentAdvice {
                        // Saved settings outlive upgrades, so a changed default
                        // never reaches anyone who has used the app before.
                        // Say so rather than silently overwriting their choices.
                        VStack(alignment: .leading, spacing: 6) {
                            Text("These settings were saved before the recommendations changed.")
                                .font(.callout).bold()
                            Text("The current recommendation is VideoToolbox at quality 62 with 10-bit, measured to match x265 CRF 20 at 27 times the speed. Your saved defaults are still whatever you last used.")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Button("Use recommended") { defaults.resetToRecommended() }
                                Button("Keep mine") { defaults.settings.schema = JobSettings.currentSchema }
                            }
                        }
                        .padding(10)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(6)
                    }
                    SettingsForm(settings: $defaults.settings, info: nil,
                                 defaultName: "")
                }
            }
            .padding(18)
        }
    }
}

/// The eye order verdict, shown under the file it belongs to.
///
/// It used to sit at the top of the settings panel, which pushed every control
/// down the moment a job finished and put the verdict a long way from the name
/// of the film it was about.
struct EyeCheckStrip: View {
    @ObservedObject var job: Job
    let queue: QueueController

    var body: some View {
        if job.eyeCheck.hasPrefix("inverted") {
            // Reported rather than corrected: the estimate is a heuristic about
            // how a scene was composed, and silently inverting a film that was
            // right is worse than leaving one that is wrong.
            VStack(alignment: .leading, spacing: 6) {
                Text("Depth reads inverted").font(.callout).bold()
                Text("Most of the frame measures as being in front of the screen, which is unusual in a film. It plays normally and nothing is wrong with the picture, but it may be uncomfortable to watch. This changes the flag players read, not the picture, so it takes a second and needs no re-encode.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Swap the eyes") { queue.swapEyes(on: job) }
                    Button("Leave it") { job.eyeCheck = "" }
                }
                Text("An estimate, not a certainty. Check it on your own display either way.")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color.orange.opacity(0.14))
            .cornerRadius(6)
        } else if job.eyeCheck == "fixed" {
            Text("StereoMode flipped. Worth confirming on your display.")
                .font(.caption).foregroundColor(.secondary)
        }
    }
}

struct JobSettingsView: View {
    @ObservedObject var job: Job
    let queue: QueueController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsForm(settings: $job.settings, info: job.info,
                         defaultName: queue.outputURL(for: job).lastPathComponent,
                         savingTo: queue.outputURL(for: job).path)
        }
        .disabled(job.state == .running || job.state == .stopping)
    }
}

struct SettingsForm: View {
    @EnvironmentObject var queue: QueueController
    @Binding var settings: JobSettings
    let info: SourceInfo?
    var defaultName: String = ""
    /// Where the output is going. Empty means nothing is selected, and the row
    /// says so rather than disappearing: a control that comes and goes is
    /// harder to find than one that is always in the same place.
    var savingTo: String = ""
    @State private var showDestination = false
    @State private var confirmReset = false

    /// The presets are re-encode targets, not copies. Saying so here heads off
    /// the obvious assumption that the top one preserves the source.
    private var crfNote: String {
        switch settings.crf {
        case 0: return "Lossless. Mathematically identical to the decoded frames, and enormous. Expect hundreds of GB for a feature."
        case 1...16: return "Re-encoded, not a copy of the source. At CRF 16 the difference is very hard to see, but it is not lossless."
        case 17...19: return "Re-encoded. Around 20% smaller than CRF 16, with slightly more grain smoothing and a little more banding risk in dark scenes."
        default: return "Re-encoded. Noticeably lossy on grain and dark gradients. Fine for casual viewing, not for archiving."
        }
    }
    /// Orange only for x264, where High 10 genuinely does not hardware decode.
    /// HEVC Main 10 is confirmed working, so warning about it was wrong.
    private var tenBitNote: String {
        if !settings.tenBit { return "8-bit output. Universal playback, and more banding in dark gradients." }
        switch settings.encoder {
        case .x265:
            return "HEVC Main 10. Confirmed playing at 3840x1080 on a 2017 Shield via Jellyfin."
        case .videotoolbox:
            return "HEVC Main 10 on the media engine. Confirmed playing at 3840x1080 on a 2017 Shield via Jellyfin. Costs nothing in size or time over 8-bit."
        case .x264:
            return "H.264 High 10. Measured on a 2017 Shield: refused, with Jellyfin reporting \"the video codec's profile is not supported\" and transcoding it. Switch the encoder to x265 or VideoToolbox, both of which direct play at 10-bit."
        }
    }

    private var vtNote: String {
        switch settings.vtQuality {
        case 0...50: return "Well below x265 CRF 20. Small files, visible loss on detailed motion."
        case 51...58: return "Below x265 CRF 20. Roughly half the size, measurably softer."
        case 59...66: return "The useful range. 62 matched x265 CRF 20 on a 3840x1080 clip, 8% larger and 27 times faster."
        default: return "Above the useful range. Quality 65 was already better than x265 CRF 20, and 80 was four times the size for no measurable gain."
        }
    }


    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Saving to").frame(width: 70, alignment: .leading)
                Text(savingTo.isEmpty ? "No file selected" : savingTo)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Destination\u{2026}") { showDestination = true }
                    .buttonStyle(.bordered)
                    .help("Output folder and file name")
            }
            GroupBox("Video") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Format").frame(width: 70, alignment: .leading)
                        Picker("", selection: $settings.layout) {
                            ForEach(Layout.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden()
                        .fixedSize()
                        .help("Full layouts keep every pixel of both eyes. Half layouts squeeze each eye to half resolution to keep the frame at 1080p")
                        Spacer()
                        // Out here rather than buried in a sheet: saved settings
                        // outlive upgrades, and a stale default is the kind of
                        // fault you only notice after an hour of encoding.
                        // Gated. It is next to a picker people change often,
                        // and silently throwing away a carefully set up job is
                        // not something a stray click should be able to do.
                        Button("Reset to Defaults") { confirmReset = true }
                            .buttonStyle(.bordered)
                            .help("Put every video setting back to the measured recommendation. Destination and file name are left alone")
                    }
                    Text(settings.layout.note).font(.caption).foregroundColor(.secondary)

                    HStack {
                        Text("Eyes").frame(width: 70, alignment: .leading)
                        Toggle("Swap left and right", isOn: $settings.swapEyes)
                            .help("Use this when depth reads inverted: near objects look far away and the picture feels wrong without being obviously broken")
                        Spacer()
                    }
                    Text(settings.swapEyes
                         ? "The frame is rebuilt with the right eye first, so this works even on a TV that ignores the 3D flag and just splits the picture."
                         : "Normal order, left eye first. If a finished film reads with inverted depth, check it with: mkvdiff --eyes yourfile.mkv")
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Encoder, depth and quality on one row. They are read
                    // together and changed together, and the panel is wide
                    // enough now that stacking them wasted the space.
                    HStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Text("Encoder")
                            Picker("", selection: $settings.encoder) {
                                ForEach(EncoderKind.allCases) { Text($0.title).tag($0) }
                            }.labelsHidden().frame(width: 165)
                            .help("x264 matches BD3D2MK3D and plays everywhere but is roughly four times the size. x265 is much smaller and slow to encode. VideoToolbox matches x265 quality on the media engine in a fraction of the time")
                        }

                        // Separated rather than merely spaced. Three unrelated
                        // controls on one row read as one control otherwise.
                        Divider().frame(height: 22).padding(.horizontal, 18)

                        Toggle("10-bit", isOn: $settings.tenBit)
                            .help("10-bit takes dither retention from about 52% to about 90% on a dark ramp, which is what stops banding, at no cost in size")

                        Divider().frame(height: 22).padding(.horizontal, 18)

                        HStack(spacing: 6) {
                            Text("Quality")
                            if settings.encoder == .videotoolbox {
                                // Not a CRF. VideoToolbox ignores CRF and
                                // preset entirely, so neither is shown.
                                Stepper(value: $settings.vtQuality, in: 1...100) {
                                    Text("\(settings.vtQuality)")
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 34, alignment: .trailing)
                                }
                                .help("VideoToolbox quality, 1 to 100. Not a CRF: higher is better here")
                            } else {
                                Stepper(value: $settings.crf, in: 0...51) {
                                    Text("CRF \(settings.crf)")
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 56, alignment: .trailing)
                                }
                                .help("Constant Rate Factor. Lower is better quality and a bigger file. 0 is lossless, 16 to 18 is the archival range")
                            }
                        }
                        Spacer()
                    }

                    Text(settings.encoder.note).font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(tenBitNote).font(.caption)
                        .foregroundColor(settings.tenBit && settings.encoder == .x264 ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if settings.encoder == .videotoolbox {
                        HStack {
                            Button("Match x265 CRF 20") { settings.vtQuality = 62 }
                                .buttonStyle(.bordered)
                                .help("Measured on a 3840x1080 clip: quality 62 matched x265 CRF 20 slow on PSNR and SSIM")
                            Spacer()
                        }
                        Text(vtNote).font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(spacing: 14) {
                            HStack(spacing: 6) {
                                Text("Preset")
                                Picker("", selection: $settings.preset) {
                                    ForEach(JobSettings.presets, id: \.self) { Text($0).tag($0) }
                                }.labelsHidden().frame(width: 130)
                                .help("How hard the encoder works for the same CRF. Slower presets give smaller files at the same quality, not better quality")
                            }
                            ForEach(QualityPreset.all) { preset in
                                Button(preset.name) { settings.crf = preset.crf }
                                    .buttonStyle(.bordered)
                                    .help(preset.detail)
                            }
                            Spacer()
                        }
                        Text(crfNote).font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(6)
            }

        }
        .confirmationDialog("Reset every video setting to the defaults?",
                            isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Yes", role: .destructive) {
                settings = JobSettings.recommended(from: settings)
            }
            Button("No", role: .cancel) {}
        } message: {
            Text("Full SBS, VideoToolbox, 10-bit, quality 62, 3D subtitles on, dark tuning off. Your destination folder and file name are left alone.")
        }
        .sheet(isPresented: $queue.advancedVisible) {
            AdvancedSheet(settings: $settings, info: info)
        }
        .sheet(isPresented: $showDestination) {
            DestinationSheet(settings: $settings, defaultName: defaultName)
        }
    }
}

struct DestinationSheet: View {
    @Binding var settings: JobSettings
    var defaultName: String = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Destination").font(.title3)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }

            FolderRow(label: "Folder", path: $settings.outputFolder,
                      placeholder: "Alongside the source file")
            Text("Only the finished file is written here. The elementary stream and the staging encode both live in the scratch folder, so a network destination sees one write rather than three.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Name").frame(width: 70, alignment: .leading)
                // Clicking in drops the automatic name in so it can be edited
                // rather than retyped from scratch.
                TextField("Automatic", text: $settings.outputName)
                    .focused($nameFocused)
                    .onChange(of: nameFocused) { focused in
                        if focused, settings.outputName.isEmpty, !defaultName.isEmpty {
                            settings.outputName = defaultName
                        }
                    }
                if !settings.outputName.isEmpty {
                    Button {
                        settings.outputName = ""
                        nameFocused = false
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Back to the automatic name")
                }
            }
            Text("Leave it empty for the automatic name, which strips .3D.MVC and similar from the source. Click the field to fill it in and edit from there.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .textSelection(.enabled)
        .frame(minWidth: 520, idealWidth: 620, maxWidth: 800)
    }
}

struct AdvancedSheet: View {
    @Binding var settings: JobSettings
    let info: SourceInfo?
    @Environment(\.dismiss) private var dismiss

    private var oneToOne: Bool { settings.layout == .fsbs || settings.layout == .ftab }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Advanced Video Settings").font(.title3)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
            GroupBox("Banding") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Dark gradient tuning", isOn: $settings.darkTuning)
                    Text("Keeps the fine dither the source uses to hide banding. Worth 5 to 8 points of dither retention at 8-bit. At 10-bit it is worth almost nothing and costs 20 to 40% more bits: measured on a dithered ramp, and confirmed on a minute of Gravity's opening where the two were indistinguishable on a plasma. Leave it on at 8-bit, turn it off at 10-bit.")
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                }
                .padding(8)
            }

            GroupBox("Subtitles") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Rebuild PGS subtitles for 3D", isOn: Binding(
                        get: { !settings.flatSubs },
                        set: { settings.flatSubs = !$0 }))
                        .disabled(!oneToOne)
                    Text(oneToOne
                         ? "Duplicates each subtitle into both eyes. The bitmaps are not touched, so nothing is re-encoded. Without this, subtitles render into the left eye only."
                         : "Only available on the 1:1 layouts. The half layouts would need the bitmaps rescaled.")
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if oneToOne && !settings.flatSubs {
                        HStack {
                            Text("Depth").frame(width: 60, alignment: .leading)
                            Stepper(value: $settings.subDepth, in: -60...60, step: 2) {
                                Text("\(settings.subDepth) px")
                            }
                            Spacer()
                        }
                        Text("Disparity between the two copies. 0 puts subtitles at screen depth. Positive brings them towards you, which helps when objects pop out in front of the screen.")
                            .font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()
                        HStack {
                            Text("Brightness").frame(width: 78, alignment: .leading)
                            Slider(value: $settings.subBrightness, in: 0.5...1.5, step: 0.05)
                            Text(String(format: "%.2f", settings.subBrightness))
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 40)
                        }
                        Text("Gamma on subtitle luminance. Below 1 brightens the anti-aliased edges, which is what looks pale after a player squeezes a 3840 wide subtitle plane onto a 1080p screen. Try 0.70. Palettes only, the bitmaps are never touched.")
                            .font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Text("Colour").frame(width: 78, alignment: .leading)
                            Picker("", selection: $settings.subColour) {
                                Text("As authored").tag("source")
                                Text("White").tag("white")
                                Text("Yellow").tag("yellow")
                                Text("Amber").tag("amber")
                                Text("Cyan").tag("cyan")
                                Text("Green").tag("green")
                            }.labelsHidden().frame(width: 160)
                            Spacer()
                        }
                        HStack {
                            Text("Opacity").frame(width: 78, alignment: .leading)
                            Slider(value: $settings.subOpacity, in: 0.3...1.0, step: 0.05)
                            Text(String(format: "%.2f", settings.subOpacity))
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 40)
                        }
                    }
                }
                .padding(8)
            }

            GroupBox("Compatibility") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Peak cap").frame(width: 78, alignment: .leading)
                        Stepper(value: $settings.maxRate, in: 0...200, step: 10) {
                            Text(settings.maxRate == 0 ? "None" : "\(settings.maxRate) Mbps")
                        }
                        Spacer()
                    }
                    Text("CRF sets quality and puts no ceiling on bitrate, so a demanding scene can peak several times the film's average. That is what stalls a player streaming over a network, or a set-top decoder running near its limit. 60 Mbps is a sensible cap at 3840x1080 and costs quality only in the scenes that were above it. Measure a finished file first with: mkvdiff --peak yourfile.mkv")
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()
                    Toggle("Drop chapters", isOn: $settings.dropChapters)
                    Text("Chapters are copied from the source by MKVToolNix rather than FFmpeg, because FFmpeg writes an end time that some players read as an ordered edition and then refuse or mis-time the file. That is fixed, so you should not need this. It stays as an escape hatch, and for excerpt runs, where chapters are dropped automatically.")
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
            }

            GroupBox("Files and decoding") {
                VStack(alignment: .leading, spacing: 8) {
                    FolderRow(label: "Scratch", path: $settings.tempFolder,
                              placeholder: "Automatic: local disk, never a network share")
                    Text("The elementary stream is roughly the size of the source video, so 25 to 45 GB. It goes beside the output, unless the output is on a network volume, in which case it falls back to local temporary storage. The decoder memory-maps this file and reads it continuously, so network storage is both slow and unreliable.")
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    Toggle("Single threaded decoding", isOn: $settings.singleThread)
                    Text("Slower, but tolerates discs that crash the multi-threaded decoder.")
                        .font(.caption).foregroundColor(.secondary)
                    HStack {
                        Text("Extra").frame(width: 60, alignment: .leading)
                        TextField("Raw FFmpeg arguments", text: $settings.extraArgs)
                    }
                }
                .padding(8)
            }

                }
                // Same trap as the help sheet: without this the content takes
                // its ideal width, wider than the window, and stops wrapping.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .textSelection(.enabled)
        // This sheet has grown a lot. Fixed at 640 wide with no scroll view, it
        // ran off the bottom of the screen and the last controls were
        // unreachable.
        .frame(minWidth: 560, idealWidth: 680, maxWidth: 900,
               minHeight: 360, idealHeight: 620, maxHeight: .infinity)
    }

    var tenBitNote: String {
        if !settings.tenBit { return "8-bit output. Universal playback." }
        switch settings.encoder {
        case .x265:
            return "HEVC Main 10. Confirmed playing at 3840x1080 on a 2017 Shield via Jellyfin, alongside 8-bit x265 and VideoToolbox HEVC. An earlier version of this app said none of them worked; that was two container faults since fixed, not the codec. Still worth a 60 second clip on your own player before a long encode."
        case .videotoolbox:
            return "HEVC Main 10 on the media engine. Confirmed playing at 3840x1080 on a 2017 Shield via Jellyfin. Costs nothing in size or time over 8-bit and is the best defence against banding, so there is no reason to leave it off."
        case .x264:
            return "H.264 High 10. No NVIDIA hardware decoder supports this, and most TVs and set-top boxes reject it. Switch the encoder to x265 or VideoToolbox for 10-bit that plays."
        }
    }
}

struct FolderRow: View {
    let label: String
    @Binding var path: String
    let placeholder: String

    var body: some View {
        HStack {
            Text(label).frame(width: 70, alignment: .leading)
            TextField(placeholder, text: $path)
            Button {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                if panel.runModal() == .OK, let url = panel.url { path = url.path }
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            if !path.isEmpty {
                Button {
                    path = ""
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

// MARK: - Bottom: sources, audio, subtitles

/// Sources, audio and subtitles, with both dividers draggable.
///
/// How much room each column needs depends entirely on what you are working
/// with: long filenames want a wide Sources list, a disc with fourteen audio
/// tracks wants a wide middle. Fixed thirds suit neither, so the split is
/// yours and it is remembered.
struct BottomPanel: View {
    @EnvironmentObject var queue: QueueController

    // 3.61 gave the three columns equal space, so that is where these start.
    // Anything else is me deciding how wide your filenames are.
    @AppStorage("bottomSourcesFraction") private var sourcesFraction: Double = 1.0 / 3.0
    @AppStorage("bottomAudioFraction") private var audioFraction: Double = 1.0 / 3.0
    /// Where a drag started. Translation is measured from the start of the
    /// gesture, so without this the columns jump on every drag event.
    @State private var dragBase: CGFloat? = nil

    private static let minSources: CGFloat = 240
    private static let minAudio: CGFloat = 240
    private static let minSubs: CGFloat = 200

    /// Clamped on the way out as well as on the way in, so a split saved on a
    /// wide display cannot leave a column unusable on a narrow one.
    private func widths(_ total: CGFloat) -> (CGFloat, CGFloat) {
        let room = max(total - 22, 1)          // the two grab handles
        var src = min(max(BottomPanel.minSources, room * CGFloat(sourcesFraction)),
                      room - BottomPanel.minAudio - BottomPanel.minSubs)
        src = max(src, BottomPanel.minSources)
        var aud = min(max(BottomPanel.minAudio, room * CGFloat(audioFraction)),
                      room - src - BottomPanel.minSubs)
        aud = max(aud, BottomPanel.minAudio)
        return (src, aud)
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                SourcesList()
                    .frame(width: widths(geo.size.width).0)
                SplitHandle(
                    onDrag: { dx in
                        let base = dragBase ?? widths(geo.size.width).0
                        dragBase = base
                        sourcesFraction = Double((base + dx) / max(geo.size.width - 22, 1))
                    },
                    onEnd: { dragBase = nil },
                    onReset: { sourcesFraction = 1.0 / 3.0 })
                TrackColumn(kind: "audio")
                    .frame(width: widths(geo.size.width).1)
                SplitHandle(
                    onDrag: { dx in
                        let base = dragBase ?? widths(geo.size.width).1
                        dragBase = base
                        audioFraction = Double((base + dx) / max(geo.size.width - 22, 1))
                    },
                    onEnd: { dragBase = nil },
                    onReset: { audioFraction = 1.0 / 3.0 })
                TrackColumn(kind: "subtitle")
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct SourcesList: View {
    @EnvironmentObject var queue: QueueController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sources").font(.caption).bold().padding(.horizontal, 12)
            List(selection: $queue.selectedJobID) {
                ForEach(queue.jobs) { job in
                    SourceRow(job: job).tag(job.id)
                }
            }
            .listStyle(.inset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

struct SourceRow: View {
    @ObservedObject var job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(job.displayName).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(job.info.durationText).font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 6) {
                if job.state == .queued {
                    Text(job.info.resolutionText).font(.caption).foregroundColor(.secondary)
                    Image(systemName: "arrow.right").font(.system(size: 8)).foregroundColor(.secondary)
                    Text(job.info.outputSize(for: job.settings.layout))
                        .font(.caption).foregroundColor(.accentColor)
                } else {
                    Text(job.state.label).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text(job.info.codecText).font(.caption).foregroundColor(.secondary)
            }
            if job.state == .running || job.state == .stopping {
                ProgressView(value: job.fraction)
                    .progressViewStyle(.linear)
            }
            if !job.message.isEmpty {
                Text(job.message).font(.caption2).foregroundColor(.orange).lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}

struct TrackColumn: View {
    @EnvironmentObject var queue: QueueController
    let kind: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kind == "audio" ? "Audio" : "Subtitles")
                .font(.caption).bold()
                .padding(.horizontal, 12)
            if let job = queue.selectedJob {
                TrackList(job: job, kind: kind)
                if kind == "subtitle", !job.info.subs.isEmpty, !job.settings.subTracks.isEmpty {
                    SubtitleNote(settings: job.settings)
                }
            } else {
                Spacer()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

/// Says what will actually happen to the subtitles, which depends on the
/// layout and the 3D rebuild toggle rather than being a fixed warning.
struct SubtitleNote: View {
    let settings: JobSettings

    private var oneToOne: Bool { settings.layout == .fsbs || settings.layout == .ftab }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: warn ? "exclamationmark.triangle.fill" : "checkmark.circle")
                .font(.caption2)
                .foregroundColor(warn ? .orange : .green)
            Text(text)
                .font(.caption2)
                .foregroundColor(warn ? .orange : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var warn: Bool { !oneToOne || settings.flatSubs }

    private var text: String {
        if !oneToOne {
            return "Half layouts keep the original 2D subtitles, so they will sit in one eye only. Use a full layout for 3D subtitles."
        }
        if settings.flatSubs {
            return "3D rebuild is off, so these stay 1920 wide and will sit in the left eye only. Turn it back on in Advanced Video Settings."
        }
        let depth = settings.subDepth == 0
            ? "at screen depth"
            : "\(settings.subDepth)px \(settings.subDepth > 0 ? "towards you" : "behind the screen")"
        return "Will be rebuilt into both eyes, \(depth). Bitmaps are copied unchanged."
    }
}

struct TrackList: View {
    @ObservedObject var job: Job
    let kind: String

    private var tracks: [TrackInfo] { kind == "audio" ? job.info.audio : job.info.subs }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                if tracks.isEmpty {
                    Text("None").font(.caption).foregroundColor(.secondary).padding(.leading, 12)
                }
                ForEach(tracks) { track in
                    HStack(spacing: 10) {
                        Toggle("", isOn: binding(for: track)).labelsHidden()
                        Text(track.language).font(.system(size: 12, design: .monospaced))
                            .frame(width: 34, alignment: .leading)
                        Text(track.codecLabel).font(.system(size: 12))
                            .lineLimit(1)
                            .frame(width: 120, alignment: .leading)
                        Text(track.summary).font(.system(size: 12)).foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 4)
        }
        .disabled(job.state == .running || job.state == .stopping)
    }

    private func binding(for track: TrackInfo) -> Binding<Bool> {
        Binding(
            get: {
                let list = kind == "audio" ? job.settings.audioTracks : job.settings.subTracks
                return list.contains(track.typeIndex)
            },
            set: { keep in
                var list = kind == "audio" ? job.settings.audioTracks : job.settings.subTracks
                if keep {
                    if !list.contains(track.typeIndex) { list.append(track.typeIndex) }
                } else {
                    list.removeAll { $0 == track.typeIndex }
                }
                if kind == "audio" { job.settings.audioTracks = list }
                else { job.settings.subTracks = list }
            }
        )
    }
}

// MARK: - Status bar

struct StatusBar: View {
    @EnvironmentObject var queue: QueueController

    var body: some View {
        Group {
            if let job = queue.selectedJob {
                // The job has to be observed here, not just read. Reading it
                // through the controller gave a status bar that only refreshed
                // when the controller itself published something.
                StatusBarContent(job: job)
            } else {
                HStack { Text("No file selected"); Spacer() }
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

struct StatusBarContent: View {
    @ObservedObject var job: Job

    var body: some View {
        HStack {
            Text(percentText).frame(width: 150, alignment: .leading)
            Spacer()
            Text("\(Job.timeText(job.elapsed)) elapsed")
            Spacer()
            Text(rateText)
            Spacer()
            Text("\(Job.timeText(job.remaining)) remain")
            Spacer()
            Text("Frame \(job.currentFrame)/\(job.totalFrames)")
                .frame(width: 190, alignment: .trailing)
        }
    }

    private var percentText: String {
        switch job.stage {
        case "extract":  return "Extracting source"
        case "scan":     return "Checking for MVC"
        case "preview":  return "Building preview"
        case "stopping": return "Stopping"
        case "mux":      return "Finishing"
        case "remux":    return "Rebuilding container"
        case "verify":   return "Checking the output"
        case "eyes":     return "Checking eye order"
        default:
            if job.state == .succeeded { return "100% Complete" }
            return String(format: "%.0f%% Complete", job.fraction * 100)
        }
    }

    private var rateText: String {
        String(format: "%.1f FPS / %@", job.fps, job.speed.isEmpty ? "0x" : job.speed)
    }
}

// MARK: - Sheets

/// A plain AppKit text view.
///
/// SwiftUI's `Text` lays out its whole string in one pass, and with
/// `.textSelection(.enabled)` it builds selection geometry for every glyph. An
/// encode log is a few hundred thousand characters, so opening the console
/// locked the app for tens of seconds. NSTextView is what a text editor uses
/// and it does not care about the size.
struct LogTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
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
        // Only follow the tail if the view was already at the tail. Scrolling
        // back to read something while a job runs must not yank you forward.
        let atBottom = scroll.contentView.bounds.maxY >= (tv.frame.height - 40)
        tv.string = text
        if atBottom { tv.scrollToEndOfDocument(nil) }
    }
}

struct ConsoleSheet: View {
    @EnvironmentObject var queue: QueueController

    private var logDir: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/mvc2sbs")
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Console").font(.headline)
                Spacer()
                Button("Save...") { save() }
                Button("Log folder") {
                    try? FileManager.default.createDirectory(
                        atPath: logDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(URL(fileURLWithPath: logDir))
                }
                Button("Close") { queue.consoleVisible = false }
            }
            LogTextView(text: queue.selectedJob?.log ?? "")
                .background(Color.black.opacity(0.25))
            Text("Every run also writes its own log to " + logDir)
                .font(.caption).foregroundColor(.secondary)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(width: 860, height: 520)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue =
            (queue.selectedJob?.displayName ?? "mvc2sbs") + ".log"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? (queue.selectedJob?.log ?? "").write(to: url, atomically: true, encoding: .utf8)
    }
}

struct SettingsSheet: View {
    @EnvironmentObject var queue: QueueController
    @EnvironmentObject var defaults: DefaultsStore
    @Environment(\.dismiss) private var dismiss
    @State private var mvc2sbs = Tools.find("mvc2sbs") ?? ""
    @State private var ffmpeg = Tools.find("ffmpeg") ?? ""
    @State private var ffprobe = Tools.find("ffprobe") ?? ""
    @State private var mkvpropedit = Tools.find("mkvpropedit") ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tool locations").font(.headline)
            Text("The app cannot see your shell PATH, so these are looked up explicitly.")
                .font(.caption).foregroundColor(.secondary)
            toolRow("mvc2sbs", $mvc2sbs)
            toolRow("ffmpeg", $ffmpeg)
            toolRow("ffprobe", $ffprobe)
            toolRow("mkvpropedit", $mkvpropedit)
            Text("mkvpropedit is optional. Without it the output plays fine but carries no 3D StereoMode flag.")
                .font(.caption).foregroundColor(.secondary)
            Divider()
            HStack {
                Text("Versions").frame(width: 80, alignment: .leading)
                Text("bundled \(Tools.toolVersion(at: Tools.bundledTool) ?? "none"), "
                     + "on PATH \(Tools.toolVersion(at: Tools.pathTool) ?? "none")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Tools.versionMismatch == nil ? .secondary : .orange)
                Spacer()
            }
            if Tools.versionMismatch != nil {
                Text("These should match. The app runs its own bundled copy, not the one on your PATH, so installing new scripts does not update the app. Rebuild with build-app.sh --install.")
                    .font(.caption).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            // Reset lives beside the Format picker now, where the settings it
            // resets are. This is only the note about where they are kept.
            Text("Saved settings persist across upgrades, so a default changed in a new version does not reach you until you use Reset to Defaults, beside the Format picker. Stored in ~/Library/Preferences/local.mvc2sbs.app.plist.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Done") {
                    Tools.setOverride("mvc2sbs", path: mvc2sbs)
                    Tools.setOverride("ffmpeg", path: ffmpeg)
                    Tools.setOverride("ffprobe", path: ffprobe)
                    Tools.setOverride("mkvpropedit", path: mkvpropedit)
                    queue.refreshToolWarning()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620)
    }

    private func toolRow(_ name: String, _ binding: Binding<String>) -> some View {
        HStack {
            Text(name).frame(width: 80, alignment: .leading)
            TextField("not found", text: binding)
                .font(.system(size: 11, design: .monospaced))
            Button {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.showsHiddenFiles = true
                if panel.runModal() == .OK, let url = panel.url { binding.wrappedValue = url.path }
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
        }
    }
}
