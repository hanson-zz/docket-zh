import Foundation

// MARK: - 消息灵动岛：每条横幅的分析记录

/// 读到的一条横幅认成了什么、为什么。设置里「复制诊断信息」用：不含发件人和消息内容，
/// summary 那一行沿用 `NotchBannerParser.summaryReport` 的规则（像 App 名才写原文，否则只写长度）。
public struct NotchBannerAnalysis: Codable, Equatable, Sendable {
    /// 最终结果。
    public enum Outcome: String, Codable, Sendable, CaseIterable {
        /// 认出来了，是启用的 App 的一条消息。
        case message
        /// 认出来了，但设置里这个 App 没打开。
        case appOff = "app-off"
        /// 认不出是哪个 App。
        case notRecognised = "not-recognised"
        /// 认出了 App，但横幅上一个字都没有（多半是刚出现、字还没填上就读了）。
        case noText = "no-text"
        /// 设置里「发一条测试通知」发出的那条。
        case test
    }

    public var at: Date
    public var path: [Int]
    public var stacked: Bool
    /// 认出的 App（rawValue），认不出但有像 App 名的字时为 other，什么都没有时为 none。
    public var app: String
    public var has: [String]
    /// summary 那一行（`summaryReport`）。
    public var summary: String
    public var matched: String
    public var bundleHint: String
    public var help: String
    public var actions: [String]
    public var close: String
    /// 横幅元素上不常见的属性名。
    public var attributes: [String]
    public var outcome: Outcome
    /// 认出的 App，结果是 message / app-off / no-text 时有。
    public var outcomeApp: String?
    /// 开始观察时屏幕上已经有的（只记下不弹）。
    public var priming: Bool = false
    /// 读这条时程序坞上三个 App 的角标（只有数字或有无，没有内容），读不到时为空。
    public var dock: String?

    /// 诊断里 `->` 后面那句。
    public var verdict: String {
        switch outcome {
        case .message: "message from \(outcomeApp ?? "?")"
        case .appOff: "\(outcomeApp ?? "?") is turned off"
        case .notRecognised: "app not recognised"
        case .noText: "\(outcomeApp ?? "?") banner has no text"
        case .test: "test banner"
        }
    }

    /// 诊断里的三行（不带时间）。
    public var lines: [String] {
        var head = "banner path=\(path) stacked=\(stacked) app=\(app) has=[\(has.joined(separator: ","))] -> \(verdict)"
        if priming { head += " (on screen at start)" }
        var extra = ["matched=\(matched)", "bundle-hint=\(bundleHint)", "help=\(help)",
                     "actions=[\(actions.joined(separator: ","))]", "close=\(close)"]
        if !attributes.isEmpty { extra.append("attrs=[\(attributes.joined(separator: ","))]") }
        if let dock { extra.append("dock=[\(dock)]") }
        return [head, "  " + summary, "  " + extra.joined(separator: " ")]
    }
}

extension NotchBannerParser {
    /// 分析一条横幅。`testTokens` 是最近发过的测试通知暗号：只有认不出是三个 App 之一、
    /// 字里又带着其中一个暗号的才算测试横幅（真实消息里碰巧有「#1234」也不会被当成测试）。
    public static func analyse(_ b: NotchBanner, path: [Int], enabled: [NotchMessageApp], testTokens: [String] = [],
                               names: NotchAppNames = .builtIn, at now: Date = Date()) -> NotchBannerAnalysis {
        let has = [b.header != nil ? "header" : nil, b.title != nil ? "title" : nil,
                   b.subtitle != nil ? "subtitle" : nil, b.body != nil ? "body" : nil,
                   b.summary != nil ? "summary" : nil].compactMap { $0 }
        let recognised = recognise(b, names: names)
        let outcome: NotchBannerAnalysis.Outcome
        var outcomeApp: String?
        if recognised == nil, testTokens.contains(where: { NotchMessageProbe.matches(b, token: $0) }) {
            outcome = .test
        } else if let incoming = incoming(b, enabled: enabled, names: names) {
            outcome = .message
            outcomeApp = incoming.app.rawValue
        } else if let known = recognised?.app {
            outcomeApp = known.rawValue
            outcome = enabled.contains(known) ? .noText : .appOff
        } else {
            outcome = .notRecognised
        }
        let shown = recognised?.app.rawValue ?? (appLabel(b, names: names) == nil ? "none" : "other")
        return NotchBannerAnalysis(
            at: now, path: path, stacked: b.stacked, app: shown, has: has,
            summary: summaryReport(b, recognised: recognised),
            matched: recognised?.source ?? "none",
            bundleHint: bundleHint(b)?.rawValue ?? "none",
            help: b.hints.isEmpty ? "no" : "present",
            actions: b.actionNames.prefix(8).map { reportWord($0) },
            close: b.close?.kind ?? "none",
            attributes: b.extraAttributes.prefix(12).map { reportWord($0) },
            outcome: outcome, outcomeApp: outcomeApp)
    }

