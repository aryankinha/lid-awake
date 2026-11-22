import Foundation
import Darwin

public enum WatchdogAction: Equatable, Sendable {
    case recovered(reason: String)
    case clearFailed(reason: String)
    case healthy
}

/// Independent, unprivileged safety process. It never turns sleep prevention
/// on; it only clears a session whose owner stopped renewing its lease or whose
/// stored safety contract has expired.
public final class WatchdogRunner {
    public let leaseStore: LeaseStoring
    public let system: SystemControlling
    public let now: () -> Date
    public let bootID: String
    public let leaseTTL: TimeInterval
    public let processAlive: (Int32) -> Bool
    public let isHelperProcess: (Int32) -> Bool

    public init(
        leaseStore: LeaseStoring,
        system: SystemControlling,
        now: @escaping () -> Date = Date.init,
        bootID: String = SystemInfo.bootID,
        leaseTTL: TimeInterval = 20,
        processAlive: @escaping (Int32) -> Bool = SystemInfo.processIsAlive,
        isHelperProcess: @escaping (Int32) -> Bool = WatchdogRunner.isCaffeinate
    ) {
        self.leaseStore = leaseStore
        self.system = system
        self.now = now
        self.bootID = bootID
        self.leaseTTL = leaseTTL
        self.processAlive = processAlive
        self.isHelperProcess = isHelperProcess
    }

    /// Avoid sending SIGTERM to a reused PID after the original caffeinate
    /// helper exited.
    public static func isCaffeinate(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = buffer.withUnsafeMutableBytes { raw in
            proc_pidpath(pid, raw.baseAddress, UInt32(MAXPATHLEN))
        }
        guard length > 0 else { return false }
        return String(cString: buffer).hasSuffix("/caffeinate")
    }

    /// The app calls this at launch with `writeHealth: false`; only the
    /// watchdog process writes the heartbeat file. That prevents a loaded but
    /// dead watchdog from looking healthy because the GUI wrote a heartbeat.
    @discardableResult
    public func runOnce(writeHealth: Bool = false) -> WatchdogAction {
        let current = now()
        if writeHealth {
            try? leaseStore.saveHealth(
                WatchdogHealth(
                    kind: "watchdog",
                    pid: SystemInfo.processID,
                    bootID: bootID,
                    updatedAt: current
                )
            )
        }

        let lease: SessionLease?
        do {
            lease = try leaseStore.load()
        } catch {
            // A corrupt ownership record is a fail-safe condition. Clear the
            // selector; if the optional pmset grant is installed, also try to
            // clear the system-wide flag. Keep the file until clearing works.
            do {
                try system.setClamshellOverride(false)
                if FileManager.default.fileExists(atPath: PmsetController.sudoersPath) {
                    try system.setSystemSleepDisabled(false)
                    let after = system.snapshot()
                    guard after.sleepDisabledKnown && !after.sleepDisabled else {
                        throw LidAwakeError.pmsetFailed(-1, "corrupt lease: pmset still on")
                    }
                } else if system.snapshot().sleepDisabled {
                    throw LidAwakeError.pmsetPermissionMissing
                }
                try leaseStore.save(nil)
                leaseStore.appendLog("WATCHDOG cleared corrupt lease: \(error.localizedDescription)")
                return .recovered(reason: "corrupt lease")
            } catch {
                leaseStore.appendLog("WATCHDOG corrupt-lease clear failed: \(error.localizedDescription)")
                return .clearFailed(reason: "corrupt lease: \(error.localizedDescription)")
            }
        }

        guard let lease else {
            return .healthy
        }

        if lease.bootID != bootID {
            return clear(lease: lease, reason: "lease is from a previous boot")
        }
        if lease.stopping {
            return clear(lease: lease, reason: "session is stopping")
        }

        let age = current.timeIntervalSince(lease.updatedAt)
        if age < 0 || age > leaseTTL {
            return clear(lease: lease, reason: age < 0 ? "clock moved backwards" : "lease expired")
        }
        if !processAlive(lease.pid) {
            return clear(lease: lease, reason: "owning process \(lease.pid) is gone")
        }

        let snapshot = system.snapshot()
        if !snapshot.batteryInfoKnown || (!snapshot.onAC && snapshot.batteryPercent == nil) {
            return clear(lease: lease, reason: "battery state is unknown")
        }
        if let deadline = lease.deadline, current >= deadline {
            return clear(lease: lease, reason: "stored deadline expired")
        }
        if !snapshot.onAC, !snapshot.charging,
           let percent = snapshot.batteryPercent, percent <= lease.batteryFloor {
            return clear(lease: lease, reason: "stored battery floor reached")
        }
        if lease.thermalGuard {
            switch snapshot.thermalState {
            case .serious, .critical:
                return clear(lease: lease, reason: "thermal protection triggered")
            default:
                break
            }
        }

        return .healthy
    }

    public func runForever(interval: TimeInterval = 5) {
        leaseStore.appendLog("WATCHDOG start pid=\(SystemInfo.processID) boot=\(bootID)")
        while true {
            _ = runOnce(writeHealth: true)
            Thread.sleep(forTimeInterval: interval)
        }
    }

    private func clear(lease: SessionLease, reason: String) -> WatchdogAction {
        do {
            var recovered = false
            try leaseStore.update { latest in
                // Hold the store lock from the ownership check through restore
                // so a renewal or a new session cannot interleave with recovery.
                guard latest == lease else { return }

                if let helperPID = lease.helperPID,
                   helperPID > 0,
                   lease.bootID == bootID,
                   isHelperProcess(helperPID) {
                    kill(helperPID, SIGTERM)
                }

                switch lease.mode {
                case .clamshell:
                    try system.setClamshellOverride(false)
                case .system:
                    if lease.ownsPmset {
                        try system.setSystemSleepDisabled(false)
                        let after = system.snapshot()
                        guard after.sleepDisabledKnown && !after.sleepDisabled else {
                            throw LidAwakeError.pmsetFailed(-1, "pmset did not restore normal sleep (state unknown or still on)")
                        }
                    }
                }
                latest = nil
                recovered = true
            }
            guard recovered else { return .healthy }
            leaseStore.appendLog("WATCHDOG cleared reason=\(reason) mode=\(lease.mode.rawValue)")
            return .recovered(reason: reason)
        } catch {
            leaseStore.appendLog("WATCHDOG clear failed reason=\(reason) error=\(error.localizedDescription)")
            return .clearFailed(reason: "\(reason): \(error.localizedDescription)")
        }
    }
}
