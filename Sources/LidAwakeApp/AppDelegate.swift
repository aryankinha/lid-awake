import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.shared
        model.start()
        menuBarController = MenuBarController(model: model)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        menuBarController?.showPopover()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        AppModel.shared.handle(urls)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if AppModel.shared.terminationPrepared {
            return .terminateNow
        }
        if AppModel.shared.shutdown(clean: true) {
            AppModel.shared.prepareForTermination()
            return .terminateNow
        }
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        if !AppModel.shared.terminationPrepared {
            _ = AppModel.shared.shutdown(clean: true)
        }
    }
}
