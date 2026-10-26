import AppKit
import LockInCore

/// Menu bar item with a native NSMenu: opens instantly, fixed position, whole rows clickable.
/// Menu is rebuilt each time it opens; while open, the header and stats rows tick live.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let c: FocusController
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var headerItem: NSMenuItem?
    private var todayItem: NSMenuItem?
    private var shown = (symbol: "", title: "")

    init(controller: FocusController) {
        c = controller
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.imagePosition = .imageLeading
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    // MARK: Menu bar

    func refresh() {
        let e = c.engine
        let symbol: String
        switch e.phase {
        case .idle, .focus: symbol = e.isPaused ? "pause.circle" : "scope"
        case .breakReady: symbol = "cup.and.saucer"
        case .onBreak: symbol = e.isRunning ? "cup.and.saucer.fill" : "pause.circle"
        }
        let title = c.timeText.isEmpty ? "" : " " + c.timeText
        if (symbol, title) != shown, let button = item.button {
            if symbol != shown.symbol {
                button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Lock In")
                button.image?.isTemplate = true
            }
            button.title = title
            shown = (symbol, title)
        }
        // Live rows while the menu is open.
        if let headerItem { headerItem.attributedTitle = headerTitle() }
        if let todayItem { todayItem.attributedTitle = todayTitle() }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        c.menuWillOpen()
        build(menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        headerItem = nil
        todayItem = nil
    }

    private func build(_ menu: NSMenu) {
        menu.removeAllItems()
        let e = c.engine

        if e.phase != .idle {
            let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            header.attributedTitle = headerTitle()
            header.isEnabled = false
            menu.addItem(header)
            headerItem = header
        }

        switch e.phase {
        case .idle:
            menu.addItem(action("Start Focus…", key: "f") { $0.askIntention() })
            menu.addItem(.separator())
            menu.addItem(radio("Timer · \(c.settings.focusMinutes) min", on: c.settings.mode == .fixed) { $0.update { $0.mode = .fixed } })
            menu.addItem(radio("Flow · count up, break scales", on: c.settings.mode == .flow) { $0.update { $0.mode = .flow } })
        case .focus:
            menu.addItem(action(e.isRunning ? "Pause" : "Resume", key: "f") { $0.pauseResume() })
            if e.target != nil { menu.addItem(action("Add 5 Minutes") { $0.extend() }) }
            menu.addItem(action(e.focusMode == .flow && e.extensionOf == nil ? "Done · Take Break" : "End Focus", key: "b") { $0.stopFocus() })
        case .breakReady:
            menu.addItem(action("Start Break · \(FocusController.duration(e.pendingBreak))", key: "b") { $0.startBreak() })
            menu.addItem(action("Keep Going · +5m") { $0.extend() })
            menu.addItem(action("Skip Break") { $0.skipBreak() })
        case .onBreak:
            menu.addItem(action(e.isRunning ? "Pause Break" : "Resume Break", key: "f") { $0.pauseResume() })
            menu.addItem(action("Skip Break", key: "b") { $0.skipBreak() })
        }

        menu.addItem(.separator())
        let today = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        today.attributedTitle = todayTitle()
        today.isEnabled = false
        menu.addItem(today)
        todayItem = today

        menu.addItem(.separator())
        menu.addItem(action("Park a Thought…", key: "p") { $0.showParkingLot() })
        menu.addItem(action("Open Parking Lot\(c.parkedCount > 0 ? " (\(c.parkedCount))" : "")") { $0.openParkingLot() })

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settings.submenu = settingsMenu()
        menu.addItem(settings)
        let quit = action("Quit Lock In") { $0.quit() }
        quit.keyEquivalent = "q"
        quit.keyEquivalentModifierMask = .command
        menu.addItem(quit)
    }

    private func settingsMenu() -> NSMenu {
        let s = c.settings
        let m = NSMenu()
        m.autoenablesItems = false
        m.addItem(choices("Focus Length", s.focusMinutes, [25, 30, 45, 50, 60, 90], unit: "min") { v in { $0.focusMinutes = v } })
        m.addItem(choices("Short Break", s.shortBreakMinutes, [5, 10, 15], unit: "min") { v in { $0.shortBreakMinutes = v } })
        m.addItem(choices("Long Break", s.longBreakMinutes, [15, 20, 30], unit: "min") { v in { $0.longBreakMinutes = v } })
        m.addItem(choices("Long Break Every", s.longBreakEvery, [2, 3, 4], unit: "blocks") { v in { $0.longBreakEvery = v } })
        m.addItem(.separator())
        m.addItem(toggle("Start Breaks Automatically", \.autoStartBreaks))
        m.addItem(toggle("Dim Screens on Break", \.breakOverlayEnabled))
        m.addItem(toggle("Pause When Away (\(s.idleMinutes) min)", \.idlePauseEnabled))
        m.addItem(.separator())
        m.addItem(toggle("Hide Distracting Apps During Focus", \.blockingEnabled))
        m.addItem(action("Edit Blocked Apps…") { $0.editBlocklist() })
        m.addItem(toggle("Do Not Disturb During Focus", \.autoDoNotDisturb))
        if s.autoDoNotDisturb && !c.dndShortcutsInstalled {
            m.addItem(action("Set Up Do Not Disturb…") { _ in DNDSetup.show() })
        }
        let sound = NSMenuItem(title: "Sound: \(s.sound)", action: nil, keyEquivalent: "")
        sound.submenu = NSMenu()
        for name in Notifier.systemSounds {
            sound.submenu?.addItem(radio(name, on: name == s.sound) { $0.update { $0.sound = name } })
        }
        m.addItem(sound)
        m.addItem(.separator())
        m.addItem(toggle("Open at Login", \.launchAtLogin))
        return m
    }

    // MARK: Titles

    /// What you're on and when it ends. The countdown itself lives in the menu bar only.
    private func headerTitle() -> NSAttributedString {
        let e = c.engine
        let text: String
        switch e.phase {
        case .idle: text = ""
        case .focus:
            // Clipped so a long intention doesn't stretch the whole menu.
            let what = e.intention.isEmpty ? "Focus" : e.intention.count > 42 ? e.intention.prefix(40) + "…" : e.intention
            text = "\(what) · \(c.idlePausedAt != nil ? "paused while away" : timing(end: "ends"))"
        case .breakReady: text = "Block done · break when ready"
        case .onBreak(let kind): text = "\(kind == .long ? "Long break" : "Break") · \(timing(end: "back at"))"
        }
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: Self.menuFont.pointSize, weight: .semibold),
        ])
    }

    /// "ends 2:15 PM" for timed segments, "since 1:05 PM" for flow, "paused" when stopped.
    private func timing(end verb: String) -> String {
        let e = c.engine
        guard e.isRunning else { return "paused" }
        if let left = e.remaining(at: c.now) { return "\(verb) \(Self.clockTime.string(from: c.now + left))" }
        return "since \(Self.clockTime.string(from: c.now - e.elapsed(at: c.now)))"
    }

    private static let clockTime: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private static let menuFont = NSFont.menuFont(ofSize: 0)

    private func todayTitle() -> NSAttributedString {
        let blocks = c.todayBlocks
        let title = NSMutableAttributedString(
            string: "Today \(FocusController.duration(c.todaySeconds)) · \(blocks) block\(blocks == 1 ? "" : "s")   ",
            attributes: [.font: Self.menuFont])
        let chart = NSTextAttachment()
        chart.image = Self.weekBars(c.stats.dailyTotals(days: 7, endingOn: c.now).map(\.seconds))
        chart.bounds = NSRect(origin: .zero, size: chart.image!.size)
        title.append(NSAttributedString(attachment: chart))
        return title
    }

    /// Last 7 days as tiny bars, today solid. Empty days keep a stub so the week still reads as seven slots.
    static func weekBars(_ values: [Double]) -> NSImage {
        let bar: CGFloat = 4, gap: CGFloat = 3, height: CGFloat = 11
        let top = max(values.max() ?? 0, 1)
        let size = NSSize(width: CGFloat(values.count) * (bar + gap) - gap, height: height)
        return NSImage(size: size, flipped: false) { _ in
            for (i, v) in values.enumerated() {
                // Muted to sit with the row's dimmed text; today one step brighter.
                (i == values.count - 1 ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor).setFill()
                let h = max(2, (height * v / top).rounded())
                NSBezierPath(roundedRect: NSRect(x: CGFloat(i) * (bar + gap), y: 0, width: bar, height: h), xRadius: 1.5, yRadius: 1.5).fill()
            }
            return true
        }
    }

    // MARK: Item builders

    private func action(_ title: String, key: String = "", _ run: @escaping (FocusController) -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, keyEquivalent: key) { [weak c] in if let c { run(c) } }
        if !key.isEmpty { item.keyEquivalentModifierMask = [.control, .option] } // mirrors the global hotkeys
        return item
    }

    private func radio(_ title: String, on: Bool, _ run: @escaping (FocusController) -> Void) -> NSMenuItem {
        let item = action(title, run)
        item.state = on ? .on : .off
        return item
    }

    private func toggle(_ title: String, _ path: WritableKeyPath<FocusSettings, Bool>) -> NSMenuItem {
        radio(title, on: c.settings[keyPath: path]) { c in c.update { $0[keyPath: path].toggle() } }
    }

    private func choices(_ title: String, _ current: Int, _ options: [Int], unit: String,
                         _ change: @escaping (Int) -> (inout FocusSettings) -> Void) -> NSMenuItem {
        let parent = NSMenuItem(title: "\(title): \(current) \(unit)", action: nil, keyEquivalent: "")
        parent.submenu = NSMenu()
        for v in Set(options + [current]).sorted() {
            parent.submenu?.addItem(radio("\(v) \(unit)", on: v == current) { $0.update(change(v)) })
        }
        return parent
    }

    // MARK: Debug

    /// Debug: dumps current menu titles (as they'd render now) to menu.txt.
    func dumpMenu(to dir: URL) {
        let m = NSMenu()
        build(m)
        headerItem = nil
        todayItem = nil
        func lines(_ menu: NSMenu, _ depth: Int) -> [String] {
            menu.items.flatMap { i -> [String] in
                let mark = i.state == .on ? "✓ " : ""
                let key = i.keyEquivalent.isEmpty ? "" : "  [\(i.keyEquivalent)]"
                let me = i.isSeparatorItem ? ["\(String(repeating: "  ", count: depth))---"]
                    : ["\(String(repeating: "  ", count: depth))\(mark)\(i.title)\(key)\(i.isEnabled ? "" : "  (info)")"]
                return me + (i.submenu.map { lines($0, depth + 1) } ?? [])
            }
        }
        try? lines(m, 0).joined(separator: "\n").write(to: dir.appendingPathComponent("menu.txt"), atomically: true, encoding: .utf8)
    }

    static func writePNG(_ view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, keyEquivalent: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) { fatalError("unused") }

    @objc private func fire() { run() }
}

/// One-time guide for the two Shortcuts that toggle Do Not Disturb.
enum DNDSetup {
    @MainActor static func show() {
        let alert = NSAlert()
        alert.messageText = "Set up Do Not Disturb"
        alert.informativeText = """
        macOS doesn't let apps switch Focus directly, so Lock In runs two Shortcuts:

        1. In Shortcuts, create “\(FocusModeBridge.onShortcut)” with the action “Set Focus → Do Not Disturb → On”.
        2. Create “\(FocusModeBridge.offShortcut)” with “Set Focus → Do Not Disturb → Off”.

        Names must match exactly. Lock In picks them up next time you open the menu.
        """
        alert.addButton(withTitle: "Open Shortcuts")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
        }
    }
}
