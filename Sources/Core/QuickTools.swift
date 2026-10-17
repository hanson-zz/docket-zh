import Foundation

// 快速开关里 8 个新工具的纯逻辑：截图识字、取色器、演示模式、只锁键盘、
// 二维码、镜子、低电量模式、重启程序坞和访达。放在 Core 里方便测试，
// 真正动系统的部分在 Services/QuickTools.swift。

// MARK: - 截图识字

public enum RecognizedText {
    /// 把识别出的每一行拼成剪贴板里的文字：去掉首尾空白，丢掉空行。
    public static func joined(_ lines: [String]) -> String {
        lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// 轻提示里的一行预览：换行变空格，超过 limit 个字截断加省略号。
    public static func preview(_ text: String, limit: Int = 24) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard flat.count > max(limit, 1) else { return flat }
        return String(flat.prefix(max(limit, 1))) + "…"
    }
}

// MARK: - 取色器

public extension ColorCode {
    /// 取色后的轻提示：`已复制 #1C1C1E（RGB 28, 28, 30）`。
    var copiedHint: String {
        let b = bytes
        return "已复制 \(hex)（RGB \(b.r), \(b.g), \(b.b)）"
    }
}

// MARK: - 二维码

public enum QRText {
    /// 识别结果是不是可以直接打开的网址：只认 http 和 https，而且要有主机名；
    /// 以 www. 开头、没写协议的也当作 https 网址。带空白的不算。
    public static func webURL(_ text: String) -> URL? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        let candidate = raw.lowercased().hasPrefix("www.") ? "https://" + raw : raw
        guard let parts = URLComponents(string: candidate),
              let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parts.host, !host.isEmpty, host.contains(".") || host == "localhost",
              parts.user == nil, let url = parts.url else { return nil }
        return url
    }

    /// 剪贴板文字能不能生成二维码：空白不行，太长也不行（二维码最多约
    /// 2953 字节，按 M 级纠错留余量取 2000）。
    public static let maxBytes = 2000

    public enum Check: Equatable {
        case ok(String)
        case empty
        case tooLong
    }

    public static func check(_ text: String?) -> Check {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard trimmed.utf8.count <= maxBytes else { return .tooLong }
        return .ok(trimmed)
    }

    /// 二维码原图每个模块只有 1 像素，放大要用整数倍才不糊：
    /// 取不超过目标边长的最大整数倍，至少 1 倍。
    public static func scale(moduleSide: Double, target: Double) -> Int {
        guard moduleSide > 0, target.isFinite, moduleSide.isFinite else { return 1 }
        return max(1, Int((target / moduleSide).rounded(.down)))
    }
}

// MARK: - 演示模式

/// 打开演示模式前的样子，关掉时照这个恢复。存进 UserDefaults，码头重启后也能恢复。
public struct PresentationSnapshot: Codable, Hashable, Sendable {
    /// 打开前桌面图标是否已经隐藏。
    public var desktopHidden: Bool
    /// 打开前是否已经在保持唤醒。
    public var keepAwake: Bool
    /// 被演示模式隐藏的 App（进程号），关掉时只把这些重新显示。
    public var hiddenApps: [Int32]
    /// 访达单独记：改桌面图标要重启访达，进程号会变，按 bundle ID 找。
    public var hidFinder: Bool

    public init(desktopHidden: Bool, keepAwake: Bool, hiddenApps: [Int32] = [], hidFinder: Bool = false) {
        self.desktopHidden = desktopHidden
        self.keepAwake = keepAwake
        self.hiddenApps = hiddenApps
        self.hidFinder = hidFinder
    }

    /// 宽松读取：少了哪个键都用默认值，以后多了键也照样读。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        desktopHidden = try c.decodeIfPresent(Bool.self, forKey: .desktopHidden) ?? false
        keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? false
        hiddenApps = try c.decodeIfPresent([Int32].self, forKey: .hiddenApps) ?? []
        hidFinder = try c.decodeIfPresent(Bool.self, forKey: .hidFinder) ?? false
    }
}

public enum PresentationPlan {
    /// 一个正在运行的 App，在演示模式眼里只需要这几样。
    public struct App: Hashable, Sendable {
        public var pid: Int32
        public var isRegular: Bool
        public var isHidden: Bool
        public var isFrontmost: Bool
        public var isSelf: Bool
        public var isFinder: Bool

