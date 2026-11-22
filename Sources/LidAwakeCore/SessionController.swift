import Foundation

public struct ActiveSession: Equatable, Sendable {
    public var config: SessionConfig
    public var mode: SleepMode
    public var startedAt: Date
    public var deadline: Date?
    public var hasSeenLidClosed: Bool
}

/// Owns the session lifecycle. Pure enough to unit-test with a fake system.
public final class SessionController {
    public private(set) var active: ActiveSession?
    /// True after a restore command failed. The watchdog must keep retrying;
    /// lease renewal must not erase the stopping intent.
    public private(set) var stopping = false
    public private(set) var helperPID: Int32?

    private let system: SystemControlling
    private let leaseStore: LeaseStoring
    private let now: () -> Date
    private let bootID: String
    private let pid: Int32
    private let ownerID = UUID()

    public init(
        system: SystemControlling,
        leaseStore: LeaseStoring,
        now: @escaping () -> Date = Date.init,
        bootID: String = SystemInfo.bootID,
        pid: Int32 = SystemInfo.processID
    ) {
        self.system = system
        self.leaseStore = leaseStore
        self.now = now
        self.bootID = bootID
        self.pid = pid
    }

    /// Start a session. The lease is written before the kernel flag is set so
    /// the watchdog always has an ownership record to recover from.
    @discardableResult
    public func arm(config: SessionConfig, helperPID: Int32? = nil) throws -> ActiveSession {
        if let active { return active }

        stopping = false
        self.helperPID = helperPID
        let start = now()
        let deadline = effectiveDeadline(config: config, start: start)
        let before = system.snapshot()
        if config.mode == .system && before.sleepDisabled {
            self.helperPID = nil
            throw LidAwakeError.pmsetFailed(
                -1,
                "System-wide SleepDisabled is already set by another owner; clear it first."
            )
        }
        let session = ActiveSession(
            config: config,
            mode: config.mode,
            startedAt: start,
            deadline: deadline,
            hasSeenLidClosed: before.lidClosed
        )

        if let existing = try? leaseStore.load(),
           existing.pid != pid,
           existing.bootID == bootID,
           !existing.stopping,
           SystemInfo.processIsAlive(existing.pid) {
            throw LidAwakeError.invalidLease("another live LidAwake session owns the sleep state")
        }

        let lease = makeLease(session: session, stopping: false)
        try leaseStore.save(lease)

        do {
            switch config.mode {
            case .clamshell:
                try system.setClamshellOverride(true)
            case .system:
                try system.setSystemSleepDisabled(true)
                let after = system.snapshot()
                guard after.sleepDisabledKnown && after.sleepDisabled else {
                    throw LidAwakeError.pmsetFailed(-1, "pmset did not turn sleep off (state unknown or unchanged)")
                }
            }
        } catch {
            // A partially successful arm must be undone before the lease is
            // removed, otherwise the global flag could remain anonymous.
            var rollbackFailed = false
            switch config.mode {
            case .clamshell:
                do { try system.setClamshellOverride(false) } catch { rollbackFailed = true }
            case .system:
                do { try system.setSystemSleepDisabled(false) } catch { rollbackFailed = true }
            }
            self.helperPID = nil
            if rollbackFailed {
                // Keep a stopping lease so the watchdog can retry the rollback.
                try? leaseStore.save(makeLease(session: session, stopping: true))
            } else {
                try? leaseStore.save(nil)
            }
            throw error
        }

        active = session
        leaseStore.appendLog("ARM mode=\(config.mode.rawValue) deadline=\(String(describing: deadline)) trip=\(config.tripMode) floor=\(config.batteryFloor)")
        return session
    }

