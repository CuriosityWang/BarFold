import Foundation

public enum AutoCollapseDelay: Int, Codable, CaseIterable, Sendable {
    case off = 0
    case seconds10 = 10
    case seconds15 = 15
    case seconds30 = 30

    public var title: String {
        switch self {
        case .off: "不自动收起"
        case .seconds10: "10 秒"
        case .seconds15: "15 秒"
        case .seconds30: "30 秒"
        }
    }

    public var seconds: TimeInterval? {
        self == .off ? nil : TimeInterval(rawValue)
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var autoCollapse: AutoCollapseDelay
    public var hotkeyEnabled: Bool

    public init(autoCollapse: AutoCollapseDelay = .off, hotkeyEnabled: Bool = false) {
        self.autoCollapse = autoCollapse
        self.hotkeyEnabled = hotkeyEnabled
    }
}

public struct PreferencesStore {
    private let defaults: UserDefaults
    private let key = "menuBarPreferences.v1"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> Preferences {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Preferences.self, from: data)
        else { return Preferences() }
        return decoded
    }

    public func save(_ preferences: Preferences) {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: key)
        }
    }
}

public enum AutoCollapsePolicy {
    public static func shouldSchedule(expanded: Bool, paused: Bool, delay: AutoCollapseDelay) -> Bool {
        expanded && !paused && delay != .off
    }

    public static func shouldDeferCollapse(settingsVisible: Bool, pointerInMenuBar: Bool) -> Bool {
        settingsVisible || pointerInMenuBar
    }
}
