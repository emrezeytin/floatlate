import Carbon.HIToolbox

final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private let signature = OSType(0x464C_5454)

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            HotKeyCenter.shared.actions[id.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }

    func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        let id = UInt32(actions.count + 1)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: signature, id: id), GetApplicationEventTarget(), 0, &ref)
        guard let ref else { return }
        refs.append(ref)
        actions[id] = action
    }
}
