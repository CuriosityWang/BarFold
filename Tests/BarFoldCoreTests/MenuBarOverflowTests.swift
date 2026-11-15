import XCTest
import CoreGraphics
@testable import BarFoldCore

final class MenuBarOverflowTests: XCTestCase {
    private let frame = CGRect(x: 994, y: 1, width: 18, height: 30)

    func testRecognizesBothSystemIdentifiers() throws {
        let closed = try XCTUnwrap(MenuBarOverflowControl(identifier: "menu-bar-overflow-indicator", frame: frame))
        let open = try XCTUnwrap(MenuBarOverflowControl(identifier: "menu-bar-overflow-indicator-expanded", frame: frame))
        XCTAssertFalse(closed.isExpanded)
        XCTAssertTrue(open.isExpanded)
        XCTAssertNil(MenuBarOverflowControl(identifier: "another-button", frame: frame))
    }

    func testInactiveWindowCannotMakeExpandedControlLookClosed() throws {
        let closed = try XCTUnwrap(MenuBarOverflowControl(identifier: "menu-bar-overflow-indicator", frame: frame))
        let open = try XCTUnwrap(MenuBarOverflowControl(identifier: "menu-bar-overflow-indicator-expanded", frame: frame))
        XCTAssertEqual(MenuBarOverflowControl.coalesced([closed, open, closed]), [open])
        XCTAssertEqual(MenuBarOverflowControl.coalesced([open, closed]), [open])
        XCTAssertEqual(MenuBarOverflowControl.coalesced([closed, closed]), [closed])
    }

    func testSeparateDisplaysRemainSeparateAndMissingControlNeedsNoClick() throws {
        let first = try XCTUnwrap(MenuBarOverflowControl(identifier: "menu-bar-overflow-indicator", frame: frame))
        let second = try XCTUnwrap(MenuBarOverflowControl(identifier: "menu-bar-overflow-indicator-expanded", frame: frame.offsetBy(dx: 1728, dy: 0)))
        XCTAssertEqual(MenuBarOverflowControl.coalesced([first, second, first]), [first, second])
        XCTAssertTrue(MenuBarOverflowControl.coalesced([]).isEmpty)
    }
}
