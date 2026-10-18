import Foundation

/// 日历小组件只管「今天」和「下一个会」：会议链接识别、倒计时文字、今日时间线的
/// 布局（时间范围、色块位置、重叠分行、刻度、现在的红线）和日期样式的小点。
///
/// 纯逻辑，界面把每个 `EKEvent` 拍平成 `CalendarSpan` 后交给这里，测试不需要
/// 日历数据库。
public struct CalendarSpan: Identifiable, Hashable, Sendable {
    public var id: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool

    public init(id: String, start: Date, end: Date, isAllDay: Bool = false) {
        self.id = id
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
    }
}

// MARK: - 会议链接

/// 日程里能「加入」的视频会议链接。
public struct MeetingLink: Equatable, Sendable {
    public enum Provider: String, CaseIterable, Sendable {
        case tencent, zoom, teams, feishu, meet, other

        /// 按钮上的名字：加入腾讯会议、加入 Zoom 会议。
        public var joinTitle: String {
            switch self {
            case .tencent: tr("加入腾讯会议")
            case .zoom: tr("加入 Zoom 会议")
            case .teams: tr("加入 Teams 会议")
            case .feishu: tr("加入飞书会议")
            case .meet: tr("加入 Google Meet")
            case .other: tr("加入会议")
            }
        }

        /// 悬停详情里的来源：腾讯会议、飞书会议。
        public var title: String {
            switch self {
            case .tencent: tr("腾讯会议")
            case .zoom: "Zoom"
            case .teams: "Teams"
            case .feishu: tr("飞书会议")
            case .meet: "Google Meet"
            case .other: tr("视频会议")
            }
        }
    }

    public var url: URL
    public var provider: Provider

    public init(url: URL, provider: Provider) {
        self.url = url
        self.provider = provider
    }

    /// 认得的会议域名。按主机名的结尾比对，所以 `xxx.zoom.us`、`vc.feishu.cn` 都算。
    static let hosts: [(suffix: String, provider: Provider)] = [
        ("meeting.tencent.com", .tencent), ("voovmeeting.com", .tencent),
        ("zoom.us", .zoom), ("zoom.com", .zoom), ("zoom.com.cn", .zoom), ("zoomgov.com", .zoom),
        ("teams.microsoft.com", .teams), ("teams.live.com", .teams), ("teams.microsoft.us", .teams),
        ("vc.feishu.cn", .feishu), ("feishu.cn", .feishu), ("larksuite.com", .feishu), ("larkoffice.com", .feishu),
        ("meet.google.com", .meet),
    ]

    public static func provider(of url: URL) -> Provider? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        for (suffix, provider) in hosts where host == suffix || host.hasSuffix("." + suffix) {
            // 飞书和 Lark 的文档、表格链接不是会议，只认视频会议的路径。
            if provider == .feishu, !(host.hasPrefix("vc.") || url.path.lowercased().contains("/j/")
                                      || url.path.lowercased().contains("/vc/")) {
                return nil
            }
            // Zoom 官网首页、下载页不算，会议链接都带 /j/、/s/、/my/ 或 /wc/。
            if provider == .zoom {
                let path = url.path.lowercased()
                guard ["/j/", "/s/", "/my/", "/wc/", "/w/"].contains(where: path.hasPrefix) else { return nil }
            }
            // Teams 的会议链接是 /l/meetup-join/ 或 /meet/。
            if provider == .teams {
                let path = url.path.lowercased()
                guard path.contains("meetup-join") || path.hasPrefix("/meet/") || path.hasPrefix("/l/meet") else {
                    return nil
                }
            }
            // Google Meet 首页不算，会议代码是一段 xxx-xxxx-xxx。
            if provider == .meet, url.path.count < 4 { return nil }
            return provider
        }
        return nil
    }

    /// 一段文字里出现的所有 http(s) 链接，按出现顺序。
    static func links(in text: String) -> [URL] {
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: range).compactMap { match in
            guard let url = match.url, let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http" else { return nil }
            return url
        }
    }

    /// 找日程的会议链接：先看日程自己的 URL 字段，再看地点和备注里认得的会议链接。
    /// URL 字段里放的就是会议入口时（日历应用「添加视频会议」写的就是这里），
    /// 不认得的域名也算，按钮写「加入会议」；地点和备注里只认会议域名，免得把
    /// 随手贴的文档链接当成会议。
    public static func find(url: URL?, location: String?, notes: String?) -> MeetingLink? {
        if let url, let provider = provider(of: url) { return MeetingLink(url: url, provider: provider) }
        for text in [location ?? "", notes ?? ""] {
            for link in links(in: text) {
                if let provider = provider(of: link) { return MeetingLink(url: link, provider: provider) }
            }
        }
        if let url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
           url.host?.isEmpty == false {
            return MeetingLink(url: url, provider: .other)
        }
        return nil
    }

    /// 地点栏里本身就是一条链接时，不当成地点显示。
    public static func isOnlyLink(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return links(in: trimmed).count == 1 && !trimmed.contains(" ")
            && (trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://"))
    }
}

