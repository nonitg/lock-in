import AppKit

/// Spotlight-style one-line capture. Doesn't activate the app, so you land right back where you were.
final class ParkingLotPanel: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    var onSave: ((String) -> Void)?
    private var panel: NSPanel?

    func show() {
        if let panel { return panel.makeKeyAndOrderFront(nil) }
        let size = NSSize(width: 480, height: 52)
        let p = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.delegate = self

        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .popover
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 12

        let field = NSTextField(frame: NSRect(x: 16, y: 12, width: size.width - 32, height: 28))
        field.placeholderString = "Park a thought… (Enter saves, Esc cancels)"
        field.font = .systemFont(ofSize: 18)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        bg.addSubview(field)
        p.contentView = bg

        let mouse = NSEvent.mouseLocation
        let screen = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main)?.visibleFrame ?? .zero
        p.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2, y: screen.maxY - screen.height * 0.25))
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(field)
        panel = p
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let text = (control as? NSTextField)?.stringValue ?? ""
            close()
            onSave?(text)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    private func close() {
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
