import Foundation

// 「Codex 用量」详情里「正在运行」的会话列表和今日 / 本周统计：都从本机
// `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` 读，这里只放纯解析和算术，
// 读文件在 Services/CodexService.swift。
//
// 会话记录不是公开接口，字段随 Codex 版本变：每个解析都只拿读得懂的部分，读不懂
// 的字段留空，界面上对应的数字就不显示，而不是报错。
//
// 审批请求（exec_approval_request 等）新版 Codex 不写进会话记录，只发给开着这个
// 会话的终端。所以「等你确认」除了旧版留下的审批事件，还认一种情况：最后一条是
// 要求提权的命令调用（sandbox_permissions = require_escalated，或旧写法
// with_escalated_permissions = true），而且还没有它的输出。

// MARK: - 会话头

/// 会话记录第一行 `session_meta` 里有用的几项。
public struct CodexSessionMeta: Equatable, Sendable {
    public var id: String?
    public var cwd: String?
    /// 谁开的会话："codex_cli_rs"、"codex_vscode"……
    public var originator: String?
    public var startedAt: Date?
    /// 主会话派生出来的子代理会话：不单独列，也不算进会话数。
    public var isSubagent: Bool

    public init(id: String? = nil, cwd: String? = nil, originator: String? = nil,
                startedAt: Date? = nil, isSubagent: Bool = false) {
        self.id = id
        self.cwd = cwd
        self.originator = originator
        self.startedAt = startedAt
        self.isSubagent = isSubagent
    }

    /// 工作目录的最后一段，当项目名。
    public var project: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }
}

// MARK: - 正在做什么

/// 会话此刻在做的事，写成一句短话放在项目名下面。
public enum CodexDoing: Equatable, Sendable {
    /// 在跑一条命令。
    case running(String)
    /// 在改文件（apply_patch）。
    case editing
    /// 在想：推理摘要的标题。
    case thinking(String)
    /// 想执行一条要提权的命令，等你批准。
    case askingToRun(String)
    /// 想改文件，等你批准。
    case askingToEdit
    /// 等你批准（不知道是什么）。
    case asking
    /// 这一轮做完了。
    case finished

    public var text: String {
        switch self {
        case .running(let command): tr("在跑 \(command)")
        case .editing: tr("在改文件")
        case .thinking(let title): title
        case .askingToRun(let command): tr("想执行 \(command)，等你批准")
        case .askingToEdit: tr("想改文件，等你批准")
        case .asking: tr("有一步要你批准")
        case .finished: tr("这一轮做完了")
        }
    }
}

/// 会话记录末尾读出来的东西。
public struct CodexTailSummary: Equatable, Sendable {
    public var lastEvent: CodexActivity?
    public var doing: CodexDoing?
    /// 最近一轮开始的时间。
    public var turnStartedAt: Date?
    /// 最近一轮结束（完成或中断）的时间。
    public var turnEndedAt: Date?
    /// 整个会话到目前的 token 数（最后一条 token_count 的 total_token_usage）。
    public var totalTokens: Int?

    public init(lastEvent: CodexActivity? = nil, doing: CodexDoing? = nil, turnStartedAt: Date? = nil,
                turnEndedAt: Date? = nil, totalTokens: Int? = nil) {
        self.lastEvent = lastEvent
        self.doing = doing
        self.turnStartedAt = turnStartedAt
        self.turnEndedAt = turnEndedAt
        self.totalTokens = totalTokens
    }
}