// MARK: - 今天

public enum CalendarDay {
    /// 旧样式「日期 + 日程列表」已经去掉，放好的卡片换成今日时间线。
    public static let legacyAgendaLayout = "agenda"
    public static let timelineLayout = "timeline"

    /// 读配置时把旧的 agenda 换成 timeline，只改这一个键。
    public static func migratingLayout(_ config: WidgetConfig) -> WidgetConfig {
        guard case .string(let layout) = config.values["layout"], layout == legacyAgendaLayout else { return config }
        var copy = config
        copy.set("layout", .string(timelineLayout))
        return copy
    }

    /// 样式名：存的是旧值也当成时间线。
    public static func layout(_ config: WidgetConfig) -> String {
        let layout = config.string("layout", default: "nextEvent")
        return layout == legacyAgendaLayout ? timelineLayout : layout
    }

    /// 「还有 25 分钟」「还有 1 小时 5 分钟」「马上开始」，开始了是「进行中 · 还剩 20 分钟」。
    public static func countdown(start: Date, end: Date, now: Date) -> String {
        if now >= start {
            let left = Int((end.timeIntervalSince(now) / 60).rounded(.up))
            return left > 0 ? tr("进行中 · 还剩 \(duration(minutes: left))") : tr("刚结束")
        }
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 1 { return tr("马上开始") }
        return tr("还有 \(duration(minutes: minutes))")
    }

    /// 时间线标题右边那句：「下一个 25 分钟后」「下一个 2 小时后」「进行中」。
    public static func nextLine(start: Date, now: Date) -> String {
        if now >= start { return tr("进行中") }
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 1 { return tr("下一个马上开始") }
        return tr("下一个 \(duration(minutes: minutes))后")
    }

    /// 25 分钟、1 小时、1 小时 5 分钟。
    public static func duration(minutes: Int) -> String {
        let m = max(0, minutes)
        if m < 60 { return tr("\(m) 分钟") }
        let h = m / 60, rest = m % 60
        return rest == 0 ? tr("\(h) 小时") : tr("\(h) 小时 \(rest) 分钟")
    }

    /// 09:30、14:00，24 小时制，和设计稿一样不跟系统的上午下午走。
    public static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// 10:30-11:15
    public static func range(_ start: Date, _ end: Date, calendar: Calendar = .current) -> String {
        "\(clock(start, calendar: calendar))-\(clock(end, calendar: calendar))"
    }

    /// 今天还没结束的定时日程（进行中的也算），按开始时间。
    public static func remaining(_ spans: [CalendarSpan], now: Date) -> [CalendarSpan] {
        spans.filter { !$0.isAllDay && $0.end > now }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    // MARK: 日期样式的小点

    /// 一个点一个会，按开始时间，最多 `limit` 个；开完的标 `past`，界面画淡一些。
    public static func dots(_ spans: [CalendarSpan], now: Date, limit: Int = 5) -> [(id: String, past: Bool)] {
        let timed = spans.filter { !$0.isAllDay }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        return timed.prefix(max(0, limit)).map { ($0.id, $0.end <= now) }
    }
}

// MARK: - 今日时间线

/// 时间线上的一块：在轴上从哪到哪（0...1），排在第几行。
public struct TimelineBlock: Equatable, Sendable {
    public var id: String
    public var from: Double
    public var to: Double
    /// 和别的日程重叠时分行，0 在上。
    public var lane: Int
    /// 这一块所在的那串重叠日程一共几行。
    public var lanes: Int
    public var isPast: Bool
    public var isNow: Bool
}

public enum DayTimeline {
    /// 默认画 9 点到 19 点；日程更早或更晚时整点往外扩。
    public static let defaultHours = 9...19

    /// 轴的范围（整点）：盖住默认的 9 到 19 点，再盖住今天每个定时日程。
    /// 跨过午夜的日程只算今天这部分。
    public static func hourRange(_ spans: [CalendarSpan], day: Date, calendar: Calendar = .current,
                                 defaults: ClosedRange<Int> = DayTimeline.defaultHours) -> ClosedRange<Int> {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        var low = defaults.lowerBound, high = defaults.upperBound
        for span in spans where !span.isAllDay {
            let start = max(span.start, dayStart), end = min(span.end, dayEnd)
            guard end > dayStart, start < dayEnd else { continue }
            let startHour = start.timeIntervalSince(dayStart) / 3_600
            let endHour = max(end, start).timeIntervalSince(dayStart) / 3_600
            low = min(low, Int(startHour.rounded(.down)))
            high = max(high, Int(endHour.rounded(.up)))
        }
        low = max(0, min(low, 23))
        high = min(24, max(high, low + 1))
        return low...high
    }

