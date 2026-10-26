import AppKit

/// Spotlight-style one-line input at a fixed spot near the top of the screen.
/// Non-activating, so Enter/Esc drops you straight back into the app you were using.
@MainActor
final class PromptPanel: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    private var panel: NSPanel?
    private var field: NSTextField?
    private var onSubmit: ((String) -> Void)?

    /// `hint` sits right-aligned in secondary text, e.g. "50 min ↩".
    func show(symbol: String, placeholder: String, hint: String, onSubmit: @escaping (String) -> Void) {
        close()
        self.onSubmit = onSubmit
        let size = NSSize(width: 600, height: 56)
        let inset: CGFloat = 18
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
        bg.layer?.cornerRadius = 16
        bg.layer?.cornerCurve = .continuous
        bg.layer?.masksToBounds = true
        bg.layer?.borderWidth = 1
        bg.effectiveAppearance.performAsCurrentDrawingAppearance {
            bg.layer?.borderColor = NSColor.separatorColor.cgColor
        }

        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = .init(pointSize: 18, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor
        icon.frame = NSRect(x: inset, y: 0, width: 24, height: size.height)

        let tail = NSTextField(labelWithString: hint)
        tail.font = .systemFont(ofSize: 13, weight: .medium)
        tail.textColor = .tertiaryLabelColor
        tail.sizeToFit()
        tail.frame.origin = NSPoint(x: size.width - inset - tail.frame.width, y: ((size.height - tail.frame.height) / 2).rounded())

        let f = NSTextField(string: "")
        f.placeholderString = placeholder
        f.font = .systemFont(ofSize: 20)
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.usesSingleLineMode = true
        f.delegate = self
        // Center on the text's line height, not an arbitrary frame, so the caret sits on the optical midline.
        let lineHeight = f.cell?.cellSize.height ?? 26
        let fieldX = icon.frame.maxX + 10
        f.frame = NSRect(x: fieldX, y: ((size.height - lineHeight) / 2).rounded(),
                         width: tail.frame.minX - 12 - fieldX, height: lineHeight)

        [icon, f, tail].forEach(bg.addSubview)
        p.contentView = bg

        // Spotlight's spot: centered on the full screen width, a fifth of the way down the screen under the mouse.
        let screen = NSScreen.underMouse
        let frame = screen?.frame ?? .zero, visible = screen?.visibleFrame ?? .zero
        p.setFrameOrigin(NSPoint(x: (frame.midX - size.width / 2).rounded(),
                                 y: (visible.maxY - frame.height * 0.2 - size.height).rounded()))
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
