import Foundation

// 界面文字的本地化。
//
// 源语言是简体中文：代码里写的中文就是 Localizable.xcstrings 的键，英文译文放在
// String Catalog 里。SwiftUI 的 Text("…") 这类字面量由系统自动查表；字符串变量、
// Core 返回给界面的文案、通知、菜单和 NSAlert 用 `tr("…")` 查表。
//
// `tr` 把插值统一记成 `%@`，参数先按普通字符串插值转成文字再填回去，所以键只和
// 中文原文有关，和插值的类型无关；字面量里的 `%` 在有插值时记成 `%%`。查不到时
// 原样返回中文。测试包的 Bundle.main 里没有这张表，所以测试里得到的始终是中文。

/// `tr("…")` 的参数：字面量本身就是键。
struct L10nString: ExpressibleByStringInterpolation, Sendable {
    let key: String
    let arguments: [String]

    init(stringLiteral value: String) {
        key = value
        arguments = []
    }

    init(stringInterpolation: Interpolation) {
        key = stringInterpolation.key
        arguments = stringInterpolation.arguments
    }

    struct Interpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []

        init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity + interpolationCount * 2)
        }

        mutating func appendLiteral(_ literal: String) {
            key += literal.replacingOccurrences(of: "%", with: "%%")
        }

        mutating func appendInterpolation<T>(_ value: T) {
            key += "%@"
            arguments.append(String(describing: value))
        }

        mutating func appendInterpolation(_ value: some CVarArg, specifier: String) {
            key += "%@"
            arguments.append(String(format: specifier, value))
        }

        mutating func appendInterpolation<F: FormatStyle>(_ value: F.FormatInput, format: F)
        where F.FormatOutput == String {
            key += "%@"
            arguments.append(format.format(value))
        }
    }
}

enum L10n {
    /// 查不到时的占位值，用来分辨“表里没有”。
    private static let missing = "\u{0}missing"

    static func lookup(_ key: String) -> String? {
        let value = Bundle.main.localizedString(forKey: key, value: missing, table: nil)
        return value == missing ? nil : value
    }

    static func fill(_ format: String, _ arguments: [String]) -> String {
        guard !arguments.isEmpty else { return format }
        return String(format: format, arguments: arguments.map { NSString(string: $0) as CVarArg })
    }

    /// 当前界面是否是英文。看的是表里的一条哨兵，测试包里永远是 false。
    static var isEnglish: Bool { lookup("__language__") == "en" }
}

/// 把中文原文换成当前界面语言的文字。
func tr(_ text: L10nString) -> String {
    L10n.fill(L10n.lookup(text.key) ?? text.key, text.arguments)
}

/// 同一个中文在不同地方意思不同（“日”可以是星期日，也可以是“日、周、月、年”的日）
/// 时，用带说明的键 `日 (period)` 区分；表里没有这条时退回普通的键。
func tr(_ text: L10nString, context: String) -> String {
    let format = L10n.lookup("\(text.key) (\(context))") ?? L10n.lookup(text.key) ?? text.key
    return L10n.fill(format, text.arguments)
}

/// 运行时才知道的中文（权限名、节日名这类同时当标识用的数据），显示前查表。
func trKey(_ key: String) -> String {
    L10n.lookup(key) ?? key
}

/// 设置 ▸ 通用 ▸ 语言。手动选择写进本应用的 AppleLanguages，重启后生效。
enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    static let defaultsKey = "AppleLanguages"

    var title: String {
        switch self {
        case .system: tr("跟随系统")
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    /// 本应用自己域里存的选择；只认第一项，没有或不认识就是跟随系统。
    static func current(_ defaults: UserDefaults = .standard) -> AppLanguage {
        guard let stored = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[defaultsKey]
                as? [String],
              let first = stored.first else { return .system }
        if first.hasPrefix("zh") { return .simplifiedChinese }
        if first.hasPrefix("en") { return .english }
        return .system
    }

    func apply(_ defaults: UserDefaults = .standard) {
        switch self {
        case .system: defaults.removeObject(forKey: Self.defaultsKey)
        case .simplifiedChinese, .english: defaults.set([rawValue], forKey: Self.defaultsKey)
        }
    }
}
