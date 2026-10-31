import Foundation

// MARK: - 替代系统音量和亮度提示：媒体键

/// 键盘上的音量、亮度键。值是 IOKit `ev_keymap.h` 里的 NX_KEYTYPE_*。
///
/// 只列码头会接管的五个；键盘背光（21～23）、播放控制（16～20）等其他媒体键
/// 解析出来是 nil，一律原样交给系统。
public enum IslandMediaKey: Int, CaseIterable, Sendable {
    case soundUp = 0          // NX_KEYTYPE_SOUND_UP
    case soundDown = 1        // NX_KEYTYPE_SOUND_DOWN
    case brightnessUp = 2     // NX_KEYTYPE_BRIGHTNESS_UP
    case brightnessDown = 3   // NX_KEYTYPE_BRIGHTNESS_DOWN
    case mute = 7             // NX_KEYTYPE_MUTE

    public var isVolume: Bool { self == .soundUp || self == .soundDown || self == .mute }
    public var isBrightness: Bool { self == .brightnessUp || self == .brightnessDown }
}

/// 一次按键：哪个键、按下还是松开、是不是按住后的连发。
public struct IslandMediaKeyPress: Equatable, Sendable {
    public var key: IslandMediaKey
    public var isDown: Bool
    public var isRepeat: Bool

    public init(key: IslandMediaKey, isDown: Bool, isRepeat: Bool = false) {
        self.key = key
        self.isDown = isDown
        self.isRepeat = isRepeat
    }

    /// NX_SYSDEFINED 事件的类型号（CGEventType 原始值 14）。
    public static let systemDefinedType: UInt32 = 14
    /// 媒体键用的子类型 NX_SUBTYPE_AUX_CONTROL_BUTTONS。
    public static let auxControlSubtype: Int16 = 8

    /// 从事件里认出音量、亮度键。
    ///
    /// data1 的高 16 位是键码，低 16 位里高字节是状态（0x0A 按下、0x0B 松开），
    /// 最低位是连发。别的事件、别的子类型、别的键和认不出的状态都是 nil。
    public static func parse(eventType: UInt32, subtype: Int16, data1: Int) -> IslandMediaKeyPress? {
        guard eventType == systemDefinedType, subtype == auxControlSubtype else { return nil }
        let code = (data1 & 0xFFFF_0000) >> 16
        let flags = data1 & 0xFFFF
        let state = (flags & 0xFF00) >> 8
        guard let key = IslandMediaKey(rawValue: code) else { return nil }
        switch state {
        case 0x0A: return IslandMediaKeyPress(key: key, isDown: true, isRepeat: flags & 0x1 != 0)
        case 0x0B: return IslandMediaKeyPress(key: key, isDown: false, isRepeat: false)
        default: return nil
        }
    }

    /// 测试和文档用：按 `parse` 的格式拼出 data1。
    public static func data1(key: IslandMediaKey, isDown: Bool, isRepeat: Bool = false) -> Int {
        (key.rawValue << 16) | ((isDown ? 0x0A : 0x0B) << 8) | (isRepeat ? 1 : 0)
    }
}

/// 按键时按着的修饰键里和音量、亮度有关的两个。
public struct IslandMediaModifiers: Equatable, Sendable {
    public var option: Bool
    public var shift: Bool

    public init(option: Bool = false, shift: Bool = false) {
        self.option = option
        self.shift = shift
    }

    /// Option+Shift：系统的四分之一小步，码头照做（1/64）。
    public var fine: Bool { option && shift }
    /// 只按 Option：系统用来打开“声音”或“显示器”设置，交还给系统。
    public var opensSystemSettings: Bool { option && !shift }
}

// MARK: - 步进

public enum IslandStep {
    /// 普通一步 1/16，和系统一样。
    public static let coarse = 16
    /// Option+Shift 一步 1/64。
    public static let fine = 64

    /// 往上或往下走一格，落在格点上并夹在 0...1。
    ///
    /// 不在格点上的值（别处用滑块拖过）先对齐到那个方向的下一个格点，
    /// 所以 0.30 往上是 5/16 = 0.3125，往下是 4/16 = 0.25，不会一步走出一格多。
    public static func next(_ level: Double, up: Bool, fine: Bool = false) -> Double {
        let count = Double(fine ? IslandStep.fine : IslandStep.coarse)
        let current = level.isFinite ? min(1, max(0, level)) : 0
        let position = current * count
        let epsilon = 1e-6
        let target = up ? (position + epsilon).rounded(.down) + 1 : (position - epsilon).rounded(.up) - 1
        return min(1, max(0, target / count))
    }
}

// MARK: - 按一下之后

