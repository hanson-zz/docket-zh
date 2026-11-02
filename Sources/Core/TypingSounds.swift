import Foundation

// MARK: - 打字音效
//
// 打字时按下一个键就响一声：机械键盘、打字机或用户导入的 Mechvibes 声音包。
// 听键盘用「输入监控」权限的只听（listen-only）事件监听，只看按下了哪个键（键码）和
// 是不是按住连发，不拦截、不记录、不存、不上传打的内容；输入密码（安全输入）时不响。
// 监听和播放在 Services 那边（TypingSoundTap、TypingSoundEngine），这里只有能测的判断：
// 键码归类、键码对到 Mechvibes 的键名、变体和音高的挑法、连发和安全输入、Pro 能用哪几款、
// Mechvibes 的 config.json 怎么读。
//
// 免费：青轴。码头 Pro：其余 6 款和导入 Mechvibes 声音包。没解锁时选着的 Pro 款按青轴响，
// 选择照旧存着，解锁或试用后自动回来，见 `TypingSoundGate.effectiveChoice`。

/// 一个键响哪一类声音。回车、空格、删除各有自己的声音，其余的键共用四个变体。
public enum TypingSoundKey: String, CaseIterable, Sendable {
    case key
    case space
    case enter
    case backspace

    /// macOS 的虚拟键码（kVK_*）归类。修饰键、音量键这类不该响的返回 nil。
    public static func of(keyCode: Int) -> TypingSoundKey? {
        switch keyCode {
        case 36, 76: return .enter            // Return、小键盘 Enter
        case 49: return .space
        case 51, 117: return .backspace       // Delete、向前删除
        case 54...63: return nil              // ⌘ ⇧ ⇪ ⌥ ⌃ fn（按下一般不来 keyDown，来了也不响）
        case 72, 73, 74: return nil           // 音量加减、静音
        default: return keyCode >= 0 && keyCode < 128 ? .key : nil
        }
    }

    /// 素材文件名里的键名。普通键有四个变体。
    public var fileKeys: [String] {
        switch self {
        case .key: (1...TypingSoundStyle.keyVariants).map { "key-\($0)" }
        case .space: ["space"]
        case .enter: ["enter"]
        case .backspace: ["backspace"]
        }
    }
}

// MARK: - 内置的七款

/// 内置的七款声音：三款现场合成（scripts/make-typing-sounds.py），四款裁自许可清楚的录音
/// （Mechvibes 自带包 MIT、OpenGameArt CC0，出处见 NOTICE.md）。界面只用通称，不写品牌。
public enum TypingSoundStyle: String, CaseIterable, Codable, Sendable {
    case blue
    case brown
    case typewriter
    case red
    case black
    case capacitive
    case quiet

    /// 普通键的变体个数。
    public static let keyVariants = 4

    /// 免费的那一款。
    public static let free: TypingSoundStyle = .blue

    public var title: String {
        switch self {
        case .blue: tr("青轴")
        case .brown: tr("茶轴")
        case .typewriter: tr("打字机")
        case .red: tr("红轴")
        case .black: tr("黑轴")
        case .capacitive: tr("静电容")
        case .quiet: tr("白噪安静款")
        }
    }

    public var caption: String {
        switch self {
        case .blue: tr("清脆的咔哒声")
        case .brown: tr("闷一点的段落感")
        case .typewriter: tr("金属敲击，回车带铃")
        case .red: tr("线性，轻快顺滑")
        case .black: tr("线性，沉稳厚实")
        case .capacitive: tr("圆润的咚咚声")
        case .quiet: tr("轻柔，不吵人")
        }
    }

    /// 裁自真实录音的四款；其余三款是合成的。
    public var isRecording: Bool {
        switch self {
        case .red, .black, .capacitive, .quiet: true
        case .blue, .brown, .typewriter: false
        }
    }

    public var isPro: Bool { self != Self.free }

    /// 资源文件名（不带 .wav），如 typing-blue-key-2。
    public func fileName(_ key: String) -> String { "typing-\(rawValue)-\(key)" }

    /// 全部资源文件名，测试和打包检查用。
    public var fileNames: [String] {
        TypingSoundKey.allCases.flatMap { $0.fileKeys }.map(fileName)
    }

