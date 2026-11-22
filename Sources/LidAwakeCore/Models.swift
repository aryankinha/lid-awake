import Foundation

/// Which mechanism is currently keeping the Mac awake.
public enum SleepMode: String, Codable, CaseIterable, Sendable {
    /// Blocks only clamshell/lid-close sleep using the private IOKit selector.
    /// Idle, low-battery and thermal sleep still work.
    case clamshell
    /// Blocks all sleep by setting the system-wide `SleepDisabled` flag.
    /// Requires the scoped sudoers fallback.
    case system

    public var displayName: String {
        switch self {
        case .clamshell: return "Lid-close + idle (no admin)"
        case .system: return "System-wide (manual fallback)"
        }
    }
}

public enum DisarmReason: String, Codable, Sendable {
    case user
    case timer
    case battery
    case thermal
    case lidOpened
    case appQuit
    case watchdog
    case error
    case loginItemDisabled

    public var displayName: String {
        switch self {
        case .user: return "Turned off"
        case .timer: return "Timer expired"
        case .battery: return "Battery floor reached"
        case .thermal: return "Thermal protection triggered"
        case .lidOpened: return "Lid opened (Trip Mode)"
        case .appQuit: return "App quit"
        case .watchdog: return "Watchdog recovery"
        case .error: return "Safety error"
        case .loginItemDisabled: return "Launch at login disabled"
        }
    }
}

/// Live state read from IOKit and Foundation. No shell parsing.
public struct SystemSnapshot: Equatable, Sendable {
    public var sleepDisabled: Bool
    public var lidClosed: Bool
    public var clamshellCausesSleep: Bool
    public var onAC: Bool
    public var batteryPercent: Int?
    public var charging: Bool
    public var thermalState: ProcessInfo.ThermalState
    public var lowPowerMode: Bool
    /// False when the IOKit clamshell property could not be read. The UI must
    /// show "unknown", not "confirmed safe".
    public var clamshellCausesSleepKnown: Bool
    /// False when the SleepDisabled IOKit property could not be read.
    public var sleepDisabledKnown: Bool
    /// False when no battery source could be read. The battery guard fails
    /// closed rather than assuming AC.
    public var batteryInfoKnown: Bool

    public init(
        sleepDisabled: Bool = false,
        lidClosed: Bool = false,
        clamshellCausesSleep: Bool = false,
        onAC: Bool = true,
        batteryPercent: Int? = nil,
        charging: Bool = false,
        thermalState: ProcessInfo.ThermalState = .nominal,
        lowPowerMode: Bool = false,
        clamshellCausesSleepKnown: Bool = true,
        sleepDisabledKnown: Bool = true,
        batteryInfoKnown: Bool = true
    ) {
        self.sleepDisabled = sleepDisabled
        self.lidClosed = lidClosed
        self.clamshellCausesSleep = clamshellCausesSleep
        self.onAC = onAC
        self.batteryPercent = batteryPercent
        self.charging = charging
        self.thermalState = thermalState
        self.lowPowerMode = lowPowerMode
        self.clamshellCausesSleepKnown = clamshellCausesSleepKnown
        self.sleepDisabledKnown = sleepDisabledKnown
        self.batteryInfoKnown = batteryInfoKnown
    }
}

public struct SessionConfig: Equatable, Sendable {
    public var mode: SleepMode
    public var duration: TimeInterval?
    public var batteryFloor: Int
    public var tripMode: Bool
    public var thermalGuard: Bool
    public var maxDuration: TimeInterval

    public init(
        mode: SleepMode = .clamshell,
        duration: TimeInterval? = 2 * 60 * 60,
        batteryFloor: Int = 20,
        tripMode: Bool = true,
        thermalGuard: Bool = true,
        maxDuration: TimeInterval = 8 * 60 * 60
    ) {
        self.mode = mode
        self.duration = duration
        self.batteryFloor = min(max(batteryFloor, 5), 50)
        self.tripMode = tripMode
        self.thermalGuard = thermalGuard
        self.maxDuration = max(maxDuration, 60)
    }
}

/// On-disk ownership record. The app renews this every few seconds; the
/// watchdog clears the sleep override if the record goes stale.
public struct SessionLease: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    /// Identifies one armed session; prevents a stale watchdog read from
    /// clearing a newer session.
    public var ownerID: UUID
    public var pid: Int32
    public var bootID: String
    public var mode: SleepMode
    public var startedAt: Date
    public var updatedAt: Date
    public var deadline: Date?
    public var tripMode: Bool
    public var batteryFloor: Int
    public var thermalGuard: Bool
    /// True when the session owns the system-wide pmset flag (fallback mode).
    public var ownsPmset: Bool
    public var stopping: Bool
    /// PID of the revocable `caffeinate -i` helper held by the app.
    public var helperPID: Int32?

    public init(
        version: Int = SessionLease.currentVersion,
        ownerID: UUID = UUID(),
        pid: Int32,
        bootID: String,
        mode: SleepMode,
        startedAt: Date,
        updatedAt: Date,
        deadline: Date?,
        tripMode: Bool,
        batteryFloor: Int,
        thermalGuard: Bool,
        ownsPmset: Bool,
        stopping: Bool = false,
        helperPID: Int32? = nil
    ) {
        self.version = version
        self.ownerID = ownerID
        self.pid = pid
        self.bootID = bootID
        self.mode = mode
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.deadline = deadline
        self.tripMode = tripMode
        self.batteryFloor = batteryFloor
        self.thermalGuard = thermalGuard
        self.ownsPmset = ownsPmset
        self.stopping = stopping
        self.helperPID = helperPID
    }
}

public struct WatchdogHealth: Codable, Equatable, Sendable {
    public var version: Int
    public var kind: String
    public var pid: Int32
    public var bootID: String
    public var updatedAt: Date

    public init(
        version: Int = 1,
        kind: String = "watchdog",
        pid: Int32,
        bootID: String,
        updatedAt: Date
    ) {
        self.version = version
        self.kind = kind
        self.pid = pid
        self.bootID = bootID
        self.updatedAt = updatedAt
    }
}

public enum LidAwakeError: Error, LocalizedError, Equatable {
    case ioKitServiceUnavailable
    case ioKitOpenFailed(kern_return_t)
    case clamshellSelectorFailed(kern_return_t)
    case pmsetPermissionMissing
    case pmsetFailed(Int32, String)
    case watchdogNotInstalled
    case invalidLease(String)

    public var errorDescription: String? {
        switch self {
        case .ioKitServiceUnavailable:
            return "IOPMrootDomain is unavailable."
        case .ioKitOpenFailed(let code):
            return "Could not open IOPMrootDomain (0x\(String(code, radix: 16)))."
        case .clamshellSelectorFailed(let code):
            return "The private clamshell selector failed (0x\(String(code, radix: 16)))."
        case .pmsetPermissionMissing:
            return "The scoped pmset permission is not installed."
        case .pmsetFailed(let status, let message):
            return "pmset failed (exit \(status)): \(message)"
        case .watchdogNotInstalled:
            return "The safety watchdog is not running."
        case .invalidLease(let reason):
            return "Invalid session lease: \(reason)"
        }
    }
}
