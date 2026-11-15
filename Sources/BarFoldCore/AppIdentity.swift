import Foundation

public enum AppIdentity {
    public static func hostAppBundleURL(for bundleURL: URL) -> URL? {
        let components = bundleURL.standardizedFileURL.pathComponents
        guard let outerIndex = components.firstIndex(where: { $0.hasSuffix(".app") }),
              outerIndex + 1 < components.count,
              components[outerIndex + 1] == "Contents"
        else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: Array(components.prefix(outerIndex + 1))))
    }

    public static func displayName(innerName: String, hostName: String?) -> String {
        let inner = stripAppSuffix(innerName).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawHost = hostName else { return inner }
        let host = stripAppSuffix(rawHost).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return inner }
        if host.caseInsensitiveCompare(inner) == .orderedSame { return host }
        if inner.lowercased().hasPrefix(host.lowercased()) {
            let remainder = inner.dropFirst(host.count)
            let boundaryChars = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—·"))
            if let first = remainder.unicodeScalars.first, boundaryChars.contains(first) {
                let suffix = remainder.trimmingCharacters(in: boundaryChars)
                return suffix.isEmpty ? host : "\(host) (\(suffix))"
            }
        }
        return "\(host) (\(inner))"
    }

    private static func stripAppSuffix(_ name: String) -> String {
        name.lowercased().hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

public enum LaunchPolicy {
    public static func shouldOpenSettingsOnLaunch(canConfigure: Bool, hasSavedRules: Bool) -> Bool {
        !canConfigure || !hasSavedRules
    }
}