    /// 每次随机的音高范围（音分，正负）。合成的放宽一点，录音的收一点免得听着假。
    public var pitchSpread: Double { isRecording ? 30 : 55 }
}

// MARK: - 选的是哪一款

/// 选的是内置的一款，还是导入的一个声音包（按包的 id）。存成字符串：内置款是 rawValue，
/// 声音包是 `pack:<id>`。
public enum TypingSoundChoice: Hashable, Sendable {
    case style(TypingSoundStyle)
    case pack(String)

    static let packPrefix = "pack:"

    public init(raw: String) {
        if raw.hasPrefix(Self.packPrefix) {
            let id = String(raw.dropFirst(Self.packPrefix.count))
            self = id.isEmpty ? .style(.free) : .pack(id)
        } else {
            self = .style(TypingSoundStyle(rawValue: raw) ?? .free)
        }
    }

    public var raw: String {
        switch self {
        case .style(let style): style.rawValue
        case .pack(let id): Self.packPrefix + id
        }
    }

    /// 免费只有青轴；其余内置款和导入的包都是 Pro。
    public var isPro: Bool {
        switch self {
        case .style(let style): style.isPro
        case .pack: true
        }
    }
}

// MARK: - 设置

/// 导入过的一个 Mechvibes 声音包。文件在 Application Support 下按 id 放一个文件夹。
public struct TypingSoundPackRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var author: String
    /// single 或 multi。
    public var method: String
    /// 定义了声音的键数。
    public var keyCount: Int

    public init(id: String, name: String, author: String = "", method: String, keyCount: Int) {
        self.id = id
        self.name = name
        self.author = author
        self.method = method
        self.keyCount = keyCount
    }
}

/// 设置 ▸ 打字音效。总开关默认关。
public struct TypingSoundSettings: Codable, Hashable, Sendable {
    public var enabled: Bool = false
    /// `TypingSoundChoice.raw`。
    public var choice: String = TypingSoundStyle.free.rawValue
    /// 相对音量 0…1，和系统音量叠乘。
    public var volume: Double = TypingSoundSettings.defaultVolume
    /// 导入的声音包，按导入顺序。
    public var packs: [TypingSoundPackRecord] = []

    public static let defaultVolume = 0.6

    public init() {}

    public var selected: TypingSoundChoice { TypingSoundChoice(raw: choice) }

    /// 读的时候夹到 0…1，写坏的配置也能用。
    public var clampedVolume: Double {
        volume.isFinite ? min(1, max(0, volume)) : Self.defaultVolume
    }

    public func pack(_ id: String) -> TypingSoundPackRecord? { packs.first { $0.id == id } }

    /// 删一个包；正选着它时退回青轴。
    public mutating func removePack(_ id: String) {
        packs.removeAll { $0.id == id }
        if selected == .pack(id) { choice = TypingSoundStyle.free.rawValue }
    }

    private enum CodingKeys: String, CodingKey { case enabled, choice, volume, packs }

    /// 宽松解码：老状态文件没有这一组，或以后多了认不出的值，都照常读。重复 id 的包只留第一个。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        if let raw = try? c.decodeIfPresent(String.self, forKey: .choice), !raw.isEmpty { choice = raw }
        volume = (try? c.decodeIfPresent(Double.self, forKey: .volume)) ?? Self.defaultVolume
        if let raw = try? c.decodeIfPresent([TypingSoundPackRecord].self, forKey: .packs) {
            var seen = Set<String>()
            packs = raw.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(choice, forKey: .choice)
        try c.encode(volume, forKey: .volume)
        try c.encode(packs, forKey: .packs)
    }
}

// MARK: - Pro 和真正响哪一款

public enum TypingSoundGate {
    /// 现在真正响哪一款：没解锁时 Pro 款按青轴；选的包已经删了也按青轴。选择本身不改。
    public static func effectiveChoice(_ settings: TypingSoundSettings, unlocked: Bool) -> TypingSoundChoice {
        let selected = settings.selected
        if case .pack(let id) = selected, settings.pack(id) == nil { return .style(.free) }
        return canChoose(selected, unlocked: unlocked) ? selected : .style(.free)
    }

