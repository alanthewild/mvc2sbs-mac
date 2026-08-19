// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Alan Wild
import SwiftUI
import AppKit

/// Closing the only window quits, which SwiftUI does not do on its own, and
/// quitting mid-sweep asks first. mkvshrink checks a finished file before it
/// touches the original, so being killed halfway leaves the original intact and
/// a partial output behind rather than the other way round. Worth saying so
/// rather than letting anyone guess.
final class ShrinkAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let ctl = ShrinkController.shared, ctl.running || ctl.scanning else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = ctl.scanning ? "A scan is still running." : "A sweep is still running."
        alert.informativeText = ctl.scanning
            ? "Nothing on disk is being changed, so quitting is safe. The plan will be lost."
            : "The file being encoded is abandoned and its original is left alone, "
              + "because originals are only touched after every check has passed. "
              + "Files already finished stay finished."
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Keep Going")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            ctl.stop()
            return .terminateNow
        }
        return .terminateCancel
    }
}

@main
struct MKVShrinkApp: App {
    @NSApplicationDelegateAdaptor(ShrinkAppDelegate.self) private var appDelegate
    @StateObject private var controller = ShrinkController()
    @StateObject private var defaults = ShrinkDefaults()

    var body: some Scene {
        WindowGroup("MKVShrink") {
            ShrinkContentView()
                .environmentObject(controller)
                .environmentObject(defaults)
                .preferredColorScheme(.dark)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
