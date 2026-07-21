import Carbon.HIToolbox

final class HotkeyManager {
    private var refs: [UInt32: EventHotKeyRef] = [:]
    fileprivate var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            var hkID = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                    EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &hkID) == noErr else {
                return noErr
            }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData!).takeUnretainedValue()
            manager.actions[hkID.id]?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if status != noErr {
            handler = nil
        }
    }

    deinit {
        unregisterAll()
        if let handler { RemoveEventHandler(handler) }
    }

    @discardableResult
    func register(_ combo: KeyCombo, action: @escaping () -> Void) -> Bool {
        guard handler != nil else { return false }
        var ref: EventHotKeyRef?
        let id = nextID
        nextID += 1
        let hkID = EventHotKeyID(signature: OSType(0x494E_5357), id: id) // 'INSW'
        guard RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, hkID,
                                  GetEventDispatcherTarget(), 0, &ref) == noErr,
              let ref else { return false }
        refs[id] = ref
        actions[id] = action
        return true
    }

    func unregisterAll() {
        refs.values.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actions.removeAll()
    }
}