public enum IslandKeyEffect {
    /// 音量键按下后的新音量和静音。
    ///
    /// - 静音键切换静音，音量不动；连发不再切（按住静音键不会来回闪）。
    /// - 加减键先解除静音再走一步，和系统一样；减到 0 时顺带静音，图标是划掉的喇叭。
    ///
    /// 返回 nil 表示这一下什么都不用改（静音键的连发）。
    public static func volume(_ press: IslandMediaKeyPress, level: Double, muted: Bool,
                              fine: Bool) -> (level: Double, muted: Bool)? {
        guard press.isDown, press.key.isVolume else { return nil }
        switch press.key {
        case .mute:
            return press.isRepeat ? nil : (level, !muted)
        case .soundUp:
            return (IslandStep.next(level, up: true, fine: fine), false)
        case .soundDown:
            let next = IslandStep.next(level, up: false, fine: fine)
            return (next, next <= 0)
        default:
            return nil
        }
    }

    /// 亮度键按下后的新亮度。
    public static func brightness(_ press: IslandMediaKeyPress, level: Double, fine: Bool) -> Double? {
        guard press.isDown, press.key.isBrightness else { return nil }
        return IslandStep.next(level, up: press.key == .brightnessUp, fine: fine)
    }
}

// MARK: - 拦下还是放行

/// 按下那一刻码头这边的情况，由 Services 读好交进来。
public struct IslandKeyContext: Equatable, Sendable {
    /// 默认输出设备能改音量（虚拟主音量或各声道）。
    public var volumeWritable: Bool
    /// 默认输出设备能改静音。
    public var muteWritable: Bool
    /// 能读写内建屏亮度，而且指针所在的屏就是内建屏（外接显示器交给系统）。
    public var brightnessWritable: Bool
    /// 清洁模式的锁键盘开着：什么都不改，交给它吞掉。
    public var keyboardLocked: Bool

    public init(volumeWritable: Bool = true, muteWritable: Bool = true,
                brightnessWritable: Bool = true, keyboardLocked: Bool = false) {
        self.volumeWritable = volumeWritable
        self.muteWritable = muteWritable
        self.brightnessWritable = brightnessWritable
        self.keyboardLocked = keyboardLocked
    }
}

public enum IslandKeyRoute {
    /// 按下（含连发）这一下码头接不接。true 就拦下自己改，false 原样交给系统。
    ///
    /// 只接打开了“替代”的那一种；只按 Option 是系统打开设置的快捷方式，放行；
    /// 设备改不了或锁键盘开着时放行。真去改时失败了，调用方也要放行。
    public static func handles(_ press: IslandMediaKeyPress, settings: IslandSettings,
                               modifiers: IslandMediaModifiers, context: IslandKeyContext) -> Bool {
        guard press.isDown, !context.keyboardLocked, !modifiers.opensSystemSettings else { return false }
        switch press.key {
        case .soundUp, .soundDown:
            return settings.replacesVolume && context.volumeWritable
        case .mute:
            return settings.replacesVolume && context.muteWritable
        case .brightnessUp, .brightnessDown:
            return settings.replacesBrightness && context.brightnessWritable
        }
    }
}

/// 记着哪些键的按下被拦了，松开时跟着拦；按下放行了的，松开也放行，
/// 系统那边不会只收到半次按键。
public struct IslandKeyLedger: Equatable, Sendable {
    private var held: Set<Int> = []

    public init() {}

    /// 按下（含连发）时记一笔。
    public mutating func down(_ key: IslandMediaKey, handled: Bool) {
        if handled { held.insert(key.rawValue) } else { held.remove(key.rawValue) }
    }

    /// 松开时问：要不要拦。问过就清掉。
    public mutating func up(_ key: IslandMediaKey) -> Bool {
        held.remove(key.rawValue) != nil
    }

    /// 拦截撤掉时清空，下次从头记。
    public mutating func reset() { held.removeAll() }
}

// MARK: - 状态

/// 设置里那一行说明。
public enum IslandTakeoverStatus: Equatable, Sendable {
    /// 开关没开，或音量、亮度提示都没开。
    case off
    /// 拦截装上了，系统提示不再出现。
    case active
    /// 没有辅助功能权限，退回只读，两个提示会同时出现。
    case needsAccess
    /// 有权限但拦截没装上，同样退回只读。
    case failed

    public static func resolve(wanted: Bool, trusted: Bool, installed: Bool) -> IslandTakeoverStatus {
        guard wanted else { return .off }
        if installed { return .active }
        return trusted ? .failed : .needsAccess
    }

    /// 设置里显示的那一行；`.off` 不显示。
    public func note(volume: Bool, brightness: Bool) -> String? {
        switch self {
        case .off:
            return nil
        case .active:
            if volume && brightness { return tr("码头正在调节音量和亮度，系统自带的提示不再出现。") }
            return volume ? tr("码头正在调节音量，系统自带的音量提示不再出现。")
                          : tr("码头正在调节亮度，系统自带的亮度提示不再出现。")
        case .needsAccess:
            return tr("需要辅助功能权限才能替代系统提示。授权前照常只读取，系统的提示也会出现。")
        case .failed:
            return tr("没能接管音量和亮度键，暂时照常只读取，系统的提示也会出现。")
        }
    }

    /// 要不要给“去授权”按钮。
    public var needsGrant: Bool { self == .needsAccess }
}
