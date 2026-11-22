import XCTest
import Foundation
@testable import LidAwakeCore

final class SessionPresentationTests: XCTestCase {
    private func make(
        active: Bool = false,
        stopping: Bool = false,
        external: Bool = false,
        externalStopping: Bool = false,
        externalFlag: Bool = false,
        error: String? = nil,
        mode: SleepMode = .clamshell,
        trip: Bool = true,
        hasSeenLidClosed: Bool = false,
        lidClosed: Bool = false,
        sleepStateKnown: Bool = true,
        causesSleepKnown: Bool = true,
        causesSleep: Bool = false,
        onAC: Bool = true,
        charging: Bool = false,
        battery: Int? = 80,
        batteryKnown: Bool = true,
        floor: Int = 20,
        thermalGuard: Bool = true,
        thermal: ProcessInfo.ThermalState = .nominal,
        watchdogHealthy: Bool = true,
        watchdogLoaded: Bool = true,
        event: DisarmEvent? = nil
    ) -> SessionPresentation {
        SessionPresentationBuilder.make(
            SessionPresentationInput(
                isActive: active,
                isStopping: stopping,
                externalSession: external,
                externalSessionStopping: externalStopping,
                externalSleepDisabled: externalFlag,
                errorMessage: error,
                mode: mode,
                tripMode: trip,
                hasSeenLidClosed: hasSeenLidClosed,
                lidClosed: lidClosed,
                sleepStateKnown: sleepStateKnown,
                clamshellCausesSleepKnown: causesSleepKnown,
                clamshellCausesSleep: causesSleep,
                onAC: onAC,
                charging: charging,
                batteryPercent: battery,
                batteryInfoKnown: batteryKnown,
                batteryFloor: floor,
                thermalGuard: thermalGuard,
                thermalState: thermal,
                watchdogHealthy: watchdogHealthy,
                watchdogLoaded: watchdogLoaded,
                lastEvent: event
            )
        )
    }

    func testOffNormalSleep() {
        let p = make()
        XCTAssertEqual(p.stateLabel, "Off")
        XCTAssertEqual(p.statusText, "Normal sleep")
        XCTAssertEqual(p.headline, "Off · Normal sleep")
        XCTAssertEqual(p.subtitle, "Your Mac sleeps when you close the lid.")
        XCTAssertEqual(p.modeShort, "Lid close")
        XCTAssertEqual(p.powerText, "80% · AC")
        XCTAssertEqual(p.thermalText, "Nominal")
        XCTAssertEqual(p.lidText, "Lid open")
        XCTAssertEqual(p.watchdogText, "Active")
        XCTAssertFalse(p.isWarning)
        XCTAssertNil(p.eventNote)
    }

    func testActiveClamshellLidOpenWithTripMode() {
        let p = make(active: true, trip: true, lidClosed: false)
        XCTAssertEqual(p.stateLabel, "On")
        XCTAssertEqual(p.statusText, "Close the lid to keep working")
        XCTAssertEqual(p.subtitle, "Close the lid once; reopening it will then stop the session.")
        XCTAssertFalse(p.isWarning)
    }

    func testTripModeAfterFirstClose() {
        let p = make(
            active: true,
            trip: true,
            hasSeenLidClosed: true,
            lidClosed: false
        )
        XCTAssertEqual(p.subtitle, "Opening the lid will turn it off.")
    }

    func testSystemModeWithUnknownSleepState() {
        let p = make(
            mode: .system,
            sleepStateKnown: false,
            watchdogHealthy: true
        )
        XCTAssertEqual(p.statusText, "Sleep state unavailable")
        XCTAssertEqual(p.subtitle, "All sleep mode can't be verified right now.")
        XCTAssertTrue(p.isWarning)
    }

    func testActiveSystemModeWithUnknownSleepState() {
        let p = make(active: true, mode: .system, sleepStateKnown: false)
        XCTAssertEqual(p.statusText, "Sleep state unavailable")
        XCTAssertTrue(p.isWarning)
    }

