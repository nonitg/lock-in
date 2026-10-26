import Foundation

public enum Blocklist {
    /// "https://www.YouTube.com/feed" -> "youtube.com"
    public static func normalize(_ entry: String) -> String {
        var s = entry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        return stripWWW(s)
    }

    public static func host(of urlString: String) -> String? {
        URL(string: urlString)?.host()?.lowercased()
    }

    /// Blocks the domain and all its subdomains.
    public static func isBlocked(host: String, domains: [String]) -> Bool {
        let h = stripWWW(host.lowercased())
        return domains.map(normalize).contains { d in !d.isEmpty && (h == d || h.hasSuffix("." + d)) }
    }

    /// Matches by visible app name or bundle id, case-insensitive.
    public static func isBlocked(appName: String?, bundleID: String?, list: [String]) -> Bool {
        let candidates = [appName, bundleID].compactMap { $0?.lowercased() }
        return list.contains { entry in
            let e = entry.trimmingCharacters(in: .whitespaces).lowercased()
            return !e.isEmpty && candidates.contains(e)
        }
    }

    /// "Slack, Discord\nMail" -> ["Slack", "Discord", "Mail"]
    public static func parseList(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func stripWWW(_ s: String) -> String {
        s.hasPrefix("www.") ? String(s.dropFirst(4)) : s
    }
}
