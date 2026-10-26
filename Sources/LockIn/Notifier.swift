import AppKit
import UserNotifications

/// Banners with action buttons. Sound is played separately so it's audible even under Do Not Disturb.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    enum Kind: String { case focusDone, breakDone }
    enum Action: String { case startBreak, extend, startFocus }

    var onAction: ((Action) -> Void)?
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        center.setNotificationCategories([
            category(.focusDone, [(.startBreak, "Start break"), (.extend, "+5 min")]),
            category(.breakDone, [(.startFocus, "Start focus")]),
        ])
        center.requestAuthorization(options: [.alert]) { _, _ in }
    }

    func post(_ kind: Kind, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = kind.rawValue
        // Same id per kind: a new banner replaces the stale one instead of stacking.
        center.add(UNNotificationRequest(identifier: kind.rawValue, content: content, trigger: nil))
    }

    func play(_ sound: String) {
        NSSound(named: NSSound.Name(sound))?.play()
    }

    static let systemSounds: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return files.map { ($0 as NSString).deletingPathExtension }.sorted()
    }()

    private func category(_ kind: Kind, _ actions: [(Action, String)]) -> UNNotificationCategory {
        UNNotificationCategory(identifier: kind.rawValue,
                               actions: actions.map { UNNotificationAction(identifier: $0.0.rawValue, title: $0.1) },
                               intentIdentifiers: [])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = Action(rawValue: response.actionIdentifier)
        DispatchQueue.main.async { [weak self] in
            if let action { self?.onAction?(action) }
            completionHandler()
        }
    }
}
