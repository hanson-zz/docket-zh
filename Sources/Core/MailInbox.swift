import Foundation

/// 邮件面板读到的一个账户：名字（「邮件」里账户的名称）、地址、收件箱未读数。
public struct MailAccount: Equatable, Sendable, Identifiable {
    public var name: String
    public var address: String
    public var unread: Int

    public var id: String { name }

    public init(name: String, address: String, unread: Int) {
        self.name = name
        self.address = address
        self.unread = unread
    }
}

/// 一封未读邮件。`mailID` 是「邮件」里的内部编号，标已读用；`messageID` 是
/// 信头里的 Message-ID，点开时拼成 message:// 链接跳到那一封。
public struct MailMessage: Equatable, Sendable, Identifiable {
    public var account: String
    public var mailID: Int
    public var messageID: String
    public var sender: String
    public var subject: String
    public var summary: String
    public var received: Date

    public var id: String { "\(account)\u{1F}\(mailID)" }

    public init(account: String, mailID: Int, messageID: String, sender: String,
                subject: String, summary: String, received: Date) {
        self.account = account
        self.mailID = mailID
        self.messageID = messageID
        self.sender = sender
        self.subject = subject
        self.summary = summary
        self.received = received
    }

    /// 发件人显示的名字：「周岚 <zhou@x>」取名字，只有地址时取地址。
    public var senderName: String { MailInbox.senderName(sender) }
}

/// 一次读到的全部：账户（按「邮件」里的顺序）和各账户最近的几封未读。
public struct MailSnapshot: Equatable, Sendable {
    public var accounts: [MailAccount]
    public var messages: [MailMessage]

    public init(accounts: [MailAccount] = [], messages: [MailMessage] = []) {
        self.accounts = accounts
        self.messages = messages
    }
}

/// 邮件面板的判断逻辑：解析 AppleScript 的返回、按设置挑出要显示的几封、
/// 时间和发件人怎么写、跳转链接和脚本里的字符串怎么拼。不碰 AppKit，放在 Core 测。
///
/// 配置键：
/// - `limit`：每次显示几封，"3" / "5" / "10"，默认 5（设置页可改，面板设置里也能改）。
/// - `summary`：显示一行摘要，默认开。
/// - `markReadOnOpen`：点开后自动标已读，默认关（关着时要点「标已读」）。
/// - `hiddenAccounts`：面板设置里关掉的账户名，由面板写、不进设置页；
///   存关掉的而不是打开的，新加的账户默认就显示。
/// - `filter`：顶部选中的账户筛选（Pro），由面板写；空是「全部」。没解锁时
///   照旧存着、不改写，只是按「全部」显示，解锁或试用时回来。
public enum MailInbox {
    public static let limitKey = "limit"
    public static let summaryKey = "summary"
    public static let markReadKey = "markReadOnOpen"
    public static let hiddenKey = "hiddenAccounts"
    public static let filterKey = "filter"

    public static let limitChoices = [3, 5, 10]
    public static let defaultLimit = 5
    /// 每个账户最多读几封：最大一档，筛选或隐藏账户后也够填满列表。
    public static var perAccount: Int { limitChoices.max() ?? 10 }

    /// AppleScript 返回里分隔记录和字段的控制字符（ASCII 30、31），正文里不会有。
    public static let recordSeparator: Character = "\u{1E}"
    public static let fieldSeparator: Character = "\u{1F}"

    // MARK: 设置

    public static func limit(_ config: WidgetConfig) -> Int {
        let raw = config.string(limitKey, default: "\(defaultLimit)")
        guard let value = Int(raw.trimmingCharacters(in: .whitespaces)), limitChoices.contains(value) else {
            return defaultLimit
        }
        return value
    }

    public static func showsSummary(_ config: WidgetConfig) -> Bool {
        config.bool(summaryKey, default: true)
    }

    public static func marksReadOnOpen(_ config: WidgetConfig) -> Bool {
        config.bool(markReadKey, default: false)
    }

    public static func hidden(_ config: WidgetConfig) -> Set<String> {
        Set(config.strings(hiddenKey))
    }

    /// 开关一个账户后的 `hiddenAccounts`：按名字排好，免得每次写出来顺序不同。
    public static func toggling(_ account: String, shown: Bool, hidden: Set<String>) -> [String] {
        var next = hidden
        if shown { next.remove(account) } else { next.insert(account) }
        return next.sorted()
    }

    /// 顶部账户筛选（Pro）能不能用。
    public static func canFilter(unlocked: Bool) -> Bool {
        ProLicenseGate.canFilterMailAccounts(unlocked: unlocked)
    }

