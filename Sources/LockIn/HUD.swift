import AppKit

/// Small transient toast under the menu bar. Never takes focus or clicks.
final class HUD {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ text: String, seconds: Double = 1.8) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 32, height: 34)

        let panel = self.panel ?? Self.makePanel()
        self.panel = panel
        let content = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        content.material = .hudWindow
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = size.height / 2
        content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true
        label.frame.origin = NSPoint(x: 16, y: (size.height - label.frame.height) / 2)
        content.addSubview(label)
        panel.contentView = content

        let screen = NSScreen.underMouse
        let frame = screen?.frame ?? .zero, visible = screen?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: (frame.midX - size.width / 2).rounded(), y: visible.maxY - size.height - 12,
                              width: size.width, height: size.height), display: true)
        panel.invalidateShadow()
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let panel = self?.panel else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 }) {
                // A newer toast may have reused the panel mid-fade.
                guard panel.alphaValue == 0 else { return }
                panel.orderOut(nil)
                if self?.panel === panel { self?.panel = nil }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private static func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return p
    }
}

extension NSScreen {
    /// The screen you're looking at: wherever the pointer is.
    static var underMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(mouse) } ?? main
    }
}
