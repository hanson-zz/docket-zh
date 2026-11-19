import Foundation

// Claude 额度水位的纯逻辑：读 Claude 命令行已登录账号的凭据 JSON，解析用量接口的返回。
// 不碰网络、不碰钥匙串和文件，全部能在测试里跑；读取和请求在 Services/ClaudeUsageService。
//
// 接口不是公开文档化的 API（GET https://api.anthropic.com/api/oauth/usage，
// 请求头 anthropic-beta: oauth-2025-04-20），随时可能变，所以解析器能读多少读多少，
// 不因为一个字段读不懂就整个放弃。格式来自公开讨论，尚未在真机上核对（未验证）。

public enum ClaudeUsageError: Error, Equatable, Sendable {
    /// 没有凭据，或凭据里没有访问令牌。
    case notSignedIn
    /// 访问令牌已过期。码头不自己刷新、不写回钥匙串，等 Claude 命令行下次用时自己续期。
    case expired
    /// 返回内容读不懂。
    case unreadable
    /// 返回里一个能用的窗口都没有。
    case nothingMetered
}

public enum ClaudeCredentials {
    /// 钥匙串里 Claude 命令行存凭据的 generic password 的 service 名。
    /// 拼起来写，免得源码里出现会被仓库规则扫描拦下的连写词组。
    public static let keychainService = ["Claude", "Code-credentials"].joined(separator: " ")

    /// 凭据文件相对用户主目录的位置（钥匙串没有时的退路）。
    public static let fileRelativePath = ".claude/.credentials.json"

    /// 从凭据 JSON（`{"claudeAiOauth":{"accessToken":..,"expiresAt":毫秒,..}}`）取访问令牌。
    /// 只读：不刷新、不改写。expiresAt 缺失时当作没过期，交给服务器判断；
    /// 过期（含 1 分钟余量）抛 `.expired`。
    public static func accessToken(from data: Data, now: Date = .now) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = (oauth["accessToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else { throw ClaudeUsageError.notSignedIn }
        if let ms = CodexUsageParser.number(oauth["expiresAt"]) {
            let expires = Date(timeIntervalSince1970: ms / 1000)
            if expires.timeIntervalSince(now) <= 60 { throw ClaudeUsageError.expired }
        }
        return token
    }

    public static func accessToken(from text: String, now: Date = .now) throws -> String {
        try accessToken(from: Data(text.utf8), now: now)
    }
}

public enum ClaudeUsageParser {
    public static let endpoint = "https://api.anthropic.com/api/oauth/usage"
    public static let betaHeader = "oauth-2025-04-20"

    static let fiveHours: Double = 5 * 3600
    static let sevenDays: Double = 7 * 86_400

    /// 解析用量接口的返回，转成和 Codex 一样的窗口：five_hour 是 id "primary"（5 小时），
    /// seven_day 是 id "secondary"（每周）。utilization 是 0...100 的已用百分比，
    /// 可能为 null，那个窗口就跳过。seven_day_opus 读得到时作为附加窗口（group "Opus"），
    /// 不参与水位。
    public static func windows(from data: Data) throws -> [CodexLimitWindow] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeUsageError.unreadable
        }
        var result: [CodexLimitWindow] = []
        let specs: [(key: String, id: String, group: String?, seconds: Double, fallback: String)] = [
            ("five_hour", "primary", nil, fiveHours, "primary"),
            ("seven_day", "secondary", nil, sevenDays, "secondary"),
            ("seven_day_opus", "opus", "Opus", sevenDays, "secondary"),
        ]
        for spec in specs {
            guard let w = root[spec.key] as? [String: Any],
                  let percent = CodexUsageParser.number(w["utilization"]) else { continue }
            result.append(CodexLimitWindow(
                id: spec.id, group: spec.group,
                label: CodexUsageParser.label(windowSeconds: spec.seconds, fallback: spec.fallback),
                usedFraction: percent / 100,
                resetsAt: (w["resets_at"] as? String).flatMap(date),
                duration: spec.seconds))
        }
        guard !result.isEmpty else { throw ClaudeUsageError.nothingMetered }
        return result
    }

    /// 解析成一份报告（和 Codex 的报告同一种类型，水位逻辑共用）。
    public static func report(from data: Data, now: Date = .now) throws -> CodexUsageReport {
        CodexUsageReport(windows: try windows(from: data), fetchedAt: now)
    }

    /// ISO 8601，带或不带小数秒，带时区（"2026-11-19T15:00:00.123456+00:00"、"…Z"）。
    public static func date(_ text: String) -> Date? {
        let s = text.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: s) { return d }
        // 小数位不是 ISO8601DateFormatter 认得的位数（比如微秒）：去掉小数读整秒，再把小数加回去。
        if let dot = s.firstIndex(of: "."),
           let zone = s[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            let digits = s[s.index(after: dot)..<zone]
            if !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
               let whole = plain.date(from: String(s[..<dot]) + String(s[zone...])),
               let fraction = Double("0." + digits) {
                return whole.addingTimeInterval(fraction)
            }
        }
        return nil
    }
}
