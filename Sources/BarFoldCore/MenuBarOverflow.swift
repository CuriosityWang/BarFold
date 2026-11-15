import CoreGraphics

public struct MenuBarOverflowControl: Equatable, Sendable {
    public let frame: CGRect
    public let isExpanded: Bool

    public init?(identifier: String, frame: CGRect) {
        switch identifier {
        case "menu-bar-overflow-indicator": isExpanded = false
        case "menu-bar-overflow-indicator-expanded": isExpanded = true
        default: return nil
        }
        self.frame = frame
    }

    public static func coalesced(_ controls: [Self]) -> [Self] {
        // These are candidate locations. Inventory hit-tests each location for its live state.
        var result: [Self] = []
        for control in controls {
            if let index = result.firstIndex(where: { $0.frame == control.frame }) {
                // macOS also exposes an inactive copy that always reports collapsed.
                if control.isExpanded { result[index] = control }
            } else {
                result.append(control)
            }
        }
        return result
    }
}
