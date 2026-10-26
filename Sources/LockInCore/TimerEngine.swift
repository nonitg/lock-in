import Foundation

public enum BreakKind: String, Codable, Sendable { case short, long }

public enum Phase: Equatable, Codable, Sendable {
    case idle
    case focus
    /// Focus finished; break is offered but waits for the user.
    case breakReady(BreakKind)
    case onBreak(BreakKind)
}

public enum TimerEvent: Equatable, Sendable {
    case focusEnded(Session)
    case breakEnded
}

/// Focus/break state machine. Wall-clock based (start dates, not tick counts) so it
/// survives sleep, relaunch and a stalled main thread. All time comes in as arguments.
public struct TimerEngine: Codable, Equatable, Sendable {
    public private(set) var phase: Phase = .idle
    public private(set) var intention = ""
    public private(set) var focusMode: Mode = .fixed
    public private(set) var segmentStartedAt: Date?
    /// Planned length of the current segment. nil = Flowtime count-up.
    public private(set) var target: TimeInterval?
    public private(set) var pendingBreak: TimeInterval = 0
    public private(set) var completedInCycle = 0
    /// Set while running "keep going" minutes after a finished block; holds the break that was offered.
    public private(set) var extensionOf: BreakKind?
    private var accumulated: TimeInterval = 0
    private var runningSince: Date?

    public init() {}

    public var isRunning: Bool { runningSince != nil }
    public var isOnBreak: Bool { if case .onBreak = phase { true } else { false } }
    public var isPaused: Bool { !isRunning && (phase == .focus || isOnBreak) }

    public func elapsed(at now: Date) -> TimeInterval {
        accumulated + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    public func remaining(at now: Date) -> TimeInterval? {
        target.map { max(0, $0 - elapsed(at: now)) }
    }

    // MARK: Focus

    public mutating func startFocus(intention: String, settings: FocusSettings, now: Date) {
        phase = .focus
        self.intention = intention.trimmingCharacters(in: .whitespacesAndNewlines)
        focusMode = settings.mode
        extensionOf = nil
        target = settings.mode == .fixed ? settings.minutes(settings.focusMinutes) : nil
        begin(now)
    }

    /// After a finished block: work a few more minutes before the offered break.
    public mutating func keepGoing(for seconds: TimeInterval, now: Date) {
        guard case .breakReady(let kind) = phase else { return }
        phase = .focus
        extensionOf = kind
        target = seconds
        begin(now)
    }

    public mutating func extend(by seconds: TimeInterval) {
        guard phase == .focus, let t = target else { return }
        target = t + seconds
    }

    /// User ends focus. Flowtime: a real block, break scales with it. Fixed (or < 1 min): partial, no break.
    public mutating func stopFocus(now: Date, settings: FocusSettings) -> TimerEvent? {
        guard phase == .focus else { return nil }
        let worked = elapsed(at: now)
        if let kind = extensionOf {
            return .focusEnded(endFocus(now: now, worked: worked, completed: false, next: .breakReady(kind)))
        }
        if focusMode == .flow && worked >= settings.minutes(1) {
            let breakMinutes = max(settings.minFlowBreakMinutes,
                                   Int((worked / settings.secondsPerMinute / Double(settings.flowBreakDivisor)).rounded()))
            pendingBreak = settings.minutes(breakMinutes)
            return .focusEnded(endFocus(now: now, worked: worked, completed: true, next: .breakReady(.short)))
        }
        return .focusEnded(endFocus(now: now, worked: worked, completed: false, next: .idle))
    }

    // MARK: Pause

    /// `at` may be in the past (idle detection rewinds to the last input).
    public mutating func pause(at time: Date) {
        guard let since = runningSince else { return }
        accumulated += max(0, time.timeIntervalSince(since))
        runningSince = nil
    }

    public mutating func resume(now: Date) {
        guard !isRunning, phase == .focus || isOnBreak else { return }
        runningSince = now
    }

    // MARK: Break

    public mutating func startBreak(now: Date) {
        guard case .breakReady(let kind) = phase else { return }
        phase = .onBreak(kind)
        extensionOf = nil
        target = pendingBreak
        begin(now)
    }

    public mutating func skipBreak() {
        switch phase {
        case .breakReady(let kind), .onBreak(let kind): finishBreak(kind)
        default: return
        }
    }

    /// Advances to the next phase when the running countdown hits zero.
    public mutating func tick(now: Date, settings: FocusSettings) -> TimerEvent? {
        guard isRunning, let left = remaining(at: now), left <= 0 else { return nil }
        switch phase {
        case .focus:
            let worked = target ?? elapsed(at: now)
            if let kind = extensionOf {
                return .focusEnded(endFocus(now: now, worked: worked, completed: false, next: .breakReady(kind)))
            }
            completedInCycle += 1
            let long = completedInCycle >= settings.longBreakEvery
            pendingBreak = settings.minutes(long ? settings.longBreakMinutes : settings.shortBreakMinutes)
            return .focusEnded(endFocus(now: now, worked: worked, completed: true, next: .breakReady(long ? .long : .short)))
        case .onBreak(let kind):
            finishBreak(kind)
            return .breakEnded
        default:
            return nil
        }
    }

    // MARK: Helpers

    private mutating func begin(_ now: Date) {
        segmentStartedAt = now
        accumulated = 0
        runningSince = now
    }

    private mutating func endFocus(now: Date, worked: TimeInterval, completed: Bool, next: Phase) -> Session {
        let session = Session(start: segmentStartedAt ?? now, end: now, focusedSeconds: worked,
                              intention: intention, completed: completed)
        phase = next
        extensionOf = nil
        stopClock()
        return session
    }

    private mutating func finishBreak(_ kind: BreakKind) {
        if kind == .long { completedInCycle = 0 }
        phase = .idle
        extensionOf = nil
        stopClock()
    }

    private mutating func stopClock() {
        runningSince = nil
        accumulated = 0
        target = nil
        segmentStartedAt = nil
    }
}
