import Foundation

/// 输入框的编辑快捷键：⌘A 全选、⌘C 拷贝、⌘X 剪切、⌘V 粘贴、⌘Z 撤销、⌘⇧Z 重做。
///
/// 码头是菜单栏应用（LSUIElement），没有自己的「编辑」菜单，而这几个快捷键
/// 平时就是靠「编辑」菜单派发的：面板、便签、AI 刘海对话、快速待办里的输入框
/// 能打字，按 ⌘A、⌘V 却没反应。窗口在 performKeyEquivalent 里认出这几个键，
/// 把对应的动作沿响应链发给正在输入的那个框（见 DockLayout.swift 的
/// `EditKeyRouting`）。这里只管「哪个键是哪个动作」和「先给输入框还是先给面板」，
/// 不依赖 AppKit，方便测试。
public enum EditShortcut: String, CaseIterable, Sendable {
    case selectAll, copy, cut, paste, undo, redo

    /// 沿响应链发送的动作名（Objective-C 选择器），和「编辑」菜单里的一样。
    public var selectorName: String { rawValue + ":" }

    /// 美式键盘上这几个字母的键码，键盘布局打出来的不是拉丁字母时（俄文等）按它认。
    public static let keyCodes: [UInt16: String] = [0: "a", 8: "c", 7: "x", 9: "v", 6: "z"]

    /// 按下的键对应哪个编辑动作；不是编辑快捷键返回 nil。
    ///
    /// - Parameters:
    ///   - characters: 不计修饰键时打出来的字（`charactersIgnoringModifiers`），按住 Shift 时可能是大写。
    ///   - keyCode: 物理键码，字不是拉丁字母时才用。
    ///   - option、control：带了就不算（⌘⌥A 这类留给别的功能）。
    public static func resolve(characters: String?, keyCode: UInt16 = .max,
                               command: Bool, shift: Bool,
                               option: Bool = false, control: Bool = false) -> EditShortcut? {
        guard command, !option, !control else { return nil }
        let typed = characters?.lowercased() ?? ""
        let letter: String
        if let ascii = typed.unicodeScalars.first, typed.unicodeScalars.count == 1, ascii.isASCII {
            letter = typed
        } else if let fallback = keyCodes[keyCode] {
            letter = fallback
        } else {
            return nil
        }
        switch (letter, shift) {
        case ("a", false): return .selectAll
        case ("c", false): return .copy
        case ("x", false): return .cut
        case ("v", false): return .paste
        case ("z", false): return .undo
        case ("z", true): return .redo
        default: return nil
        }
    }

    /// 先交给谁。
    public enum Route: Sendable, Equatable {
        /// 先发给正在输入的框；框不接再交给面板自己的快捷键。
        case fieldFirst
        /// 先交给面板自己的快捷键（比如汇率页 ⌘C 拷贝换算结果），面板不接再沿响应链发。
        case panelFirst
    }

    /// - Parameters:
    ///   - textFocused: 焦点在可编辑或可选中的文字上。
    ///   - hasSelection: 选中了至少一个字。
    ///
    /// 没在打字时面板优先。在打字时输入框优先，只有一个例外：⌘C、⌘X 但什么都没选，
    /// 对输入框是空操作，留给面板（汇率、计算器的 ⌘C 拷贝结果照旧能用）。
    public static func route(_ shortcut: EditShortcut, textFocused: Bool, hasSelection: Bool) -> Route {
        guard textFocused else { return .panelFirst }
        switch shortcut {
        case .copy, .cut: return hasSelection ? .fieldFirst : .panelFirst
        case .selectAll, .paste, .undo, .redo: return .fieldFirst
        }
    }
}

/// 面板被 macOS 固定在了另一个桌面（Space）上。
///
/// 窗口设了「出现在所有桌面」，系统有时仍把它钉在某一个桌面：在别的桌面点开，
/// 窗口「开着、摆好了、排到最前」，却不在眼前这个桌面，点了等于没反应。新建的窗口
/// 总是落在当前桌面，所以发现这种情况就丢掉旧窗口、在新窗口里重新摆一次。
/// 每次打开最多重建一次，免得系统一直报不在当前桌面时来回重建。
public enum PanelSpaceRescue {
    public static func shouldRebuild(isOnActiveSpace: Bool, alreadyRebuilt: Bool) -> Bool {
        !isOnActiveSpace && !alreadyRebuilt
    }
}
