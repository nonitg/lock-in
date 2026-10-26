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
        if announce { onBlocked?(app.localizedName ?? "App") }
    }
}

/// Redirects blocked sites in Arc's active tab. Polls only while Arc is frontmost during focus.
final class ArcBlocker {
    static let bundleID = "company.thebrowser.Browser"

    var onBlocked: ((String) -> Void)?
    var onPermissionDenied: (() -> Void)?
    var redirectURL: ((String) -> String?)?
    private var domains: [String] = []
    private var observer: NSObjectProtocol?
    private var poller: Timer?
    private var warnedAboutPermission = false
    private lazy var readURL: NSAppleScript? = {
        let script = NSAppleScript(source: "tell application id \"\(Self.bundleID)\" to return URL of active tab of front window")
        script?.compileAndReturnError(nil)
        return script
    }()

    func setActive(_ on: Bool, domains: [String]) {
        self.domains = domains
        if on, observer == nil {
            observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.updatePolling() }
            updatePolling()
        } else if !on {
            if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
            observer = nil
            stopPolling()
        }
    }

    private var arcIsFront: Bool { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.bundleID }

    private func updatePolling() {
        guard arcIsFront else { return stopPolling() }
        check()
        guard poller == nil else { return }
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.check() }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        poller = t
    }

    private func stopPolling() {
        poller?.invalidate()
        poller = nil
    }

    private func check() {
        guard arcIsFront, let readURL else { return stopPolling() }
        var error: NSDictionary?
        let result = readURL.executeAndReturnError(&error)
        if let error {
            // -1743: user hasn't allowed Automation for Arc yet.
            if (error[NSAppleScript.errorNumber] as? Int) == -1743, !warnedAboutPermission {
                warnedAboutPermission = true
                onPermissionDenied?()
            }
            return
        }
        guard let url = result.stringValue, let host = Blocklist.host(of: url),
              Blocklist.isBlocked(host: host, domains: domains),
              let target = redirectURL?(host) else { return }
        let escaped = target.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        NSAppleScript(source: "tell application id \"\(Self.bundleID)\" to set URL of active tab of front window to \"\(escaped)\"")?
            .executeAndReturnError(nil)
        onBlocked?(host)
    }
}
