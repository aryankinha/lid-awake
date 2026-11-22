import AppKit
import SwiftUI

/// A normal macOS window for diagnostics. A SwiftUI `Window` scene would also
/// work, but this keeps the menu bar popover independent of scene presentation
/// and gives a predictable, reusable window.
@MainActor
final class DiagnosticsWindowController {
    static let shared = DiagnosticsWindowController()

    private var window: NSWindow?

    func show(model: AppModel) {
        // Recreate the content so a second open always shows fresh diagnostics
        // instead of a stale snapshot. The frame autosave restores its position.
        window?.close()

        let hosting = NSHostingController(rootView: DiagnosticsView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "LidAwake Diagnostics"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 420))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
