import Foundation

/// Fallback path: toggles the system-wide `SleepDisabled` flag through a
/// two-command sudoers rule. This is only used when the private clamshell
/// selector is unavailable or the user explicitly chooses system-wide mode.
public final class PmsetController {
    public static let sudoersPath = "/etc/sudoers.d/lidawake-disablesleep"
    private let pmsetPath = "/usr/bin/pmset"
    private let sudoPath = "/usr/bin/sudo"

    public init() {}

    public var isGrantInstalled: Bool {
        FileManager.default.fileExists(atPath: Self.sudoersPath)
    }

    public func setSystemSleepDisabled(_ enabled: Bool) throws {
        let result = run(
            sudoPath,
            ["-n", pmsetPath, "-a", "disablesleep", enabled ? "1" : "0"]
        )
        guard result.status == 0 else {
            if result.stderr.localizedCaseInsensitiveContains("password is required") ||
                result.stderr.localizedCaseInsensitiveContains("not allowed") {
                throw LidAwakeError.pmsetPermissionMissing
            }
            throw LidAwakeError.pmsetFailed(result.status, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Explicit user action: asks macOS for administrator authorization and
    /// clears a system-wide flag that was set outside LidAwake. Never called
    /// automatically.
    public func clearSystemFlagWithAuthorization() throws {
        let command = "\(pmsetPath) -a disablesleep 0"
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let result = run(
            "/usr/bin/osascript",
            ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
        )
        guard result.status == 0 else {
            throw LidAwakeError.pmsetFailed(result.status, result.stderr)
        }
    }

    private struct ProcessResult {
        var status: Int32
        var stderr: String
    }

    private func run(_ executable: String, _ arguments: [String]) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        environment["LC_ALL"] = "C"
        process.environment = environment

        let stderr = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return ProcessResult(status: -1, stderr: error.localizedDescription)
        }

        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ProcessResult(
            status: process.terminationStatus,
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
