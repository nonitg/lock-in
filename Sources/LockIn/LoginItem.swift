import Foundation
import ServiceManagement

/// Bundled LaunchAgent: starts at login, relaunches after a crash, stays quit after "Quit"
/// (KeepAlive only on unsuccessful exit).
enum LoginItem {
    private static let agent = SMAppService.agent(plistName: "com.nonit.lockin.agent.plist")

    static var isEnabled: Bool { agent.status == .enabled }
    static var needsApproval: Bool { agent.status == .requiresApproval }

    static func sync(enabled: Bool) {
        // Only register the installed copy, never a dev build in dist/.
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        do {
            if enabled, agent.status != .enabled { try agent.register() }
            if !enabled, agent.status == .enabled { try agent.unregister() }
        } catch {
            log.error("login item sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
