import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
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
