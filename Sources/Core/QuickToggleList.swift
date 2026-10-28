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
    /// 截图识字和取色器另有自己的卡片，这里写明是“快捷按钮”：一键开始，不显示结果。
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
        case .textCapture: tr("快捷按钮：框选屏幕上的一块区域，识别其中的文字并拷贝（截图工具卡片里也有）")
        case .colorPicker: tr("快捷按钮：用放大镜取屏幕上任意一点的颜色，拷贝 HEX，并记进取色器的最近颜色")
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
    /// 圆钮下显示名字时每个按钮占 46pt 宽（名字最多四个字）。不显示名字时每个 36pt：
    /// 圆钮 28pt（图标 14pt）加 8pt 间距。原来 22pt 圆钮、11pt 图标在深色玻璃上几乎看不清。
    public static func length(count: Int, names: Bool = false) -> Double {
        Double(max(count, 1)) * (names ? 46 : 36) + 20
    }

    /// 侧边（竖向）扩展栏里一列圆钮的高度。卡片上下不留内边距，所以要装下
    /// 圆钮本身和它们之间的间距：不显示名字时 28pt 圆钮、间距 6pt，每个按 36pt 算；
    /// 显示名字时圆钮、2pt 间距和一行 10pt 名字，每个按 46pt 算。另留 8pt。
    /// 以前按 22pt 圆钮每个 30pt 算，圆钮放大后四个以上就会超出卡片。
    public static func columnLength(count: Int, names: Bool = false) -> Double {
        Double(max(count, 1)) * (names ? 46 : 36) + 8
    }

    // MARK: 卡片名字和面板

    /// 卡片圆钮下显示名字的开关（设置和面板编辑里都能改）。旧卡片没有这个键，照旧不显示。
    public static let showNamesKey = "showNames"

    public static func showsNames(_ config: WidgetConfig) -> Bool {
        config.bool(showNamesKey, default: false)
    }

    /// 卡片圆钮下的短名字，最多四个字，排得进 46pt。
    public var shortTitle: String {
        switch self {
        case .darkMode: tr("深色")
        case .keepAwake: tr("唤醒")
        case .lock: tr("锁屏")
        case .screenSaver: tr("屏保")
        case .emptyTrash: tr("废纸篓")
        case .hiddenFiles: tr("隐藏文件")
        case .hideDesktop: tr("桌面图标")
        case .extensions: tr("扩展名")
        case .muteMic: tr("麦克风")
        case .ejectDisks: tr("推出")
        case .clearClipboard: tr("剪贴板")
        case .cleanScreen: tr("清洁")
        case .quitApps: tr("退出应用")
        case .textCapture: tr("识字")
        case .colorPicker: tr("取色")
        case .presentation: tr("演示")
        case .keyboardLock: tr("锁键盘")
        case .qrCode: tr("二维码")
        case .mirror: tr("镜子")
        case .lowPower: tr("低电量")
        case .restartDock: tr("重启")
        }
    }

    /// 面板大按钮上的名字：五个字以内用全名，更长的（清洁屏幕和键盘、重启程序坞和访达）
    /// 用短名字，三列的按钮里 13pt 放得下，不缩小字。
    public var panelTitle: String {
        title.count <= 5 ? title : shortTitle
    }

    /// 面板大按钮名字下面那行：有开关的写开或关（保持唤醒另算，见 `KeepAwakeTimer`），
    /// 一次性的动作写点了会怎样。
    public func caption(on: Bool) -> String {
        if hasState { return on ? tr("开") : tr("关") }
        switch self {
        case .lock: return tr("点按锁定")
        case .screenSaver: return tr("点按启动")
        case .emptyTrash, .quitApps, .restartDock: return tr("会先确认")
        case .ejectDisks: return tr("推出全部")
        case .clearClipboard: return tr("点按清空")
        case .cleanScreen: return tr("点按开始")
        case .textCapture: return tr("框选拷贝")
        case .colorPicker: return tr("点按取色")
        case .qrCode: return tr("生成或识别")
        case .mirror: return tr("照一照")
        default: return ""
        }
    }
}

/// 保持唤醒多久：30 分钟、1 小时、2 小时或一直（0），到点自动关。
///
/// 存在卡片的 `keepAwakeFor` 里（分钟数的字符串）。旧卡片和新放的卡片都是「一直」，
/// 和以前一样；在面板或设置里选了时长，之后每次打开保持唤醒都按这个时长。
public enum KeepAwakeTimer {
    public static let key = "keepAwakeFor"
    public static let choices = [30, 60, 120, 0]
    public static let defaultMinutes = 0

    public static func minutes(_ config: WidgetConfig) -> Int {
        let value = Int(config.string(key, default: String(defaultMinutes))) ?? defaultMinutes
        return choices.contains(value) ? value : defaultMinutes
    }

    public static func title(_ minutes: Int) -> String {
        switch minutes {
        case 0: tr("一直")
        case 60: tr("1 小时")
        case 120: tr("2 小时")
        default: tr("\(minutes) 分钟")
        }
    }

    /// 到点的时刻；一直开着是 nil。
    public static func deadline(minutes: Int, from now: Date) -> Date? {
        minutes > 0 ? now.addingTimeInterval(Double(minutes) * 60) : nil
    }

    /// 面板和卡片悬停写的剩余时间：“剩 42 分”“剩 1 小时 5 分”，不到一分钟算一分钟；
    /// 没有到点时刻是“一直开着”。
    /// `minutesOnly` 时只按分钟写（“剩 105 分”），面板三列的按钮里放得下。
    public static func remaining(until deadline: Date?, now: Date, minutesOnly: Bool = false) -> String {
        guard let deadline else { return tr("一直开着") }
        let minutes = max(1, Int((deadline.timeIntervalSince(now) / 60).rounded(.up)))
        if minutes < 60 || minutesOnly { return tr("剩 \(minutes) 分") }
        let rest = minutes % 60
        return rest == 0 ? tr("剩 \(minutes / 60) 小时") : tr("剩 \(minutes / 60) 小时 \(rest) 分")
    }
}
