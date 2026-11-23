import XCTest
@testable import LidAwakeApp

final class WakeControlStateTests: XCTestCase {
    func testIdleOffersStartAndShowsSessionOff() {
        let state = makeState()
        XCTAssertEqual(state.actionTitle, "Turn On")
        XCTAssertEqual(state.requestedActive, true)
        XCTAssertEqual(state.sessionValue(remaining: nil), "Off")
    }

    func testRunningOffersStopEvenWhenStartingWouldBeBlocked() {
        let state = makeState(isActive: true, isArmBlocked: true)
        XCTAssertEqual(state.actionTitle, "Turn Off")
        XCTAssertEqual(state.requestedActive, false)
        XCTAssertEqual(state.sessionValue(remaining: "1:23"), "1:23")
        XCTAssertEqual(state.sessionValue(remaining: nil), "On")
    }

    func testRecoveryTakesPriorityOverActiveExternalAndBusyStates() {
        let state = makeState(isActive: true, isRestoring: true, isExternal: true, isBusy: true)
        XCTAssertEqual(state, .restoring)
        XCTAssertNil(state.requestedActive)
        XCTAssertEqual(state.sessionValue(remaining: "1:23"), "Ending")
    }

    func testUnavailableStatesCannotStartOrStopASession() {
        let states = [
            makeState(isExternal: true, isArmBlocked: true),
            makeState(isActive: true, isBusy: true),
            makeState(isArmBlocked: true)
        ]
        XCTAssertEqual(states, [.external, .busy, .blocked])
        for state in states { XCTAssertNil(state.requestedActive) }
    }

    private func makeState(
        isActive: Bool = false,
        isRestoring: Bool = false,
        isExternal: Bool = false,
        isBusy: Bool = false,
        isArmBlocked: Bool = false
    ) -> WakeControlState {
        WakeControlState(
            isActive: isActive,
            isRestoring: isRestoring,
            isExternal: isExternal,
            isBusy: isBusy,
            isArmBlocked: isArmBlocked
        )
    }
}
