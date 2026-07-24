@preconcurrency import Carbon

final class StopHotKeyMonitor: HotKeyMonitoring {
    private static let signature: OSType = 0x48435844 // HCXD
    private static let identifier: UInt32 = 1

    private let onPressed: @Sendable () -> Void
    private let keyCode: UInt32
    private let modifiers: UInt32
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    init(shortcut: CodexShortcut, onPressed: @escaping @Sendable () -> Void) {
        keyCode = UInt32(shortcut.keyCode)
        modifiers = StopShortcut.carbonModifiers(from: shortcut.flags)
        self.onPressed = onPressed
    }

    deinit {
        stop()
    }

    func start() -> Bool {
        guard hotKey == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handleHotKey,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else { return false }

        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: Self.identifier
        )
        let registrationStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )

        if registrationStatus != noErr {
            stop()
            return false
        }

        return true
    }

    func stop() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        hotKey = nil
        eventHandler = nil
    }

    private static let handleHotKey: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              hotKeyID.signature == signature,
              hotKeyID.id == identifier
        else { return OSStatus(eventNotHandledErr) }

        let monitor = Unmanaged<StopHotKeyMonitor>
            .fromOpaque(userData)
            .takeUnretainedValue()
        monitor.onPressed()
        return noErr
    }
}
