import Foundation

/// Installs the unprivileged watchdog LaunchAgent and the copied helper.
/// No administrator access is required.
public final class WatchdogInstaller {
    public static let label = "com.aryankinha.LidAwake.watchdog"

    public let store: FileLeaseStore
    public let fileManager = FileManager.default

    public init(store: FileLeaseStore = FileLeaseStore()) {
        self.store = store
    }

    public var supportDirectory: URL { store.directory }
    public var binDirectory: URL { supportDirectory.appendingPathComponent("bin", isDirectory: true) }
    public var helperURL: URL { binDirectory.appendingPathComponent("lidawake-ctl") }
    public var launchAgentURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(Self.label).plist")
    }
    public var logURL: URL { supportDirectory.appendingPathComponent("watchdog.log") }

    public func install(helperSource: URL) throws {
        try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: launchAgentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: helperURL.path) {
            try? fileManager.removeItem(at: helperURL)
        }
        try fileManager.copyItem(at: helperSource, to: helperURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)

        let plist = launchAgentPlist()
        try plist.write(to: launchAgentURL, atomically: true, encoding: .utf8)
        try? fileManager.removeItem(at: store.healthURL)

        let domain = "gui/\(getuid())"
        _ = run("/bin/launchctl", ["bootout", "\(domain)/\(Self.label)"])
        let result = run("/bin/launchctl", ["bootstrap", domain, launchAgentURL.path])
        guard result.status == 0 else {
            throw LidAwakeError.pmsetFailed(result.status, "launchctl bootstrap failed: \(result.stderr)")
        }
    }

    /// Returns false when the watchdog could not be confirmed stopped. The
    /// caller must not delete the support directory in that case.
    @discardableResult
    public func uninstall() -> Bool {
        let domain = "gui/\(getuid())"
        _ = run("/bin/launchctl", ["bootout", "\(domain)/\(Self.label)"])
        // Confirm launchd reaped the watchdog instead of relying on a fixed
        // sleep. An in-flight heartbeat must not recreate the cache after
        // store.clearAll().
        let deadline = Date().addingTimeInterval(2)
        while isLoaded && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard !isLoaded else { return false }
        try? fileManager.removeItem(at: launchAgentURL)
        try? fileManager.removeItem(at: helperURL)
        return true
    }

    public var isLoaded: Bool {
        let domain = "gui/\(getuid())"
        return run("/bin/launchctl", ["print", "\(domain)/\(Self.label)"]).status == 0
    }

    public func isHealthy(now: Date = Date(), maxAge: TimeInterval = 15) -> Bool {
        guard isLoaded else { return false }
        return isHeartbeatFresh(now: now, maxAge: maxAge)
    }

    /// Cheap check used by the UI every second. Reads the heartbeat file only;
    /// it does not spawn `launchctl`.
    public func isHeartbeatFresh(now: Date = Date(), maxAge: TimeInterval = 15) -> Bool {
        guard let health = try? store.loadHealth(),
              health.kind == "watchdog" else { return false }
        return health.bootID == SystemInfo.bootID &&
            now.timeIntervalSince(health.updatedAt) <= maxAge
    }

    private func launchAgentPlist() -> String {
        let arguments = [helperURL.path, "watchdog"]
        let escaped = arguments.map { xmlEscape($0) }.map { "<string>\($0)</string>" }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(Self.label)</string>
            <key>ProgramArguments</key><array>\(escaped)</array>
            <key>RunAtLoad</key><true/>
            <key>KeepAlive</key><true/>
            <key>ThrottleInterval</key><integer>10</integer>
            <key>ProcessType</key><string>Background</string>
            <key>StandardOutPath</key><string>\(xmlEscape(logURL.path))</string>
            <key>StandardErrorPath</key><string>\(xmlEscape(logURL.path))</string>
        </dict>
        </plist>
        """
    }

    private func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private struct CommandResult {
        var status: Int32
        var stderr: String
    }

    private func run(_ executable: String, _ arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, stderr: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(
            status: process.terminationStatus,
            stderr: String(data: data, encoding: .utf8) ?? ""
        )
    }
}
