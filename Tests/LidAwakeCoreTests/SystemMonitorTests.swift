import IOKit.ps
import XCTest
@testable import LidAwakeCore

final class SystemMonitorTests: XCTestCase {
    func testExternalUPSDoesNotOverrideInternalBattery() {
        let ups: [String: Any] = [
            kIOPSTypeKey: kIOPSUPSType,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue,
            kIOPSCurrentCapacityKey: 95,
            kIOPSMaxCapacityKey: 100
        ]
        let internalBattery: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue,
            kIOPSCurrentCapacityKey: 900,
            kIOPSMaxCapacityKey: 4500
        ]

        let expected = BatteryReading(onAC: false, percent: 20, charging: false, known: true)
        XCTAssertEqual(BatteryReading.read([ups, internalBattery]), expected)
        XCTAssertEqual(BatteryReading.read([internalBattery, ups]), expected)
        XCTAssertEqual(BatteryReading.read([ups]), .unknown)
    }

    func testMissingBatteryStateDoesNotAssumeACPower() {
        let source: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: 60,
            kIOPSMaxCapacityKey: 100
        ]
        XCTAssertEqual(BatteryReading.read([source]), .unknown)
    }

    func testInternalTransportWorksWhenSourceTypeIsMissing() {
        let source: [String: Any] = [
            kIOPSTransportTypeKey: kIOPSInternalType,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue,
            kIOPSCurrentCapacityKey: 580,
            kIOPSMaxCapacityKey: 1000,
            kIOPSIsChargingKey: true
        ]
        XCTAssertEqual(BatteryReading.read([source]), BatteryReading(onAC: true, percent: 58, charging: true, known: true))
    }
}