    /// 能不能选这一款（免费用户点 Pro 款弹升级页，不改设置）。
    public static func canChoose(_ choice: TypingSoundChoice, unlocked: Bool) -> Bool {
        !choice.isPro || ProLicenseGate.canUse(.typingSounds, unlocked: unlocked)
    }

    /// 能不能导入 Mechvibes 声音包（Pro）。
    public static func canImport(unlocked: Bool) -> Bool {
        ProLicenseGate.canUse(.typingSounds, unlocked: unlocked)
    }

    /// 要不要装键盘监听：开着且有输入监控权限。
    public static func shouldListen(_ settings: TypingSoundSettings, permitted: Bool) -> Bool {
        settings.enabled && permitted
    }
}

// MARK: - 连发和安全输入

/// 一次按键要不要出声。
///
/// - 安全输入（密码框）开着：不响。
/// - 按住不放的自动连发：最多每 `repeatInterval` 秒响一下，不跟着连发的速度狂响。
/// - 两声之间至少隔 `minimumGap` 秒，同时按下好几个键时不叠成一团。
public struct TypingSoundThrottle: Sendable, Equatable {
    public static let repeatInterval: Double = 0.15
    public static let minimumGap: Double = 0.012

    private var lastPlay = -Double.infinity
    private var lastRepeat = -Double.infinity

    public init() {}

    /// `now` 是秒（单调时钟）。返回 true 时已经记下这一声。
    public mutating func admit(isRepeat: Bool, secureInput: Bool, now: Double) -> Bool {
        guard !secureInput else { return false }
        guard now - lastPlay >= Self.minimumGap else { return false }
        if isRepeat {
            guard now - lastRepeat >= Self.repeatInterval else { return false }
            lastRepeat = now
        } else {
            // 新按下一个键：连发重新计时，下一次连发要再等满一个间隔。
            lastRepeat = now
        }
        lastPlay = now
        return true
    }
}

// MARK: - 变体和音高

/// 普通键四个变体里挑一个：随机，但不连着两次一样，听着不机械。音高和响度再略微随机。
public struct TypingSoundVariantPicker: Sendable, Equatable {
    private var last: [String: Int] = [:]

    public init() {}

    /// `random` 取 [0, 1)。`slot` 区分不同的键类（key、space…）。
    public mutating func next(_ slot: String, count: Int, random: Double) -> Int {
        guard count > 1 else { return 0 }
        let r = min(max(random, 0), 0.999_999)
        var index: Int
        if let previous = last[slot], previous < count {
            // 从另外 count - 1 个里挑。
            index = Int(r * Double(count - 1))
            if index >= previous { index += 1 }
        } else {
            index = Int(r * Double(count))
        }
        last[slot] = index
        return index
    }

    /// 播放速率：在 ±spread 音分里随机（1200 音分一个八度）。`random` 取 [0, 1)。
    public static func rate(spread: Double, random: Double) -> Float {
        let cents = (min(max(random, 0), 1) * 2 - 1) * max(0, spread)
        return Float(pow(2, cents / 1200))
    }

    /// 每一声的响度在 0.85…1 之间随机。
    public static func gain(random: Double) -> Float {
        Float(0.85 + 0.15 * min(max(random, 0), 1))
    }
}

// MARK: - 键码对照