extension CodexRollout {
    /// 读 `session_meta`。第一行可能带着几十 KB 的系统提示，读进来的开头不一定
    /// 是完整的一行，这时按 JSON 解析不了，就退回在文字里找 "cwd" 这几个键。
    public static func meta(inHead data: Data) -> CodexSessionMeta? {
        let firstLine = data.split(separator: UInt8(ascii: "\n"), maxSplits: 1, omittingEmptySubsequences: true).first
        if let firstLine,
           let record = try? JSONSerialization.jsonObject(with: Data(firstLine)) as? [String: Any],
           (record["type"] as? String) == "session_meta",
           let payload = record["payload"] as? [String: Any] {
            let source = payload["source"]
            let subagent = payload["parent_thread_id"] is String
                || (source as? [String: Any])?["subagent"] != nil
            return CodexSessionMeta(id: payload["id"] as? String,
                                    cwd: (payload["cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                                    originator: payload["originator"] as? String,
                                    startedAt: (payload["timestamp"] as? String).flatMap(timestamp)
                                        ?? (record["timestamp"] as? String).flatMap(timestamp),
                                    isSubagent: subagent)
        }
        // 截断处可能落在一个汉字中间，按 UTF-8 宽松解码（坏字节换成替代字符）。
        let text = String(decoding: data.prefix(256 * 1024), as: UTF8.self)
        guard text.contains("\"session_meta\"") else { return nil }
        let meta = CodexSessionMeta(id: field("id", in: text), cwd: field("cwd", in: text),
                                    originator: field("originator", in: text),
                                    startedAt: field("timestamp", in: text).flatMap(timestamp),
                                    isSubagent: text.contains("\"parent_thread_id\":\""))
        return meta.cwd == nil && meta.id == nil ? nil : meta
    }

    /// `"key":"value"` 里的 value（第一处），JSON 转义的 `\/` 和 `\\` 还原。
    static func field(_ key: String, in text: String) -> String? {
        guard let start = text.range(of: "\"\(key)\":\"") else { return nil }
        var value = ""
        var escaped = false
        for ch in text[start.upperBound...] {
            if escaped {
                value.append(ch)
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "\"" {
                return value.isEmpty ? nil : value
            } else {
                value.append(ch)
            }
            if value.count > 4096 { return nil }
        }
        return nil
    }

    /// 会话记录里的时间："2026-10-22T08:13:05.123Z"，有没有毫秒都认。
    public static func timestamp(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: fractionalStyle) { return date }
        return try? Date(text, strategy: plainStyle)
    }

    private static let fractionalStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plainStyle = Date.ISO8601FormatStyle()

    /// 读末尾：最近的生命周期事件（同 `lastEvent`）、在做什么、这一轮从什么时候
    /// 开始、token 总数。
    public static func summary(inTail data: Data) -> CodexTailSummary {
        var summary = CodexTailSummary(lastEvent: lastEvent(inTail: data))
        let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        // 有输出的调用；倒着读，先看到输出再看到调用。
        var answered = Set<String>()
        var sawDoing = false
        for line in lines.reversed() {
            guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let payload = record["payload"] as? [String: Any],
                  let type = payload["type"] as? String else { continue }
            let kind = (record["type"] as? String) ?? ""
            var at: Date? { (record["timestamp"] as? String).flatMap(timestamp) }
            switch (kind, type) {
            case ("event_msg", "token_count"):
                if summary.totalTokens == nil,
                   let info = payload["info"] as? [String: Any],
                   let total = info["total_token_usage"] as? [String: Any],
                   let n = CodexUsageParser.number(total["total_tokens"]) {
                    summary.totalTokens = Int(n)
                }
            case ("event_msg", "task_started"), ("event_msg", "turn_started"):
                if summary.turnStartedAt == nil {
                    summary.turnStartedAt = (CodexUsageParser.number(payload["started_at"]))
                        .map { Date(timeIntervalSince1970: $0) } ?? at
                }
            case ("event_msg", "task_complete"), ("event_msg", "turn_complete"):
                if summary.turnEndedAt == nil, summary.turnStartedAt == nil {
                    summary.turnEndedAt = CodexUsageParser.number(payload["completed_at"])
                        .map { Date(timeIntervalSince1970: $0) } ?? at
                }
                if !sawDoing { summary.doing = .finished; sawDoing = true }
            case ("event_msg", "turn_aborted"):
                if summary.turnEndedAt == nil, summary.turnStartedAt == nil { summary.turnEndedAt = at }
            case ("event_msg", "exec_approval_request"):
                if !sawDoing {
                    summary.doing = commandText(payload["command"]).map(CodexDoing.askingToRun) ?? .asking
                    sawDoing = true
                }
            case ("event_msg", "apply_patch_approval_request"):
                if !sawDoing { summary.doing = .askingToEdit; sawDoing = true }
            case ("event_msg", "request_permissions"), ("event_msg", "elicitation_request"):
                if !sawDoing { summary.doing = .asking; sawDoing = true }
            case ("response_item", "function_call_output"), ("response_item", "custom_tool_call_output"):
                if let id = payload["call_id"] as? String { answered.insert(id) }
            case ("response_item", "function_call"), ("response_item", "local_shell_call"):
                guard !sawDoing else { continue }
                let id = payload["call_id"] as? String
                let open = id.map { !answered.contains($0) } ?? false
                let args = arguments(payload)
                let command = commandText(args?["command"] ?? args?["cmd"]
                                          ?? (payload["action"] as? [String: Any])?["command"])
                let name = (payload["name"] as? String) ?? ""
                if name == "apply_patch" {
                    summary.doing = open && asksEscalation(args) ? .askingToEdit : .editing
                } else if let command {
                    if open, asksEscalation(args) {
                        summary.doing = .askingToRun(command)
                        // 新版不写审批事件：要提权、还没输出，就是在等你。
                        if summary.lastEvent == .working || summary.lastEvent == nil { summary.lastEvent = .waiting }
                    } else {
                        summary.doing = .running(command)
                    }
                } else {
                    continue
                }
                sawDoing = true
            case ("response_item", "custom_tool_call"):
                guard !sawDoing else { continue }
                if (payload["name"] as? String) == "apply_patch" {
                    summary.doing = .editing
                    sawDoing = true
                }
            case ("event_msg", "agent_reasoning"):
                guard !sawDoing, let title = reasoningTitle(payload["text"] as? String) else { continue }
                summary.doing = .thinking(title)
                sawDoing = true
            case ("response_item", "reasoning"):
                guard !sawDoing,
                      let parts = payload["summary"] as? [[String: Any]],
                      let title = reasoningTitle(parts.last?["text"] as? String) else { continue }
                summary.doing = .thinking(title)
                sawDoing = true
            default:
                continue
            }
            if summary.totalTokens != nil, sawDoing,
               summary.turnStartedAt != nil || summary.turnEndedAt != nil { break }
        }
        return summary
    }

    /// 调用的参数：`arguments` 是一段 JSON 文字。
    private static func arguments(_ payload: [String: Any]) -> [String: Any]? {
        if let text = payload["arguments"] as? String,
           let data = text.data(using: .utf8),
           let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return args
        }
        return payload["arguments"] as? [String: Any]
    }

    /// 这次调用要不要提权（会弹审批）。
    static func asksEscalation(_ args: [String: Any]?) -> Bool {
        guard let args else { return false }
        if (args["with_escalated_permissions"] as? Bool) == true { return true }
        if let mode = args["sandbox_permissions"] as? String, mode.contains("escalat") { return true }
        return false
    }

    /// 命令写成一行短字：`["bash", "-lc", "npm test"]` 取最后一段；太长截断。
    public static func commandText(_ value: Any?) -> String? {
        var text: String?
        if let parts = value as? [String], !parts.isEmpty {
            if parts.count >= 3, ["bash", "zsh", "sh", "/bin/bash", "/bin/zsh", "/bin/sh"].contains(parts[0]),
               parts[1].hasPrefix("-") {
                text = parts[2...].joined(separator: " ")
            } else {
                text = parts.joined(separator: " ")
            }
        } else if let s = value as? String {
            text = s
        }
        guard let line = text?.split(whereSeparator: \.isNewline).first
                .map({ $0.trimmingCharacters(in: .whitespaces) }), !line.isEmpty else { return nil }
        return line.count > 48 ? String(line.prefix(47)) + "…" : line
    }

    /// 推理摘要的标题：开头 `**标题**` 那一段；没有粗体时取第一行。
    static func reasoningTitle(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        var line = String(text.split(whereSeparator: \.isNewline).first ?? "")
        line = line.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        return line.count > 40 ? String(line.prefix(39)) + "…" : line
    }

    /// 一个会话里各轮加起来用了多久（秒）。没有任何一轮可算时为 nil（不可靠，
    /// 界面就不显示时长）。还没结束的那一轮不算。
    ///
    /// 只解析带轮次事件的行，其余行连 JSON 都不解，几十 MB 的记录也读得快。
    public static func activeSeconds(inLog data: Data) -> Double? {
        let started = Data("\"task_started\"".utf8), complete = Data("\"task_complete\"".utf8)
        let startedV2 = Data("\"turn_started\"".utf8), completeV2 = Data("\"turn_complete\"".utf8)
        let aborted = Data("\"turn_aborted\"".utf8)
        var total = 0.0
        var counted = false
        var open: Date?
        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            let isStart = line.range(of: started) != nil || line.range(of: startedV2) != nil
            let isEnd = line.range(of: complete) != nil || line.range(of: completeV2) != nil
                || line.range(of: aborted) != nil
            guard isStart || isEnd,
                  let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  (record["type"] as? String) == "event_msg",
                  let payload = record["payload"] as? [String: Any],
                  let type = payload["type"] as? String else { continue }
            let at = (record["timestamp"] as? String).flatMap(timestamp)
            switch type {
            case "task_started", "turn_started":
                open = at
            case "task_complete", "turn_complete", "turn_aborted":
                if let ms = CodexUsageParser.number(payload["duration_ms"]), ms >= 0 {
                    total += ms / 1000
                    counted = true
                } else if let start = open, let end = at, end >= start {
                    total += end.timeIntervalSince(start)
                    counted = true
                }
                open = nil
            default:
                continue
            }
        }
        return counted ? total : nil
    }
}

