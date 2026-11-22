import Foundation

/// Login-at-login via a user LaunchAgent. This avoids SMAppService's
/// code-signing/approval requirements for a locally built, ad-hoc-signed app
/// and gives the uninstaller a single file to remove.
public final class LoginItemInstaller {
    public static let label = "com.aryankinha.LidAwake.login"

    private let fileManager = FileManager.default
    public init() {}

    public var launchAgentURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(Self.label).plist")
    }

    public var isInstalled: Bool {
        let domain = "gui/\(getuid())"
        return run("/bin/launchctl", ["print", "\(domain)/\(Self.label)"]).status == 0
    }

    /// Cheap UI check; avoids spawning launchctl every second.
    public var isConfigured: Bool {
        fileManager.fileExists(atPath: launchAgentURL.path)
    }

    public func install(appPath: String) throws {
        try fileManager.createDirectory(
            at: launchAgentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(Self.label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/open</string>
                <string>\(xmlEscape(appPath))</string>
            </array>
            <key>RunAtLoad</key><true/>
            <key>KeepAlive</key><false/>
            <key>ProcessType</key><string>Interactive</string>
        </dict>
        </plist>
        """
        try plist.write(to: launchAgentURL, atomically: true, encoding: .utf8)

        let domain = "gui/\(getuid())"
        _ = run("/bin/launchctl", ["bootout", "\(domain)/\(Self.label)"])
        let result = run("/bin/launchctl", ["bootstrap", domain, launchAgentURL.path])
        guard result.status == 0 else {
            throw LidAwakeError.pmsetFailed(result.status, "launchctl bootstrap failed: \(result.stderr)")
        }
    }

    public func uninstall() {
        let domain = "gui/\(getuid())"
        _ = run("/bin/launchctl", ["bootout", "\(domain)/\(Self.label)"])
        try? fileManager.removeItem(at: launchAgentURL)
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
