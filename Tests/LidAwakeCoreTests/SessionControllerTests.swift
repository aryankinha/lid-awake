import XCTest
import Foundation
@testable import LidAwakeCore

final class FakeSystem: SystemControlling {
    var state: SystemSnapshot
    var clamshellCalls: [Bool] = []
    var pmsetCalls: [Bool] = []
    var clamshellError: Error?
    var pmsetError: Error?

    init(state: SystemSnapshot = SystemSnapshot()) {
        self.state = state
    }

    func snapshot() -> SystemSnapshot { state }

    func setClamshellOverride(_ enabled: Bool) throws {
        if let clamshellError { throw clamshellError }
        clamshellCalls.append(enabled)
    }

    func setSystemSleepDisabled(_ enabled: Bool) throws {
        if let pmsetError { throw pmsetError }
        pmsetCalls.append(enabled)
        state.sleepDisabled = enabled
    }
}

final class MemoryLeaseStore: LeaseStoring {
    var lease: SessionLease?
    var health: WatchdogHealth?
    var log: [String] = []

    func load() throws -> SessionLease? { lease }
    func save(_ lease: SessionLease?) throws { self.lease = lease }
    func saveHealth(_ health: WatchdogHealth) throws { self.health = health }
    func loadHealth() throws -> WatchdogHealth? { health }
    func appendLog(_ line: String) { log.append(line) }
}

final class ThrowingLeaseStore: LeaseStoring {
    func load() throws -> SessionLease? { throw LidAwakeError.invalidLease("corrupt") }
    func save(_ lease: SessionLease?) throws {}
    func saveHealth(_ health: WatchdogHealth) throws {}
    func loadHealth() throws -> WatchdogHealth? { nil }
    func appendLog(_ line: String) {}
}

