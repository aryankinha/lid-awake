import Foundation
import XCTest
@testable import LidAwakeApp

final class PopoverInteractionTests: XCTestCase {
    func testMultipleMeasurementsApplyOnlyTheLatestHeight() {
        var updates = PopoverHeightUpdates()
        XCTAssertTrue(updates.enqueue(530))
        XCTAssertFalse(updates.enqueue(572))
        XCTAssertFalse(updates.enqueue(610))
        XCTAssertEqual(updates.takeHeight(currentHeight: 470), 610)
        XCTAssertNil(updates.takeHeight(currentHeight: 610))
    }

    func testCancelingExpansionInTheSamePassDoesNotResize() {
        var updates = PopoverHeightUpdates()
        XCTAssertTrue(updates.enqueue(630))
        XCTAssertFalse(updates.enqueue(510))
        XCTAssertNil(updates.takeHeight(currentHeight: 510))
    }

    func testSmallLayoutNoiseAndInvalidMeasurementsDoNotResize() {
        var updates = PopoverHeightUpdates()
        XCTAssertFalse(updates.enqueue(.nan))
        XCTAssertFalse(updates.enqueue(.infinity))
        XCTAssertFalse(updates.enqueue(0))
        XCTAssertTrue(updates.enqueue(510.3))
        XCTAssertFalse(updates.enqueue(-1))
        XCTAssertNil(updates.takeHeight(currentHeight: 510))
        XCTAssertTrue(updates.enqueue(510.9))
        XCTAssertEqual(updates.takeHeight(currentHeight: 510), 511)
    }

    func testFirstOpenHeightIsDeterministicOnANormalScreen() {
        XCTAssertEqual(PopoverLayout.initialContentHeight(screenHeight: 944), 504)
    }

    func testFirstOpenHeightCapsOnAShortScreenBeforeShowing() {
        XCTAssertEqual(PopoverLayout.initialContentHeight(screenHeight: 500), 460)
        XCTAssertEqual(PopoverLayout.initialContentHeight(screenHeight: 300), 260)
    }

    func testClickInsidePopoverOrOnStatusItemDoesNotDismissIt() {
        let popover = CGRect(x: 70, y: 80, width: 360, height: 500)
        let anchor = CGRect(x: 220, y: 581, width: 32, height: 24)
        XCTAssertFalse(PopoverDismissal.isOutside(CGPoint(x: 105, y: 550), popoverFrame: popover, anchorFrame: anchor))
        XCTAssertFalse(PopoverDismissal.isOutside(CGPoint(x: 230, y: 590), popoverFrame: popover, anchorFrame: anchor))
    }

    func testClickOutsidePopoverAndOnAnotherDisplayDismissesIt() {
        let popover = CGRect(x: 70, y: 80, width: 360, height: 500)
        let anchor = CGRect(x: 220, y: 581, width: 32, height: 24)
        XCTAssertTrue(PopoverDismissal.isOutside(CGPoint(x: 433, y: 420), popoverFrame: popover, anchorFrame: anchor))
        XCTAssertTrue(PopoverDismissal.isOutside(CGPoint(x: -170, y: 210), popoverFrame: popover, anchorFrame: anchor))
    }
}
