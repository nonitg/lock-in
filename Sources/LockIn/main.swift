import AppKit

let app = NSApplication.shared
// Menu bar only: no Dock icon, no app switcher entry, no main window.
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
