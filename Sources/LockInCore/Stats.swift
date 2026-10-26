import Foundation

public struct Session: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var focusedSeconds: TimeInterval
    public var intention: String
    /// Counts as a finished block (vs. ended early or "keep going" overtime).
    public var completed: Bool

    public init(start: Date, end: Date, focusedSeconds: TimeInterval, intention: String, completed: Bool) {
        self.start = start
        self.end = end
        self.focusedSeconds = focusedSeconds
        self.intention = intention
        self.completed = completed
    }
}

/// Append-only JSON Lines log of focus sessions. Only recent days stay in memory.
public final class StatsStore {
    public private(set) var sessions: [Session] = []
    private let url: URL
    private static let keepDays = 14

    public init(url: URL, now: Date = Date()) {
        self.url = url
        guard let data = try? Data(contentsOf: url) else { return }
        let cutoff = now.addingTimeInterval(-Double(Self.keepDays) * 86_400)
        let decoder = Self.decoder
        sessions = data.split(separator: UInt8(ascii: "\n"))
            .compactMap { try? decoder.decode(Session.self, from: Data($0)) }
            .filter { $0.end >= cutoff }
    }

    public func append(_ session: Session) {
        sessions.append(session)
        guard var line = try? Self.encoder.encode(session) else { return }
        line.append(UInt8(ascii: "\n"))
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url)
        }
    }

    public func focusedSeconds(on day: Date, calendar: Calendar = .current) -> TimeInterval {
        sessions.filter { calendar.isDate($0.end, inSameDayAs: day) }.reduce(0) { $0 + $1.focusedSeconds }
    }

    public func completedBlocks(on day: Date, calendar: Calendar = .current) -> Int {
        sessions.filter { $0.completed && calendar.isDate($0.end, inSameDayAs: day) }.count
    }

    /// Oldest first, ending with `day`.
    public func dailyTotals(days: Int, endingOn day: Date, calendar: Calendar = .current) -> [(day: Date, seconds: TimeInterval)] {
        (0..<days).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: day).map { ($0, focusedSeconds(on: $0, calendar: calendar)) }
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .sortedKeys
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
