import AppKit
import Carbon.HIToolbox
import LockInCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: FocusController!
    private var statusItem: StatusItemController!
    private let hotKeys = HotKeys()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Login agent and a manual launch can race; keep exactly one instance.
        let me = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != me.processIdentifier }
        if !others.isEmpty { exit(0) }

        controller = FocusController()
        statusItem = StatusItemController(controller: controller)
        controller.onChange = { [weak self] in self?.statusItem.refresh() }
        controller.requestPopover = { [weak self] in self?.statusItem.showPopover() }
        statusItem.refresh()

        let mods = controlKey | optionKey
        hotKeys.register(keyCode: kVK_ANSI_F, modifiers: mods) { [weak self] in self?.controller.primaryAction() }
        hotKeys.register(keyCode: kVK_ANSI_B, modifiers: mods) { [weak self] in self?.controller.breakAction() }
        hotKeys.register(keyCode: kVK_ANSI_P, modifiers: mods) { [weak self] in self?.controller.showParkingLot() }

        LoginItem.sync(enabled: controller.settings.launchAtLogin)
    }

    /// lockin://start?intent=…, toggle, stop, break, skip, extend, park?text=…, show, quit
    /// Handy for Raycast/Shortcuts and for scripted testing.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { controller?.handle(url: url) }
    }
}
