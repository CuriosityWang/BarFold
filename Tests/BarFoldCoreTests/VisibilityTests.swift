import XCTest
@testable import BarFoldCore

final class VisibilityTests: XCTestCase {
    func testThreePlacementsAndUnknownApps() {
        let rules = [
            "always": SavedRule(name: "A", placement: .visible),
            "fold": SavedRule(name: "B", placement: .collapsed),
            "never": SavedRule(name: "C", placement: .hidden),
        ]
        let running: Set<String> = ["always", "fold", "never", "new", "self"]
        let closed = VisibilityPlan(rules: rules, expanded: false, running: running, ownID: "self")
        XCTAssertEqual(closed.hidden, ["fold", "never"])
        XCTAssertEqual(closed.allowed, ["always", "new", "self"])
        let open = VisibilityPlan(rules: rules, expanded: true, running: running, ownID: "self")
        XCTAssertEqual(open.hidden, ["never"])
        XCTAssertTrue(open.allowed.contains("fold"))
    }

    func testOwnEntryCannotBeHiddenAndOfflineRuleDoesNotActivateAssertion() {
        let rules = ["self": SavedRule(name: "Self", placement: .hidden), "offline": SavedRule(name: "Offline", placement: .hidden)]
        let plan = VisibilityPlan(rules: rules, expanded: false, running: ["self", "new"], ownID: "self")
        XCTAssertTrue(plan.hidden.isEmpty)
        XCTAssertTrue(plan.allowed.contains("self"))
        let relaunched = VisibilityPlan(rules: rules, expanded: false, running: ["offline"], ownID: "self")
        XCTAssertEqual(relaunched.hidden, ["offline"])
    }

    func testRulesSurviveReloadAndReturnToVisible() throws {
        let suite = "BarFoldTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RuleStore(defaults: defaults)
        let rules = ["app": SavedRule(name: "应用", placement: .hidden)]
        try store.save(rules)
        XCTAssertEqual(try RuleStore(defaults: defaults).load(), rules)
        try store.save([:])
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testInvalidConfigIsReportedWithoutOverwritingIt() throws {
        let suite = "BarFoldTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = Data("broken".utf8)
        defaults.set(data, forKey: "menuBarRules.v1")
        XCTAssertThrowsError(try RuleStore(defaults: defaults).load())
        XCTAssertEqual(defaults.data(forKey: "menuBarRules.v1"), data)
    }
}
