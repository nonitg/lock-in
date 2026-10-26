import AppKit
import LockInCore
import os
import UniformTypeIdentifiers

let log = Logger(subsystem: "com.nonit.lockin", category: "app")

/// Owns the timer and keeps every side effect (blocking, DND, overlay, notifications) in sync with it.
@MainActor
final class FocusController {
    private(set) var engine: TimerEngine
    private(set) var settings: FocusSettings
    private(set) var now = Date()
    private(set) var parkedCount = 0
    /// Set when focus auto-paused because nobody was at the keyboard.
    private(set) var idlePausedAt: Date?
    private(set) var dndShortcutsInstalled = false

    /// UI refresh hook (menu bar title, open menu, overlay).
    var onChange: (() -> Void)?
    /// Debug hook so the menu can dump its items alongside overlay/prompt PNGs.
    var onSnapshot: ((URL) -> Void)?
    let stats: StatsStore
    let parkingLot: ParkingLot
    let blocklist: BlocklistFile
    private let notifier = Notifier()
    private let hud = HUD()
    private let appBlocker = AppBlocker()
    private let dnd = FocusModeBridge()
    private lazy var overlay = BreakOverlay(controller: self)
    private let prompt = PromptPanel()
    private var ticker: Timer?
    private var returnWatcher: Timer?
    private var lastPhase: Phase = .idle

    init() {
        let dir = Storage.directory
        stats = StatsStore(url: dir.appendingPathComponent("sessions.jsonl"))
        parkingLot = ParkingLot(url: dir.appendingPathComponent("parking-lot.md"))
        blocklist = BlocklistFile(url: dir.appendingPathComponent("blocklist.txt"))
        settings = Storage.load(FocusSettings.self, key: Storage.settingsKey) ?? FocusSettings()
        engine = Storage.load(TimerEngine.self, key: Storage.engineKey) ?? TimerEngine()
        let debugScale = UserDefaults.standard.double(forKey: "debugSecondsPerMinute")
        if debugScale > 0 { settings.secondsPerMinute = debugScale }
        parkedCount = parkingLot.openCount()
        lastPhase = engine.phase

        notifier.onAction = { [weak self] action in self?.handle(action) }
        appBlocker.onBlocked = { [weak self] name in self?.blocked(name) }
        dnd.onInstalledChange = { [weak self] installed in self?.dndShortcutsInstalled = installed }
        if settings.autoDoNotDisturb { dnd.refreshInstalled() }

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
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
        case .focus, .onBreak: return Self.clock(engine.remaining(at: now) ?? engine.elapsed(at: now))
        }
    }

    var todaySeconds: TimeInterval { stats.focusedSeconds(on: now) + (engine.phase == .focus ? engine.elapsed(at: now) : 0) }
    var todayBlocks: Int { stats.completedBlocks(on: now) }

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
        case .idle: askIntention()
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

    func askIntention() {
        let mode = settings.mode == .fixed ? "\(settings.focusMinutes) min" : "Flow"
        prompt.show(symbol: "scope", placeholder: "What's the one thing for this block?", hint: "\(mode)  ↩") { [weak self] text in
            self?.start(intention: text)
        }
    }

    func start(intention: String) {
        engine.startFocus(intention: intention, settings: settings, now: Date())
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

    func showParkingLot() {
        prompt.show(symbol: "tray.and.arrow.down", placeholder: "Park a thought for later", hint: "Save  ↩") { [weak self] text in self?.park(text) }
    }

    func openParkingLot() {
        openAsText(parkingLot.ensureExists())
    }

    func editBlocklist() { openAsText(blocklist.ensureExists()) }

    /// Plain-text editor (TextEdit unless changed), not whatever claims .md — often Xcode.
    private func openAsText(_ url: URL) {
        guard let editor = NSWorkspace.shared.urlForApplication(toOpen: .plainText) else { NSWorkspace.shared.open(url); return }
        NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Cheap refreshes worth doing when the user looks at the menu.
    func menuWillOpen() {
        parkedCount = parkingLot.openCount()
        if settings.autoDoNotDisturb && !dndShortcutsInstalled { dnd.refreshInstalled() }
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

    func quit() {
        if engine.phase == .focus, settings.autoDoNotDisturb { dnd.set(false) }
        Storage.save(engine, key: Storage.engineKey)
        NSApp.terminate(nil)
    }

    /// lockin://start?intent=…, ask, toggle, stop, break, skip, extend, park?text=…, quit, snapshot?dir=…
    /// Handy for Raycast/Shortcuts and for scripted testing.
    func handle(url: URL) {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let param = { (name: String) in query.first { $0.name == name }?.value }
        switch url.host() {
        case "start": start(intention: param("intent") ?? "")
        case "ask": askIntention()
        case "toggle": primaryAction()
        case "stop": stopFocus()
        case "break": breakAction()
        case "skip": skipBreak()
        case "extend": extend()
        case "park": param("text").map(park)
        case "quit": quit()
        case "snapshot":
            let dir = URL(fileURLWithPath: param("dir") ?? NSTemporaryDirectory())
            overlay.snapshot(to: dir)
            prompt.snapshot(to: dir)
            onSnapshot?(dir)
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
        if engine.isOnBreak { overlay.refresh() }
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
        case .startFocus: askIntention()
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
        let blocking = phase == .focus && engine.isRunning && settings.blockingEnabled

        if blocking && lastPhase != .focus { blocklist.reload() }
        appBlocker.setActive(blocking, apps: blocklist.apps)

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
            RunLoop.main.add(t, forMode: .common) // keeps counting while the menu is open
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

    private func blocked(_ what: String) {
        log.info("blocked \(what, privacy: .public)")
        hud.show("\(what) blocked · \(timeText) left")
    }

    // MARK: Parking lot

    private func park(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try parkingLot.append(text)
            parkedCount = parkingLot.openCount()
            hud.show("Parked · back to it")
            onChange?()
        } catch {
            hud.show("Couldn't save: \(error.localizedDescription)")
        }
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