    /// 面板里看得到的账户：没在设置里关掉的，按「邮件」里的顺序。
    public static func shownAccounts(_ accounts: [MailAccount], hidden: Set<String>) -> [MailAccount] {
        accounts.filter { !hidden.contains($0.name) }
    }

    /// 真正生效的筛选：没解锁、选的账户不在了或被关掉了，都按「全部」（nil）。
    public static func effectiveFilter(_ filter: String?, accounts: [MailAccount],
                                       hidden: Set<String>, unlocked: Bool) -> String? {
        guard canFilter(unlocked: unlocked), let filter, !filter.isEmpty,
              shownAccounts(accounts, hidden: hidden).contains(where: { $0.name == filter }) else { return nil }
        return filter
    }

    /// 读到了账户，但在设置里全关掉了：面板提示去打开，而不是说「读完了」。
    public static func allAccountsHidden(_ accounts: [MailAccount], hidden: Set<String>) -> Bool {
        !accounts.isEmpty && shownAccounts(accounts, hidden: hidden).isEmpty
    }

    /// 顶部要不要出账户筛选胶囊：看得到的账户有两个以上才有意义。
    public static func showsFilterChips(_ accounts: [MailAccount], hidden: Set<String>) -> Bool {
        shownAccounts(accounts, hidden: hidden).count >= 2
    }

    /// 列表里显示的几封：去掉关掉的账户，按筛选，新的在前，最多 `limit` 封。
    public static func visible(_ snapshot: MailSnapshot, hidden: Set<String>, filter: String?,
                               unlocked: Bool, limit: Int) -> [MailMessage] {
        let shown = Set(shownAccounts(snapshot.accounts, hidden: hidden).map(\.name))
        let chosen = effectiveFilter(filter, accounts: snapshot.accounts, hidden: hidden, unlocked: unlocked)
        let picked = snapshot.messages.filter { message in
            shown.contains(message.account) && (chosen == nil || message.account == chosen)
        }
        let sorted = picked.sorted { a, b in
            a.received != b.received ? a.received > b.received : a.id < b.id
        }
        return Array(sorted.prefix(max(0, limit)))
    }

    /// 标题下面写的未读总数：看得到的账户（按筛选）收件箱未读数之和。
    public static func unreadTotal(_ snapshot: MailSnapshot, hidden: Set<String>, filter: String?,
                                   unlocked: Bool) -> Int {
        let chosen = effectiveFilter(filter, accounts: snapshot.accounts, hidden: hidden, unlocked: unlocked)
        return shownAccounts(snapshot.accounts, hidden: hidden)
            .filter { chosen == nil || $0.name == chosen }
            .reduce(0) { $0 + max(0, $1.unread) }
    }

    /// 「全部标为已读」要动哪些账户：看得到的（按筛选）且有未读的。
    public static func accountsToMarkAll(_ snapshot: MailSnapshot, hidden: Set<String>, filter: String?,
                                         unlocked: Bool) -> [String] {
        let chosen = effectiveFilter(filter, accounts: snapshot.accounts, hidden: hidden, unlocked: unlocked)
        return shownAccounts(snapshot.accounts, hidden: hidden)
            .filter { (chosen == nil || $0.name == chosen) && $0.unread > 0 }
            .map(\.name)
    }

    /// 标已读之后先在本地拿掉那一封、账户未读数减一，不等下次读取。
    public static func removing(_ message: MailMessage, from snapshot: MailSnapshot) -> MailSnapshot {
        var next = snapshot
        guard let index = next.messages.firstIndex(where: { $0.id == message.id }) else { return next }
        next.messages.remove(at: index)
        if let a = next.accounts.firstIndex(where: { $0.name == message.account }) {
            next.accounts[a].unread = max(0, next.accounts[a].unread - 1)
        }
        return next
    }

    /// 同上，一次清掉几个账户的全部未读。
    public static func clearing(_ accounts: [String], from snapshot: MailSnapshot) -> MailSnapshot {
        let set = Set(accounts)
        var next = snapshot
        next.messages.removeAll { set.contains($0.account) }
        for i in next.accounts.indices where set.contains(next.accounts[i].name) {
            next.accounts[i].unread = 0
        }
        return next
    }

    // MARK: 解析

