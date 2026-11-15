import XCTest
@testable import BarFoldCore

final class AppIdentityTests: XCTestCase {
    func testExtractsHostAppBundleURLOnlyForNestedContentsBundles() {
        let larkHelper = URL(fileURLWithPath: "/Applications/Lark.app/Contents/Frameworks/Lark Framework.framework/Versions/147.0/Helpers/Lark Helper.app")
        XCTAssertEqual(AppIdentity.hostAppBundleURL(for: larkHelper), URL(fileURLWithPath: "/Applications/Lark.app"))

        let weatherMenu = URL(fileURLWithPath: "/System/Applications/Weather.app/Contents/Library/LoginItems/WeatherMenu.app")
        XCTAssertEqual(AppIdentity.hostAppBundleURL(for: weatherMenu), URL(fileURLWithPath: "/System/Applications/Weather.app"))

        let standalone = URL(fileURLWithPath: "/Applications/Trae CN.app")
        XCTAssertNil(AppIdentity.hostAppBundleURL(for: standalone))

        let nonBundleDirectory = URL(fileURLWithPath: "/Volumes/Apps.app/Standalone.app")
        XCTAssertNil(AppIdentity.hostAppBundleURL(for: nonBundleDirectory))
    }

    func testFormatsDisplayNameWithHostAppWithoutRedundantPrefix() {
        XCTAssertEqual(
            AppIdentity.displayName(innerName: "Lark Helper", hostName: "Feishu"),
            "Feishu (Lark Helper)"
        )
        XCTAssertEqual(
            AppIdentity.displayName(innerName: "Microsoft Defender Helper", hostName: "Microsoft Defender"),
            "Microsoft Defender (Helper)"
        )
        XCTAssertEqual(
            AppIdentity.displayName(innerName: "Microsoft Defender", hostName: "Microsoft Defender"),
            "Microsoft Defender"
        )
        XCTAssertEqual(
            AppIdentity.displayName(innerName: "WeatherMenu.app", hostName: "Weather"),
            "Weather (WeatherMenu)"
        )
        XCTAssertEqual(
            AppIdentity.displayName(innerName: "TRAE CN.app", hostName: nil),
            "TRAE CN"
        )
    }

    func testOpensSettingsOnLaunchOnlyWhenUnconfiguredOrEmpty() {
        XCTAssertFalse(LaunchPolicy.shouldOpenSettingsOnLaunch(canConfigure: true, hasSavedRules: true))
        XCTAssertTrue(LaunchPolicy.shouldOpenSettingsOnLaunch(canConfigure: true, hasSavedRules: false))
        XCTAssertTrue(LaunchPolicy.shouldOpenSettingsOnLaunch(canConfigure: false, hasSavedRules: true))
        XCTAssertTrue(LaunchPolicy.shouldOpenSettingsOnLaunch(canConfigure: false, hasSavedRules: false))
    }
}