    func testActiveClamshellLidOpenWithoutTripMode() {
        let p = make(active: true, trip: false, lidClosed: false)
        XCTAssertEqual(p.statusText, "Lid-close sleep is blocked")
        XCTAssertEqual(p.subtitle, "It turns off when the timer ends.")
    }

    func testActiveClamshellLidClosed() {
        let p = make(active: true, lidClosed: true, causesSleep: false)
        XCTAssertEqual(p.statusText, "Running with the lid closed")
        XCTAssertEqual(p.subtitle, "Lid-close sleep is blocked. Keep the Mac ventilated.")
        XCTAssertFalse(p.isClamshellWarning)
    }

    func testActiveClamshellStillCausesSleep() {
        let p = make(active: true, lidClosed: true, causesSleep: true)
        XCTAssertEqual(p.statusText, "Lid-close sleep may not be blocked")
        XCTAssertEqual(p.subtitle, "macOS still reports lid-close sleep.")
        XCTAssertTrue(p.isClamshellWarning)
        XCTAssertTrue(p.isWarning)
    }

    func testSystemModeWinsOverTripMode() {
        let p = make(active: true, mode: .system, trip: true, lidClosed: false)
        XCTAssertEqual(p.statusText, "All sleep is blocked")
        XCTAssertEqual(p.subtitle, "Idle and lid-close sleep are blocked.")
        XCTAssertEqual(p.modeShort, "All sleep")
    }

    func testExternalSession() {
        let p = make(external: true)
        XCTAssertEqual(p.stateLabel, "Other")
        XCTAssertEqual(p.statusText, "Another session is active")
        XCTAssertEqual(p.subtitle, "Turn it off there before using this one.")
        XCTAssertTrue(p.isWarning)
    }

    func testExternalStoppingSession() {
        let p = make(external: true, externalStopping: true)
        XCTAssertEqual(p.stateLabel, "Ending")
        XCTAssertEqual(p.statusText, "A previous session is restoring sleep")
        XCTAssertEqual(p.subtitle, "LidAwake is waiting for the safety check to finish.")
        XCTAssertTrue(p.isWarning)
    }

    func testRestoringNormalSleep() {
        let p = make(active: true, stopping: true)
        XCTAssertEqual(p.stateLabel, "Ending")
        XCTAssertEqual(p.statusText, "Restoring normal sleep")
        XCTAssertEqual(p.subtitle, "The safety check is restoring normal sleep.")
    }

    func testLowBatteryOnBatteryPower() {
        let p = make(onAC: false, battery: 15, floor: 20)
        XCTAssertEqual(p.statusText, "Battery is below your limit")
        XCTAssertEqual(p.subtitle, "Charge above 20% or lower the limit.")
        XCTAssertEqual(p.powerText, "15% · Battery")
        XCTAssertTrue(p.isLowBattery)
        XCTAssertTrue(p.isWarning)
    }

    func testBatteryAtFloorWhileChargingIsNotLow() {
        let p = make(onAC: false, charging: true, battery: 15, floor: 20)
        XCTAssertFalse(p.isLowBattery)
        XCTAssertEqual(p.powerText, "15% · Charging")
    }

    func testThermalPressure() {
        let p = make(thermal: .serious)
        XCTAssertEqual(p.statusText, "The Mac is too hot to start")
        XCTAssertEqual(p.subtitle, "Let it cool, then try again.")
        XCTAssertEqual(p.thermalText, "Hot")
        XCTAssertTrue(p.isThermallyConstrained)
        XCTAssertTrue(p.isWarning)
    }

    func testUnknownBattery() {
        let p = make(battery: nil, batteryKnown: false)
        XCTAssertEqual(p.statusText, "Battery state unavailable")
        XCTAssertEqual(p.powerText, "Battery unknown")
        XCTAssertTrue(p.isWarning)
    }