// MARK: - 会话列表

/// 「正在运行」里的一行。
public struct CodexSession: Equatable, Sendable, Identifiable {
    public var id: String
    public var project: String?
    public var originator: String?
    public var state: CodexActivity
    public var doing: CodexDoing?
    /// 工作中 / 等你确认：这一轮开始的时间；已完成：结束的时间。
    public var since: Date?
    public var modified: Date

    public init(id: String, project: String?, originator: String? = nil, state: CodexActivity,
                doing: CodexDoing? = nil, since: Date? = nil, modified: Date) {
        self.id = id
        self.project = project
        self.originator = originator
        self.state = state
        self.doing = doing
        self.since = since
        self.modified = modified
    }

    /// 由会话头、末尾摘要和文件修改时间合成一行；空闲的会话不列（返回 nil）。
    public static func make(id: String, meta: CodexSessionMeta?, tail: CodexTailSummary,
                            modified: Date, now: Date) -> CodexSession? {
        guard meta?.isSubagent != true else { return nil }
        let state = CodexRollout.state(lastEvent: tail.lastEvent, modified: modified, now: now)
        guard state != .idle else { return nil }
        var doing = tail.doing
        switch state {
        case .done: doing = .finished
        case .waiting:
            if doing == nil || doing == .finished { doing = .asking }
        case .working:
            if case .askingToRun(let command)? = doing { doing = .running(command) }
            if doing == .askingToEdit { doing = .editing }
            if doing == .asking || doing == .finished { doing = nil }
        case .idle: break
        }
        let since = state == .done ? (tail.turnEndedAt ?? modified) : (tail.turnStartedAt ?? meta?.startedAt)
        return CodexSession(id: meta?.id ?? id, project: meta?.project, originator: meta?.originator,
                            state: state, doing: doing, since: since, modified: modified)
    }

