// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Alan Wild
import SwiftUI
import AppKit

/// Standard Mac behaviour: closing the only window quits the app. SwiftUI does
/// not do this by default for a WindowGroup, so it needs an app delegate.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let queue = QueueController.shared, queue.isRunning else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "A conversion is still running."
        alert.informativeText = "Quitting stops it and deletes the scratch file. The partial output is not usable."
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Keep Converting")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            // mvc2sbs traps SIGTERM, so it tears down its own pipeline and
            // removes the scratch file even once this app is gone.
            queue.stop()
            return .terminateNow
        }
        return .terminateCancel
    }
}

@main
struct StereoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var queue = QueueController()
    @StateObject private var defaults = DefaultsStore()

    var body: some Scene {
        WindowGroup("MVC2SBS") {
            ContentView()
                .environmentObject(queue)
                .environmentObject(defaults)
                .preferredColorScheme(.dark)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
