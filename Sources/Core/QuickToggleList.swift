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
    // 第二批工具。截图识字、取色器、演示模式在新放的卡片默认里，其余用户在设置里自己勾。
    case textCapture, colorPicker, presentation, keyboardLock
    case qrCode, mirror, lowPower, restartDock

    public var id: String { rawValue }

    public static let key = "actions"
    /// 新放的快速开关带的按钮（`WidgetCatalog` 用它作默认值）：原来的四个，
    /// 加上清洁屏幕和键盘、截图识字、取色器和演示模式。已经放好的卡片存着
    /// 自己的列表，不受影响。
    public static let defaults: [QuickToggle] = [.darkMode, .keepAwake, .lock, .emptyTrash,
                                                 .cleanScreen, .textCapture, .colorPicker, .presentation]

    /// 存着空列表（全取消勾选）的旧卡片一直退回这四个，保持不变。
    public static let emptyFallback: [QuickToggle] = [.darkMode, .keepAwake, .lock, .emptyTrash]

    public var title: String {
        switch self {
        case .darkMode: tr("深色模式")
        case .keepAwake: tr("保持唤醒")
        case .lock: tr("锁屏")
        case .screenSaver: tr("屏幕保护程序")
        case .emptyTrash: tr("清空废纸篓")
        case .hiddenFiles: tr("显示隐藏文件")
        case .hideDesktop: tr("隐藏桌面图标")
        case .extensions: tr("显示文件扩展名")
        case .muteMic: tr("麦克风静音")
        case .ejectDisks: tr("推出所有磁盘")
        case .clearClipboard: tr("清空剪贴板")
        case .cleanScreen: tr("清洁屏幕和键盘")
        case .quitApps: tr("退出其他应用")
        case .textCapture: tr("截图识字")
        case .colorPicker: tr("取色器")
        case .presentation: tr("演示模式")
        case .keyboardLock: tr("只锁键盘")
        case .qrCode: tr("二维码")
        case .mirror: tr("镜子")
        case .lowPower: tr("低电量模式")
        case .restartDock: tr("重启程序坞和访达")
        }
    }

    /// The tooltip, which says what a click does rather than what it is.
    public var help: String {
        switch self {
        case .darkMode: tr("切换深色模式")
        case .keepAwake: tr("阻止 Mac 和显示器休眠")
        case .lock: tr("关闭显示器并锁定")
        case .screenSaver: tr("启动屏幕保护程序")
        case .emptyTrash: tr("清空废纸篓（会先确认）")
        case .hiddenFiles: tr("在访达中显示或隐藏以“.”开头的文件")
        case .hideDesktop: tr("隐藏或显示桌面上的文件和图标")
        case .extensions: tr("在访达中始终显示文件扩展名")
        case .muteMic: tr("把麦克风输入音量调为 0，再点一次恢复")
        case .ejectDisks: tr("推出所有外置磁盘和已装载的磁盘映像")
        case .clearClipboard: tr("清空当前剪贴板内容")
        case .cleanScreen: tr("黑屏并暂时锁住键盘，方便擦拭")
        case .quitApps: tr("正常退出其他应用（会先确认，未存储的内容由各应用询问）")
        case .textCapture: tr("框选屏幕上的一块区域，识别其中的文字并拷贝")
        case .colorPicker: tr("用放大镜取屏幕上任意一点的颜色，拷贝 HEX")
        case .presentation: tr("隐藏桌面图标和其他应用并保持唤醒，再点一次恢复原样")
        case .keyboardLock: tr("暂时锁住键盘，屏幕照常显示，长按浮窗按钮 3 秒解锁")
        case .qrCode: tr("把剪贴板文字生成二维码，或识别屏幕上的二维码")
        case .mirror: tr("打开摄像头小窗照一照，点外面或按 Esc 关闭")
        case .lowPower: tr("切换系统的低电量模式（需要管理员密码）")
        case .restartDock: tr("重新启动程序坞和访达（会先确认）")
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
        case .textCapture: "text.viewfinder"
        case .colorPicker: "eyedropper"
        case .presentation: "play.rectangle.on.rectangle"
        case .keyboardLock: "keyboard.badge.ellipsis"
        case .qrCode: "qrcode"
        case .mirror: "person.crop.square"
        case .lowPower: "battery.25"
        case .restartDock: "arrow.clockwise"
        }
    }

    /// Whether it has an on and an off rather than being a one-shot action.
    public var hasState: Bool {
        switch self {
        case .darkMode, .keepAwake, .hiddenFiles, .hideDesktop, .extensions, .muteMic: true
        case .presentation, .keyboardLock, .lowPower: true
        default: false
        }
    }

    /// The chosen switches in their saved order, unknown names dropped and
    /// repeats removed. No list at all is a new card and gets the defaults; an
    /// empty choice falls back to the original four (`emptyFallback`), since a
    /// card with no buttons is just an empty card and an existing card should
    /// not grow four more buttons by itself.
    public static func chosen(_ config: WidgetConfig) -> [QuickToggle] {
        guard config[key] != nil else { return defaults }
        var seen = Set<QuickToggle>()
        let list = config.strings(key).compactMap(QuickToggle.init(rawValue:)).filter { seen.insert($0).inserted }
        return list.isEmpty ? emptyFallback : list
    }

    /// Room for the round buttons in a row, or a column on a side shelf.
    public static func length(count: Int) -> Double {
        Double(max(count, 1)) * 30 + 20
    }
}