    /// 右边那一小格："4 分钟"、"1 小时 3 分"；已完成是"刚刚"、"6 分钟前"。
    public func elapsedText(now: Date) -> String {
        guard let since else { return "" }
        let seconds = max(0, now.timeIntervalSince(since))
        if state == .done {
            return seconds < 60 ? tr("刚刚") : tr("\(Int(seconds / 60)) 分钟前")
        }
        let minutes = Int(seconds / 60)
        if minutes < 1 { return tr("不到 1 分钟") }
        if minutes < 60 { return tr("\(minutes) 分钟") }
        return minutes % 60 > 0 ? tr("\(minutes / 60) 小时 \(minutes % 60) 分") : tr("\(minutes / 60) 小时")
    }
}

public enum CodexSessionList {
    /// 等你确认的排最前，然后是工作中、已完成；同一种按最近写过的在前。
    public static func sorted(_ sessions: [CodexSession]) -> [CodexSession] {
        sessions.sorted {
            let a = rank($0.state), b = rank($1.state)
            return a == b ? $0.modified > $1.modified : a < b
        }
    }

    /// 卡片上显示的总状态：有一个在等你就是等你确认，其次工作中、已完成。
    public static func overall(_ sessions: [CodexSession]) -> CodexActivity {
        sorted(sessions).first?.state ?? .idle
    }

