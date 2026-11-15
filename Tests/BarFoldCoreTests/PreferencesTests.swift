import XCTest
@testable import BarFoldCore

final class PreferencesTests: XCTestCase {
    func testPreferencesDefaultToDisabledAutoCollapseAndNoHotkey() {
        let suite = "BarFoldPrefsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return XCTFail("Missing suite") }
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PreferencesStore(defaults: defaults)
        let loaded = store.load()
        XCTAssertEqual(loaded.autoCollapse, .off)
        XCTAssertFalse(loaded.hotkeyEnabled)
    }

    func testPreferencesPersistAutoCollapseAndHotkeyAcrossReload() {
        let suite = "BarFoldPrefsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return XCTFail("Missing suite") }
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PreferencesStore(defaults: defaults)
        let updated = Preferences(autoCollapse: .seconds15, hotkeyEnabled: true)
        store.save(updated)

        XCTAssertEqual(PreferencesStore(defaults: defaults).load(), updated)
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