    func testBatteryPercentageMissingOnBattery() {
        let p = make(onAC: false, battery: nil, batteryKnown: true)
        XCTAssertEqual(p.statusText, "Battery state unavailable")
        XCTAssertEqual(p.powerText, "Battery unknown")
        XCTAssertTrue(p.isWarning)
    }

    func testPowerTextOnACWithoutBatteryReading() {
        let p = make(onAC: true, battery: nil, batteryKnown: true)
        XCTAssertEqual(p.powerText, "AC power")
        XCTAssertEqual(p.statusText, "Normal sleep")
        XCTAssertFalse(p.isWarning)
    }

    func testThermalPressureWithGuardOff() {
        let p = make(thermalGuard: false, thermal: .serious)
        XCTAssertEqual(p.statusText, "Normal sleep")
        XCTAssertTrue(p.isThermallyConstrained)
        XCTAssertFalse(p.isWarning)
    }

    func testExternalSleepFlag() {
        let p = make(externalFlag: true)
        XCTAssertEqual(p.statusText, "Sleep is already off")
        XCTAssertEqual(p.subtitle, "Sleep was disabled outside LidAwake.")
        XCTAssertTrue(p.isWarning)
    }

    func testActiveBatteryRiskNote() {
        let p = make(active: true, onAC: false, battery: 23, floor: 20)
        XCTAssertEqual(p.riskNote, "Battery at 23%; this session stops at 20%.")
        XCTAssertTrue(p.isWarning)
        XCTAssertFalse(p.isLowBattery)
    }

    func testActiveThermalRiskNote() {
        let p = make(active: true, thermalGuard: true, thermal: .serious)
        XCTAssertEqual(p.riskNote, "The Mac is warm; this session may stop.")
        XCTAssertTrue(p.isWarning)
    }

    func testActiveThermalRiskSuppressedWhenGuardOff() {
        let p = make(active: true, thermalGuard: false, thermal: .serious)
        XCTAssertNil(p.riskNote)
        XCTAssertFalse(p.isWarning)
    }

    func testWatchdogStates() {
        XCTAssertEqual(make(watchdogHealthy: true).watchdogText, "Active")
        XCTAssertEqual(make(watchdogHealthy: false, watchdogLoaded: true).watchdogText, "Not responding")
        XCTAssertEqual(make(watchdogHealthy: false, watchdogLoaded: false).watchdogText, "Not installed")
        XCTAssertTrue(make(watchdogHealthy: false).isWarning)
    }

    func testLastStopPersistsUntilNextArm() {
        let event = DisarmEvent(
            reason: .battery,
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let p = make(event: event)
        XCTAssertEqual(p.eventNote, "Last session ended at the battery limit.")
    }

    func testLastStopReasons() {
        let now = Date()
        XCTAssertEqual(
            make(event: DisarmEvent(reason: .timer, date: now)).eventNote,
            "Last session ended when the timer finished."
        )
        XCTAssertEqual(
            make(event: DisarmEvent(reason: .thermal, date: now)).eventNote,
            "Last session ended because the Mac got hot."
        )
        XCTAssertEqual(
            make(event: DisarmEvent(reason: .lidOpened, date: now)).eventNote,
            "Last session ended when the lid opened."
        )
        XCTAssertEqual(
            make(event: DisarmEvent(reason: .watchdog, date: now)).eventNote,
            "Last session ended by the safety check."
        )
        XCTAssertEqual(
            make(event: DisarmEvent(reason: .error, date: now)).eventNote,
            "Last session ended after a safety check failed."
        )
        XCTAssertNil(make(event: DisarmEvent(reason: .user, date: now)).eventNote)
        XCTAssertNil(make(event: DisarmEvent(reason: .appQuit, date: now)).eventNote)
    }

    func testLastStopHiddenWhileActive() {
        let event = DisarmEvent(reason: .battery)
        XCTAssertNil(make(active: true, event: event).eventNote)
    }
}
