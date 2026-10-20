import Foundation

// 截图工具、最近截图、取色器三张卡片分工后的纯逻辑：
// 截图工具是“动作”（截区域、截窗口、识字、录屏），最近截图是“结果”（一张大图加几张
// 缩略图），取色器是“最近颜色”。快速开关里的识字、取色按钮只是一键快捷入口，
// 取到的颜色和取色器记在同一个历史里（`ColorHistory`）。

// MARK: - 截图工具的四个动作

/// 截图工具能放上卡片的动作。卡片上放哪几个、什么顺序由 `CaptureButtons` 决定
/// （最多 4 个，默认截区域、截窗口、识字、录区域）。
public enum CaptureAction: String, CaseIterable, Sendable, Identifiable {
    case region, window, text, record, recordRegion

    public var id: String { rawValue }

    /// 按钮下面的两个字。
    public var title: String {
        switch self {
        case .region: tr("截区域")
        case .window: tr("截窗口")
        case .text: tr("识字")
        case .record: tr("录屏")
        case .recordRegion: tr("录区域")
        }
    }

    /// 悬停提示，说点一下会发生什么。
    public var help: String {
        switch self {
        case .region: tr("框选一块区域截图")
        case .window: tr("点选一个窗口截图")
        case .text: tr("框选一块区域，识别其中的文字并拷贝")
        case .record: tr("录制整个屏幕，再点一次停止，存到截图文件夹")
        case .recordRegion: tr("框选一块区域录屏（单击录整个屏幕），再点一次停止")
        }
    }

    public var symbol: String {
        switch self {
        case .region: "rectangle.dashed"
        case .window: "macwindow"
        case .text: "text.viewfinder"
        case .record: "record.circle"
        case .recordRegion: "rectangle.dashed.badge.record"
        }
    }

    /// 录屏的两个动作：录着时按钮都变成停止。
    public var isRecording: Bool { self == .record || self == .recordRegion }

    /// 识字和快速开关里的“截图识字”是同一个 Pro 工具，锁跟着它走。
    public var quickToggle: QuickToggle? {
        self == .text ? .textCapture : nil
    }
}

/// 截图和录屏的文件名，和 macOS 自己起的一样，最近截图才认得出来
/// （见 `ScreenshotNaming.prefixes`）。
public enum CaptureFileName {
    public static func screenshot(at date: Date, timeZone: TimeZone = .current,
                                  format: CaptureFormat = .png) -> String {
        "截屏\(stamp(date, timeZone: timeZone)).\(format.fileExtension)"
    }

    public static func recording(at date: Date, timeZone: TimeZone = .current) -> String {
        "录屏\(stamp(date, timeZone: timeZone)).mov"
    }

    private static func stamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: date)
    }
}

/// 录屏的计时文字：“0:07”“12:34”“1:02:03”。
public enum RecordingClock {
    public static func text(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds : 0))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - 最近截图：一张大图加几张缩略图

/// 底栏卡片上最新一张画大，右边 2×2 四格放后面的；放不下时最后一格写“+N”。
public enum RecentShots {
    /// 右边的格子数。
    public static let slots = 4

    public struct Strip: Equatable, Sendable {
        /// 有没有大图（一张截图都没有时没有）。
        public var hero: Bool
        /// 画成缩略图的张数（不含大图）。
        public var thumbs: Int
        /// 最后一格写的“+N”，0 表示不写。
        public var more: Int
    }

    public static func strip(count: Int) -> Strip {
        let total = max(0, count)
        guard total > 0 else { return Strip(hero: false, thumbs: 0, more: 0) }
        let rest = total - 1
        if rest <= slots { return Strip(hero: true, thumbs: rest, more: 0) }
        return Strip(hero: true, thumbs: slots - 1, more: rest - (slots - 1))
    }
}

// MARK: - 取色历史（取色器卡片和快速开关共用）

/// 最近取的颜色，取色器卡片、它的面板和快速开关里的取色按钮共用一份，存在
/// UserDefaults 里（逗号分隔的 HEX，新的在前）。
///
/// 以前每张取色器卡片把颜色记在自己的配置 `recent` 里。那份不删也不再写：显示时
/// 共享历史在前、卡片自己的旧颜色接在后面（去重、截断），所以升级后卡片上的颜色
/// 一个不少；再取到一样的颜色时它挪到最前面。
public enum ColorHistory {
    public static let defaultsKey = "colorPicker.history"
    /// 卡片配置里旧的颜色列表的键。
    public static let legacyKey = "recent"
    public static let limit = 12

    /// 解析存着的字符串：认不出的丢掉，统一成大写 `#RRGGBB`，去重。
    public static func decode(_ raw: String) -> [String] {
        normalized(raw.split(separator: ",").map(String.init))
    }

    public static func encode(_ list: [String]) -> String {
        normalized(list).joined(separator: ",")
    }

    /// 卡片上显示的颜色：共享历史在前，卡片自己的旧颜色在后。
    public static func merged(shared: [String], legacy: [String], limit: Int = limit) -> [ColorCode] {
        Array(normalized(shared + legacy).prefix(max(0, limit))).compactMap { ColorCode(hex: $0) }
    }

    /// 记一个新取的颜色，返回新的存储字符串。从取色器卡片取时把那张卡片的旧颜色
    /// 一起并进来，以后共享历史就是完整的。
    public static func adding(_ code: ColorCode, to raw: String, legacy: [String] = [],
                              limit: Int = limit) -> String {
        let current = normalized(decode(raw) + legacy)
        return encode(RecentList.inserting(code.hex, into: current, limit: limit))
    }

    public static func stored(in defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: defaultsKey) ?? ""
    }

    public static func record(_ code: ColorCode, legacy: [String] = [],
                              in defaults: UserDefaults = .standard) {
        defaults.set(adding(code, to: stored(in: defaults), legacy: legacy), forKey: defaultsKey)
    }

    private static func normalized(_ list: [String]) -> [String] {
        var seen = Set<String>()
        return list.compactMap { ColorCode(hex: $0)?.hex }.filter { seen.insert($0).inserted }
    }
}
