import AppKit
import LockInCore
import SwiftUI

struct PopoverView: View {
    @Bindable var c: FocusController
    let close: () -> Void
    @State private var showSettings = false
    @FocusState private var intentionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            current
            Divider()
            today
            DisclosureGroup("Settings", isExpanded: $showSettings) {
                SettingsView(c: c).padding(.top, 8)
            }
            footer
        }
        .padding(16)
        .frame(width: 310)
    }

    // MARK: Phase views

    @ViewBuilder private var current: some View {
        switch c.engine.phase {
        case .idle:
            VStack(alignment: .leading, spacing: 10) {
                Text("One thing for this block?").font(.headline)
                TextField("e.g. ship the onboarding PR", text: $c.draftIntention)
                    .textFieldStyle(.roundedBorder)
                    .focused($intentionFocused)
                    .onSubmit { act { c.start() } }
                HStack {
                    Picker("Mode", selection: c.binding(\.mode)) {
                        Text("\(c.settings.focusMinutes) min").tag(Mode.fixed)
                        Text("Flow").tag(Mode.flow)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help("Timer: fixed blocks with set breaks. Flow: count up, break scales with focus.")
                    Spacer()
                    Button("Start") { act { c.start() } }.keyboardShortcut(.defaultAction)
                }
            }
            .onAppear { DispatchQueue.main.async { intentionFocused = true } }

        case .focus:
            VStack(alignment: .leading, spacing: 10) {
                header(c.engine.intention.isEmpty ? "Focus" : c.engine.intention,
                       subtitle: c.idlePausedAt != nil ? "Paused while you were away" : (c.engine.isPaused ? "Paused" : nil))
                HStack {
                    Button(c.engine.isRunning ? "Pause" : "Resume") { c.pauseResume() }
                    if c.engine.target != nil { Button("+5 min") { c.extend() } }
                    Spacer()
                    Button(c.engine.focusMode == .flow ? "Done · break" : "End") { c.stopFocus() }
                }
            }

        case .breakReady(let kind):
            VStack(alignment: .leading, spacing: 10) {
                header("Block done", subtitle: "\(kind == .long ? "Long" : "Short") break · \(FocusController.duration(c.engine.pendingBreak))")
                HStack {
                    Button("Start break") { act { c.startBreak() } }.keyboardShortcut(.defaultAction)
                    Button("+5 min") { c.extend() }
                    Spacer()
                    Button("Skip") { c.skipBreak() }
                }
            }

        case .onBreak:
            VStack(alignment: .leading, spacing: 10) {
                header("Break", subtitle: c.engine.isPaused ? "Paused" : "Step away from the screen")
                HStack {
                    Button(c.engine.isRunning ? "Pause" : "Resume") { c.pauseResume() }
                    Spacer()
                    Button("Skip break") { c.skipBreak() }
                }
            }
        }
    }

    private func header(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(c.timeText.isEmpty ? " " : c.timeText)
                .font(.system(size: 34, weight: .light, design: .rounded).monospacedDigit())
            Text(title).font(.headline).lineLimit(2)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }
    }

    // MARK: Stats

    private var today: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today").font(.caption).foregroundStyle(.secondary)
                Text("\(FocusController.duration(c.todaySeconds)) · \(c.todayBlocks) block\(c.todayBlocks == 1 ? "" : "s")")
                    .font(.callout.monospacedDigit())
            }
            Spacer()
            WeekBars(values: c.stats.dailyTotals(days: 7, endingOn: c.now).map(\.seconds))
        }
    }

    private var footer: some View {
        HStack {
            Button("Parking lot\(c.parkedCount > 0 ? " (\(c.parkedCount))" : "")") { act { c.openParkingLot() } }
            Spacer()
            Text("⌃⌥F go · ⌃⌥P park").font(.caption2).foregroundStyle(.tertiary)
            Button("Quit") { c.quit() }
        }
        .buttonStyle(.borderless)
    }

    /// Run, close, and hand keyboard focus back to the app you came from.
    private func act(_ action: () -> Void) {
        action()
        close()
        NSApp.hide(nil)
    }
}

private struct WeekBars: View {
    let values: [TimeInterval]

    var body: some View {
        let top = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(values.indices, id: \.self) { i in
                Capsule()
                    .fill(i == values.count - 1 ? Color.accentColor : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: max(2, 26 * values[i] / top))
            }
        }
        .frame(height: 26, alignment: .bottom)
        .help("Last 7 days")
    }
}

private struct SettingsView: View {
    let c: FocusController
    @State private var apps = ""
    @State private var sites = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper("Focus \(c.settings.focusMinutes) min", value: c.binding(\.focusMinutes), in: 5...180, step: 5)
            Stepper("Short break \(c.settings.shortBreakMinutes) min", value: c.binding(\.shortBreakMinutes), in: 1...60)
            Stepper("Long break \(c.settings.longBreakMinutes) min", value: c.binding(\.longBreakMinutes), in: 5...90, step: 5)
            Stepper("Long break every \(c.settings.longBreakEvery) blocks", value: c.binding(\.longBreakEvery), in: 2...8)
            Toggle("Start breaks automatically", isOn: c.binding(\.autoStartBreaks))
            Toggle("Dim screens on break", isOn: c.binding(\.breakOverlayEnabled))
            Toggle("Pause when away \(c.settings.idleMinutes) min", isOn: c.binding(\.idlePauseEnabled))

            Divider()
            Toggle("Block distractions during focus", isOn: c.binding(\.blockingEnabled))
            labeled("Apps") {
                TextField("Slack, Discord", text: $apps, axis: .vertical)
                    .lineLimit(1...3)
                    .onChange(of: apps) { c.update { $0.blockedApps = Blocklist.parseList(apps) } }
            }
            labeled("Sites in Arc") {
                TextField("x.com, youtube.com", text: $sites, axis: .vertical)
                    .lineLimit(1...4)
                    .onChange(of: sites) { c.update { $0.blockedSites = Blocklist.parseList(sites) } }
            }

            Divider()
            Toggle("Do Not Disturb during focus", isOn: c.binding(\.autoDoNotDisturb))
            if c.settings.autoDoNotDisturb && !c.dndShortcutsInstalled {
                Text("One-time setup: in Shortcuts, make “\(FocusModeBridge.onShortcut)” (Set Focus: Do Not Disturb on) and “\(FocusModeBridge.offShortcut)” (turn it off).")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Open Shortcuts") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")) }
            }
            Picker("Sound", selection: c.binding(\.sound)) {
                ForEach(Notifier.systemSounds, id: \.self) { Text($0) }
            }
            Toggle("Open at login", isOn: c.binding(\.launchAtLogin))
        }
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
        .onAppear {
            apps = c.settings.blockedApps.joined(separator: ", ")
            sites = c.settings.blockedSites.joined(separator: ", ")
        }
    }

    private func labeled(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}
