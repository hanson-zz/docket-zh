import Foundation

// The pure half of the Codex usage widget: parsing what Codex's own backend
// and its local files say, and the arithmetic drawn from them. Nothing here
// touches the network or the file system, so all of it runs in tests.
//
// The endpoints and file layouts were learned from Codenotch
// (https://github.com/vinzdg/codenotch, MIT, Copyright (c) Vincent de Gans);
// see NOTICE.md. They are not a published API: OpenAI can change them at any
// time, which is why every parser here keeps whatever it can read rather than
// failing the whole reading over one odd field.

/// One rate-limit window, such as the 5-hour session or the week.
public struct CodexLimitWindow: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    /// Group for the extra windows ("Spark", "代码审查"); nil for the main pair.
    public var group: String?
    public var label: String
    /// 0...1 of the window used.
    public var usedFraction: Double
    public var resetsAt: Date?
    /// Length of the window in seconds, when the server says.
    public var duration: Double?

    public init(id: String, group: String? = nil, label: String, usedFraction: Double,
                resetsAt: Date? = nil, duration: Double? = nil) {
        self.id = id
        self.group = group
        self.label = label
        self.usedFraction = min(max(usedFraction, 0), 1)
        self.resetsAt = resetsAt
        self.duration = duration
    }

    public var remainingFraction: Double { 1 - usedFraction }

    /// "5 小时" for the ring's caption, from the full label.
    public var shortLabel: String {
        label.replacingOccurrences(of: "额度", with: "")
            .replacingOccurrences(of: "每", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Tokens Codex counted on one calendar day, as the profile page reports.
public struct CodexDailyTokens: Codable, Equatable, Sendable {
    /// "2026-10-12".
    public var day: String
    public var tokens: Int

    public init(day: String, tokens: Int) {
        self.day = day
        self.tokens = tokens
    }
}

/// Everything one refresh learned. Codable so the last good reading survives
/// a relaunch and an offline hour.
public struct CodexUsageReport: Codable, Equatable, Sendable {
    public var windows: [CodexLimitWindow]
    public var plan: String?
    /// Unused rate-limit resets on the account, when the server lists them.
    public var resetCredits: Int?
    public var daily: [CodexDailyTokens]
    public var fetchedAt: Date
    /// Which way the reading was taken. Optional so a reading cached before
    /// this field existed still decodes.
    public var source: CodexUsageSource?

    public init(windows: [CodexLimitWindow], plan: String? = nil, resetCredits: Int? = nil,
                daily: [CodexDailyTokens] = [], fetchedAt: Date, source: CodexUsageSource? = nil) {
        self.windows = windows
        self.plan = plan
        self.resetCredits = resetCredits
        self.daily = daily
        self.fetchedAt = fetchedAt
        self.source = source
    }

    /// The session window. Named, never `windows.first`, so an extra can never
    /// take the main ring.
    public var primary: CodexLimitWindow? { windows.first { $0.id == "primary" } ?? windows.first { $0.id == "credits" } }
    public var weekly: CodexLimitWindow? { windows.first { $0.id == "secondary" } }
    public var extras: [CodexLimitWindow] { windows.filter { $0.group != nil } }

    /// The windows a ring is drawn for: the main pair, or the credit cap.
    public var ringWindows: [CodexLimitWindow] { [primary, weekly].compactMap { $0 } }

    /// Whether the reading is old enough that the tile should say so.
    public func isStale(now: Date, after: TimeInterval = 30 * 60) -> Bool {
        now.timeIntervalSince(fetchedAt) > after
    }
}

public enum CodexUsageError: Error, Equatable, Sendable {
    /// No auth.json, or one without a ChatGPT sign-in.
    case notSignedIn
    /// The token in auth.json has expired; running Codex once renews it.
    case expired
    case unreadable
    case nothingMetered
}

// MARK: - auth.json

public enum CodexAuth {
    public struct Credential: Equatable, Sendable {
        public var accessToken: String
        public var accountID: String
        public var email: String?
        public var plan: String?
    }

    /// Reads `~/.codex/auth.json`. The file is only ever read: Codex owns it
    /// and refreshes it, and writing it could sign Codex out.
    public static func credential(from data: Data, now: Date = .now) throws -> Credential {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let access = (tokens["access_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !access.isEmpty
        else { throw CodexUsageError.notSignedIn }
        let accessClaims = claims(inJWT: access)
        let account = (tokens["account_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ((accessClaims?["https://api.openai.com/auth"] as? [String: Any])?["chatgpt_account_id"] as? String)
        guard let account, !account.isEmpty else { throw CodexUsageError.notSignedIn }
        if let exp = accessClaims?["exp"] as? Double, exp <= now.timeIntervalSince1970 {
            throw CodexUsageError.expired
        }
        let idClaims = (tokens["id_token"] as? String).flatMap(claims(inJWT:))
        let auth = idClaims?["https://api.openai.com/auth"] as? [String: Any]
        return Credential(accessToken: access, accountID: account,
                          email: idClaims?["email"] as? String,
                          plan: (auth?["chatgpt_plan_type"] as? String).flatMap(nonEmpty))
    }

    /// The payload of a JWT. Read for labels and an expiry hint only; the
    /// server is what validates the token.
    public static func claims(inJWT token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func nonEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - /wham/usage

public enum CodexUsageParser {
    /// Parses `GET https://chatgpt.com/backend-api/wham/usage`.
    ///
    /// A window that cannot be read is skipped, never the whole response: a
    /// null percentage on the session window must not hide a good weekly one.
    public static func windows(from data: Data, now: Date = .now,
                               includeExtras: Bool = true) throws -> [CodexLimitWindow] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexUsageError.unreadable
        }
        var result: [CodexLimitWindow] = []
        let main = root["rate_limit"] as? [String: Any]
        for (id, key) in [("primary", "primary_window"), ("secondary", "secondary_window")] {
            if let w = main?[key] as? [String: Any],
               let item = window(id: id, group: nil, w, fallback: id, now: now) {
                result.append(item)
            }
        }
        if includeExtras {
            for extra in (root["additional_rate_limits"] as? [[String: Any]]) ?? [] {
                let names = [extra["limit_name"], extra["metered_feature"]].compactMap { $0 as? String }
                guard names.contains(where: { $0.range(of: "spark", options: .caseInsensitive) != nil }) else { continue }
                append(extra["rate_limit"] as? [String: Any], ids: ("spark", "spark-secondary"),
                       group: "Spark", now: now, to: &result)
            }
            append(root["code_review_rate_limit"] as? [String: Any],
                   ids: ("code-review", "code-review-secondary"), group: "代码审查", now: now, to: &result)
        }
        // A Business or Team seat has no rolling windows, only a credit cap.
        if result.isEmpty,
           let credit = (root["spend_control"] as? [String: Any])?["individual_limit"] as? [String: Any],
           let percent = number(credit["used_percent"]) {
            result.append(CodexLimitWindow(id: "credits", label: "额度上限", usedFraction: percent / 100,
                                           resetsAt: number(credit["reset_at"]).map { Date(timeIntervalSince1970: $0) }))
        }
        guard !result.isEmpty else { throw CodexUsageError.nothingMetered }
        return result
    }

    public static func plan(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plan = (root["plan_type"] as? String)?.trimmingCharacters(in: .whitespaces),
              !plan.isEmpty else { return nil }
        return plan
    }

    /// `GET /wham/profiles/me`: tokens per day.
    public static func daily(from data: Data) -> [CodexDailyTokens] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stats = root["stats"] as? [String: Any],
              let buckets = stats["daily_usage_buckets"] as? [[String: Any]] else { return [] }
        return buckets.compactMap { b in
            guard let day = b["start_date"] as? String, let tokens = number(b["tokens"]) else { return nil }
            return CodexDailyTokens(day: String(day.prefix(10)), tokens: Int(tokens))
        }.sorted { $0.day < $1.day }
    }

    /// `GET /wham/rate-limit-reset-credits`: how many resets are unused.
    public static func resetCredits(from data: Data) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let count = number(root["available_count"]) { return Int(count) }
        guard let credits = root["credits"] as? [[String: Any]] else { return nil }
        return credits.filter { ($0["status"] as? String) == "available" }.count
    }

    /// The label follows the length the server sent, not the plan we assume:
    /// a free account has reported a 30-day window where Plus has 5 hours.
    public static func label(windowSeconds: Double, fallback: String) -> String {
        guard windowSeconds > 0 else { return fallback == "primary" ? "当前会话" : "较长窗口" }
        let minutes = windowSeconds / 60
        if minutes < 60 { return "\(Int(minutes)) 分钟额度" }
        if minutes < 60 * 24 { return "\(Int((minutes / 60).rounded())) 小时额度" }
        let days = Int((minutes / (60 * 24)).rounded())
        switch days {
        case 7: return "每周额度"
        case 28...31: return "每月额度"
        default: return "\(days) 天额度"
        }
    }

    /// The plan in the words ChatGPT uses for it.
    public static func planTitle(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "free": return "Free"
        case "go": return "Go"
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case "edu": return "Edu"
        default: return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }

    // MARK: Helpers

    private static func append(_ limit: [String: Any]?, ids: (String, String), group: String,
                               now: Date, to result: inout [CodexLimitWindow]) {
        for (id, key, fallback) in [(ids.0, "primary_window", "primary"), (ids.1, "secondary_window", "secondary")] {
            guard !result.contains(where: { $0.id == id }),
                  let w = limit?[key] as? [String: Any],
                  let item = window(id: id, group: group, w, fallback: fallback, now: now) else { continue }
            result.append(item)
        }
    }

    private static func window(id: String, group: String?, _ w: [String: Any],
                               fallback: String, now: Date) -> CodexLimitWindow? {
        guard let percent = number(w["used_percent"]) else { return nil }
        let seconds = number(w["limit_window_seconds"])
        let resets = number(w["reset_at"]).map { Date(timeIntervalSince1970: $0) }
            ?? number(w["reset_after_seconds"]).map { now.addingTimeInterval($0) }
        return CodexLimitWindow(id: id, group: group,
                                label: label(windowSeconds: seconds ?? 0, fallback: fallback),
                                usedFraction: percent / 100, resetsAt: resets, duration: seconds)
    }

    /// Numbers arrive as numbers or as decimal strings ("374.92").
    static func number(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d.isFinite ? d : nil
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }
}

// MARK: - Session activity

/// What Codex is doing, read from the end of its newest session log
/// (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`).
public enum CodexActivity: String, Codable, Equatable, Sendable {
    case idle
    case working
    /// Waiting for the user to approve a command or a patch.
    case waiting
    case done

    public var title: String {
        switch self {
        case .idle: "空闲"
        case .working: "正在工作"
        case .waiting: "等你确认"
        case .done: "已完成"
        }
    }
}

public enum CodexRollout {
    /// The newest lifecycle event in the given tail of a rollout, or nil when
    /// the tail holds none. `item_completed` is ignored on purpose: commands
    /// emit it too, and only `task_complete` ends a turn.
    ///
    /// Codenotch reads only start and complete. Approval requests are read
    /// here as well, so the tile can say Codex is waiting on you rather than
    /// spinning as if it were busy.
    public static func lastEvent(inTail data: Data) -> CodexActivity? {
        let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        for line in lines.reversed() {
            guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let payload = record["payload"] as? [String: Any],
                  let type = payload["type"] as? String else { continue }
            let kind = record["type"] as? String
            switch type {
            case "task_started" where kind == "event_msg": return .working
            case "task_complete" where kind == "event_msg": return .done
            case "turn_aborted" where kind == "event_msg": return .idle
            case "exec_approval_request", "apply_patch_approval_request",
                 "request_permissions", "elicitation_request":
                return .waiting
            // The user answered; the turn carries on.
            case "user_message" where kind == "event_msg", "exec_command_begin", "patch_apply_begin":
                return .working
            default: continue
            }
        }
        return nil
    }

    /// The state the tile shows, from the log's last event and how long ago
    /// it was written.
    ///
    /// A quiet log is not proof a turn ended (a long build is quiet too), so a
    /// working turn stays working for `staleAfter`, and only then falls back to
    /// idle. A finished turn shows as done for `doneFor`, long enough to be
    /// seen when you look back at the screen.
    public static func state(lastEvent: CodexActivity?, modified: Date?, now: Date,
                             staleAfter: TimeInterval = 20 * 60,
                             doneFor: TimeInterval = 10 * 60,
                             freshWrite: TimeInterval = 8) -> CodexActivity {
        guard let modified else { return .idle }
        let age = now.timeIntervalSince(modified)
        switch lastEvent {
        case .working?: return age < staleAfter ? .working : .idle
        case .waiting?: return age < staleAfter * 3 ? .waiting : .idle
        case .done?: return age < doneFor ? .done : .idle
        case .idle?: return .idle
        case nil: return age < freshWrite ? .working : .idle
        }
    }

    /// Day folders worth looking in: today and yesterday, so a session that
    /// crossed midnight is still found.
    public static func dayFolders(now: Date, calendar: Calendar = .current) -> [String] {
        [0, -1].compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { return nil }
            let c = calendar.dateComponents([.year, .month, .day], from: day)
            return String(format: "%04d/%02d/%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
    }
}

// MARK: - Arithmetic for the panel

public enum CodexPace {
    /// How far through its window a reading is, 0...1, when the window's
    /// length and reset are known.
    public static func elapsedFraction(_ w: CodexLimitWindow, now: Date) -> Double? {
        guard let duration = w.duration, duration > 0, let resets = w.resetsAt else { return nil }
        let start = resets.addingTimeInterval(-duration)
        return min(max(now.timeIntervalSince(start) / duration, 0), 1)
    }

    /// When the window runs out at the rate used so far, or nil when it will
    /// last until it resets (or there is too little to go on).
    public static func runsOutAt(_ w: CodexLimitWindow, now: Date) -> Date? {
        guard let duration = w.duration, duration > 0, let resets = w.resetsAt,
              w.usedFraction > 0.02 else { return nil }
        if w.usedFraction >= 1 { return now }
        let elapsed = now.timeIntervalSince(resets.addingTimeInterval(-duration))
        // Ten minutes in, one prompt looks like a stampede.
        guard elapsed > min(600, duration * 0.05) else { return nil }
        let rate = w.usedFraction / elapsed
        let out = now.addingTimeInterval((1 - w.usedFraction) / rate)
        return out < resets ? out : nil
    }

    /// Used minus elapsed: above zero is ahead of an even pace.
    public static func delta(_ w: CodexLimitWindow, now: Date) -> Double? {
        elapsedFraction(w, now: now).map { w.usedFraction - $0 }
    }

    /// "2 小时 14 分", "3 天 4 小时", "不到 1 分钟".
    public static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "不到 1 分钟" }
        let minutes = s / 60, hours = minutes / 60, days = hours / 24
        if days > 0 { return hours % 24 > 0 ? "\(days) 天 \(hours % 24) 小时" : "\(days) 天" }
        if hours > 0 { return minutes % 60 > 0 ? "\(hours) 小时 \(minutes % 60) 分" : "\(hours) 小时" }
        return "\(minutes) 分钟"
    }

    /// "2:14" for the tile, where space is short. Days past 24 hours.
    public static func compact(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let hours = s / 3600, minutes = (s % 3600) / 60
        if hours >= 24 { return "\(hours / 24) 天" }
        return String(format: "%d:%02d", hours, minutes)
    }

    /// "1.2M", "38k", "512", for token counts.
    public static func tokens(_ n: Int) -> String {
        switch n {
        case ..<1000: return "\(max(0, n))"
        case ..<1_000_000:
            let v = Double(n) / 1000
            return (v < 10 ? String(format: "%.1f", v) : String(format: "%.0f", v)) + "k"
        case ..<1_000_000_000:
            let v = Double(n) / 1_000_000
            return (v < 10 ? String(format: "%.1f", v) : String(format: "%.0f", v)) + "M"
        default:
            return String(format: "%.1f", Double(n) / 1_000_000_000) + "B"
        }
    }

    /// The last `days` days as a gapless series, zero where the server had no
    /// bucket, ending today.
    public static func series(_ daily: [CodexDailyTokens], days: Int = 30, now: Date,
                              calendar: Calendar = .current) -> [Int] {
        let byDay = Dictionary(daily.map { ($0.day, $0.tokens) }, uniquingKeysWith: +)
        let today = calendar.startOfDay(for: now)
        return (0..<days).map { i in
            guard let d = calendar.date(byAdding: .day, value: i - days + 1, to: today) else { return 0 }
            let c = calendar.dateComponents([.year, .month, .day], from: d)
            return byDay[String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)] ?? 0
        }
    }
}

public enum CodexAlert {
    /// The highest threshold the reading has just risen past, or nil.
    ///
    /// Only a rise counts: a window that reset and came back up warns again,
    /// one that sits at 90% does not warn every five minutes.
    public static func crossed(previous: Double?, current: Double, thresholds: [Double]) -> Double? {
        guard let previous else { return nil }
        return thresholds.sorted().last { previous < $0 && current >= $0 }
    }

    /// The thresholds for a configured first warning: that one, and 95% and
    /// the cap itself above it.
    public static func thresholds(first: Int) -> [Double] {
        let base = Double(min(max(first, 50), 95)) / 100
        return Array(Set([base, 0.95, 1.0].filter { $0 >= base })).sorted()
    }
}

/// When to try again after a failure.
///
/// Codenotch retried Claude every poll after a 429 and got itself throttled
/// for longer; this doubles the wait, honours the server's own Retry-After,
/// and never waits past half an hour.
public enum CodexBackoff {
    public static func delay(failures: Int, retryAfter: TimeInterval? = nil) -> TimeInterval {
        guard failures > 0 else { return 0 }
        let doubled = 60 * pow(2, Double(min(failures - 1, 6)))
        return min(1800, max(retryAfter ?? 0, doubled))
    }

    /// A Retry-After header in seconds or as an HTTP date.
    public static func retryAfter(_ header: String?, now: Date) -> TimeInterval? {
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else { return nil }
        if let seconds = TimeInterval(header), seconds.isFinite { return max(0, seconds) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.date(from: header).map { max(0, $0.timeIntervalSince(now)) }
    }
}

/// The proxy the widget sends its requests through, typed by the user.
///
/// An app opened from Finder does not see `HTTPS_PROXY` set in a shell, so a
/// Mac that reaches chatgpt.com only through a terminal proxy would otherwise
/// never get a reading.
public struct CodexProxy: Equatable, Sendable {
    public enum Kind: String, Sendable { case http, socks }
    public var kind: Kind
    public var host: String
    public var port: Int

    /// "127.0.0.1:7890", "http://127.0.0.1:7890", "socks5://localhost:1080".
    public static func parse(_ text: String) -> CodexProxy? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        var kind = Kind.http
        if let range = s.range(of: "://") {
            let scheme = s[..<range.lowerBound].lowercased()
            switch scheme {
            case "http", "https": kind = .http
            case "socks", "socks5", "socks5h", "socks4": kind = .socks
            default: return nil
            }
            s = String(s[range.upperBound...])
        }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        guard let colon = s.lastIndex(of: ":") else { return nil }
        let host = String(s[..<colon]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !host.isEmpty, !host.contains(" "),
              let port = Int(s[s.index(after: colon)...]), (1...65535).contains(port) else { return nil }
        return CodexProxy(kind: kind, host: host, port: port)
    }

    public var display: String { "\(kind == .socks ? "socks5" : "http")://\(host):\(port)" }
}
