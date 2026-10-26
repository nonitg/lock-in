import Foundation

public enum Blocklist {
    /// Matches by visible app name or bundle id, case-insensitive.
    public static func isBlocked(appName: String?, bundleID: String?, list: [String]) -> Bool {
        let candidates = [appName, bundleID].compactMap { $0?.lowercased() }
        return list.contains { entry in
            let e = entry.trimmingCharacters(in: .whitespaces).lowercased()
            return !e.isEmpty && candidates.contains(e)
        }
    }
}

/// Plain-text list of apps to hide during focus, edited in any text editor. Read at the start of each block.
public final class BlocklistFile {
    public let url: URL
    public private(set) var apps: [String] = []

    public static let defaultText = """
    # Lock In: apps hidden during focus blocks. One app name per line, as shown in the Dock.
    # Lines starting with # are ignored. Changes apply from the next focus block.

    Slack
    Discord
    Messages
    Mail

    """

    public init(url: URL) {
        self.url = url
        reload()
    }

    public func reload() {
        apps = Self.parse((try? String(contentsOf: url, encoding: .utf8)) ?? Self.defaultText)
    }

    /// Writes the default file on first use so there's something to edit.
    public func ensureExists() -> URL {
        if !FileManager.default.fileExists(atPath: url.path) { try? Self.defaultText.write(to: url, atomically: true, encoding: .utf8) }
        return url
    }

    public static func parse(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}
