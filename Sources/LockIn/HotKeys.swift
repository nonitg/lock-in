import Carbon.HIToolbox

/// System-wide shortcuts via Carbon. Needs no Accessibility permission.
final class HotKeys {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false
    private var refs: [EventHotKeyRef] = []

    func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        Self.installHandlerOnce()
        let id = UInt32(Self.actions.count + 1)
        Self.actions[id] = action
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C4B_494E), id: id) // "LKIN"
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        if let ref { refs.append(ref) }
    }

    private static func installHandlerOnce() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            HotKeys.actions[hotKeyID.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }
}
