import AppKit
import Carbon.HIToolbox

/// 截图编辑、截图翻译两个全局快捷键。默认都不设，在“设置 ▸ 快捷键”里录制
/// （`PersistedState.shotHotKeys`）。
///
/// 和快速待办、展开 AI 对话一个写法：Carbon 的 `RegisterEventHotKey`，不需要辅助功能或
/// 输入监控权限。签名“DkSh”，id 1 是截图编辑、2 是截图翻译；认不出的交给下一个处理函数。
@MainActor
final class ShotHotKey {
    static let shared = ShotHotKey()

    private var keys = ShotHotKeys()
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var suspended = false

    nonisolated private static let signature: OSType = 0x446B_5368

    private init() {}

    func apply(_ wanted: ShotHotKeys) {
        guard wanted != keys else { return }
        keys = wanted
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
        guard !suspended else { return }
        let wanted = keys.registrable
        let list: [(UInt32, KeyCombo?)] = [(1, wanted.edit), (2, wanted.translate)]
        guard list.contains(where: { $0.1 != nil }) else { return }
        installHandlerIfNeeded()
        for (id, combo) in list {
            guard let combo else { continue }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(combo.keyCode, combo.modifiers,
                                             EventHotKeyID(signature: Self.signature, id: id),
                                             GetApplicationEventTarget(), 0, &ref)
            // 别的 App 已经占了这个组合时注册失败，什么也不做，等用户换一个。
            guard status == noErr, let ref else { continue }
            refs.append(ref)
        }
    }

    private func unregister() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }

    private func fire(_ id: UInt32) {
        switch id {
        case 1: ShotEditor.shared.begin()
        case 2: ShotEditor.shared.beginTranslate()
        default: break
        }
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
            guard status == noErr, hotKeyID.signature == ShotHotKey.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let id = hotKeyID.id
            MainActor.assumeIsolated { ShotHotKey.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}