final class SessionControllerTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeController(
        system: FakeSystem,
        leaseStore: MemoryLeaseStore = MemoryLeaseStore()
    ) -> SessionController {
        SessionController(
            system: system,
            leaseStore: leaseStore,
            now: { self.now },
            bootID: "boot-1",
            pid: 4242
        )
    }

    func testArmClamshellWritesLeaseBeforeSettingFlag() throws {
        let system = FakeSystem(state: SystemSnapshot(lidClosed: false))
        let store = MemoryLeaseStore()
        let controller = makeController(system: system, leaseStore: store)

        let session = try controller.arm(config: SessionConfig(mode: .clamshell, duration: 3600))

        XCTAssertEqual(system.clamshellCalls, [true])
        XCTAssertTrue(system.pmsetCalls.isEmpty)
        XCTAssertEqual(store.lease?.mode, .clamshell)
        XCTAssertEqual(store.lease?.pid, 4242)
        XCTAssertEqual(store.lease?.bootID, "boot-1")
        XCTAssertEqual(session.deadline, now.addingTimeInterval(3600))
        XCTAssertTrue(controller.active != nil)
    }

    func testArmSystemModeVerifiesFlag() throws {
        let system = FakeSystem(state: SystemSnapshot(sleepDisabled: false))
        let store = MemoryLeaseStore()
        let controller = makeController(system: system, leaseStore: store)

        try controller.arm(config: SessionConfig(mode: .system, duration: 60))

        XCTAssertEqual(system.pmsetCalls, [true])
        XCTAssertEqual(store.lease?.mode, .system)
        XCTAssertTrue(store.lease?.ownsPmset ?? false)
    }

    func testSystemModeDetectsLostFlag() throws {
        let system = FakeSystem(state: SystemSnapshot(sleepDisabled: false))
        let store = MemoryLeaseStore()
        let controller = makeController(system: system, leaseStore: store)

        try controller.arm(config: SessionConfig(mode: .system, duration: 3600))
        XCTAssertEqual(controller.tick(now: now.addingTimeInterval(1)), nil)

        system.state.sleepDisabled = false
        XCTAssertEqual(controller.tick(now: now.addingTimeInterval(2)), .error)
    }

    func testArmFailureKeepsStoppingLeaseWhenRollbackFails() {
        let system = FakeSystem()
        system.clamshellError = LidAwakeError.clamshellSelectorFailed(-1)
        let store = MemoryLeaseStore()
        let controller = makeController(system: system, leaseStore: store)

        XCTAssertThrowsError(try controller.arm(config: SessionConfig(mode: .clamshell)))
        XCTAssertNil(controller.active)
        XCTAssertTrue(store.lease?.stopping ?? false)
    }

    func testNewSessionCannotReplacePendingRecovery() throws {
        let system = FakeSystem()
        let store = MemoryLeaseStore()
        let original = makeController(system: system, leaseStore: store)
        let config = SessionConfig(mode: .clamshell)
        try original.arm(config: config)
        var recovering = try XCTUnwrap(store.lease)
        recovering.stopping = true
        store.lease = recovering

        let replacement = makeController(system: system, leaseStore: store)
        XCTAssertThrowsError(try replacement.arm(config: config))
        XCTAssertEqual(store.lease, recovering)
        XCTAssertEqual(system.clamshellCalls, [true])
    }

    func testArmDoesNotOverwriteUnreadableLease() {
        let system = FakeSystem()
        let controller = SessionController(system: system, leaseStore: ThrowingLeaseStore())
        XCTAssertThrowsError(try controller.arm(config: SessionConfig(mode: .clamshell)))
        XCTAssertTrue(system.clamshellCalls.isEmpty)
    }

    func testDisarmRestoresAndClearsLease() throws {
        let system = FakeSystem()
        let store = MemoryLeaseStore()
        let controller = makeController(system: system, leaseStore: store)
        try controller.arm(config: SessionConfig(mode: .clamshell, duration: 60))

        try controller.disarm(reason: .user)

        XCTAssertEqual(system.clamshellCalls, [true, false])
        XCTAssertNil(store.lease)
        XCTAssertNil(controller.active)
    }

    func testDisarmFailureKeepsLeaseForWatchdog() throws {
        let system = FakeSystem()
        let store = MemoryLeaseStore()
        let controller = makeController(system: system, leaseStore: store)
        try controller.arm(config: SessionConfig(mode: .clamshell, duration: 60))
        system.clamshellError = LidAwakeError.clamshellSelectorFailed(-2)

        XCTAssertThrowsError(try controller.disarm(reason: .user))
        XCTAssertNotNil(store.lease)
        XCTAssertNotNil(controller.active)
        XCTAssertTrue(store.lease?.stopping ?? false)
    }

    func testFailedDisarmDoesNotRenewAsLive() throws {
        let system = FakeSystem()
        let store = MemoryLeaseStore()
        let controller = makeController(system: system, leaseStore: store)
        try controller.arm(config: SessionConfig(mode: .clamshell, duration: 60), helperPID: 999)
        system.clamshellError = LidAwakeError.clamshellSelectorFailed(-2)

        XCTAssertThrowsError(try controller.disarm(reason: .battery))
        XCTAssertTrue(store.lease?.stopping ?? false)
        XCTAssertEqual(store.lease?.helperPID, 999)
        XCTAssertTrue(controller.stopping)

        now = now.addingTimeInterval(5)
        controller.renewLease()
        XCTAssertTrue(store.lease?.stopping ?? false)
    }

    func testSystemModeRefusesExternalFlag() {
        let system = FakeSystem(state: SystemSnapshot(sleepDisabled: true))
        let store = MemoryLeaseStore()
        let controller = makeController(system: system, leaseStore: store)

        XCTAssertThrowsError(try controller.arm(config: SessionConfig(mode: .system)))
        XCTAssertNil(controller.active)
        XCTAssertNil(store.lease)
    }

    func testTimerExpires() throws {
        let system = FakeSystem()
        let controller = makeController(system: system)
        try controller.arm(config: SessionConfig(mode: .clamshell, duration: 60))

        XCTAssertNil(controller.tick(now: now.addingTimeInterval(59)))
        XCTAssertEqual(controller.tick(now: now.addingTimeInterval(61)), .timer)
    }

    func testBatteryFloorTriggersOnBatteryButNotWhileCharging() throws {
        let system = FakeSystem(state: SystemSnapshot(onAC: false, batteryPercent: 19, charging: false))
        let controller = makeController(system: system)
        try controller.arm(config: SessionConfig(mode: .clamshell, duration: 600, batteryFloor: 20))

        XCTAssertEqual(controller.tick(now: now), .battery)
        system.state.charging = true
        XCTAssertNil(controller.tick(now: now))
    }

    func testBatteryFloorTriggersAtExactFloor() throws {
        let system = FakeSystem(state: SystemSnapshot(onAC: false, batteryPercent: 20))
        let controller = makeController(system: system)
        try controller.arm(config: SessionConfig(mode: .clamshell, duration: 600, batteryFloor: 20))

        XCTAssertEqual(controller.tick(now: now), .battery)
    }

    func testBatteryFloorDoesNotTriggerOnAC() throws {
        let system = FakeSystem(state: SystemSnapshot(onAC: true, batteryPercent: 5))
        let controller = makeController(system: system)
        try controller.arm(config: SessionConfig(mode: .clamshell, duration: 600, batteryFloor: 20))

        XCTAssertNil(controller.tick(now: now))
    }

    func testUnreadableBatteryFailsSafe() throws {
        let system = FakeSystem(state: SystemSnapshot(
            onAC: false,
            batteryPercent: nil,
            batteryInfoKnown: false
        ))
        let controller = makeController(system: system)
        try controller.arm(config: SessionConfig(mode: .clamshell, duration: 600))

        XCTAssertEqual(controller.tick(now: now), .error)
    }

    func testThermalProtection() throws {
        let system = FakeSystem(state: SystemSnapshot(thermalState: .serious))
        let controller = makeController(system: system)
        try controller.arm(config: SessionConfig(mode: .clamshell, duration: 600, thermalGuard: true))

        XCTAssertEqual(controller.tick(now: now), .thermal)

        let critical = FakeSystem(state: SystemSnapshot(thermalState: .critical))
        let controller2 = makeController(system: critical)
        try controller2.arm(config: SessionConfig(mode: .clamshell, duration: 600, thermalGuard: true))
        XCTAssertEqual(controller2.tick(now: now), .thermal)

        let disabled = FakeSystem(state: SystemSnapshot(thermalState: .critical))
        let controller3 = makeController(system: disabled)
        try controller3.arm(config: SessionConfig(mode: .clamshell, duration: 600, thermalGuard: false))
        XCTAssertNil(controller3.tick(now: now))
    }

    func testTripModeWaitsForCloseThenDisarmsOnOpen() throws {
        let system = FakeSystem(state: SystemSnapshot(lidClosed: false))
        let controller = makeController(system: system)
        try controller.arm(config: SessionConfig(mode: .clamshell, duration: 600, tripMode: true))

        XCTAssertNil(controller.tick(now: now))
        system.state.lidClosed = true
        XCTAssertNil(controller.tick(now: now))
        system.state.lidClosed = false
        XCTAssertEqual(controller.tick(now: now), .lidOpened)
    }

    func testTripModeDoesNotDisarmIfLidNeverClosed() throws {
        let system = FakeSystem(state: SystemSnapshot(lidClosed: false))
        let controller = makeController(system: system)
        try controller.arm(config: SessionConfig(mode: .clamshell, duration: 600, tripMode: true))

        XCTAssertNil(controller.tick(now: now))
    }

    func testNoTimerStillHasEightHourSafetyCap() throws {
        let system = FakeSystem()
        let controller = makeController(system: system)
        try controller.arm(config: SessionConfig(mode: .clamshell, duration: nil))

        XCTAssertNil(controller.tick(now: now.addingTimeInterval(7 * 3600)))
        XCTAssertEqual(controller.tick(now: now.addingTimeInterval(8 * 3600 + 1)), .timer)
    }

    func testMaxDurationCapsLongTimer() throws {
        let system = FakeSystem()
        let controller = makeController(system: system)
        let session = try controller.arm(
            config: SessionConfig(
                mode: .clamshell,
                duration: 48 * 3600,
                maxDuration: 8 * 3600
            )
        )

        XCTAssertEqual(session.deadline, now.addingTimeInterval(8 * 3600))
    }

    func testRenewLeaseUpdatesTimestamp() throws {
        let system = FakeSystem()
        let store = MemoryLeaseStore()
        let controller = makeController(system: system, leaseStore: store)
        try controller.arm(config: SessionConfig(mode: .clamshell, duration: 600))
        let first = store.lease?.updatedAt
        now = now.addingTimeInterval(5)

        controller.renewLease()

        XCTAssertNotEqual(first, store.lease?.updatedAt)
        XCTAssertEqual(store.lease?.updatedAt, now)
    }
}

