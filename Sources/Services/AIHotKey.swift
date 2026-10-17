import AppKit
import Carbon.HIToolbox

/// 展开刘海对话的全局快捷键。默认不设，用户在“设置 ▸ 通用 ▸ AI 助手”里录制。
///
/// 和切换布局的快捷键一样用 Carbon 的 `RegisterEventHotKey`：不需要辅助
/// 功能或输入监控权限。签名不同（“DkAi”），两边的处理函数各认各的，
/// 认不出的交给下一个处理函数。
@MainActor
final class AIHotKey {
    static let shared = AIHotKey()

    var onPress: (@MainActor () -> Void)?

    private var combo: KeyCombo?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var suspended = false

    nonisolated private static let signature: OSType = 0x446B_4169

    private init() {}

    func update(_ wanted: KeyCombo?) {
        guard wanted != combo else { return }
        combo = wanted
        reregister()
    }

    /// 录制快捷键时先放开，免得按下已有的组合被自己吃掉。
    func suspend() {
        guard !suspended else { return }
        suspended = true
        unregister()
    }

    func resume() {
        guard suspended else { return }
        suspended = false
        reregister()
    }

    private func reregister() {
        unregister()
        guard !suspended, let combo, combo.hasRequiredModifier else { return }
        installHandlerIfNeeded()
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers,
                                         EventHotKeyID(signature: Self.signature, id: 1),
                                         GetApplicationEventTarget(), 0, &newRef)
        // 别的 App 已经占了这个组合时注册失败，什么也不做，等用户换一个。
        guard status == noErr, let newRef else { return }
        ref = newRef
    }

    private func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
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
            guard status == noErr, hotKeyID.signature == AIHotKey.signature else {
                return OSStatus(eventNotHandledErr)
            }
            MainActor.assumeIsolated { AIHotKey.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}
