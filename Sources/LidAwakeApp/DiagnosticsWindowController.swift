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
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: DiagnosticsView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "LidAwake Diagnostics"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 420))
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 400, height: 260)
        window.center()
        window.setFrameAutosaveName("LidAwakeDiagnostics")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