/// macOS 键码和 Mechvibes 键名（W3C KeyboardEvent.code，Mechvibes 配置第 2 版用的）、
/// 以及第 1 版配置的 iohook 数字键码之间的对照。
public enum TypingKeyCodes {
    /// macOS 虚拟键码 → KeyboardEvent.code。
    public static let macToWeb: [Int: String] = [
        0: "KeyA", 1: "KeyS", 2: "KeyD", 3: "KeyF", 4: "KeyH", 5: "KeyG", 6: "KeyZ", 7: "KeyX",
        8: "KeyC", 9: "KeyV", 10: "IntlBackslash", 11: "KeyB", 12: "KeyQ", 13: "KeyW", 14: "KeyE", 15: "KeyR",
        16: "KeyY", 17: "KeyT", 18: "Digit1", 19: "Digit2", 20: "Digit3", 21: "Digit4", 22: "Digit6",
        23: "Digit5", 24: "Equal", 25: "Digit9", 26: "Digit7", 27: "Minus", 28: "Digit8", 29: "Digit0",
        30: "BracketRight", 31: "KeyO", 32: "KeyU", 33: "BracketLeft", 34: "KeyI", 35: "KeyP", 36: "Enter",
        37: "KeyL", 38: "KeyJ", 39: "Quote", 40: "KeyK", 41: "Semicolon", 42: "Backslash", 43: "Comma",
        44: "Slash", 45: "KeyN", 46: "KeyM", 47: "Period", 48: "Tab", 49: "Space", 50: "Backquote",
        51: "Backspace", 53: "Escape", 54: "MetaRight", 55: "MetaLeft", 56: "ShiftLeft", 57: "CapsLock",
        58: "AltLeft", 59: "ControlLeft", 60: "ShiftRight", 61: "AltRight", 62: "ControlRight",
        64: "F17", 65: "NumpadDecimal", 67: "NumpadMultiply", 69: "NumpadAdd", 71: "NumLock",
        75: "NumpadDivide", 76: "NumpadEnter", 78: "NumpadSubtract", 79: "F18", 80: "F19", 81: "NumpadEqual",
        82: "Numpad0", 83: "Numpad1", 84: "Numpad2", 85: "Numpad3", 86: "Numpad4", 87: "Numpad5",
        88: "Numpad6", 89: "Numpad7", 90: "F20", 91: "Numpad8", 92: "Numpad9", 93: "IntlYen",
        94: "IntlRo", 95: "NumpadComma", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        102: "Lang2", 103: "F11", 104: "Lang1", 105: "F13", 106: "F16", 107: "F14", 109: "F10",
        110: "ContextMenu", 111: "F12", 113: "F15", 114: "Insert", 115: "Home", 116: "PageUp",
        117: "Delete", 118: "F4", 119: "End", 120: "F2", 121: "PageDown", 122: "F1",
        123: "ArrowLeft", 124: "ArrowRight", 125: "ArrowDown", 126: "ArrowUp",
    ]

    /// 第 1 版配置（iohook / libuiohook 的扫描码）→ KeyboardEvent.code。主键区按扫描码，
    /// 扩展键按老 Mechvibes 包里常见的写法（0x0E__、0xE0__ 两种都认）。
    public static let iohookToWeb: [Int: String] = {
        var map: [Int: String] = [
            1: "Escape", 2: "Digit1", 3: "Digit2", 4: "Digit3", 5: "Digit4", 6: "Digit5", 7: "Digit6",
            8: "Digit7", 9: "Digit8", 10: "Digit9", 11: "Digit0", 12: "Minus", 13: "Equal", 14: "Backspace",
            15: "Tab", 16: "KeyQ", 17: "KeyW", 18: "KeyE", 19: "KeyR", 20: "KeyT", 21: "KeyY", 22: "KeyU",
            23: "KeyI", 24: "KeyO", 25: "KeyP", 26: "BracketLeft", 27: "BracketRight", 28: "Enter",
            29: "ControlLeft", 30: "KeyA", 31: "KeyS", 32: "KeyD", 33: "KeyF", 34: "KeyG", 35: "KeyH",
            36: "KeyJ", 37: "KeyK", 38: "KeyL", 39: "Semicolon", 40: "Quote", 41: "Backquote",
            42: "ShiftLeft", 43: "Backslash", 44: "KeyZ", 45: "KeyX", 46: "KeyC", 47: "KeyV", 48: "KeyB",
            49: "KeyN", 50: "KeyM", 51: "Comma", 52: "Period", 53: "Slash", 54: "ShiftRight",
            55: "NumpadMultiply", 56: "AltLeft", 57: "Space", 58: "CapsLock", 59: "F1", 60: "F2", 61: "F3",
            62: "F4", 63: "F5", 64: "F6", 65: "F7", 66: "F8", 67: "F9", 68: "F10", 69: "NumLock",
            70: "ScrollLock", 71: "Numpad7", 72: "Numpad8", 73: "Numpad9", 74: "NumpadSubtract",
            75: "Numpad4", 76: "Numpad5", 77: "Numpad6", 78: "NumpadAdd", 79: "Numpad1", 80: "Numpad2",
            81: "Numpad3", 82: "Numpad0", 83: "NumpadDecimal", 87: "F11", 88: "F12",
        ]
        // 扩展键：0x0E00 + 扫描码（老包常见）和 0xE000 + 扫描码。
        let extended: [Int: String] = [
            0x1C: "NumpadEnter", 0x1D: "ControlRight", 0x35: "NumpadDivide", 0x37: "PrintScreen",
            0x38: "AltRight", 0x45: "Pause", 0x47: "Home", 0x48: "ArrowUp", 0x49: "PageUp",
            0x4B: "ArrowLeft", 0x4D: "ArrowRight", 0x4F: "End", 0x50: "ArrowDown", 0x51: "PageDown",
            0x52: "Insert", 0x53: "Delete", 0x5B: "MetaLeft", 0x5C: "MetaRight", 0x5D: "ContextMenu",
        ]
        for (scan, code) in extended {
            map[0x0E00 + scan] = code
            map[0xE000 + scan] = code
        }
        return map
    }()

