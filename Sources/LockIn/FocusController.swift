import AppKit
import LockInCore
import Observation
import os
import SwiftUI

let log = Logger(subsystem: "com.nonit.lockin", category: "app")

/// Owns the timer and keeps every side effect (blocking, DND, overlay, notifications) in sync with it.
@MainActor @Observable
final class FocusController {
    private(set) var engine: TimerEngine
    private(set) var settings: FocusSettings
    private(set) var now = Date()
    private(set) var parkedCount = 0
    /// Set when focus auto-paused because nobody was at the keyboard.
    private(set) var idlePausedAt: Date?
    private(set) var dndShortcutsInstalled = false
    var draftIntention = ""

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var requestPopover: (() -> Void)?
    @ObservationIgnored let stats: StatsStore
    @ObservationIgnored let parkingLot: ParkingLot
    @ObservationIgnored private let notifier = Notifier()
    @ObservationIgnored private let hud = HUD()
    @ObservationIgnored private let appBlocker = AppBlocker()
    @ObservationIgnored private let arcBlocker = ArcBlocker()
    @ObservationIgnored private let dnd = FocusModeBridge()
    @ObservationIgnored private lazy var overlay = BreakOverlay(controller: self)
    @ObservationIgnored private lazy var parkingPanel = ParkingLotPanel()
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var returnWatcher: Timer?
    @ObservationIgnored private var lastPhase: Phase = .idle