        public init(pid: Int32, isRegular: Bool, isHidden: Bool, isFrontmost: Bool, isSelf: Bool,
                    isFinder: Bool = false) {
            self.pid = pid
            self.isRegular = isRegular
            self.isHidden = isHidden
            self.isFrontmost = isFrontmost
            self.isSelf = isSelf
            self.isFinder = isFinder
        }
    }

    /// 要做的几件事，nil 表示这一项不用动。
    public struct Changes: Equatable, Sendable {
        public var setDesktopHidden: Bool?
        public var setKeepAwake: Bool?
        public var hide: [Int32]
        public var unhide: [Int32]
        public var hideFinder: Bool = false
        public var unhideFinder: Bool = false
    }

    /// 打开：记下原样，隐藏桌面、保持唤醒，隐藏除了最前面的 App 和码头之外
    /// 还显示着的普通 App。已经是目标状态的项不重复去改。
    public static func enter(desktopHidden: Bool, keepAwake: Bool,
                             apps: [App]) -> (snapshot: PresentationSnapshot, changes: Changes) {
        let visible = apps.filter { $0.isRegular && !$0.isHidden && !$0.isFrontmost && !$0.isSelf }
        let hide = visible.filter { !$0.isFinder }.map(\.pid)
        let hideFinder = visible.contains(where: \.isFinder)
        let snapshot = PresentationSnapshot(desktopHidden: desktopHidden, keepAwake: keepAwake,
                                            hiddenApps: hide, hidFinder: hideFinder)
        let changes = Changes(setDesktopHidden: desktopHidden ? nil : true,
                              setKeepAwake: keepAwake ? nil : true,
                              hide: hide, unhide: [], hideFinder: hideFinder)
        return (snapshot, changes)
    }

    /// 关闭：桌面图标和保持唤醒回到打开前的样子（和现在一样就不动），
    /// 只把演示模式隐藏的、现在还在运行而且还隐藏着的 App 显示回来。
    public static func exit(_ snapshot: PresentationSnapshot, desktopHidden: Bool, keepAwake: Bool,
                            apps: [App]) -> Changes {
        let stillHidden = Set(apps.filter { $0.isHidden && !$0.isFinder }.map(\.pid))
        let restartsFinder = desktopHidden != snapshot.desktopHidden
        // 访达要重启时进程是新的，没法先看是不是还藏着，直接按记录显示回来。
        let finderHidden = restartsFinder || apps.contains { $0.isFinder && $0.isHidden }
        return Changes(setDesktopHidden: restartsFinder ? snapshot.desktopHidden : nil,
                       setKeepAwake: keepAwake == snapshot.keepAwake ? nil : snapshot.keepAwake,
                       hide: [],
                       unhide: snapshot.hiddenApps.filter { stillHidden.contains($0) },
                       unhideFinder: snapshot.hidFinder && finderHidden)
    }
}

// MARK: - 只锁键盘

public enum KeyboardLockTiming {
    /// 长按多久解锁。
    public static let holdSeconds: Double = 3
    /// 多久后自动解锁。
    public static let autoUnlockSeconds: Double = 600

    /// 长按进度 0...1。
    public static func holdProgress(elapsed: Double) -> Double {
        guard elapsed.isFinite, elapsed > 0 else { return 0 }
        return min(1, elapsed / holdSeconds)
    }

    /// 浮窗上的剩余时间，例如 `9:05 后自动解锁`。
    public static func remainingText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d 后自动解锁", total / 60, total % 60)
    }
}

// MARK: - 低电量模式

public enum LowPowerSetting {
    /// `pmset -g` 里读到的设置：用的是哪个键、现在是不是低电量。
    /// 多数 Mac 是 `lowpowermode 0/1`；带“高性能模式”的机型是
    /// `powermode 0/1/2`（自动、低电量、高性能）。
    public struct Reading: Equatable, Sendable {
        public var key: String
        public var isOn: Bool
    }

    public static func parse(_ output: String) -> Reading? {
        var fallback: Reading?
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2, let value = Int(parts[1]) else { continue }
            switch parts[0] {
            case "lowpowermode": return Reading(key: "lowpowermode", isOn: value == 1)
            case "powermode": fallback = fallback ?? Reading(key: "powermode", isOn: value == 1)
            default: continue
            }
        }
        return fallback
    }

    /// 切换用的命令。键名只接受读到的这两个，免得拼进别的东西。
    public static func command(key: String, on: Bool) -> String? {
        guard key == "lowpowermode" || key == "powermode" else { return nil }
        return "/usr/bin/pmset -a \(key) \(on ? 1 : 0)"
    }
}