    /// 一个 macOS 键码对应的 KeyboardEvent.code，认不出时 nil。
    public static func web(keyCode: Int) -> String? { macToWeb[keyCode] }

    /// 第 1 版配置里的键（数字字符串）→ KeyboardEvent.code。已经是名字的原样返回。
    public static func web(v1Key: String) -> String? {
        if let number = Int(v1Key) { return iohookToWeb[number] }
        return v1Key.isEmpty ? nil : v1Key
    }

    /// 字母键，导入包里找不到某个键时从这里随机借一个。
    public static let letters: [String] = (UInt8(ascii: "A")...UInt8(ascii: "Z")).map { "Key\(Character(UnicodeScalar($0)))" }
}

// MARK: - Mechvibes 声音包

/// 读 Mechvibes 声音包的 config.json，支持第 1 版（`defines`、iohook 数字键码）和第 2 版
/// （`definitions` / `defs`、KeyboardEvent.code）；single（一个文件按时间切）和 multi（每个键
/// 一个文件）两种。只读按下的那一段，抬起的声音不用。
public struct MechvibesPack: Equatable, Sendable {
    public enum Method: String, Sendable { case single, multi }

    /// 一个键按下时放的那一段：哪个文件，从第几毫秒到第几毫秒（nil 表示整个文件）。
    public struct Segment: Hashable, Sendable {
        public var file: String
        public var start: Double?
        public var end: Double?

        public init(file: String, start: Double? = nil, end: Double? = nil) {
            self.file = file
            self.start = start
            self.end = end
        }
    }

    public var name: String
    public var author: String
    public var method: Method
    /// KeyboardEvent.code → 按下时放的那一段。
    public var definitions: [String: Segment]

    /// 用到的全部文件（相对声音包文件夹的路径），按名字排。
    public var files: [String] { Array(Set(definitions.values.map(\.file))).sorted() }

    /// 支持的音频扩展名；ogg、flac 交给 Core Audio 试着解，解不开时导入会说清楚
    /// （OGG 见 `TypingSoundAudioFormat.oggUnsupportedMessage`）。
    public static let audioExtensions: Set<String> = ["wav", "ogg", "mp3", "flac", "m4a", "aac", "aif", "aiff", "caf"]
    /// 一个包最多用多少个文件、定义多少个键。
    public static let maxFiles = 300
    public static let maxDefinitions = 400

    public enum ParseError: Error, Equatable, Sendable {
        case invalidJSON
        case noDefinitions
        case missingAudioFile
        case unsafePath(String)
        case unsupportedFormat(String)
        case tooNewVersion
        case tooManyFiles

        public var message: String {
            switch self {
            case .invalidJSON: tr("config.json 不是有效的 JSON。")
            case .noDefinitions: tr("config.json 里没有定义任何键的声音。")
            case .missingAudioFile: tr("config.json 没写声音文件（sound 或 audio_file）。")
            case .unsafePath(let path): tr("声音文件路径不安全：\(path)")
            case .unsupportedFormat(let ext): tr("不支持 .\(ext) 格式，请用 wav、mp3、m4a 或 flac。")
            case .tooNewVersion: tr("这个声音包要更新版本的 Mechvibes 才能读。")
            case .tooManyFiles: tr("声音包里的文件太多。")
            }
        }
    }

    public init(name: String, author: String, method: Method, definitions: [String: Segment]) {
        self.name = name
        self.author = author
        self.method = method
        self.definitions = definitions
    }

