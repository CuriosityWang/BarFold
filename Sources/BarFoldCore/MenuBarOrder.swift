import Foundation
import CoreGraphics

public struct MenuBarItemFrame: Equatable, Sendable {
    public let bundleID: String
    public let frame: CGRect

    public init(bundleID: String, frame: CGRect) {
        self.bundleID = bundleID
        self.frame = frame
    }
}

public struct MenuBarMove: Equatable, Sendable {
    public let item: MenuBarItemFrame
    public let destination: CGPoint
}

public enum MenuBarOrder {
    public static func nextMove(items: [MenuBarItemFrame], rules: [String: SavedRule], ownID: String) -> MenuBarMove? {
        guard let anchor = items.first(where: { $0.bundleID == ownID }) else { return nil }
        let ordered = items.filter { $0.bundleID != ownID }.sorted { $0.frame.minX < $1.frame.minX }
        // Move the nearest misplaced item first to retain order within each group.
        if let item = ordered.last(where: {
            $0.frame.maxX <= anchor.frame.minX + 1 && (rules[$0.bundleID]?.placement ?? .visible) == .visible
        }) {
            return MenuBarMove(item: item, destination: CGPoint(x: anchor.frame.maxX - 2, y: anchor.frame.midY))
        }
        if let item = ordered.first(where: {
            $0.frame.minX >= anchor.frame.maxX - 1 && rules[$0.bundleID]?.placement == .collapsed
        }) {
            return MenuBarMove(item: item, destination: CGPoint(x: anchor.frame.minX + 2, y: anchor.frame.midY))
        }
        return nil
    }
}
