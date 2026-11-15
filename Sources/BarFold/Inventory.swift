import AppKit
import ApplicationServices
import BarFoldCore

typealias MenuApp = MenuAppRow

enum InventoryError: Error { case permission, unavailable, unreadable }

enum AppBundleMetadata {
    static func localizedName(for bundleURL: URL) -> String {
        if let name = try? bundleURL.resourceValues(forKeys: [.localizedNameKey]).localizedName, !name.isEmpty {
            return name
        }
        return FileManager.default.displayName(atPath: bundleURL.path)
    }

    static func displayName(for app: NSRunningApplication, id: String) -> String {
        let inner = app.localizedName ?? app.bundleURL.map(localizedName(for:)) ?? id
        guard let url = app.bundleURL, let hostURL = AppIdentity.hostAppBundleURL(for: url) else {
            return AppIdentity.displayName(innerName: inner, hostName: nil)
        }
        return AppIdentity.displayName(innerName: inner, hostName: localizedName(for: hostURL))
    }

    static func displayName(forBundleIdentifier id: String, fallback: String) -> String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            return displayName(for: app, id: id)
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            return AppIdentity.displayName(innerName: fallback, hostName: nil)
        }
        let inner = localizedName(for: url)
        let hostName = AppIdentity.hostAppBundleURL(for: url).map(localizedName(for:))
        return AppIdentity.displayName(innerName: inner, hostName: hostName)
    }

    static func iconURL(forBundleIdentifier id: String) -> URL? {
        let url = NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        guard let url else { return nil }
        if let hostURL = AppIdentity.hostAppBundleURL(for: url),
           Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleIconFile") == nil,
           Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleIconName") == nil {
            return hostURL
        }
        return url
    }
}

actor MenuBarInventory {
    private func windows() throws -> (pid_t, [AXUIElement]) {
        guard AXIsProcessTrusted() else { throw InventoryError.permission }
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first else {
            throw InventoryError.unavailable
        }
        let agentPID = agent.processIdentifier
        let root = AXUIElementCreateApplication(agentPID)
        AXUIElementSetMessagingTimeout(root, 0.25)

        let windows: [AXUIElement]
        if let direct = attribute(root, kAXWindowsAttribute) as? [AXUIElement], !direct.isEmpty {
            windows = direct
        } else if let children = attribute(root, kAXChildrenAttribute) as? [AXUIElement] {
            windows = children.filter { attribute($0, kAXRoleAttribute) as? String == kAXWindowRole }
        } else {
            throw InventoryError.unreadable
        }

        return (agentPID, windows)
    }

    func scan(ownID: String) throws -> [DiscoveredApp] {
        let (agentPID, windows) = try windows()
        var counts: [String: Int] = [:]
        var names: [String: String] = [:]
        var pidCache: [pid_t: (id: String, name: String)?] = [:]
        var readWindow = false

        for window in windows {
            guard let groups = attribute(window, kAXChildrenAttribute) as? [AXUIElement] else { continue }
            readWindow = true
            var displayCounts: [String: Int] = [:]
            for group in groups {
                let children = attribute(group, kAXChildrenAttribute) as? [AXUIElement] ?? []
                // A group represents one status item. Custom views may have several children.
                for child in children {
                    var pid: pid_t = 0
                    AXUIElementGetPid(child, &pid)
                    guard pid > 0, pid != agentPID else { continue }
                    let resolved: (id: String, name: String)?
                    if let cached = pidCache[pid] {
                        resolved = cached
                    } else {
                        let entry: (id: String, name: String)?
                        if let app = NSRunningApplication(processIdentifier: pid),
                           let id = app.bundleIdentifier, id != ownID,
                           !(app.bundleURL?.path.hasPrefix("/System/Library/CoreServices/") ?? false) {
                            entry = (id, AppBundleMetadata.displayName(for: app, id: id))
                        } else {
                            entry = nil
                        }
                        pidCache[pid] = entry
                        resolved = entry
                    }
                    guard let resolved else { continue }
                    displayCounts[resolved.id, default: 0] += 1
                    names[resolved.id] = resolved.name
                    break
                }
            }
            for (id, count) in displayCounts { counts[id] = max(counts[id, default: 0], count) }
        }
        guard readWindow else { throw InventoryError.unreadable }
        return counts.map { DiscoveredApp(id: $0.key, name: names[$0.key] ?? $0.key, count: $0.value) }
    }

    func layout(ownID: String) throws -> [MenuBarItemFrame] {
        let (agentPID, windows) = try windows()
        let visibleWindows = visibleOverflowElements(in: windows).compactMap { element -> AXUIElement? in
            guard let value = attribute(element, kAXWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
        let orderedWindows = visibleWindows + windows.filter { window in
            !visibleWindows.contains(where: { CFEqual($0, window) })
        }
        for window in orderedWindows {
            var items: [MenuBarItemFrame] = []
            for group in attribute(window, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                guard let value = attribute(group, "AXFrame"), CFGetTypeID(value) == AXValueGetTypeID() else { continue }
                var frame = CGRect.zero
                guard AXValueGetValue(value as! AXValue, .cgRect, &frame), frame.width > 0, frame.height > 0 else { continue }
                for child in attribute(group, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                    var pid: pid_t = 0
                    AXUIElementGetPid(child, &pid)
                    guard pid > 0, pid != agentPID,
                          let app = NSRunningApplication(processIdentifier: pid), let id = app.bundleIdentifier,
                          !(app.bundleURL?.path.hasPrefix("/System/Library/CoreServices/") ?? false)
                    else { continue }
                    items.append(MenuBarItemFrame(bundleID: id, frame: frame))
                    break
                }
            }
            // The host exposes duplicate windows, including system-only ones.
            if items.contains(where: { $0.bundleID == ownID }) { return items }
        }
        throw InventoryError.unreadable
    }

    func overflowControls() throws -> [MenuBarOverflowControl] {
        let (_, windows) = try windows()
        return visibleOverflowElements(in: windows).compactMap { overflowControl(for: $0) }
    }

    private func visibleOverflowElements(in windows: [AXUIElement]) -> [AXUIElement] {
        let candidates = MenuBarOverflowControl.coalesced(windows.flatMap { overflowControls(in: $0) })
        let system = AXUIElementCreateSystemWide()
        return candidates.compactMap { candidate in
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(system, Float(candidate.frame.midX), Float(candidate.frame.midY), &hit) == .success,
                  let hit, overflowControl(for: hit) != nil else { return nil }
            return hit
        }
    }

    private func overflowControl(for element: AXUIElement) -> MenuBarOverflowControl? {
        guard let identifier = attribute(element, kAXIdentifierAttribute) as? String,
              identifier.hasPrefix("menu-bar-overflow-indicator"),
              let value = attribute(element, "AXFrame"), CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var frame = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &frame), frame.width > 0, frame.height > 0 else { return nil }
        return MenuBarOverflowControl(identifier: identifier, frame: frame)
    }

    private func overflowControls(in window: AXUIElement) -> [MenuBarOverflowControl] {
        var controls: [MenuBarOverflowControl] = []
        for group in attribute(window, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            let elements = [group] + (attribute(group, kAXChildrenAttribute) as? [AXUIElement] ?? [])
            for element in elements {
                if let control = overflowControl(for: element) { controls.append(control) }
            }
        }
        return controls
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