final class WatchdogRunnerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func lease(
        boot: String = "boot-1",
        pid: Int32 = 1234,
        updated: Date? = nil,
        deadline: Date? = nil,
        mode: SleepMode = .clamshell,
        stopping: Bool = false,
        helperPID: Int32? = nil
    ) -> SessionLease {
        SessionLease(
            pid: pid,
            bootID: boot,
            mode: mode,
            startedAt: now.addingTimeInterval(-60),
            updatedAt: updated ?? now,
            deadline: deadline ?? now.addingTimeInterval(600),
            tripMode: true,
            batteryFloor: 20,
            thermalGuard: true,
            ownsPmset: mode == .system,
            stopping: stopping,
            helperPID: helperPID
        )
    }

    func testFreshLeaseIsHealthy() {
        let store = MemoryLeaseStore()
        store.lease = lease()
        let system = FakeSystem()
        let runner = WatchdogRunner(
            leaseStore: store,
            system: system,
            now: { self.now },
            bootID: "boot-1",
            leaseTTL: 20,
            processAlive: { _ in true }
        )

        XCTAssertEqual(runner.runOnce(), .healthy)
        XCTAssertTrue(system.clamshellCalls.isEmpty)
    }

    func testExpiredLeaseClearsClamshell() {
        let store = MemoryLeaseStore()
        store.lease = lease(updated: now.addingTimeInterval(-30))
        let system = FakeSystem()
        let runner = WatchdogRunner(
            leaseStore: store,
            system: system,
            now: { self.now },
            bootID: "boot-1",
            leaseTTL: 20,
            processAlive: { _ in true }
        )

        XCTAssertEqual(runner.runOnce(), .recovered(reason: "lease expired"))
        XCTAssertEqual(system.clamshellCalls, [false])
        XCTAssertNil(store.lease)
    }

    func testDeadProcessClearsClamshell() {
        let store = MemoryLeaseStore()
        store.lease = lease()
        let system = FakeSystem()
        let runner = WatchdogRunner(
            leaseStore: store,
            system: system,
            now: { self.now },
            bootID: "boot-1",
            leaseTTL: 20,
            processAlive: { _ in false }
        )

        XCTAssertEqual(runner.runOnce(), .recovered(reason: "owning process 1234 is gone"))
        XCTAssertEqual(system.clamshellCalls, [false])
        XCTAssertNil(store.lease)
    }

    func testOldBootLeaseClears() {
        let store = MemoryLeaseStore()
        store.lease = lease(boot: "old-boot")
        let system = FakeSystem()
        let runner = WatchdogRunner(
            leaseStore: store,
            system: system,
            now: { self.now },
            bootID: "new-boot",
            processAlive: { _ in true }
        )

        XCTAssertEqual(runner.runOnce(), .recovered(reason: "lease is from a previous boot"))
        XCTAssertEqual(system.clamshellCalls, [false])
        XCTAssertNil(store.lease)
    }

    func testSystemLeaseClearsPmset() {
        let store = MemoryLeaseStore()
        store.lease = lease(updated: now.addingTimeInterval(-30), mode: .system)
        let system = FakeSystem(state: SystemSnapshot(sleepDisabled: true))
        let runner = WatchdogRunner(
            leaseStore: store,
            system: system,
            now: { self.now },
            bootID: "boot-1",
            processAlive: { _ in true }
        )

        XCTAssertEqual(runner.runOnce(), .recovered(reason: "lease expired"))
        XCTAssertEqual(system.pmsetCalls, [false])
        XCTAssertNil(store.lease)
    }

    func testOnBatteryWithoutPercentageFailsClosed() {
        let store = MemoryLeaseStore()
        store.lease = lease()
        let system = FakeSystem(state: SystemSnapshot(
            onAC: false,
            batteryPercent: nil,
            batteryInfoKnown: true
        ))
        let runner = WatchdogRunner(
            leaseStore: store,
            system: system,
            now: { self.now },
            bootID: "boot-1",
            processAlive: { _ in true }
        )

        XCTAssertEqual(runner.runOnce(), .recovered(reason: "battery state is unknown"))
        XCTAssertEqual(system.clamshellCalls, [false])
    }

    func testStoredDeadlineIsEnforced() {
        let store = MemoryLeaseStore()
        store.lease = lease(deadline: now.addingTimeInterval(-1))
        let system = FakeSystem()
        let runner = WatchdogRunner(
            leaseStore: store,
            system: system,
            now: { self.now },
            bootID: "boot-1",
            processAlive: { _ in true }
        )

        XCTAssertEqual(runner.runOnce(), .recovered(reason: "stored deadline expired"))
        XCTAssertEqual(system.clamshellCalls, [false])
        XCTAssertNil(store.lease)
    }

    func testNoLeaseNeverClearsExternalState() {
        let store = MemoryLeaseStore()
        let system = FakeSystem(state: SystemSnapshot(sleepDisabled: true))
        let runner = WatchdogRunner(
            leaseStore: store,
            system: system,
            now: { self.now },
            bootID: "boot-1",
            processAlive: { _ in true }
        )

        XCTAssertEqual(runner.runOnce(), .healthy)
        XCTAssertTrue(system.clamshellCalls.isEmpty)
        XCTAssertTrue(system.pmsetCalls.isEmpty)
    }

    func testCorruptLeaseFailsSafe() {
        let system = FakeSystem()
        let runner = WatchdogRunner(
            leaseStore: ThrowingLeaseStore(),
            system: system,
            now: { self.now },
            bootID: "boot-1",
            processAlive: { _ in true }
        )

        XCTAssertEqual(runner.runOnce(), .recovered(reason: "corrupt lease"))
        XCTAssertEqual(system.clamshellCalls, [false])
    }

    func testClearFailureKeepsLease() {
        let store = MemoryLeaseStore()
        store.lease = lease(updated: now.addingTimeInterval(-30))
        let system = FakeSystem()
        system.clamshellError = LidAwakeError.clamshellSelectorFailed(-3)
        let runner = WatchdogRunner(
            leaseStore: store,
            system: system,
            now: { self.now },
            bootID: "boot-1",
            processAlive: { _ in true }
        )

        guard case .clearFailed = runner.runOnce() else {
            return XCTFail("expected clearFailed")
        }
        XCTAssertNotNil(store.lease)
    }
}

