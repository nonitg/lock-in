import AppKit

/// Dims every screen at break start so you actually step away. Esc hides it; the break keeps running.
/// Plain AppKit; windows exist only during a break.
@MainActor
final class BreakOverlay {
    private unowned let controller: FocusController
    private var windows: [NSWindow] = []
    private var clocks: [NSTextField] = []
    private var parkedButtons: [NSButton] = []

    init(controller: FocusController) { self.controller = controller }

    func show() {
        guard windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .floating // above apps, below the menu bar so the timer stays visible
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.isOpaque = false
            w.backgroundColor = .clear
            w.isReleasedWhenClosed = false
            w.animationBehavior = .none
            w.onEscape = { [weak self] in self?.hide() }
            w.contentView = makeContent(size: screen.frame.size)
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            windows.append(w)
        }
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
    }

    func refresh() {
        guard !windows.isEmpty else { return }
        let time = controller.timeText
        clocks.forEach { if $0.stringValue != time { $0.stringValue = time } }
        let n = controller.parkedCount
        parkedButtons.forEach {
            $0.isHidden = n == 0
            $0.title = "\(n) parked thought\(n == 1 ? "" : "s") · open"
        }
    }

    func snapshot(to dir: URL) {
        guard let view = windows.first?.contentView else { return }
        StatusItemController.writePNG(view, to: dir.appendingPathComponent("overlay.png"))
    }

    func hide() {
        guard !windows.isEmpty else { return }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        clocks.removeAll()
        parkedButtons.removeAll()
        NSApp.hide(nil) // hand focus back to whatever you were using
    }

    private func makeContent(size: NSSize) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = .init(pointSize: 40, weight: .regular)
        icon.contentTintColor = .white

        let clock = label("", font: .monospacedDigitSystemFont(ofSize: 76, weight: .light))
        clocks.append(clock)
        let message = label("Stand up. Look far away. Drink some water.", font: .systemFont(ofSize: 20))
        message.alphaValue = 0.85

        let parked = NSButton(title: "", target: self, action: #selector(openParked))
        parked.isBordered = false
        parked.contentTintColor = .white
        parkedButtons.append(parked)

        let hide = NSButton(title: "Hide  (Esc)", target: self, action: #selector(hideTapped))
        let skip = NSButton(title: "Skip break", target: self, action: #selector(skipTapped))
        [hide, skip].forEach { $0.bezelStyle = .push; $0.controlSize = .large }
        let buttons = NSStackView(views: [hide, skip])
        buttons.spacing = 12

        let stack = NSStackView(views: [icon, clock, message, parked, buttons])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.setCustomSpacing(28, after: parked)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Layer-backed with a solid-color layer: no full-screen bitmap, and each tick redraws only the clock.
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true
        root.layerContentsRedrawPolicy = .never
        root.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        root.appearance = NSAppearance(named: .darkAqua)
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        return root
    }

    private func label(_ text: String, font: NSFont) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = font
        l.textColor = .white
        l.alignment = .center
        return l
    }

    @objc private func hideTapped() { hide() }
    @objc private func skipTapped() { controller.skipBreak() }
    @objc private func openParked() { controller.openParkingLot() }
}

private final class OverlayWindow: NSWindow {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}