    /// 卡片上那一个会话（排第一的）。
    public static func lead(_ sessions: [CodexSession]) -> CodexSession? { sorted(sessions).first }

    private static func rank(_ state: CodexActivity) -> Int {
        switch state {
        case .waiting: 0
        case .working: 1
        case .done: 2
        case .idle: 3
        }
    }

    /// 最近多久写过的记录才值得读末尾：等你确认最长保留一小时（见
    /// `CodexRollout.state` 的 staleAfter × 3）。
    public static let recentWindow: TimeInterval = 60 * 60
}

// MARK: - 统计

/// 一个会话算统计要的三样。
public struct CodexSessionRecord: Equatable, Sendable {
    public var startedAt: Date
    public var activeSeconds: Double?
    public var tokens: Int?

    public init(startedAt: Date, activeSeconds: Double?, tokens: Int?) {
        self.startedAt = startedAt
        self.activeSeconds = activeSeconds
        self.tokens = tokens
    }
}

/// 今天或本周的一格。读不准的项是 nil，界面不显示那一项。
public struct CodexStatBucket: Equatable, Sendable {
    public var sessions: Int
    public var seconds: Double?
    public var tokens: Int?

    public init(sessions: Int, seconds: Double?, tokens: Int?) {
        self.sessions = sessions
        self.seconds = seconds
        self.tokens = tokens
    }
}

public enum CodexStats {
    /// 本周一 0 点（中国习惯周一开始，不跟系统的每周第一天）。
    public static func weekStart(now: Date, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
    }

    /// 本周要读的日期文件夹（"2026/10/20" 这种），从周一到今天，最多 7 个。
    public static func weekFolders(now: Date, calendar: Calendar = .current) -> [String] {
        let start = weekStart(now: now, calendar: calendar)
        var day = calendar.startOfDay(for: now)
        var folders: [String] = []
        while day >= start, folders.count < 7 {
            let c = calendar.dateComponents([.year, .month, .day], from: day)
            folders.append(String(format: "%04d/%02d/%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0))
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return folders
    }

    /// 按会话开始的时间分到今天和本周。时长有一个会话读不出来，这一格就不报
    /// 时长（免得少算还像真的）；token 只加读得到的，一个都没有时为 nil。
    public static func buckets(_ records: [CodexSessionRecord], now: Date,
                               calendar: Calendar = .current) -> (today: CodexStatBucket, week: CodexStatBucket) {
        let todayStart = calendar.startOfDay(for: now)
        let weekStart = weekStart(now: now, calendar: calendar)
        func bucket(from start: Date) -> CodexStatBucket {
            let picked = records.filter { $0.startedAt >= start && $0.startedAt <= now }
            let seconds: Double? = picked.contains { $0.activeSeconds == nil }
                ? nil : picked.reduce(0) { $0 + ($1.activeSeconds ?? 0) }
            let tokenValues = picked.compactMap(\.tokens)
            return CodexStatBucket(sessions: picked.count, seconds: picked.isEmpty ? 0 : seconds,
                                   tokens: tokenValues.isEmpty ? nil : tokenValues.reduce(0, +))
        }
        return (bucket(from: todayStart), bucket(from: weekStart))
    }

    /// chatgpt.com 按天给的 token（`CodexUsageReport.daily`）：今天和本周。没有
    /// 数据时为 nil，界面退回本机会话记录里的数。
    public static func serverTokens(_ daily: [CodexDailyTokens], now: Date,
                                    calendar: Calendar = .current) -> (today: Int, week: Int)? {
        guard !daily.isEmpty else { return nil }
        let series = CodexPace.series(daily, days: 7, now: now, calendar: calendar)
        let days = weekFolders(now: now, calendar: calendar).count
        return (series.last ?? 0, series.suffix(days).reduce(0, +))
    }

    /// 大数字和单位："1,240" + "万 tokens"（中文）或 "12.4M" + "tokens"（英文）。
    public static func tokenParts(_ n: Int, english: Bool) -> (number: String, unit: String) {
        let n = max(0, n)
        if english {
            return (CodexPace.tokens(n), "tokens")
        }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "zh_Hans_CN")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        if n >= 100_000_000 {
            f.maximumFractionDigits = 1
            return (f.string(from: NSNumber(value: Double(n) / 100_000_000)) ?? "0", "亿 tokens")
        }
        if n >= 10_000 {
            return (f.string(from: NSNumber(value: (Double(n) / 10_000).rounded())) ?? "0", "万 tokens")
        }
        return (f.string(from: NSNumber(value: n)) ?? "0", "tokens")
    }

    /// "2 小时 35 分"、"14 小时"、"18 分钟"。
    public static func durationText(_ seconds: Double) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if minutes < 60 { return tr("\(minutes) 分钟") }
        let hours = minutes / 60
        if hours >= 10 || minutes % 60 == 0 { return tr("\(hours) 小时") }
        return tr("\(hours) 小时 \(minutes % 60) 分")
    }
}

// MARK: - 去终端

/// 「去终端」「打开终端」把哪个 App 叫到前面。Codex 不让别的程序替你点允许，
/// 能做的只是把开着这个会话的地方带到前台。
public enum CodexTerminal {
    public enum Host: Equatable, Sendable { case terminal, editor, codexApp }

