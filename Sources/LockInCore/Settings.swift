import Foundation

public enum Mode: String, Codable, Sendable, CaseIterable {
    /// Classic Pomodoro: fixed focus length, fixed breaks.
    case fixed
    /// Flowtime: count up until you stop, break scales with focus time.
    case flow
}

public struct FocusSettings: Codable, Equatable, Sendable {
    public var mode: Mode = .fixed
    public var focusMinutes = 50
    public var shortBreakMinutes = 10
    public var longBreakMinutes = 20
    public var longBreakEvery = 3
    /// Flowtime break = focus time / divisor.
    public var flowBreakDivisor = 5
    public var minFlowBreakMinutes = 3
    public var autoStartBreaks = false

    public var blockingEnabled = true
    public var blockedApps = ["Slack", "Discord", "Messages", "Mail"]
    public var blockedSites = ["x.com", "twitter.com", "youtube.com", "reddit.com", "news.ycombinator.com", "instagram.com"]

    public var autoDoNotDisturb = false
    public var idlePauseEnabled = true
    public var idleMinutes = 5
    public var breakOverlayEnabled = true
    public var launchAtLogin = true
    public var sound = "Glass"

    /// Debug only: shrink a "minute" so a whole cycle can be tested fast. Never persisted.
    public var secondsPerMinute: Double = 60

    public init() {}

    public func minutes(_ m: Int) -> TimeInterval { Double(m) * secondsPerMinute }

    private enum CodingKeys: String, CodingKey {
        case mode, focusMinutes, shortBreakMinutes, longBreakMinutes, longBreakEvery
        case flowBreakDivisor, minFlowBreakMinutes, autoStartBreaks
        case blockingEnabled, blockedApps, blockedSites
        case autoDoNotDisturb, idlePauseEnabled, idleMinutes, breakOverlayEnabled, launchAtLogin, sound
    }

    // Tolerant decode so settings saved by older builds keep working when fields are added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FocusSettings()
        func v<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? fallback }
        mode = v(.mode, d.mode)
        focusMinutes = v(.focusMinutes, d.focusMinutes)
        shortBreakMinutes = v(.shortBreakMinutes, d.shortBreakMinutes)
        longBreakMinutes = v(.longBreakMinutes, d.longBreakMinutes)
        longBreakEvery = v(.longBreakEvery, d.longBreakEvery)
        flowBreakDivisor = v(.flowBreakDivisor, d.flowBreakDivisor)
        minFlowBreakMinutes = v(.minFlowBreakMinutes, d.minFlowBreakMinutes)
        autoStartBreaks = v(.autoStartBreaks, d.autoStartBreaks)
        blockingEnabled = v(.blockingEnabled, d.blockingEnabled)
        blockedApps = v(.blockedApps, d.blockedApps)
        blockedSites = v(.blockedSites, d.blockedSites)
        autoDoNotDisturb = v(.autoDoNotDisturb, d.autoDoNotDisturb)
        idlePauseEnabled = v(.idlePauseEnabled, d.idlePauseEnabled)
        idleMinutes = v(.idleMinutes, d.idleMinutes)
        breakOverlayEnabled = v(.breakOverlayEnabled, d.breakOverlayEnabled)
        launchAtLogin = v(.launchAtLogin, d.launchAtLogin)
        sound = v(.sound, d.sound)
    }
}
