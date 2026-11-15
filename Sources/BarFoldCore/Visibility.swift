import Foundation

public enum Placement: String, Codable, CaseIterable, Sendable {
    case visible, collapsed, hidden

    public var title: String {
        switch self {
        case .visible: "常驻显示"
        case .collapsed: "收起"
        case .hidden: "永久隐藏"
        }
    }

    public func isVisible(expanded: Bool) -> Bool {
        self == .visible || (self == .collapsed && expanded)
    }
}

public struct SavedRule: Codable, Equatable, Sendable {
    public var name: String
    public var placement: Placement

    public init(name: String, placement: Placement) {
        self.name = name
        self.placement = placement
    }
}

public struct VisibilityPlan: Equatable, Sendable {
    public let allowed: Set<String>
    public let hidden: Set<String>

    public init(rules: [String: SavedRule], expanded: Bool, running: Set<String>, ownID: String) {
        // Include every running app, even one whose status item has not appeared yet.
        hidden = Set(rules.compactMap { id, rule in
            id != ownID && running.contains(id) && !rule.placement.isVisible(expanded: expanded) ? id : nil
        })
        allowed = running.subtracting(hidden).union([ownID])
    }
}

public struct RuleStore {
    private let defaults: UserDefaults
    private let key = "menuBarRules.v1"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() throws -> [String: SavedRule] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return try JSONDecoder().decode([String: SavedRule].self, from: data)
    }

    public func save(_ rules: [String: SavedRule]) throws {
        defaults.set(try JSONEncoder().encode(rules), forKey: key)
    }
}