final class FileLeaseStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LidAwakeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSaveLoadAndClear() throws {
        let store = FileLeaseStore(directory: directory)
        let lease = SessionLease(
            pid: 123,
            bootID: "boot",
            mode: .clamshell,
            startedAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            deadline: Date(timeIntervalSince1970: 300),
            tripMode: true,
            batteryFloor: 20,
            thermalGuard: true,
            ownsPmset: false
        )

        try store.save(lease)
        XCTAssertEqual(try store.load(), lease)
        try store.save(nil)
        XCTAssertNil(try store.load())
    }

    func testRenewalDoesNotRecreateOrReplaceRecoveredLease() throws {
        let store = FileLeaseStore(directory: directory)
        let system = FakeSystem()
        let controller = SessionController(system: system, leaseStore: store, bootID: "boot", pid: 123)
        let config = SessionConfig(mode: .clamshell, duration: 60)
        try controller.arm(config: config)
        let original = try XCTUnwrap(store.load())

        let watchdog = WatchdogRunner(
            leaseStore: store, system: system, bootID: "boot", processAlive: { _ in false }
        )
        guard case .recovered = watchdog.runOnce() else {
            return XCTFail("Watchdog did not recover the old session")
        }
        controller.renewLease()
        XCTAssertNil(try store.load())

        let next = SessionController(system: system, leaseStore: store, bootID: "boot", pid: 123)
        try next.arm(config: config)
        let replacement = try XCTUnwrap(store.load())
        XCTAssertNotEqual(replacement.ownerID, original.ownerID)
        controller.renewLease()
        XCTAssertEqual(try store.load(), replacement)

        try controller.disarm(reason: .user)
        XCTAssertNil(controller.active)
        XCTAssertEqual(try store.load(), replacement)
        XCTAssertEqual(system.clamshellCalls, [true, false, true])
    }

    func testHealthRoundTrip() throws {
        let store = FileLeaseStore(directory: directory)
        let health = WatchdogHealth(pid: 9, bootID: "boot", updatedAt: Date(timeIntervalSince1970: 500))
        try store.saveHealth(health)
        XCTAssertEqual(try store.loadHealth(), health)
    }
}