    /// 解析脚本返回：记录用 ASCII 30 分开，字段用 ASCII 31 分开。
    /// - `A 账户名 地址 未读数`
    /// - `M 账户名 内部编号 Message-ID 发件人 主题 多少秒以前 摘要`
    /// 坏掉的记录跳过；同一账户出现两次（统一收件箱下重复的邮箱）时未读数相加。
    public static func parse(_ text: String, now: Date) -> MailSnapshot {
        var accounts: [MailAccount] = []
        var messages: [MailMessage] = []
        var seen = Set<String>()
        for record in text.split(separator: recordSeparator, omittingEmptySubsequences: true) {
            let fields = record.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
            guard let tag = fields.first?.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
            if tag == "A", fields.count >= 4 {
                let name = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let unread = max(0, Int(fields[3].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
                if let i = accounts.firstIndex(where: { $0.name == name }) {
                    accounts[i].unread += unread
                    if accounts[i].address.isEmpty { accounts[i].address = fields[2].trimmingCharacters(in: .whitespaces) }
                } else {
                    accounts.append(MailAccount(name: name, address: fields[2].trimmingCharacters(in: .whitespaces),
                                                unread: unread))
                }
            } else if tag == "M", fields.count >= 7 {
                let account = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !account.isEmpty,
                      let mailID = Int(fields[2].trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
                let message = MailMessage(
                    account: account,
                    mailID: mailID,
                    messageID: fields[3].trimmingCharacters(in: .whitespacesAndNewlines),
                    sender: oneLine(fields[4]),
                    subject: oneLine(fields[5]),
                    summary: fields.count > 7 ? summary(fields[7]) : "",
                    received: now.addingTimeInterval(-max(0, seconds(fields[6]))))
                guard seen.insert(message.id).inserted else { continue }
                messages.append(message)
            }
        }
        return MailSnapshot(accounts: accounts, messages: messages)
    }

    /// AppleScript 把日期差写成整数，也可能带小数点或逗号（地区设置）。
    static func seconds(_ raw: String) -> TimeInterval {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        return TimeInterval(trimmed) ?? 0
    }

    /// 一行文字：换行和连着的空白收成一个空格。
    public static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }

    /// 摘要：一行，最多 `summaryLength` 个字。
    public static let summaryLength = 120

    public static func summary(_ text: String) -> String {
        let line = oneLine(text)
        return line.count > summaryLength ? String(line.prefix(summaryLength)) : line
    }

    // MARK: 显示

    /// 「周岚 <zhou@x>」→「周岚」，「"Zhou, Lan" <z@x>」→「Zhou, Lan」，
    /// 「<z@x>」或「z@x」→「z@x」，空的写「未知发件人」。
    public static func senderName(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = text.lastIndex(of: "<") {
            let name = text[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
            let address = text[text.index(after: open)...].replacingOccurrences(of: ">", with: "")
                .trimmingCharacters(in: .whitespaces)
            if !address.isEmpty { return address }
        }
        return text.isEmpty ? tr("未知发件人") : text
    }

    /// 头像上的一个字：名字的第一个字母或汉字，英文大写。
    public static func initial(_ name: String) -> String {
        guard let first = name.first(where: { $0.isLetter || $0.isNumber }) else { return "?" }
        return String(first).uppercased()
    }

    /// 头像颜色，取自效果图；按名字算，同一个人每次同一个颜色
    /// （不用 hashValue，它每次启动都变）。
    public static let avatarHexes = ["#5873D6", "#3FA75B", "#C2553A", "#8E6CE0", "#D9A520", "#2F9BB5"]

    public static func avatarHex(_ name: String) -> String {
        let sum = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        return avatarHexes[sum % avatarHexes.count]
    }

    /// 账户小圆点的颜色：第一个工作青、第二个个人橙（效果图），之后依次往下。
    public static let accountHexes = ["#6FD6C0", "#FFB86B", "#C9A6FF", "#FF8FB1", "#8DD7FF", "#E7D36F"]

    public static func accountHex(_ name: String, in accounts: [MailAccount]) -> String {
        guard let index = accounts.firstIndex(where: { $0.name == name }) else { return "#9AA0AA" }
        return accountHexes[index % accountHexes.count]
    }

    /// 右上角的时间：今天写「10:12」，昨天写「昨天」，一周内写「周日」，
    /// 再早写「10月3日」，跨年写「2025/10/3」。
    public static func timeLabel(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) || date > now {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        if days == 1 { return tr("昨天") }
        if days < 7 {
            let weekday = calendar.component(.weekday, from: date)
            return weekdayName(weekday)
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        if parts.year != calendar.component(.year, from: now) {
            return "\(parts.year ?? 0)/\(parts.month ?? 0)/\(parts.day ?? 0)"
        }
        return tr("\(parts.month ?? 0)月\(parts.day ?? 0)日")
    }

    /// 1 是周日，和 `Calendar` 一致。
    static func weekdayName(_ weekday: Int) -> String {
        switch weekday {
        case 1: tr("周日")
        case 2: tr("周一")
        case 3: tr("周二")
        case 4: tr("周三")
        case 5: tr("周四")
        case 6: tr("周五")
        default: tr("周六")
        }
    }

    // MARK: 跳转和脚本

    /// 跳到那一封的链接：message://%3C<Message-ID>%3E，「邮件」认这个写法。
    /// 没有 Message-ID 时为 nil，面板退回只打开「邮件」。
    public static func messageURL(_ messageID: String) -> URL? {
        var id = messageID.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.hasPrefix("<") { id.removeFirst() }
        if id.hasSuffix(">") { id.removeLast() }
        guard !id.isEmpty else { return nil }
        // 只放过 ASCII 的字母数字和这几个符号，其余（空格、斜杠、汉字）都转义。
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~!$&'()*+,;=:@")
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "message://%3C\(encoded)%3E")
    }

    /// 放进 AppleScript 的字符串字面量：加引号，反斜杠和引号转义，换行去掉。
    public static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }

    /// 找各账户收件箱的脚本片段：统一收件箱下面每个账户一个邮箱；
    /// 读不到时退回每个账户里叫 INBOX / Inbox 的邮箱。
    static let boxesHandler = """
    on inboxBoxes()
        tell application id "com.apple.mail"
            set boxes to {}
            try
                set boxes to every mailbox of inbox
            end try
            if (count of boxes) = 0 then
                repeat with acc in every account
                    try
                        set end of boxes to mailbox "INBOX" of acc
                    on error
                        try
                            set end of boxes to mailbox "Inbox" of acc
                        end try
                    end try
                end repeat
            end if
            return boxes
        end tell
    end inboxBoxes
    """

    /// 读账户和最近未读的脚本。只在「邮件」开着时跑（问一个没开的「邮件」会把它打开）。
    /// 每个账户最多 `perAccount` 封；邮件按收件箱里的顺序取，先看两头哪边新，
    /// 从新的一头开始拿。摘要要读正文，关掉摘要时不读，快一些。
    public static func fetchScript(perAccount: Int, summary: Bool) -> String {
        """
        \(boxesHandler)
        set RS to character id 30
        set US to character id 31
        set nowDate to current date
        set out to ""
        set boxes to inboxBoxes()
        tell application id "com.apple.mail"
            repeat with boxRef in boxes
                try
                    set mb to contents of boxRef
                    set acc to account of mb
                    set accName to name of acc
                    set addr to ""
                    try
                        set addr to item 1 of (email addresses of acc)
                    end try
                    set n to unread count of mb
                    set out to out & "A" & US & accName & US & addr & US & n & RS
                    if n > 0 then
                        set ms to (messages of mb whose read status is false)
                        set k to count of ms
                        set rev to false
                        if k > 1 then
                            try
                                set rev to ((date received of item 1 of ms) < (date received of item k of ms))
                            end try
                        end if
                        set lim to k
                        if lim > \(max(1, perAccount)) then set lim to \(max(1, perAccount))
                        repeat with i from 1 to lim
                            try
                                if rev then
                                    set m to item (k - i + 1) of ms
                                else
                                    set m to item i of ms
                                end if
                                set mid to ""
                                try
                                    set mid to message id of m
                                end try
                                set who to ""
                                try
                                    set who to sender of m
                                end try
                                set subj to ""
                                try
                                    set subj to subject of m
                                end try
                                if subj is missing value then set subj to ""
                                set ago to 0
                                try
                                    set ago to nowDate - (date received of m)
                                end try
                                set summ to ""
                                if \(summary ? "true" : "false") then
                                    try
                                        set c to content of m
                                        if (length of c) > 300 then set c to text 1 thru 300 of c
                                        set summ to c
                                    end try
                                end if
                                set out to out & "M" & US & accName & US & (id of m) & US & mid & US & who & US & subj & US & ago & US & summ & RS
                            end try
                        end repeat
                    end if
                end try
            end repeat
        end tell
        return out
        """
    }

    /// 把一封标成已读：按账户名和内部编号找。
    public static func markReadScript(account: String, mailID: Int) -> String {
        """
        \(boxesHandler)
        set boxes to inboxBoxes()
        tell application id "com.apple.mail"
            repeat with boxRef in boxes
                try
                    set mb to contents of boxRef
                    if name of (account of mb) is \(quoted(account)) then
                        set read status of (messages of mb whose id is \(mailID)) to true
                    end if
                end try
            end repeat
        end tell
        """
    }

    /// 把几个账户收件箱里的未读全部标成已读。
    public static func markAllReadScript(accounts: [String]) -> String {
        let list = "{" + accounts.map(quoted).joined(separator: ", ") + "}"
        return """
        \(boxesHandler)
        set boxes to inboxBoxes()
        set wanted to \(list)
        tell application id "com.apple.mail"
            repeat with boxRef in boxes
                try
                    set mb to contents of boxRef
                    if wanted contains (name of (account of mb)) then
                        set read status of (messages of mb whose read status is false) to true
                    end if
                end try
            end repeat
        end tell
        """
    }
}
