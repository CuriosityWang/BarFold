import XCTest
import CoreGraphics
@testable import BarFoldCore

final class MenuBarOrderTests: XCTestCase {
    private func item(_ id: String, _ x: CGFloat, width: CGFloat = 30) -> MenuBarItemFrame {
        MenuBarItemFrame(bundleID: id, frame: CGRect(x: x, y: 0, width: width, height: 24))
    }

    func testCollapsedItemMovesLeftOfArrow() throws {
        let lark = item("lark", 130, width: 52)
        let move = try XCTUnwrap(MenuBarOrder.nextMove(items: [item("self", 100), lark],
            rules: ["lark": SavedRule(name: "飞书", placement: .collapsed)], ownID: "self"))
        XCTAssertEqual(move.item, lark)
        XCTAssertEqual(move.destination, CGPoint(x: 102, y: 12))
    }

    func testReturningToVisibleMovesRightWithoutSavedRule() throws {
        let lark = item("lark", 48, width: 52)
        let move = try XCTUnwrap(MenuBarOrder.nextMove(items: [lark, item("self", 100)], rules: [:], ownID: "self"))
        XCTAssertEqual(move.item, lark)
        XCTAssertEqual(move.destination, CGPoint(x: 128, y: 12))
    }

    func testCorrectOrderDoesNotMoveAnything() {
        let rules = ["fold": SavedRule(name: "F", placement: .collapsed), "hidden": SavedRule(name: "H", placement: .hidden)]
        XCTAssertNil(MenuBarOrder.nextMove(items: [item("hidden", 10), item("fold", 40), item("self", 70), item("new", 100)], rules: rules, ownID: "self"))
        XCTAssertNil(MenuBarOrder.nextMove(items: [item("self", 70), item("new", 100)], rules: rules, ownID: "self"))
    }

    func testMoveNearestItemToPreserveRelativeOrderAndHandleMultipleIcons() {
        let items = [item("a", 10), item("b", 40), item("self", 70), item("fold", 100), item("fold", 130)]
        let rules = ["fold": SavedRule(name: "F", placement: .collapsed)]
        XCTAssertEqual(MenuBarOrder.nextMove(items: items, rules: rules, ownID: "self")?.item.bundleID, "b")
        XCTAssertEqual(MenuBarOrder.nextMove(items: Array(items.dropFirst(2)), rules: rules, ownID: "self")?.item.frame.minX, 100)
    }

    func testMissingArrowAndOwnRuleNeverMoveAnchor() {
        XCTAssertNil(MenuBarOrder.nextMove(items: [item("a", 10)], rules: [:], ownID: "self"))
        XCTAssertNil(MenuBarOrder.nextMove(items: [item("self", 10), item("a", 40)],
            rules: ["self": SavedRule(name: "Self", placement: .hidden)], ownID: "self"))
    }

    func testPermanentHiddenItemsDoNotNeedReorderingBeforeHiding() {
        XCTAssertNil(MenuBarOrder.nextMove(items: [item("self", 70), item("hidden", 100)],
            rules: ["hidden": SavedRule(name: "H", placement: .hidden)], ownID: "self"))
    }
}
