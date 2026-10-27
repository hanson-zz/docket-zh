import AppKit
import SwiftUI
import WidgetKit

// 系统小组件扩展里共用的东西：读快照、按码头的界面语言查表、配色和图片。
//
// 扩展是沙盒里的独立进程，只编 Sources/Core/SystemWidgetSnapshot.swift 这一个 Core
// 文件。数据由主 App 写进 ~/Library/Application Support/com.docket-zh.app/SystemWidgets，
// 见那个文件开头的说明。

enum Shared {
    static let store = SystemWidgetStore.standard()

    /// 快照叠上还没合并的点按。主 App 从没运行过（或文件读不出来）时 nil。
    static func snapshot(now: Date = .now) -> SystemWidgetSnapshot? {
        store.current(now: now)
    }

    /// 码头里选的界面语言；没有快照时跟系统。
    static func language(_ snapshot: SystemWidgetSnapshot?) -> String {
        if let snapshot { return snapshot.language }
        let first = Locale.preferredLanguages.first ?? "zh-Hans"
        return first.hasPrefix("zh") ? "zh-Hans" : "en"
    }

    /// 告诉主 App 有新的点按（主 App 也盯着动作文件夹，这条只是让它更快）。
    static func notifyApp() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(SystemWidgetStore.actionNotification), object: nil, userInfo: nil,
            deliverImmediately: true)
    }
}

/// 按码头的界面语言取文字：键就是简体中文原文（和主 App 的 `tr` 同一张表），英文从
/// 扩展自己带的 Localizable 表里查，查不到时用中文。插值统一写成 `%@`。
struct Words: Sendable {
    let lang: String

    var isEnglish: Bool { !lang.hasPrefix("zh") }

    private static let english: Bundle? = {
        guard let path = Bundle.main.path(forResource: "en", ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }()

    func callAsFunction(_ key: String, _ args: String...) -> String {
        var format = key
        if isEnglish, let bundle = Self.english {
            format = bundle.localizedString(forKey: key, value: key, table: nil)
        }
        guard !args.isEmpty else { return format }
        return String(format: format, arguments: args.map { NSString(string: $0) as CVarArg })
    }

    var locale: Locale { Locale(identifier: isEnglish ? "en" : "zh-Hans") }

    /// 时:分，按语言习惯（中文 24 小时制）。
    func time(_ date: Date, zone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: date)
    }

    /// 「10月27日 周二」/「Tue, Oct 27」。
    func dayLine(_ date: Date, zone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.setLocalizedDateFormatFromTemplate(isEnglish ? "EEEMMMd" : "MMMdEEE")
        return formatter.string(from: date)
    }

    func hour(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter.string(from: date)
    }
}

enum Look {
    /// 小熊猫橙红，码头的主题色。
    static let panda = Color(red: 0xE0 / 255, green: 0x68 / 255, blue: 0x2C / 255)
    static let water = Color(red: 0x2F / 255, green: 0x8F / 255, blue: 0xE0 / 255)

    static func color(hex: String?) -> Color? {
        guard let hex, let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16)
        else { return nil }
        return Color(red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }

    /// 浅色纸上用深墨，深色纸上用浅墨。
    static func inkIsDark(on hex: String) -> Bool {
        guard let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16)
        else { return true }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.55
    }
}

/// Resources/Pet 和 Resources/Water 里的小熊猫（和扩展栏卡片同一套图）。
enum PetArt {
    static func image(_ name: String) -> Image? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: image)
    }

    /// 找不到就退回小熊猫坐着的那张。
    static func view(_ name: String, height: CGFloat) -> some View {
        (image(name) ?? image("pet-panda-idle") ?? Image(systemName: "pawprint.fill"))
            .resizable()
            .widgetAccentedRenderingMode(.fullColor)
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

/// 没有快照或没有对应卡片时的提示：小熊猫加一句话。
struct EmptyHint: View {
    var words: Words
    var line: String

    var body: some View {
        VStack(spacing: 6) {
            PetArt.view("pet-panda-idle", height: 54)
            Text(verbatim: line)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func noApp(_ words: Words) -> EmptyHint {
        EmptyHint(words: words, line: words("打开码头一次，就能在这里看到"))
    }

    static func noCard(_ words: Words, kind: String) -> EmptyHint {
        EmptyHint(words: words, line: words("先在扩展栏添加「%@」卡片", kind))
    }
}

/// 卡片标题行：小字、次要色。
struct Caption: View {
    var text: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Look.panda)
                    .widgetAccentable()
            }
            Text(verbatim: text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

extension View {
    /// 跟随系统的小组件底：桌面上由系统做成玻璃或着色，浅色、深色都对。
    func dockBackground() -> some View {
        containerBackground(.background, for: .widget)
    }
}

/// 下一个零点，纪念日、喝水按天变的小组件在这时刷新。
func nextMidnight(after date: Date) -> Date {
    let calendar = Calendar.current
    return calendar.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0, second: 5),
                             matchingPolicy: .nextTime) ?? date.addingTimeInterval(3600)
}