    init() {
        let dir = Storage.directory
        stats = StatsStore(url: dir.appendingPathComponent("sessions.jsonl"))
        parkingLot = ParkingLot(url: dir.appendingPathComponent("parking-lot.md"))
        settings = Storage.load(FocusSettings.self, key: Storage.settingsKey) ?? FocusSettings()
        engine = Storage.load(TimerEngine.self, key: Storage.engineKey) ?? TimerEngine()
        let debugScale = UserDefaults.standard.double(forKey: "debugSecondsPerMinute")
        if debugScale > 0 { settings.secondsPerMinute = debugScale }
        parkedCount = parkingLot.openCount()
        lastPhase = engine.phase

        notifier.onAction = { [weak self] action in self?.handle(action) }
        appBlocker.onBlocked = { [weak self] name in self?.hud.show("\(name) blocked · \(self?.timeText ?? "")") }
        arcBlocker.onBlocked = { [weak self] host in self?.hud.show("\(host) blocked · \(self?.timeText ?? "")") }
        arcBlocker.onPermissionDenied = { [weak self] in
            self?.hud.show("Allow Lock In to control Arc: System Settings › Privacy › Automation", seconds: 5)
        }
        arcBlocker.redirectURL = { [weak self] host in self?.blockedPageURL(host: host) }
        parkingPanel.onSave = { [weak self] text in self?.park(text) }
        dnd.onInstalledChange = { [weak self] installed in self?.dndShortcutsInstalled = installed }
        if settings.autoDoNotDisturb { dnd.refreshInstalled() }

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.autoPause(at: Date()) }
        }

        // Catch up on anything that finished while the app wasn't running.
        tick()
        sync(force: true)
    }

    // MARK: Display

    var timeText: String {
        switch engine.phase {
        case .idle: return ""
        case .breakReady: return "Break"
        case .focus, .onBreak:
            return Self.clock(engine.remaining(at: now) ?? engine.elapsed(at: now))
        }
    }

    var todaySeconds: TimeInterval { stats.focusedSeconds(on: now) + liveFocusSeconds }
    var todayBlocks: Int { stats.completedBlocks(on: now) }

    /// Focus time of the block in progress, so "today" moves while you work.
    private var liveFocusSeconds: TimeInterval { engine.phase == .focus ? engine.elapsed(at: now) : 0 }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds / 60)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    // MARK: Actions

    /// ⌃⌥F: the one key that always moves you forward.
    func primaryAction() {
        switch engine.phase {
        case .idle: requestPopover?()
        case .focus, .onBreak: pauseResume()
        case .breakReady: startBreak()
        }
    }

    /// ⌃⌥B
    func breakAction() {
        switch engine.phase {
        case .focus: stopFocus()
        case .breakReady: startBreak()
        case .onBreak: skipBreak()
        case .idle: break
        }
    }

    func start(intention: String? = nil) {
        engine.startFocus(intention: intention ?? draftIntention, settings: settings, now: Date())
        draftIntention = ""
        sync()
    }

    func pauseResume() {
        if engine.isRunning { engine.pause(at: Date()) } else { engine.resume(now: Date()) }
        idlePausedAt = nil
        stopReturnWatch()
        sync()
    }

    func extend() {
        if case .breakReady = engine.phase {
            engine.keepGoing(for: settings.minutes(5), now: Date())
        } else {
            engine.extend(by: settings.minutes(5))
        }
        sync()
    }

    func stopFocus() {
        if let event = engine.stopFocus(now: Date(), settings: settings) { handle(event) }
        idlePausedAt = nil
        sync()
    }

    func startBreak() {
        engine.startBreak(now: Date())
        sync()
    }

    func skipBreak() {
        engine.skipBreak()
        sync()
    }

    func hideOverlay() { overlay.hide() }

    func showParkingLot() { parkingPanel.show() }

    func openParkingLot() {
        if !FileManager.default.fileExists(atPath: parkingLot.url.path) { try? parkingLot.append("(parking lot created)") }
        NSWorkspace.shared.open(parkingLot.url)
    }

    func update(_ change: (inout FocusSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        let old = settings
        settings = next
        Storage.save(settings, key: Storage.settingsKey)
        if old.launchAtLogin != next.launchAtLogin { LoginItem.sync(enabled: next.launchAtLogin) }
        if old.sound != next.sound { notifier.play(next.sound) }
        if !old.autoDoNotDisturb && next.autoDoNotDisturb { dnd.refreshInstalled() }
        sync()
    }

    func binding<T>(_ path: WritableKeyPath<FocusSettings, T>) -> Binding<T> {
        Binding(get: { self.settings[keyPath: path] }, set: { value in self.update { $0[keyPath: path] = value } })
    }

    func quit() {
        if engine.phase == .focus, settings.autoDoNotDisturb { dnd.set(false) }
        Storage.save(engine, key: Storage.engineKey)
        NSApp.terminate(nil)
    }

    func handle(url: URL) {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let param = { (name: String) in query.first { $0.name == name }?.value }
        switch url.host() {
        case "start": start(intention: param("intent") ?? "")
        case "toggle": primaryAction()
        case "stop": stopFocus()
        case "break": breakAction()
        case "skip": skipBreak()
        case "extend": extend()
        case "park": param("text").map(park)
        case "show": requestPopover?()
        case "quit": quit()
        default: log.error("unknown url \(url.absoluteString, privacy: .public)")
        }
    }

    // MARK: Engine plumbing

    private func tick() {
        now = Date()
        if let event = engine.tick(now: now, settings: settings) {
            handle(event)
            sync()
        } else {
            checkIdle()
        }
        onChange?()
    }

    private func handle(_ event: TimerEvent) {
        switch event {
        case .focusEnded(let session):
            stats.append(session)
            guard case .breakReady = engine.phase else { return }
            notifier.play(settings.sound)
            if settings.autoStartBreaks {
                engine.startBreak(now: Date())
            } else {
                // Give the DND shortcut a moment to switch off so the banner isn't swallowed.
                notifyAfterDND(.focusDone, title: "Focus complete", body: "Break when ready · \(Self.duration(engine.pendingBreak)).")
            }
        case .breakEnded:
            notifier.play(settings.sound)
            notifier.post(.breakDone, title: "Break over", body: "Ready for the next block?")
        }
    }

    private func handle(_ action: Notifier.Action) {
        switch action {
        case .startBreak: startBreak()
        case .extend: extend()
        case .startFocus: requestPopover?()
        case .resume: if engine.isPaused { pauseResume() }
        }
    }

    private func notifyAfterDND(_ kind: Notifier.Kind, title: String, body: String) {
        let delay = settings.autoDoNotDisturb ? 1.5 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [notifier] in
            notifier.post(kind, title: title, body: body)
        }
    }

    /// Reconciles blockers, DND, overlay, ticker and persistence with the engine state.
    private func sync(force: Bool = false) {
        now = Date()
        let phase = engine.phase
        let focusing = phase == .focus && engine.isRunning
        let blocking = focusing && settings.blockingEnabled

        appBlocker.setActive(blocking, apps: settings.blockedApps)
        arcBlocker.setActive(blocking, domains: settings.blockedSites)

        let wasFocus = lastPhase == .focus, isFocus = phase == .focus
        if settings.autoDoNotDisturb, force ? isFocus : wasFocus != isFocus { dnd.set(isFocus) }

        if engine.isOnBreak {
            if !isBreak(lastPhase), settings.breakOverlayEnabled { overlay.show() }
        } else {
            overlay.hide()
        }

        if phase != lastPhase { parkedCount = parkingLot.openCount() }
        lastPhase = phase
        updateTicker()
        Storage.save(engine, key: Storage.engineKey)
        log.info("phase=\(String(describing: phase), privacy: .public) running=\(self.engine.isRunning, privacy: .public) time=\(self.timeText, privacy: .public)")
        onChange?()
    }

    private func isBreak(_ phase: Phase) -> Bool { if case .onBreak = phase { true } else { false } }

    /// 1 Hz only while a clock is running; nothing scheduled when idle or paused.
    private func updateTicker() {
        if engine.isRunning, ticker == nil {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            t.tolerance = 0.2
            RunLoop.main.add(t, forMode: .common)
            ticker = t
        } else if !engine.isRunning {
            ticker?.invalidate()
            ticker = nil
        }
    }

    // MARK: Idle

    private func checkIdle() {
        guard settings.idlePauseEnabled, engine.phase == .focus, engine.isRunning else { return }
        let idle = IdleClock.secondsSinceInput()
        guard idle >= settings.minutes(settings.idleMinutes) else { return }
        autoPause(at: Date().addingTimeInterval(-idle))
    }

    private func autoPause(at time: Date) {
        guard settings.idlePauseEnabled, engine.phase == .focus, engine.isRunning else { return }
        engine.pause(at: time)
        idlePausedAt = time
        sync()
        startReturnWatch()
    }

    private func startReturnWatch() {
        stopReturnWatch()
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, IdleClock.secondsSinceInput() < 4 else { return }
                self.stopReturnWatch()
                let away = Self.duration(Date().timeIntervalSince(self.idlePausedAt ?? Date()))
                self.notifier.post(.idleBack, title: "Welcome back", body: "Focus paused while you were away (\(away)). Resume?")
            }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        returnWatcher = t
    }

    private func stopReturnWatch() {
        returnWatcher?.invalidate()
        returnWatcher = nil
    }

    // MARK: Parking lot

    private func park(_ text: String) {
        do {
            try parkingLot.append(text)
            parkedCount = parkingLot.openCount()
            hud.show("Parked · back to it")
        } catch {
            hud.show("Couldn't save: \(error.localizedDescription)")
        }
    }

    // MARK: Blocked page

    private func blockedPageURL(host: String) -> String? {
        guard let page = Bundle.main.url(forResource: "blocked", withExtension: "html"),
              var c = URLComponents(url: page, resolvingAgainstBaseURL: false) else { return nil }
        var items = [URLQueryItem(name: "site", value: host), URLQueryItem(name: "intent", value: engine.intention)]
        if let left = engine.remaining(at: Date()) {
            items.append(URLQueryItem(name: "until", value: String(Int(Date().addingTimeInterval(left).timeIntervalSince1970))))
        }
        c.queryItems = items
        return c.url?.absoluteString
    }
}

enum IdleClock {
    static func secondsSinceInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}

enum Storage {
    static let settingsKey = "settings.v1"
    static let engineKey = "engine.v1"

    static let directory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LockIn", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
}