    public static func parse(_ data: Data) throws -> MechvibesPack {
        guard let object = try? JSONSerialization.jsonObject(with: data), let root = object as? [String: Any] else {
            throw ParseError.invalidJSON
        }
        let name = (root["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let author = (root["author"] as? String) ?? (root["m_author"] as? String) ?? ""
        if let version = Self.number(root["config_version"]), version > 2 { throw ParseError.tooNewVersion }

        let pack: MechvibesPack
        if let defs = (root["definitions"] ?? root["defs"]) as? [String: Any] {
            pack = try parseV2(root, defs: defs, name: name, author: author)
        } else if let defines = root["defines"] as? [String: Any] {
            pack = try parseV1(root, defines: defines, name: name, author: author)
        } else {
            throw ParseError.noDefinitions
        }
        guard !pack.definitions.isEmpty else { throw ParseError.noDefinitions }
        guard pack.files.count <= maxFiles else { throw ParseError.tooManyFiles }
        for file in pack.files {
            let ext = (file as NSString).pathExtension.lowercased()
            guard audioExtensions.contains(ext) else { throw ParseError.unsupportedFormat(ext.isEmpty ? "?" : ext) }
        }
        return pack
    }

    // 第 2 版：{"KeyA": {"timing": [[start, end], [start, end]], "audio_file": "a.ogg"}}
    private static func parseV2(_ root: [String: Any], defs: [String: Any], name: String,
                                author: String) throws -> MechvibesPack {
        let method = Method(rawValue: (root["definition_method"] as? String)?.lowercased() ?? "single") ?? .single
        let mainRaw = (root["audio_file"] as? String) ?? (root["sound"] as? String)
        let main = try mainRaw.flatMap { $0.isEmpty ? nil : try cleanPath($0) }
        var result: [String: Segment] = [:]
        for (code, value) in defs.sorted(by: { $0.key < $1.key }).prefix(maxDefinitions) {
            guard let entry = value as? [String: Any] else { continue }
            var file = main
            if method == .multi, let own = entry["audio_file"] as? String, !own.isEmpty {
                file = try cleanPath(own)
            }
            guard let file else { continue }
            let timing = (entry["timing"] as? [Any])?.first as? [Any]
            let start = timing.flatMap { $0.count == 2 ? number($0[0]) : nil }
            let end = timing.flatMap { $0.count == 2 ? number($0[1]) : nil }
            if method == .single, start == nil || end == nil { continue }
            if let start, let end, end <= start { continue }
            result[code] = Segment(file: file, start: start, end: end)
        }
        if result.isEmpty, method == .single, main == nil { throw ParseError.missingAudioFile }
        return MechvibesPack(name: name, author: author, method: method, definitions: result)
    }

    // 第 1 版：single 是 {"30": [start, duration]} 加 "sound"；multi 是 {"30": "a.wav"}。
    private static func parseV1(_ root: [String: Any], defines: [String: Any], name: String,
                                author: String) throws -> MechvibesPack {
        let type = (root["key_define_type"] as? String)?.lowercased() ?? "single"
        let method: Method = type == "multi" ? .multi : .single
        var result: [String: Segment] = [:]
        switch method {
        case .single:
            guard let sound = root["sound"] as? String, !sound.isEmpty else { throw ParseError.missingAudioFile }
            let file = try cleanPath(sound)
            for (key, value) in defines.sorted(by: { $0.key < $1.key }).prefix(maxDefinitions) {
                guard let code = TypingKeyCodes.web(v1Key: key), let pair = value as? [Any], pair.count >= 2,
                      let start = number(pair[0]), let length = number(pair[1]), length > 0 else { continue }
                result[code] = Segment(file: file, start: start, end: start + length)
            }
        case .multi:
            for (key, value) in defines.sorted(by: { $0.key < $1.key }).prefix(maxDefinitions) {
                guard let code = TypingKeyCodes.web(v1Key: key), let raw = value as? String,
                      !raw.isEmpty, raw != "null" else { continue }
                result[code] = Segment(file: try cleanPath(raw))
            }
        }
        return MechvibesPack(name: name, author: author, method: method, definitions: result)
    }

    /// 相对路径整理：反斜杠换成 /，去掉开头的 ./；绝对路径和带 .. 的（会跑出包的文件夹）不收。
    public static func cleanPath(_ raw: String) throws -> String {
        var path = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\", with: "/")
        while path.hasPrefix("./") { path.removeFirst(2) }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !path.isEmpty, !path.hasPrefix("/"), !parts.isEmpty,
              !parts.contains(where: { $0 == ".." || $0 == "." }), !path.contains("\0") else {
            throw ParseError.unsafePath(raw)
        }
        return parts.joined(separator: "/")
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: return n.doubleValue.isFinite ? n.doubleValue : nil
        case let s as String: return Double(s).flatMap { $0.isFinite ? $0 : nil }
        default: return nil
        }
    }

    /// 按下一个 macOS 键码时放哪一段。包里没定义这个键时：回车、空格、删除互相不借，
    /// 普通键从定义了的字母键里随机借一个（再没有就从全部定义里借），`random` 取 [0, 1)。
    public func segment(keyCode: Int, random: Double) -> Segment? {
        if let code = TypingKeyCodes.web(keyCode: keyCode), let own = definitions[code] { return own }
        switch TypingSoundKey.of(keyCode: keyCode) {
        case .none: return nil
        case .enter: if let s = definitions["Enter"] ?? definitions["NumpadEnter"] { return s }
        case .space: if let s = definitions["Space"] { return s }
        case .backspace: if let s = definitions["Backspace"] ?? definitions["Delete"] { return s }
        case .key: break
        }
        let pool = fallbackCodes
        guard !pool.isEmpty else { return nil }
        let index = min(pool.count - 1, Int(min(max(random, 0), 0.999_999) * Double(pool.count)))
        return definitions[pool[index]]
    }

    /// 借声音时挑的键：定义了的字母键，没有时全部定义的键，按名字排。
    public var fallbackCodes: [String] {
        let letters = TypingKeyCodes.letters.filter { definitions[$0] != nil }
        return letters.isEmpty ? definitions.keys.sorted() : letters
    }
}

/// 导入的声音包在 Application Support 下放哪。
public enum TypingSoundPacks {
    public static let folderName = "TypingSoundPacks"
    /// .zip 最大多少字节。
    public static let maxZipBytes = 80 * 1024 * 1024
    /// 一个声音文件最长解多少秒（一般的 single 包整个文件一分钟上下）。
    public static let maxFileSeconds: Double = 180
    /// 一段按键声音最长放多少秒。
    public static let maxSegmentSeconds: Double = 1.5