    /// 认同一条横幅用的键：有系统标识用标识，没有时用字算一个摘要（FNV-1a，只用来比较，
    /// 不能还原出内容）。同一条横幅会被读好几次（出现、排版变化、补读），按它合成一条记录。
    public static func identityKey(_ b: NotchBanner) -> String {
        if let id = cleaned(b.identifier) { return "id:" + id }
        let joined = [b.header, b.title, b.subtitle, b.body, b.summary].map { $0 ?? "" }.joined(separator: "\u{1F}")
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in joined.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return "h:" + String(hash, radix: 16)
    }
}

/// 诊断用的横幅记录：最近 `keep` 条非测试横幅、最近一条测试横幅分开存，互不覆盖；另有计数
/// （按横幅算，同一条读几次只算一次，后一次的结果顶替前一次）。存在 UserDefaults 里，码头
/// 重开后还在；换了版本清空。
public struct NotchBannerLog: Codable, Equatable, Sendable {
    public static let keep = 5
    /// 记多少个见过的键，防同一条横幅重复计数。
    static let rememberedKeys = 64

    public struct Entry: Codable, Equatable, Sendable {
        public var key: String
        public var analysis: NotchBannerAnalysis
    }

    /// 最近的非测试横幅，旧的在前。
    public private(set) var real: [Entry] = []
    public private(set) var test: Entry?
    public private(set) var realBanners = 0
    public private(set) var recognised = 0
    public private(set) var rejected = 0
    /// 按结果分的个数（rawValue → 个数），不含测试。
    public private(set) var reasons: [String: Int] = [:]
    /// 见过的键和它当时算进计数的结果。
    private var seen: [String] = []
    private var seenOutcome: [String: NotchBannerAnalysis.Outcome] = [:]
    /// 记录属于哪个版本，换版本清空。
    public var build: String = ""
    /// 第一条记录的时间。
    public private(set) var since: Date?

    public init(build: String = "") { self.build = build }

    /// 记一条。同一个键再来时：测试的换掉测试那条；非测试的换掉原来那条并改计数。
    public mutating func record(_ analysis: NotchBannerAnalysis, key: String) {
        since = since ?? analysis.at
        if analysis.outcome == .test {
            test = Entry(key: key, analysis: analysis)
            // 先当真实横幅记过（暗号还没设上时读到）的，挪出来、计数退回去。
            if let old = seenOutcome[key] {
                count(old, -1)
                seenOutcome[key] = nil
                seen.removeAll { $0 == key }
                real.removeAll { $0.key == key }
            }
            return
        }
        if test?.key == key { return }
        if let old = seenOutcome[key] {
            if old != analysis.outcome {
                count(old, -1)
                count(analysis.outcome, 1)
                seenOutcome[key] = analysis.outcome
            }
            if let index = real.firstIndex(where: { $0.key == key }) {
                // 认出过的不让后来的空读（字没了、快消失时）顶掉。
                if real[index].analysis.outcome == .message, analysis.outcome != .message { return }
                real.remove(at: index)
                real.append(Entry(key: key, analysis: analysis))
            }
            return
        }
        seen.append(key)
        seenOutcome[key] = analysis.outcome
        if seen.count > Self.rememberedKeys {
            let dropped = seen.removeFirst()
            seenOutcome[dropped] = nil
        }
        count(analysis.outcome, 1)
        real.append(Entry(key: key, analysis: analysis))
        if real.count > Self.keep { real.removeFirst(real.count - Self.keep) }
    }

    private mutating func count(_ outcome: NotchBannerAnalysis.Outcome, _ delta: Int) {
        guard outcome != .test else { return }
        realBanners += delta
        if outcome == .message { recognised += delta } else { rejected += delta }
        let next = (reasons[outcome.rawValue] ?? 0) + delta
        reasons[outcome.rawValue] = next > 0 ? next : nil
    }

    /// 计数那一行。
    public var countsLine: String {
        let grouped = reasons.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ", ")
        return "realBanners=\(realBanners) recognised=\(recognised) rejected=\(rejected) reasons=[\(grouped)]"
    }

    /// 诊断里的两段：最近的非测试横幅（新的在前）和测试横幅。
    public func report(time: (Date) -> String) -> [String] {
        var lines = [countsLine]
        lines.append("--- last \(Self.keep) real banners (newest first) ---")
        if real.isEmpty { lines.append("none") }
        for entry in real.reversed() {
            let a = entry.analysis
            lines.append(time(a.at) + " " + a.lines[0])
            lines.append(contentsOf: a.lines.dropFirst())
        }
        lines.append("--- test banner ---")
        if let test {
            let a = test.analysis
            lines.append(time(a.at) + " " + a.lines[0])
            lines.append(contentsOf: a.lines.dropFirst())
        } else {
            lines.append("none")
        }
        return lines
    }
}
