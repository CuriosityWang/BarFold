import Foundation

public struct DiscoveredApp: Equatable, Sendable {
    public let id: String
    public let name: String
    public let count: Int

    public init(id: String, name: String, count: Int) {
        self.id = id
        self.name = name
        self.count = count
    }
}

public struct MenuAppRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let count: Int
    public let running: Bool

    public init(id: String, name: String, count: Int, running: Bool) {
        self.id = id
        self.name = name
        self.count = count
        self.running = running
    }
}

public enum ProcessEligibility {
    public static func eligibleBundleIDs(from processes: [(bundleID: String?, isProhibited: Bool)]) -> Set<String> {
        var ids = Set<String>()
        ids.reserveCapacity(processes.count)
        for process in processes where !process.isProhibited {
            if let id = process.bundleID { ids.insert(id) }
        }
        return ids
    }
}

public enum InventoryCatalog {
    public static func buildRows(
        known: [String: DiscoveredApp],
        discovered: [DiscoveredApp],
        rules: [String: SavedRule],
        running: Set<String>,
        nameResolver: (String, String) -> String = { _, fallback in fallback }
    ) -> [MenuAppRow] {
        var merged = known
        for item in discovered { merged[item.id] = item }

        var result: [String: MenuAppRow] = [:]
        for (id, item) in merged where running.contains(id) || rules[id] != nil {
            result[id] = MenuAppRow(
                id: id,
                name: nameResolver(id, item.name),
                count: item.count,
                running: running.contains(id)
            )
        }
        for (id, rule) in rules where result[id] == nil {
            result[id] = MenuAppRow(
                id: id,
                name: nameResolver(id, rule.name),
                count: 1,
                running: running.contains(id)
            )
        }
        return result.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
