import Foundation

/// macOS has no public API to toggle Focus, so we run two user-made Shortcuts.
final class FocusModeBridge {
    static let onShortcut = "LockIn Focus On"
    static let offShortcut = "LockIn Focus Off"

    private(set) var installed = false
    var onInstalledChange: ((Bool) -> Void)?

    func refreshInstalled() {
        run(["list"]) { [weak self] output in
            guard let self else { return }
            let names = Set(output.split(separator: "\n").map(String.init))
            installed = names.contains(Self.onShortcut) && names.contains(Self.offShortcut)
            onInstalledChange?(installed)
        }
    }

    func set(_ on: Bool) {
        guard installed else { return }
        run(["run", on ? Self.onShortcut : Self.offShortcut]) { _ in }
    }

    private func run(_ args: [String], completion: @escaping (String) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        DispatchQueue.global(qos: .utility).async {
            do { try process.run() } catch {
                log.error("shortcuts failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            // Drain before waiting so a long `list` can't fill the pipe and deadlock.
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            DispatchQueue.main.async { completion(output) }
        }
    }
}
