import Foundation

/// 快速开关里可以放的按钮，按设置里勾选的顺序排列。
///
/// The list of switches follows OnlySwitch (jacklandrin/OnlySwitch, MIT):
/// most of them are the same public `defaults` keys and AppleScript commands
/// it uses, credited in NOTICE. A switch with a state (Keep Awake, hidden
/// files) is drawn lit while on; an action (lock, eject) just runs.
public enum QuickToggle: String, CaseIterable, Sendable, Identifiable {
    case darkMode, keepAwake, lock, screenSaver, emptyTrash
    case hiddenFiles, hideDesktop, extensions, muteMic
    case ejectDisks, clearClipboard, cleanScreen, quitApps

    public var id: String { rawValue }

    public static let key = "actions"
    public static let defaults: [QuickToggle] = [.darkMode, .keepAwake, .lock, .emptyTrash]

    public var title: String {
        switch self {
        case .darkMode: "深色模式"
        case .keepAwake: "保持唤醒"
        case .lock: "锁屏"
        case .screenSaver: "屏幕保护程序"
        case .emptyTrash: "清空废纸篓"
        case .hiddenFiles: "显示隐藏文件"
        case .hideDesktop: "隐藏桌面图标"
        case .extensions: "显示文件扩展名"
        case .muteMic: "麦克风静音"
        case .ejectDisks: "推出所有磁盘"
        case .clearClipboard: "清空剪贴板"
        case .cleanScreen: "清洁屏幕和键盘"
        case .quitApps: "退出其他应用"
        }
    }

    /// The tooltip, which says what a click does rather than what it is.
    public var help: String {
        switch self {
        case .darkMode: "切换深色模式"
        case .keepAwake: "阻止 Mac 和显示器休眠"
        case .lock: "关闭显示器并锁定"
        case .screenSaver: "启动屏幕保护程序"
        case .emptyTrash: "清空废纸篓（会先确认）"
        case .hiddenFiles: "在访达中显示或隐藏以“.”开头的文件"
        case .hideDesktop: "隐藏或显示桌面上的文件和图标"
        case .extensions: "在访达中始终显示文件扩展名"
        case .muteMic: "把麦克风输入音量调为 0，再点一次恢复"
        case .ejectDisks: "推出所有外置磁盘和已装载的磁盘映像"
        case .clearClipboard: "清空当前剪贴板内容"
        case .cleanScreen: "黑屏并暂时锁住键盘，方便擦拭"
        case .quitApps: "正常退出其他应用（会先确认，未存储的内容由各应用询问）"
        }
    }

    public var symbol: String {
        switch self {
        case .darkMode: "circle.lefthalf.filled"
        case .keepAwake: "cup.and.saucer.fill"
        case .lock: "lock.fill"
        case .screenSaver: "sparkles.tv"
        case .emptyTrash: "trash"
        case .hiddenFiles: "eye"
        case .hideDesktop: "menubar.dock.rectangle"
        case .extensions: "doc.badge.ellipsis"
        case .muteMic: "mic.slash.fill"
        case .ejectDisks: "eject.fill"
        case .clearClipboard: "clipboard"
        case .cleanScreen: "sparkles"
        case .quitApps: "xmark.rectangle"
        }
    }

    /// Whether it has an on and an off rather than being a one-shot action.
    public var hasState: Bool {
        switch self {
        case .darkMode, .keepAwake, .hiddenFiles, .hideDesktop, .extensions, .muteMic: true
        default: false
        }
    }

    /// The chosen switches in their saved order, unknown names dropped and
    /// repeats removed. An empty choice falls back to the defaults, since a
    /// card with no buttons is just an empty card.
    public static func chosen(_ config: WidgetConfig) -> [QuickToggle] {
        guard config[key] != nil else { return defaults }
        var seen = Set<QuickToggle>()
        let list = config.strings(key).compactMap(QuickToggle.init(rawValue:)).filter { seen.insert($0).inserted }
        return list.isEmpty ? defaults : list
    }

    /// Room for the round buttons in a row, or a column on a side shelf.
    public static func length(count: Int) -> Double {
        Double(max(count, 1)) * 30 + 20
    }
}
