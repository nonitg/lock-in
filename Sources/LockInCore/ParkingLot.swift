import Foundation

/// Markdown checklist of thoughts parked mid-focus, reviewed on break.
public struct ParkingLot: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func append(_ text: String, at date: Date = Date()) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let stamp = Self.stampFormatter.string(from: date)
        let line = Data("- [ ] \(stamp) \(trimmed)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try (Data("# Parking lot\n\n".utf8) + line).write(to: url)
        }
    }

    /// Unchecked items.
    public func openCount() -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return text.split(separator: "\n").filter { $0.hasPrefix("- [ ]") }.count
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}