    /// Stop a session and restore normal sleep. If the restore command fails,
    /// the ownership lease is kept so the watchdog can retry.
    public func disarm(reason: DisarmReason) throws {
        guard let session = active else {
            // Do not delete a lease owned by another process or boot.
            if let lease = try? leaseStore.load(),
               lease.pid == pid,
               lease.bootID == bootID {
                try? leaseStore.save(nil)
            }
            stopping = false
            helperPID = nil
            return
        }

        stopping = true
        var stoppingLease = makeLease(session: session, stopping: true)
        stoppingLease.updatedAt = now()
        try? leaseStore.save(stoppingLease)

        do {
            switch session.mode {
            case .clamshell:
                try system.setClamshellOverride(false)
            case .system:
                try system.setSystemSleepDisabled(false)
                let after = system.snapshot()
                guard after.sleepDisabledKnown && !after.sleepDisabled else {
                    throw LidAwakeError.pmsetFailed(-1, "pmset did not restore sleep (state unknown or still on)")
                }
            }
            active = nil
            stopping = false
            helperPID = nil
            try? leaseStore.save(nil)
            leaseStore.appendLog("DISARM reason=\(reason.rawValue)")
        } catch {
            // Keep active + stopping. The watchdog sees stopping and retries;
            // renewLease must not rewrite a non-stopping lease.
            // The app stops its caffeinate helper after this returns; drop the
            // PID so the watchdog cannot later signal a reused PID.
            self.helperPID = nil
            try? leaseStore.save(makeLease(session: session, stopping: true))
            leaseStore.appendLog("DISARM failed reason=\(reason.rawValue) error=\(error.localizedDescription)")
            throw error
        }
    }

    /// Abandon a local session without touching the kernel flag. Used when the
    /// lease has been taken over by another process and clearing would disrupt
    /// that owner.
    public func abandonLocalSession() {
        active = nil
        stopping = false
        helperPID = nil
    }

    public func setHelperPID(_ pid: Int32?) {
        helperPID = pid
        renewLease()
    }

    /// Re-evaluate safety conditions. Returns a reason if the session should
    /// be disarmed. The app is responsible for calling `disarm(reason:)`.
    public func tick(now current: Date? = nil) -> DisarmReason? {
        guard !stopping, var session = active else { return nil }
        let current = current ?? now()
        let snapshot = system.snapshot()

        if let deadline = session.deadline, current >= deadline {
            return .timer
        }

        if session.mode == .system {
            // The fallback owns a global flag. If IOKit can no longer confirm
            // it, stop claiming the Mac is protected and let the app restore.
            if !snapshot.sleepDisabledKnown || !snapshot.sleepDisabled {
                return .error
            }
        }

        if !snapshot.batteryInfoKnown {
            return .error
        }

        if !snapshot.onAC {
            guard let percent = snapshot.batteryPercent else {
                return .error
            }
            if !snapshot.charging, percent <= session.config.batteryFloor {
                return .battery
            }
        }

        if session.config.thermalGuard {
            switch snapshot.thermalState {
            case .serious, .critical:
                return .thermal
            default:
                break
            }
        }

        if session.config.tripMode {
            if snapshot.lidClosed {
                if !session.hasSeenLidClosed {
                    session.hasSeenLidClosed = true
                    active = session
                    renewLease()
                }
            } else if session.hasSeenLidClosed {
                return .lidOpened
            }
        }

        return nil
    }

    /// Called by the app every few seconds to keep the ownership lease fresh.
    public func renewLease() {
        guard let session = active else { return }
        try? leaseStore.save(makeLease(session: session, stopping: stopping))
    }

    /// Called at app launch. Returns a stale lease if one exists.
    public func loadExistingLease() -> SessionLease? {
        try? leaseStore.load()
    }

    public func clearLease() {
        try? leaseStore.save(nil)
    }

    private func effectiveDeadline(config: SessionConfig, start: Date) -> Date? {
        let maxDeadline = start.addingTimeInterval(config.maxDuration)
        if let duration = config.duration, duration > 0 {
            return min(start.addingTimeInterval(duration), maxDeadline)
        }
        return maxDeadline
    }

    private func makeLease(session: ActiveSession, stopping: Bool) -> SessionLease {
        SessionLease(
            ownerID: ownerID,
            pid: pid,
            bootID: bootID,
            mode: session.mode,
            startedAt: session.startedAt,
            updatedAt: now(),
            deadline: session.deadline,
            tripMode: session.config.tripMode,
            batteryFloor: session.config.batteryFloor,
            thermalGuard: session.config.thermalGuard,
            ownsPmset: session.mode == .system,
            stopping: stopping,
            helperPID: helperPID
        )
    }
}
