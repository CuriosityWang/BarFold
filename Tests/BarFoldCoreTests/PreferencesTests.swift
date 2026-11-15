import XCTest
@testable import BarFoldCore

final class PreferencesTests: XCTestCase {
    func testPreferencesDefaultToDisabledAutoCollapse() {
        let suite = "BarFoldPrefsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return XCTFail("Missing suite") }
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PreferencesStore(defaults: defaults)
        let loaded = store.load()
        XCTAssertEqual(loaded.autoCollapse, .off)
    }

    func testPreferencesPersistAutoCollapseAcrossReload() {
        let suite = "BarFoldPrefsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return XCTFail("Missing suite") }
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PreferencesStore(defaults: defaults)
        let updated = Preferences(autoCollapse: .seconds15)
        store.save(updated)

        XCTAssertEqual(PreferencesStore(defaults: defaults).load(), updated)
    }

    func testLegacyPreferencesPreserveAutoCollapseAndDropRemovedField() throws {
        let suite = "BarFoldPrefsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"autoCollapse":15,"hotkeyEnabled":true}"#.utf8), forKey: "menuBarPreferences.v1")

        let store = PreferencesStore(defaults: defaults)
        let loaded = store.load()
        XCTAssertEqual(loaded.autoCollapse, .seconds15)
        store.save(loaded)
        let saved = try XCTUnwrap(defaults.data(forKey: "menuBarPreferences.v1"))
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), ["autoCollapse"])
    }

    func testAutoCollapseShouldHoldOnlyWhenExpandedAndPanelOpenOrPointerInMenuBar() {
        XCTAssertFalse(AutoCollapsePolicy.shouldSchedule(expanded: false, paused: false, delay: .seconds15))
        XCTAssertFalse(AutoCollapsePolicy.shouldSchedule(expanded: true, paused: true, delay: .seconds15))
        XCTAssertFalse(AutoCollapsePolicy.shouldSchedule(expanded: true, paused: false, delay: .off))
        XCTAssertTrue(AutoCollapsePolicy.shouldSchedule(expanded: true, paused: false, delay: .seconds10))

        XCTAssertTrue(AutoCollapsePolicy.shouldDeferCollapse(settingsVisible: true, pointerInMenuBar: false))
        XCTAssertTrue(AutoCollapsePolicy.shouldDeferCollapse(settingsVisible: false, pointerInMenuBar: true))
        XCTAssertFalse(AutoCollapsePolicy.shouldDeferCollapse(settingsVisible: false, pointerInMenuBar: false))
    }
}
