import AppKit
import LockInCore

/// Hides blocked apps the moment they come to the front during focus. No permissions needed.
final class AppBlocker {
    var onBlocked: ((String) -> Void)?
    private var apps: [String] = []
    private var observer: NSObjectProtocol?

    func setActive(_ on: Bool, apps: [String]) {
        self.apps = apps
        if on, observer == nil {
            observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.blockIfNeeded(app, announce: true)
            }
            // Blocked apps already open in the background get tucked away quietly.
            NSWorkspace.shared.runningApplications.forEach { blockIfNeeded($0, announce: $0.isActive) }
        } else if !on, let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    private func blockIfNeeded(_ app: NSRunningApplication, announce: Bool) {
        guard app.activationPolicy == .regular,
              Blocklist.isBlocked(appName: app.localizedName, bundleID: app.bundleIdentifier, list: apps) else { return }
        app.hide()
        // A just-launched app can put its first window up after our hide; catch it once more.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { if !app.isHidden { app.hide() } }
        if announce { onBlocked?(app.localizedName ?? "App") }
    }
}