    /// 一段 [startMs, endMs) 毫秒对到第几帧到第几帧：先在 Double 里夹到文件范围内再转 Int
    /// （config.json 里写个 1e300 也不会溢出崩溃），最长 `maxSegmentSeconds` 秒。
    /// 太短（不到 16 帧）或整段落在文件外时返回 nil。
    public static func frameRange(startMs: Double?, endMs: Double?, sampleRate: Double,
                                  totalFrames: Int) -> Range<Int>? {
        guard sampleRate.isFinite, sampleRate > 0, totalFrames > 0 else { return nil }
        let total = Double(totalFrames)
        func frame(_ ms: Double) -> Double {
            guard ms.isFinite else { return ms > 0 ? total : 0 }
            return min(total, max(0, (ms / 1000 * sampleRate).rounded()))
        }
        let start = frame(startMs ?? 0)
        let end = min(endMs.map(frame) ?? total, start + (maxSegmentSeconds * sampleRate).rounded())
        guard end - start > 16 else { return nil }
        return Int(start)..<Int(end)
    }

    /// 包的显示名：config 里的名字，没有时用文件夹或 zip 的名字。
    public static func displayName(_ pack: MechvibesPack, fallback: String) -> String {
        let name = pack.name.isEmpty ? fallback : pack.name
        return String(name.prefix(60))
    }

    /// 包的 id 和文件夹名：只用小写字母、数字和横线。
    public static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}

// MARK: - Pro

extension ProLicenseGate {
    /// 打字音效的 Pro 款（青轴以外）和导入 Mechvibes 声音包能不能用。没解锁时选着的
    /// Pro 款按青轴响，选择照旧存着，见 `TypingSoundGate.effectiveChoice`。
    public static func typingSoundsProActive(unlocked: Bool) -> Bool {
        canUse(.typingSounds, unlocked: unlocked)
    }
}
