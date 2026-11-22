import Foundation

/// Holds the idle-sleep assertion in a separate `caffeinate` process so the
/// watchdog can revoke it by PID if the GUI hangs. `-w <app pid>` also makes
/// it exit automatically if the app dies.
final class CaffeinateHelper {
    private var process: Process?

    var pid: Int32? {
        process?.processIdentifier
    }

    func start() -> Int32? {
        stop()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-i", "-w", "\(getpid())"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            self.process = process
            return process.processIdentifier
        } catch {
            self.process = nil
            return nil
        }
    }

    func stop() {
        guard let process else { return }
        if process.isRunning {
            process.terminate()
        }
        self.process = nil
    }
}