    /// 某个时刻在轴上的位置，0 是左端，1 是右端，可以超出。
    public static func fraction(_ date: Date, hours: ClosedRange<Int>, day: Date,
                                calendar: Calendar = .current) -> Double {
        let dayStart = calendar.startOfDay(for: day)
        let hour = date.timeIntervalSince(dayStart) / 3_600
        let span = Double(max(1, hours.upperBound - hours.lowerBound))
        return (hour - Double(hours.lowerBound)) / span
    }

    /// 现在的红线位置；不在轴上时为 nil。
    public static func nowFraction(_ now: Date, hours: ClosedRange<Int>, day: Date,
                                   calendar: Calendar = .current) -> Double? {
        guard calendar.isDate(now, inSameDayAs: day) else { return nil }
        let f = fraction(now, hours: hours, day: day, calendar: calendar)
        return (0...1).contains(f) ? f : nil
    }

    /// 每个定时日程一块。重叠的分行：一串互相重叠的日程按开始时间放进第一条空着的行，
    /// 这串一共几行就是 `lanes`，界面按它把高度平分。最多 `maxLanes` 行，再多的挤进最后一行。
    public static func blocks(_ spans: [CalendarSpan], hours: ClosedRange<Int>, day: Date, now: Date,
                              maxLanes: Int = 2, calendar: Calendar = .current) -> [TimelineBlock] {
        let timed = spans.filter { !$0.isAllDay }
            .sorted { $0.start == $1.start ? ($0.end == $1.end ? $0.id < $1.id : $0.end > $1.end) : $0.start < $1.start }
        var result: [TimelineBlock] = []
        var cluster: [Int] = []
        var laneEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func closeCluster() {
            let count = max(1, min(maxLanes, laneEnds.count))
            for index in cluster { result[index].lanes = count }
            cluster.removeAll()
            laneEnds.removeAll()
        }

        for span in timed {
            let end = max(span.end, span.start.addingTimeInterval(60))
            if span.start >= clusterEnd, !cluster.isEmpty { closeCluster() }
            var lane = laneEnds.firstIndex { $0 <= span.start } ?? laneEnds.count
            if lane >= maxLanes { lane = max(0, maxLanes - 1) }
            if lane < laneEnds.count { laneEnds[lane] = max(laneEnds[lane], end) } else { laneEnds.append(end) }
            clusterEnd = max(clusterEnd, end)
            let from = max(0, fraction(span.start, hours: hours, day: day, calendar: calendar))
            let to = min(1, fraction(end, hours: hours, day: day, calendar: calendar))
            result.append(TimelineBlock(id: span.id, from: from, to: max(from, to), lane: lane, lanes: 1,
                                        isPast: span.end <= now, isNow: span.start <= now && now < span.end))
            cluster.append(result.count - 1)
        }
        if !cluster.isEmpty { closeCluster() }
        return result
    }

    /// 刻度下面写字的整点：两头都写，中间等距，最多 `maxLabels` 个。
    /// 9 到 19 点写 9、12、15、18，和设计稿一样。
    public static func labelHours(_ hours: ClosedRange<Int>, maxLabels: Int = 4) -> [Int] {
        let span = hours.upperBound - hours.lowerBound
        let step = [1, 2, 3, 4, 6, 8, 12].first { span / $0 + 1 <= max(1, maxLabels) } ?? 12
        return stride(from: hours.lowerBound, through: hours.upperBound, by: step).filter { $0 < 24 }
    }

    /// 指针在轴上的位置落在哪一块：先找正好盖住的，再找 `slack` 以内最近的。
    public static func block(at x: Double, in blocks: [TimelineBlock], slack: Double = 0.02) -> Int? {
        if let hit = blocks.indices.last(where: { blocks[$0].from <= x && x <= blocks[$0].to }) { return hit }
        let near = blocks.indices.min { distance(x, blocks[$0]) < distance(x, blocks[$1]) }
        guard let near, distance(x, blocks[near]) <= slack else { return nil }
        return near
    }

    private static func distance(_ x: Double, _ block: TimelineBlock) -> Double {
        x < block.from ? block.from - x : (x > block.to ? x - block.to : 0)
    }
}
