import Foundation

/// 隔空投送面板的「最近发过」：码头经手、系统报告发送成功的文件，最多 5 个。
///
/// 只记文件位置和发送时间，存在小组件自己的配置里（`sent` 路径、`sentAt`
/// 同样顺序的秒数），不是设置项。系统不告诉别的 App 隔空投送的记录，所以
/// 只有从卡片或面板发出去的才在这里。
public enum AirDropHistory {
    public static let pathsKey = "sent"
    public static let datesKey = "sentAt"
    public static let limit = 5

    public struct Entry: Equatable, Sendable {
        public var path: String
        public var sent: Date

        public init(path: String, sent: Date) {
            self.path = path
            self.sent = sent
        }

        public var name: String { (path as NSString).lastPathComponent }
    }

    public static func read(_ config: WidgetConfig) -> [Entry] {
        let paths = config.strings(pathsKey)
        var stamps: [Double] = []
        if case .list(let list)? = config.values[datesKey] {
            stamps = list.map { value -> Double in
                if case .number(let n) = value { return n }
                return 0
            }
        }
        return paths.enumerated().map { index, path in
            Entry(path: path, sent: Date(timeIntervalSince1970: index < stamps.count ? stamps[index] : 0))
        }
    }

    public static func write(_ entries: [Entry], into config: inout WidgetConfig) {
        config.set(pathsKey, .list(entries.map { .string($0.path) }))
        config.set(datesKey, .list(entries.map { .number($0.sent.timeIntervalSince1970) }))
    }

    /// 一次发了几个文件，每个一行，按发送的顺序排在最前；同一个文件再发只留最新一次。
    public static func recording(_ paths: [String], at now: Date, into entries: [Entry],
                                 limit: Int = AirDropHistory.limit) -> [Entry] {
        var seen = Set<String>()
        let incoming = paths.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !incoming.isEmpty else { return entries }
        let fresh = incoming.map { Entry(path: $0, sent: now) }
        return Array((fresh + entries.filter { !seen.contains($0.path) }).prefix(max(0, limit)))
    }

    public static func removing(_ path: String, from entries: [Entry]) -> [Entry] {
        entries.filter { $0.path != path }
    }

    /// 行里第二行：今天「10:02」、昨天「昨天」、一周内「周日」、更早「10月3日」；
    /// 文件已经不在了写「找不到了」。
    public static func caption(_ entry: Entry, exists: Bool, now: Date,
                               calendar: Calendar = .current) -> String {
        exists ? FileDate.short(entry.sent, now: now, calendar: calendar) : tr("找不到了")
    }

    /// 点「再发一次」时文件不在了的提示。
    public static func goneNotice(_ name: String) -> String {
        tr("「\(name)」找不到了，可能被移走或删掉了")
    }
}
