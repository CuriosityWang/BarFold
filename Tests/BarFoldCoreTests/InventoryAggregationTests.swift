import XCTest
@testable import BarFoldCore

final class InventoryAggregationTests: XCTestCase {
    func testExcludesProhibitedProcessesFromEligibleBundleIdentifiers() {
        let candidates: [(bundleID: String?, isProhibited: Bool)] = [
            ("com.apple.Safari", false),
            ("com.apple.Safari.SandboxBroker", true),
            ("com.electron.lark.helper", false),
            (nil, false),
        ]
        XCTAssertEqual(
            ProcessEligibility.eligibleBundleIDs(from: candidates),
            ["com.apple.Safari", "com.electron.lark.helper"]
        )
    }

    func testMergesDiscoveredKnownAndSavedRulesAndRemovesOfflineRulesWhenReset() {
        let discovered = [
            DiscoveredApp(id: "live.visible", name: "Live Visible", count: 2),
        ]
        let known: [String: DiscoveredApp] = [
            "live.visible": DiscoveredApp(id: "live.visible", name: "Live Visible", count: 2),
            "live.hidden": DiscoveredApp(id: "live.hidden", name: "Live Hidden", count: 1),
            "quit.stale": DiscoveredApp(id: "quit.stale", name: "Quit Stale", count: 1),
        ]
        let rules: [String: SavedRule] = [
            "live.hidden": SavedRule(name: "Old Saved Name", placement: .hidden),
            "offline.saved": SavedRule(name: "Offline App", placement: .collapsed),
        ]
        let running: Set<String> = ["live.visible", "live.hidden"]

        let rows = InventoryCatalog.buildRows(
            known: known,
            discovered: discovered,
            rules: rules,
            running: running,
            nameResolver: { id, fallback in id == "offline.saved" ? "Resolved Offline" : fallback }
        )

        // quit.stale is not running and has no saved rule -> omitted!
        XCTAssertEqual(rows.map(\.id), ["live.hidden", "live.visible", "offline.saved"])
        XCTAssertEqual(rows.first(where: { $0.id == "live.visible" })?.count, 2)
        XCTAssertEqual(rows.first(where: { $0.id == "live.hidden" })?.running, true)
        XCTAssertEqual(rows.first(where: { $0.id == "offline.saved" })?.name, "Resolved Offline")
        XCTAssertEqual(rows.first(where: { $0.id == "offline.saved" })?.running, false)
    }
}
