import AppKit
import SwiftUI

/// Dims every screen at break start so you actually step away. Esc hides it; the break keeps running.
@MainActor
final class BreakOverlay {
    private weak var controller: FocusController?
    private var windows: [NSWindow] = []

    init(controller: FocusController) { self.controller = controller }

    func show() {
        guard let controller, windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .floating // above apps, below the menu bar so the timer stays visible
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.isOpaque = false
            w.backgroundColor = .clear
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: BreakOverlayView(c: controller))
            w.alphaValue = 0
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            w.animator().alphaValue = 1
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
    }

    func hide() {
        guard !windows.isEmpty else { return }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        NSApp.hide(nil) // hand focus back to whatever you were using
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private struct BreakOverlayView: View {
    let c: FocusController

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 40))
                Text(c.timeText)
                    .font(.system(size: 72, weight: .light, design: .rounded).monospacedDigit())
                Text("Stand up. Look far away. Drink some water.")
                    .font(.title3)
                    .opacity(0.85)
                if c.parkedCount > 0 {
                    Button("\(c.parkedCount) parked thought\(c.parkedCount == 1 ? "" : "s") · open") { c.openParkingLot() }
                        .buttonStyle(.link)
                }
                HStack(spacing: 12) {
                    Button("Hide (Esc)") { c.hideOverlay() }
                        .keyboardShortcut(.cancelAction)
                    Button("Skip break") { c.skipBreak() }
                }
                .controlSize(.large)
                .padding(.top, 8)
            }
            .foregroundStyle(.white)
        }
    }
}