    /// 按常用程度排：先找已经开着的。都没开时打开系统「终端」。
    public static let terminals = [
        "com.mitchellh.ghostty", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "com.github.wez.wezterm", "net.kovidgoyal.kitty", "org.alacritty", "com.apple.Terminal",
    ]
    public static let editors = [
        "com.todesktop.230313mzl4w4u92", "com.microsoft.VSCode", "com.exafunction.windsurf",
        "com.microsoft.VSCodeInsiders",
    ]
    public static let codexApps = ["com.openai.codex"]
    public static let fallback = "com.apple.Terminal"

    /// 从会话头的 originator 认是在哪开的。
    public static func host(originator: String?) -> Host {
        let o = (originator ?? "").lowercased()
        if o.contains("vscode") || o.contains("cursor") || o.contains("windsurf") { return .editor }
        if o.contains("desktop") || o.contains("codex_app") || o == "codex app" { return .codexApp }
        return .terminal
    }

    /// 该叫到前台的 App：会话所在那一类里已经开着的第一个，没有就找开着的终端，
    /// 再没有就是系统「终端」。
    public static func target(host: Host, running: [String]) -> String {
        let preferred: [String]
        switch host {
        case .terminal: preferred = terminals
        case .editor: preferred = editors + terminals
        case .codexApp: preferred = codexApps + terminals
        }
        return preferred.first { running.contains($0) } ?? fallback
    }
}

// MARK: - 卡片

/// 扩展栏上的两种卡片：小（状态 + 两个圆环）和中（小熊猫、项目和正在做什么 +
/// 两条进度条）。没存 layout 的老卡片按小卡读。
public enum CodexCard {
    public static let small = "small"
    public static let medium = "medium"

    public static func isMedium(_ config: WidgetConfig) -> Bool {
        config.string("layout", default: small) == medium
    }

    /// 卡片上的窗口名："5 小时"、"本周"。七天的窗口叫本周（原来的短名是“周”）。
    public static func label(_ w: CodexLimitWindow) -> String {
        if let duration = w.duration, abs(duration - 604_800) < 60 { return tr("本周") }
        if w.id == "secondary", w.duration == nil, w.label == tr("每周额度") { return tr("本周") }
        return w.shortLabel
    }

    /// 小卡圆环旁的重置倒计时："2:14"，过了一天是 "1天22时"。
    public static func resetShort(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let hours = s / 3600
        if hours >= 24 { return tr("\(hours / 24)天\(hours % 24)时") }
        return String(format: "%d:%02d", hours, (s % 3600) / 60)
    }

    /// 中卡和面板角落的小熊猫，随状态换姿势，都是 Resources/Pet 里现成的图。
    public static func pandaImage(_ activity: CodexActivity) -> String {
        switch activity {
        case .working: "pet-panda-eat"
        case .waiting: "pet-panda-hungry"
        case .done: "pet-panda-cheer"
        case .idle: "pet-panda-rest"
        }
    }
}
