import AppKit
import Carbon.HIToolbox

/// System-wide hotkeys for switching layouts.
///
/// Carbon's `RegisterEventHotKey` rather than an event monitor or tap: it is
/// still the one API that delivers a global key combination without asking
/// for Accessibility or Input Monitoring, and it consumes the press, so the
/// frontmost app never also sees it.
@MainActor
final class HotKeyService {
    static let shared = HotKeyService()

    /// Called with the profile whose combination was pressed.
    var onPress: (@MainActor (UUID) -> Void)?

    private var bindings: [ShortcutBinding] = []
    private var refs: [EventHotKeyRef] = []
    /// Carbon hands back a numeric id, not the profile.
    private var targets: [UInt32: UUID] = [:]
    private var handler: EventHandlerRef?
    /// While Settings records a new combination. A registered hotkey is
    /// consumed before any window sees it, so recording the combination a
    /// layout already has would switch layouts instead of being recorded.
    private var suspended = false

    /// "DkHk", so a press from some other registration in this process is
    /// never mistaken for one of ours. Nonisolated because the Carbon
    /// callback reads it before it has hopped onto the main actor.
    nonisolated private static let signature: OSType = 0x446B_486B

    private init() {}

    func update(_ wanted: [ShortcutBinding]) {
        guard wanted != bindings else { return }
        bindings = wanted
        reregister()
    }

    func suspend() {
        guard !suspended else { return }
        suspended = true
        unregisterAll()
    }

    func resume() {
        guard suspended else { return }
        suspended = false
        reregister()
    }

    private func reregister() {
        unregisterAll()
        guard !suspended, !bindings.isEmpty else { return }
        installHandlerIfNeeded()
        for (offset, binding) in bindings.enumerated() {
            let number = UInt32(offset + 1)
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: number)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(binding.combo.keyCode, binding.combo.modifiers,
                                             hotKeyID, GetApplicationEventTarget(), 0, &ref)
            // A combination another app already holds fails here. Skipped
            // rather than retried: there is nothing to retry until the user
            // picks a different one.
            guard status == noErr, let ref else { continue }
            refs.append(ref)
            targets[number] = binding.profileID
        }
    }

    private func unregisterAll() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        targets.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == HotKeyService.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let number = hotKeyID.id
            // The application event target dispatches on the main thread.
            MainActor.assumeIsolated { HotKeyService.shared.fire(number) }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    private func fire(_ number: UInt32) {
        guard let id = targets[number] else { return }
        onPress?(id)
    }
}
