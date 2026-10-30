import AppKit

/// 消息灵动岛认 App 名用的额外名字：从这台 Mac 上装的信息、WhatsApp、微信自己的包里读
/// 显示名（Info.plist 的 CFBundleDisplayName / CFBundleName，各语言 InfoPlist.strings 或
/// InfoPlist.loctable 里的本地化名字，访达显示名），交给 Core 的 `NotchAppNames`。
///
/// 横幅上写的 App 名就是系统按当前语言取的这个显示名，内置名字表没收的语言或 App 改了名
/// （比如微信 4.x 换显示名）时靠它补。只读文件，不启动 App；读不到就是没有，照常用内置表。
enum NotchAppNameCatalog {
    /// 读一遍装着的三个 App。在后台队列上调用（几次小文件读取）。
    static func load() -> NotchAppNames {
        var extra: [NotchMessageApp: [String]] = [:]
        for app in NotchMessageApp.allCases {
            var names: [String] = []
            for id in app.bundleIDs {
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
                names += Self.names(at: url)
            }
            if !names.isEmpty { extra[app] = names }
        }
        return NotchAppNames(extra: extra)
    }

    private static let keys = ["CFBundleDisplayName", "CFBundleName"]

    /// 一个 App 包里所有能当显示名的字。
    static func names(at url: URL) -> [String] {
        var names: [String] = []
        func add(_ raw: Any?) {
            guard let text = raw as? String else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !names.contains(trimmed) { names.append(trimmed) }
        }
        let shown = FileManager.default.displayName(atPath: url.path)
        add(shown.hasSuffix(".app") ? String(shown.dropLast(4)) : shown)
        guard let bundle = Bundle(url: url) else { return names }
        for key in keys {
            add(bundle.localizedInfoDictionary?[key])
            add(bundle.infoDictionary?[key])
        }
        // 各语言的 InfoPlist.strings（老格式）。
        for localization in bundle.localizations {
            guard let path = bundle.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil,
                                         forLocalization: localization),
                  let table = NSDictionary(contentsOfFile: path) else { continue }
            for key in keys { add(table[key]) }
        }
        // 新格式 InfoPlist.loctable：一个文件里按语言分组。
        if let path = bundle.path(forResource: "InfoPlist", ofType: "loctable"),
           let table = NSDictionary(contentsOfFile: path) {
            for case let entry as NSDictionary in table.allValues {
                for key in keys { add(entry[key]) }
            }
        }
        return names
    }
}
