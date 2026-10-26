import AppKit
import SwiftUI

/// Plain AppKit status item. The SwiftUI popover is built on open and released on close to keep RAM low.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let controller: FocusController
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var popover: NSPopover?
    private var shown = (symbol: "", title: "")

    init(controller: FocusController) {
        self.controller = controller
        super.init()
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.imagePosition = .imageLeading
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    func refresh() {
        let e = controller.engine
        let symbol: String
        switch e.phase {
        case .idle: symbol = "scope"
        case .focus: symbol = e.isRunning ? "scope" : "pause.circle"
        case .breakReady: symbol = "cup.and.saucer"
        case .onBreak: symbol = e.isRunning ? "cup.and.saucer.fill" : "pause.circle"
        }
        let title = controller.timeText.isEmpty ? "" : " " + controller.timeText
        guard (symbol, title) != shown, let button = item.button else { return }
        if symbol != shown.symbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Lock In")
            button.image?.isTemplate = true
        }
        button.title = title
        shown = (symbol, title)
    }

    @objc private func toggle() {
        if let popover, popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    func showPopover() {
        guard let button = item.button else { return }
        if popover?.isShown == true { return }
        let p = NSPopover()
        p.behavior = .transient
        p.animates = false
        p.delegate = self
        p.contentViewController = NSHostingController(rootView: PopoverView(c: controller, close: { [weak self] in
            self?.popover?.performClose(nil)
        }))
        popover = p
        // Accessory apps must activate for the text field to take typing.
        NSApp.activate(ignoringOtherApps: true)
        p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func popoverDidClose(_ notification: Notification) {
        popover?.contentViewController = nil
        popover = nil
    }
}
