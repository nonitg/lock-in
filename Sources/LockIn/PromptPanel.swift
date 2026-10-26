import AppKit

/// Spotlight-style one-line input at a fixed spot near the top of the screen.
/// Non-activating, so Enter/Esc drops you straight back into the app you were using.
@MainActor
final class PromptPanel: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    private var panel: NSPanel?
    private var field: NSTextField?
    private var onSubmit: ((String) -> Void)?

    func show(placeholder: String, onSubmit: @escaping (String) -> Void) {
        close()
        self.onSubmit = onSubmit
        let size = NSSize(width: 560, height: 56)
        let p = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.animationBehavior = .none
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.delegate = self

        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .popover
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 12
        bg.layer?.masksToBounds = true

        let f = NSTextField(frame: NSRect(x: 18, y: 14, width: size.width - 36, height: 28))
        f.placeholderString = placeholder
        f.font = .systemFont(ofSize: 19)
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.delegate = self
        bg.addSubview(f)
        p.contentView = bg

        // Fixed spot: horizontally centered, a fifth of the way down the screen under the mouse.
        let mouse = NSEvent.mouseLocation
        let screen = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main)?.visibleFrame ?? .zero
        p.setFrameOrigin(NSPoint(x: (screen.midX - size.width / 2).rounded(),
                                 y: (screen.maxY - screen.height * 0.2 - size.height).rounded()))
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(f)
        panel = p
        field = f
    }

    func snapshot(to dir: URL) {
        guard let view = panel?.contentView else { return }
        StatusItemController.writePNG(view, to: dir.appendingPathComponent("prompt.png"))
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let text = field?.stringValue ?? ""
            let submit = onSubmit
            close()
            submit?(text)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }

    /// Clicking elsewhere dismisses, like Spotlight.
    func windowDidResignKey(_ notification: Notification) { close() }

    private func close() {
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        field = nil
        onSubmit = nil
    }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
